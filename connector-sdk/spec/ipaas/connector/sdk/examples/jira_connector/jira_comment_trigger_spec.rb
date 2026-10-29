require 'spec_helper'
require_relative 'jira_context'

describe 'Jira Comment Event Trigger', :jira, :trigger do
  let(:trigger_template_id) { '01a13f2d-b655-70c4-97fa-7c335f215c06' }
  let(:comment_url) { "#{api}/issue/10221/comment/10150" }
  let(:trigger_config) { { project_key: 'KAN', fire_on: %w[comment_created comment_updated] } }

  before { stub_trigger_projects }

  let(:author) { { accountId: 'acc-1', displayName: 'Aman' } }
  let(:editor) { { accountId: 'acc-2', displayName: 'Bea' } }
  let(:comment_payload) do
    {
      timestamp: 1_792_761_232_344,
      webhookEvent: 'comment_updated',
      comment: {
        id: '10150',
        author: author,
        updateAuthor: editor,
        body: 'Hello [~accountid:acc-3] please check',
        created: '2026-10-23T18:43:52.344+0530',
        updated: '2026-10-23T18:44:10.000+0530',
      },
      issue: {
        id: '10221',
        key: 'KAN-204',
        fields: {
          summary: 'Sync it',
          issuetype: { id: '10003', name: 'Task' },
          project: { id: '10000', key: 'KAN' },
          assignee: nil,
          priority: { id: '2', name: 'High' },
          status: { id: '10000', name: 'To Do' },
        },
      },
    }
  end
  let(:mention_paragraph) do
    {
      type: 'paragraph',
      content: [
        { type: 'text', text: 'Hello ' },
        { type: 'mention', attrs: { id: 'acc-3', text: '@Cleo' } },
        { type: 'text', text: ' please check' },
      ],
    }
  end
  let(:fetched_comment) do
    {
      id: '10150',
      author: author,
      updateAuthor: editor,
      body: { type: 'doc', content: [mention_paragraph] },
      created: '2026-10-23T18:43:52.344+0530',
      updated: '2026-10-23T18:44:10.000+0530',
    }
  end

  around { |example| Timecop.freeze(Time.at(1_792_761_292, in: 'UTC')) { example.run } }

  describe 'config_schema' do
    it 'offers Created and Updated comments under Fire on, both picked by default' do
      field = trigger.config_schema.field(:fire_on)
      expect(field.enumeration).to eq([
        { id: 'comment_created', label: 'Created' },
        { id: 'comment_updated', label: 'Updated' },
      ])
      expect(field.default).to eq(%w[comment_created comment_updated])
    end
  end

  describe 'provision' do
    it 'registers the comment events for the picked project' do
      jql = 'project = "KAN"'
      expected = { 'events' => %w[comment_created comment_updated],
                   'filters' => { 'issue-related-events-section' => jql }, }
      stub = stub_request(:post, webhook_api)
             .with { |request| JSON.parse(request.body).slice('events', 'filters') == expected }
             .to_return(status: 201, body: { self: "#{webhook_api}/57", filters: expected['filters'],
                                             isSigned: true, }.to_json)
      stub_webhook_list
      trigger.provision
      expect(stub).to have_been_requested.once
    end
  end

  describe 'respond_with' do
    before { allow(runbook).to receive(:trigger_output).and_return(nil) }

    it 'answers 503 when iPaaS dropped the comment event for the concurrency limit, so Jira sends it again' do
      response = trigger.respond_with(nil, nil, {}, { error: IPaaS::Job::DiscardTriggerEvent.new })
      expect(response[:status]).to eq(503)
      expect(response[:headers]['Retry-After']).to eq('60')
    end
  end

  describe 'deprovision' do
    it 'deletes its webhook when the trigger is removed' do
      seed_stored_webhook(id: '57', secret: nil, host: 'acme.atlassian.net')
      stub = stub_request(:delete, "#{webhook_api}/57").to_return(status: 204, body: '')
      trigger.deprovision
      expect(stub).to have_been_requested.once
      expect(trigger.store.read('webhook')).to be_blank
    end
  end

  describe 'parse' do
    before do
      seed_stored_webhook(id: '57')
      outbound_connection.store.write('cloud_id:acme.atlassian.net', 'cloud-1')
    end

    it 'reports the comment body as plain text read from Jira, with the issue it belongs to' do
      stub_request(:get, comment_url).to_return(status: 200, body: fetched_comment.to_json)
      output = signed_post(comment_payload)
      expect(output).to include(webhook_event: 'comment_updated', comment_id: '10150',
                                comment_body: 'Hello @Cleo please check', issue_key: 'KAN-204',
                                issue_id: '10221', summary: 'Sync it', status: 'To Do', priority: 'High',
                                issue_type: 'Task', project: 'KAN', updated: '2026-10-23T18:44:10.000+0530')
      expect(output[:text_unavailable_reason]).to be_nil
      expect(runbook).to have_received(:store_job_context_identifier).with('KAN-204')
    end

    it 'reports a comment of two paragraphs with a blank line between them' do
      second = { type: 'paragraph', content: [{ type: 'text', text: 'Thanks' }] }
      two_paragraphs = fetched_comment.merge(body: { type: 'doc', content: [mention_paragraph, second] })
      stub_request(:get, comment_url).to_return(status: 200, body: two_paragraphs.to_json)
      output = signed_post(comment_payload)
      expect(output[:comment_body]).to eq("Hello @Cleo please check\n\nThanks")
    end

    it 'reports a new comment with its body read from Jira' do
      stub_request(:get, comment_url).to_return(status: 200, body: fetched_comment.to_json)
      output = signed_post(comment_payload.merge(webhookEvent: 'comment_created'))
      expect(output).to include(webhook_event: 'comment_created', comment_id: '10150',
                                comment_body: 'Hello @Cleo please check', issue_key: 'KAN-204')
    end

    it 'reports who last edited the comment, because comment events name no user' do
      stub_request(:get, comment_url).to_return(status: 200, body: fetched_comment.to_json)
      output = signed_post(comment_payload)
      expect(output[:author]).to include(account_id: 'acc-1')
      expect(output[:update_author]).to include(account_id: 'acc-2', display_name: 'Bea')
    end

    it 'leaves the body empty and names the reason when the account cannot see the comment' do
      stub_request(:get, comment_url).to_return(status: 404, body: { errorMessages: ['Not found'] }.to_json)
      output = signed_post(comment_payload)
      expect(output).to include(comment_id: '10150', comment_body: nil, text_unavailable_reason: 'not_visible')
      expect(output[:author]).to include(account_id: 'acc-1')
    end

    it 'leaves the body empty and names the reason when Jira refuses to show the comment' do
      stub_request(:get, comment_url).to_return(status: 403, body: { errorMessages: ['Forbidden'] }.to_json)
      output = signed_post(comment_payload)
      expect(output).to include(comment_id: '10150', comment_body: nil, text_unavailable_reason: 'not_visible')
    end

    it 'delivers the body Jira sent, with its mention as plain text, when Jira rejects the credentials' do
      stub_request(:get, comment_url).to_return(status: 401, body: { code: 401, message: 'Unauthorized' }.to_json)
      output = signed_post(comment_payload)
      expect(output).to include(comment_id: '10150', comment_body: 'Hello @acc-3 please check',
                                text_unavailable_reason: 'fetch_failed')
      expect(output[:author]).to include(account_id: 'acc-1')
    end

    it 'delivers the body Jira sent when Jira is briefly unavailable, rather than refusing the event' do
      stub_request(:get, comment_url).to_return(status: 503, body: 'down')
      output = trigger.parse_request(signed_request(comment_payload))
      expect(output).to include(comment_body: 'Hello @acc-3 please check', text_unavailable_reason: 'fetch_failed')
    end

    it 'discards an issue event' do
      output = signed_post(comment_payload.merge(webhookEvent: 'jira:issue_created'))
      expect(output[:result]).to eq('Discarded')
    end

    context 'when only Created is picked under Fire on' do
      let(:trigger_config) { { project_key: 'KAN', fire_on: ['comment_created'] } }

      it 'discards an edited comment' do
        output = signed_post(comment_payload)
        expect(output[:result]).to eq('Discarded')
      end
    end
  end
end
