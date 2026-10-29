require 'spec_helper'
require_relative 'jira_context'

describe 'Jira Issue Event Trigger', :jira, :trigger do
  let(:trigger_template_id) { '01a13f2d-b655-7c0d-be71-eec8ecb4ea91' }
  let(:filter_key) { 'issue-related-events-section' }
  let(:trigger_config) { { project_key: 'KAN', fire_on: ['jira:issue_created'] } }
  let(:event_time) { Time.at(1_792_000_000, in: 'UTC') }

  let(:issue_payload) do
    {
      webhookEvent: 'jira:issue_created',
      timestamp: 1_792_000_000_000,
      user: { accountId: 'acc-1', displayName: 'Bot' },
      issue: { id: '1', key: 'KAN-1', fields: { summary: 'Build it' } },
    }
  end

  around { |example| Timecop.freeze(event_time + 60) { example.run } }

  before { stub_trigger_projects }

  def registered(id, jql: 'project = KAN', signed: true)
    { status: 201, body: { self: "#{webhook_api}/#{id}", filters: { filter_key => jql }, isSigned: signed }.to_json }
  end

  def stub_registration(id, sent_secrets)
    stub_request(:post, webhook_api).to_return do |request|
      sent_secrets.push(JSON.parse(request.body)['secret'])
      registered(id)
    end
  end

  def post_signed_with(secret)
    post_trigger(issue_payload, headers: { 'X-Hub-Signature' => hub_signature(issue_payload.to_json, secret) })
  end

  def healthy(jql: 'project = KAN', enabled: true, signed: true,
              url: trigger.endpoint, events: trigger.config[:fire_on])
    body = { enabled: enabled, isSigned: signed, filters: { filter_key => jql }, url: url, events: events }
    { status: 200, body: body.to_json }
  end

  describe 'config_schema' do
    it 'offers Created and Updated under Fire on, both picked by default' do
      field = trigger.config_schema.field(:fire_on)
      expect(field.enumeration).to eq([
        { id: 'jira:issue_created', label: 'Created' },
        { id: 'jira:issue_updated', label: 'Updated' },
      ])
      expect(field.default).to eq(%w[jira:issue_created jira:issue_updated])
    end
  end

  describe 'provision' do
    before { stub_webhook_list }

    it 'registers no webhook when this account cannot open the project' do
      stub_missing_project('KAN')

      expect { trigger.provision }.to raise_error(
        IPaaS::Job::FailJob,
        'Project KAN was not found, or this account cannot see it (HTTP 404): ' \
        "No project could be found with key 'KAN'.",
      )
      expect(a_request(:post, webhook_api)).not_to have_been_made
    end

    it 'registers the admin webhook through the Atlassian gateway with a generated secret' do
      sent_secrets = []
      stub = stub_registration(55, sent_secrets)
      trigger.provision
      expect(stub).to have_been_requested.once
      stored = trigger.store.read('webhook')
      expect(stored[:id]).to eq('55')
      expect(stored[:host]).to eq('acme.atlassian.net')
      expect(post_signed_with(sent_secrets.first)[:issue_key]).to eq('KAN-1')
    end

    it 'does nothing when it is already subscribed to the same thing' do
      stub_request(:post, webhook_api).to_return(registered(55))
      trigger.provision
      WebMock.reset!
      stub_trigger_projects
      stub_webhook_list
      stub_request(:get, "#{webhook_api}/55").to_return(healthy)
      trigger.provision
      expect(a_request(:post, webhook_api)).not_to have_been_made
    end

    it 'registers the webhook again when it was deleted in Jira, and checks deliveries with the new secret' do
      sent_secrets = []
      stub_registration(55, sent_secrets)
      trigger.provision
      WebMock.reset!
      stub_trigger_projects
      stub_webhook_list
      stub_request(:get, "#{webhook_api}/55").to_return(status: 404, body: '')
      stub_request(:delete, "#{webhook_api}/55").to_return(status: 404, body: '')
      stub_registration(56, sent_secrets)
      trigger.provision
      expect(trigger.store.read('webhook')[:id]).to eq('56')
      expect(post_signed_with(sent_secrets.last)[:issue_key]).to eq('KAN-1')
    end

    it 'deletes the schedule a polling trigger of this runbook left behind' do
      solution = double('solution', uuid: 'solution-1', soft_delete_schedule: nil)
      allow(trigger).to receive(:solution).and_return(solution)
      trigger.store.write('schedule', { reference: 'ref-1' })
      stub_request(:post, webhook_api).to_return(registered(55))
      trigger.provision
      expect(solution).to have_received(:soft_delete_schedule).with('ref-1')
      expect(trigger.store.read('schedule')).to be_nil
    end

    context 'with the poll cursor of a polling trigger of this runbook stored' do
      let(:stored_cursor) { { 'at' => 1_790_000_000_000, 'keys' => [], 'scope' => 'project = "KAN"' } }

      before { trigger.store.write('poll_cursor', stored_cursor) }

      it 'deletes the poll cursor once the webhook is registered, so a later switch back starts afresh' do
        stub_request(:post, webhook_api).to_return(registered(55))
        trigger.provision
        expect(trigger.store.read('poll_cursor')).to be_nil
      end

      it 'keeps the poll cursor when Jira refuses the registration, so polling can resume where it stopped' do
        stub_request(:post, webhook_api).to_return(status: 403, body: { errorMessages: ['Forbidden'] }.to_json)
        expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob)
        expect(trigger.store.read('poll_cursor')).to eq(stored_cursor)
      end
    end

    it 'keeps the stored webhook and registers nothing when Jira does not answer the check of it' do
      stub_request(:post, webhook_api).to_return(registered(55))
      trigger.provision
      WebMock.reset!
      stub_trigger_projects
      stub_webhook_list
      stub_request(:get, "#{webhook_api}/55").to_timeout
      allow(trigger).to receive(:log)
      trigger.provision
      expect(a_request(:post, webhook_api)).not_to have_been_made
      expect(trigger.store.read('webhook')[:id]).to eq('55')
      expect(trigger).to have_received(:log).with(/did not answer the check of webhook 55 .*so the webhook is kept/)
    end

    [
      ['disabled', { enabled: false }],
      ['no longer signed', { signed: false }],
      ['filtered on another project', { jql: 'project = OPS' }],
      ['sending to another address', { url: 'https://elsewhere.example/hook' }],
      ['no longer sending an event picked under Fire on', { events: [] }],
    ].each do |state, reply|
      it "registers a new webhook and deletes the stored one when Jira reports it #{state}" do
        stub_request(:post, webhook_api).to_return(registered(55))
        trigger.provision
        WebMock.reset!
        stub_trigger_projects
        stub_webhook_list
        stub_request(:get, "#{webhook_api}/55").to_return(healthy(**reply))
        create = stub_request(:post, webhook_api).to_return(registered(56))
        delete = stub_request(:delete, "#{webhook_api}/55").to_return(status: 204, body: '')
        trigger.provision
        expect(create).to have_been_requested.once
        expect(delete).to have_been_requested.once
        expect(trigger.store.read('webhook')[:id]).to eq('56')
      end
    end

    it 'deletes a webhook that sends to this trigger but that iPaaS does not hold, after registering' do
      stub_request(:post, webhook_api).to_return(registered(55))
      stub_webhook_list([{ self: "#{webhook_api}/40", url: trigger.endpoint },
                         { self: "#{webhook_api}/55", url: trigger.endpoint },
                         { self: "#{webhook_api}/41", url: 'https://elsewhere.example/hook' },
                         { self: "#{webhook_api}/..%2Fx", url: trigger.endpoint },])
      leftover = stub_request(:delete, "#{webhook_api}/40").to_return(status: 204, body: '')
      trigger.provision
      expect(leftover).to have_been_requested.once
      expect(a_request(:delete, "#{webhook_api}/55")).not_to have_been_made
      expect(a_request(:delete, "#{webhook_api}/41")).not_to have_been_made
      expect(a_request(:delete, /x\z/)).not_to have_been_made
    end

    it 'deletes a webhook that sends to this trigger but that iPaaS does not hold, also when the stored one is kept' do
      stub_request(:post, webhook_api).to_return(registered(55))
      trigger.provision
      WebMock.reset!
      stub_trigger_projects
      stub_request(:get, "#{webhook_api}/55").to_return(healthy)
      stub_webhook_list([{ self: "#{webhook_api}/40", url: trigger.endpoint },
                         { self: "#{webhook_api}/55", url: trigger.endpoint },])
      leftover = stub_request(:delete, "#{webhook_api}/40").to_return(status: 204, body: '')
      trigger.provision
      expect(leftover).to have_been_requested.once
      expect(a_request(:post, webhook_api)).not_to have_been_made
    end

    it 'keeps the registration when Jira does not answer the search for leftover webhooks' do
      stub_request(:post, webhook_api).to_return(registered(55))
      stub_request(:get, webhook_api).to_timeout
      trigger.provision
      expect(trigger.store.read('webhook')[:id]).to eq('55')
    end

    it 'names both a bad token and the wrong kind of token when Jira answers 401 to the registration' do
      stub_request(:post, webhook_api).to_return(status: 401, body: { message: 'Unauthorized' }.to_json)
      expect { trigger.provision }.to raise_error(
        IPaaS::Job::FailJob,
        'Jira refused to register the webhook (HTTP 401): Unauthorized. The API token is wrong, revoked or expired, ' \
        'or it is a scoped or service-account token: Jira manages webhooks only for a classic API token of a user ' \
        'with the Administer Jira permission.'
      )
    end

    it 'keeps the stored webhook when Jira reads the filter back without the quotes the connector sent' do
      stub_request(:post, webhook_api).to_return(registered(55))
      trigger.provision
      expect(trigger.store.read('webhook')[:filter]).to eq('project = KAN')
      WebMock.reset!
      stub_trigger_projects
      stub_webhook_list
      stub_request(:get, "#{webhook_api}/55").to_return(healthy)
      trigger.provision
      expect(a_request(:post, webhook_api)).not_to have_been_made
    end

    it 'keeps the stored webhook and registers nothing when Jira answers the check with an error' do
      stub_request(:post, webhook_api).to_return(registered(55))
      trigger.provision
      WebMock.reset!
      stub_trigger_projects
      stub_webhook_list
      stub_request(:get, "#{webhook_api}/55").to_return(status: 503, body: '<html>busy</html>')
      trigger.provision
      expect(a_request(:post, webhook_api)).not_to have_been_made
      expect(trigger.store.read('webhook')[:id]).to eq('55')
    end

    it 'registers, checks and deletes webhooks with short timeouts, so a slow Jira cannot outlast the promote' do
      short = hash_including(open_timeout: JiraConnector::SHORT_OPEN_TIMEOUT, timeout: JiraConnector::SHORT_TIMEOUT)
      reads = []
      allow(trigger).to receive(:http_get).and_wrap_original do |original, url, *rest, **options|
        reads.push([url, options])
        original.call(url, *rest, **options)
      end
      allow(trigger).to receive(:http_post).and_call_original
      allow(trigger).to receive(:http_delete).and_call_original
      seed_stored_webhook(id: '54', jql: 'project = "OLD"')
      stub_request(:post, webhook_api).to_return(registered(55))
      stub_request(:delete, "#{webhook_api}/54").to_return(status: 204, body: '')
      trigger.provision
      expect(trigger).to have_received(:http_post).with(webhook_api, anything, anything, short)
      expect(trigger).to have_received(:http_delete).with("#{webhook_api}/54", nil, nil, short)
      expect(reads.map(&:first)).to include("#{api}/project/KAN", webhook_api)
      expect(reads.map(&:last)).to all(include(open_timeout: JiraConnector::SHORT_OPEN_TIMEOUT,
                                               timeout: JiraConnector::SHORT_TIMEOUT))
    end

    it 'registers the whole body Jira expects, with a fresh random secret' do
      bodies = []
      stub_request(:post, webhook_api).to_return do |request|
        bodies.push(JSON.parse(request.body))
        registered(55)
      end
      trigger.provision
      expect(bodies.size).to eq(1)
      expect(bodies.first.except('secret')).to eq(
        'name' => "iPaaS #{trigger.endpoint}", 'url' => trigger.endpoint, 'events' => ['jira:issue_created'],
        'filters' => { filter_key => 'project = "KAN"' }, 'excludeBody' => false
      )
      expect(bodies.first['secret']).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    end

    it 'deletes a webhook Jira registered without the secret, and says its events would not be signed' do
      stub_request(:post, webhook_api).to_return(registered(55, signed: false))
      delete = stub_request(:delete, "#{webhook_api}/55").to_return(status: 204, body: '')
      expect { trigger.provision }.to raise_error(
        IPaaS::Job::FailJob,
        'Jira registered webhook 55 without the secret, so its events are not signed, so iPaaS deleted it again.'
      )
      expect(delete).to have_been_requested.once
    end

    it 'names the Administer Jira permission when Jira refuses the registration' do
      stub_request(:post, webhook_api).to_return(status: 403, body: { errorMessages: ['Forbidden'] }.to_json)
      expect { trigger.provision }
        .to raise_error(IPaaS::Job::FailJob, /Forbidden\. The account needs the Administer Jira permission\./)
    end

    context 'with an issue type picked' do
      let(:trigger_config) { { project_key: 'KAN', issue_type: '10001', fire_on: ['jira:issue_updated'] } }

      it 'sends the project and the issue type as the JQL filter Jira reads' do
        jql = 'project = "KAN" AND issuetype = 10001'
        expected = { 'filters' => { filter_key => jql }, 'events' => ['jira:issue_updated'] }
        stub = stub_request(:post, webhook_api)
               .with { |request| JSON.parse(request.body).slice('filters', 'events', 'jqlFilter') == expected }
               .to_return(registered(55, jql: jql))
        trigger.provision
        expect(stub).to have_been_requested.once
      end
    end

    context 'with an issue type name instead of an ID' do
      let(:trigger_config) do
        { project_key: 'KAN', issue_type: 'Task" OR project = "OPS', fire_on: ['jira:issue_created'] }
      end

      it 'refuses it before anything reaches Jira' do
        expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /is not a Jira issue type ID/)
        expect(a_request(:post, webhook_api)).not_to have_been_made
      end
    end

    context 'with no events selected' do
      let(:trigger_config) { { project_key: 'KAN', fire_on: [] } }

      it 'refuses rather than subscribing to nothing' do
        expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /under Fire on/)
        expect(a_request(:post, /webhook/)).not_to have_been_made
      end
    end

    it 'says the webhook may have been registered when Jira does not answer the registration' do
      stub_request(:post, webhook_api).to_timeout
      expect { trigger.provision }
        .to raise_error(IPaaS::Job::FailJob, /\AJira did not answer \(.*\)\. The change may have been made/)
      expect(trigger.store.read('webhook')).to be_blank
    end

    it 'refuses a trigger address that is not HTTPS, because Jira refuses it too' do
      allow(trigger).to receive(:endpoint).and_return('http://ipaas.example/inbound/1')
      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /HTTPS addresses only/)
      expect(a_request(:post, webhook_api)).not_to have_been_made
    end

    it 'fails when Jira registers the webhook but returns no webhook ID' do
      stub_request(:post, webhook_api).to_return(status: 201, body: { isSigned: true }.to_json)
      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /returned no webhook ID/)
      expect(trigger.store.read('webhook')).to be_blank
    end

    it 'deletes the webhook again and fails when Jira drops the JQL filter' do
      stub_request(:post, webhook_api)
        .to_return(status: 201, body: { self: "#{webhook_api}/55", isSigned: true }.to_json)
      delete = stub_request(:delete, "#{webhook_api}/55").to_return(status: 204, body: '')
      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /webhook 55 without the JQL filter/)
      expect(delete).to have_been_requested.once
      expect(trigger.store.read('webhook')).to be_blank
    end

    it 'keeps the webhook ID without a secret when Jira registers it unsigned and refuses to delete it' do
      stub_request(:post, webhook_api).to_return(registered(55, signed: false))
      stub_request(:delete, "#{webhook_api}/55").to_return(status: 403, body: { errorMessages: ['No'] }.to_json)
      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /did not delete webhook 55/)
      stored = trigger.store.read('webhook')
      expect(stored[:replaces][:id]).to eq('55')
      expect(stored[:secret]).to be_nil
    end
  end

  describe 'deprovision' do
    it 'deletes the webhook it registered through the gateway and forgets it' do
      seed_stored_webhook(id: '55')
      stub = stub_request(:delete, "#{webhook_api}/55").to_return(status: 204, body: '')
      trigger.deprovision
      expect(stub).to have_been_requested.once
      expect(trigger.store.read('webhook')).to be_blank
    end

    it 'tries again later and keeps the webhook when Jira limits the rate' do
      seed_stored_webhook(id: '55')
      stub_request(:delete, "#{webhook_api}/55").to_return(status: 429, headers: { 'Retry-After' => '5' }, body: '')
      expect_reschedule_after(5) { trigger.deprovision }
      expect(trigger.store.read('webhook')).to be_present
    end

    it 'keeps the webhook and says it may have been deleted when Jira does not answer the delete' do
      seed_stored_webhook(id: '55')
      stub_request(:delete, "#{webhook_api}/55").to_timeout
      expect { trigger.deprovision }
        .to raise_error(IPaaS::Job::FailJob, /\AJira did not answer \(.*\)\. The change may have been made/)
      expect(trigger.store.read('webhook')[:id]).to eq('55')
    end

    it 'keeps the webhook and fails when no Jira site answers at the address of the connection' do
      stub_request(:get, tenant_info_url).to_return(status: 404, body: '')
      seed_stored_webhook(id: '55', host: 'acme.atlassian.net')
      expect { trigger.deprovision }.to raise_error(IPaaS::Job::FailJob, /No Jira Cloud site answers at acme/)
      expect(trigger.store.read('webhook')[:id]).to eq('55')
    end

    it 'does nothing when there is nothing stored' do
      trigger.deprovision
      expect(a_request(:delete, /atlassian/)).not_to have_been_made
    end

    it 'keeps the webhook and fails when Jira refuses to delete it' do
      seed_stored_webhook(id: '55')
      stub_request(:delete, "#{webhook_api}/55")
        .to_return(status: 403, body: { messages: [{ key: 'Not allowed' }] }.to_json)
      expect { trigger.deprovision }
        .to raise_error(IPaaS::Job::FailJob, /delete webhook 55 \(HTTP 403\): Not allowed\. Delete it in Jira/)
      expect(trigger.store.read('webhook')[:id]).to eq('55')
    end

    it 'asks to try again later instead of a delete by hand when Jira is briefly unavailable' do
      seed_stored_webhook(id: '55')
      stub_request(:delete, "#{webhook_api}/55").to_return(status: 503, body: 'down')
      expect { trigger.deprovision }.to raise_error(
        IPaaS::Job::FailJob,
        'Jira did not delete webhook 55 (HTTP 503): down. Jira is briefly unavailable. Try again in a few minutes.'
      )
      expect(trigger.store.read('webhook')[:id]).to eq('55')
    end

    it 'keeps the webhook and says where to delete it by hand when Jira refuses the token for webhooks' do
      seed_stored_webhook(id: '55')
      stub_request(:delete, "#{webhook_api}/55")
        .to_return(status: 401, body: { code: 401, message: 'Unauthorized' }.to_json)
      expect { trigger.deprovision }.to raise_error(
        IPaaS::Job::FailJob,
        'Jira did not delete webhook 55 (HTTP 401): Unauthorized. The API token is wrong, revoked or expired, or it ' \
        'is a scoped or service-account token: Jira manages webhooks only for a classic API token of a user with the ' \
        'Administer Jira permission. Delete webhook 55 in Jira on acme.atlassian.net under System, WebHooks, then ' \
        'try again.'
      )
      expect(trigger.store.read('webhook')[:id]).to eq('55')
    end

    context 'when the connection moved to another site after the webhook was registered' do
      let(:old_webhook) { 'https://api.atlassian.com/ex/jira/cloud-old/rest/webhooks/1.0/webhook/55' }
      let(:forgotten) do
        'iPaaS forgets webhook 55 on old.atlassian.net, because %s and the connection now points to ' \
          'acme.atlassian.net. Delete the webhook in Jira on old.atlassian.net under System, WebHooks.'
      end

      before do
        seed_stored_webhook(id: '55', host: 'old.atlassian.net')
        allow(trigger).to receive(:log)
      end

      def old_site_answers(cloud_id)
        stub_request(:get, 'https://old.atlassian.net/_edge/tenant_info')
          .to_return(status: 200, body: { cloudId: cloud_id }.to_json)
      end

      it 'forgets the webhook and logs where to delete it when the old site answers 401' do
        old_site_answers('cloud-old')
        stub_request(:delete, old_webhook).to_return(status: 401, body: { message: 'Unauthorized' }.to_json)
        trigger.deprovision
        expect(trigger.store.read('webhook')).to be_blank
        expect(trigger).to have_received(:log)
          .with(format(forgotten, 'Jira there refused to delete it (HTTP 401)'))
      end

      it 'forgets the webhook and logs where to delete it when the old site answers 403' do
        old_site_answers('cloud-old')
        stub_request(:delete, old_webhook).to_return(status: 403, body: { message: 'Forbidden' }.to_json)
        trigger.deprovision
        expect(trigger.store.read('webhook')).to be_blank
        expect(trigger).to have_received(:log)
          .with(format(forgotten, 'Jira there refused to delete it (HTTP 403)'))
      end

      it 'forgets the webhook and logs where to delete it when no Jira site answers at the old address' do
        stub_request(:get, 'https://old.atlassian.net/_edge/tenant_info').to_return(status: 404, body: '')
        trigger.deprovision
        expect(a_request(:delete, /webhook/)).not_to have_been_made
        expect(trigger.store.read('webhook')).to be_blank
        expect(trigger).to have_received(:log).with(format(forgotten, 'no Jira Cloud site answers there'))
      end

      it 'keeps the webhook and fails when the old address is another name of the same site' do
        old_site_answers('cloud-1')
        stub_request(:delete, "#{webhook_api}/55").to_return(status: 403, body: { message: 'Forbidden' }.to_json)
        expect { trigger.deprovision }.to raise_error(IPaaS::Job::FailJob, /did not delete webhook 55 \(HTTP 403\)/)
        expect(trigger.store.read('webhook')[:id]).to eq('55')
      end
    end

    it 'deletes the webhook on the site it was registered on' do
      stub_request(:get, 'https://old.atlassian.net/_edge/tenant_info')
        .to_return(status: 200, body: { cloudId: 'cloud-old' }.to_json)
      seed_stored_webhook(id: '55', host: 'old.atlassian.net')
      stub = stub_request(:delete, 'https://api.atlassian.com/ex/jira/cloud-old/rest/webhooks/1.0/webhook/55')
             .to_return(status: 204, body: '')
      trigger.deprovision
      expect(stub).to have_been_requested.once
    end
  end

  describe 'provision replacing an existing subscription' do
    before { stub_webhook_list }

    it 'registers the replacement before it deletes the previous webhook' do
      stub_request(:post, webhook_api).to_return(registered(55))
      trigger.provision

      WebMock.reset!
      stub_trigger_projects
      stub_webhook_list
      allow(trigger).to receive(:config).and_return({ project_key: 'KAN',
                                                      fire_on: %w[jira:issue_created jira:issue_updated], })
      calls = []
      stub_request(:delete, "#{webhook_api}/55").to_return do
        calls.push(:delete)
        { status: 204, body: '' }
      end
      stub_request(:post, webhook_api).to_return do
        calls.push(:post)
        registered(56)
      end
      trigger.provision
      expect(calls).to eq([:post, :delete])
      expect(trigger.store.read('webhook')[:id]).to eq('56')
    end

    it 'does not re-register when only the order of the same events changed' do
      allow(trigger).to receive(:config).and_return({ project_key: 'KAN',
                                                      fire_on: %w[jira:issue_updated jira:issue_created], })
      stub_request(:post, webhook_api).to_return(registered(55))
      trigger.provision
      WebMock.reset!
      stub_trigger_projects
      stub_webhook_list
      stub_request(:get, "#{webhook_api}/55").to_return(healthy)
      allow(trigger).to receive(:config).and_return({ project_key: 'KAN',
                                                      fire_on: %w[jira:issue_created jira:issue_updated], })
      trigger.provision
      expect(a_request(:post, webhook_api)).not_to have_been_made
    end

    it 'keeps the working webhook when Jira refuses the replacement' do
      seed_stored_webhook(id: '54', jql: 'project = "OLD"')
      stub_request(:post, webhook_api).to_return(status: 400, body: { errorMessages: ['Bad filter'] }.to_json)
      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /Bad filter/)
      expect(a_request(:delete, /webhook/)).not_to have_been_made
      expect(trigger.store.read('webhook')[:id]).to eq('54')
    end

    it 'keeps the old webhook for a later delete, and fails, when Jira refuses to delete it after the replacement' do
      seed_stored_webhook(id: '54', jql: 'project = "OLD"')
      stub_request(:post, webhook_api).to_return(registered(55))
      stub_request(:delete, "#{webhook_api}/54").to_return(status: 500, body: 'down')
      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /did not delete webhook 54/)
      stored = trigger.store.read('webhook')
      expect(stored[:id]).to eq('55')
      expect(stored[:replaces][:id]).to eq('54')
    end

    it 'deletes the old webhook first on the next provision when an earlier delete failed' do
      seed_stored_webhook(id: '54', jql: 'project = "OLD"')
      stub_request(:post, webhook_api).to_return(registered(55))
      stub_request(:delete, "#{webhook_api}/54").to_return(status: 500, body: 'down')
      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob)
      WebMock.reset!
      stub_trigger_projects
      stub_webhook_list
      delete = stub_request(:delete, "#{webhook_api}/54").to_return(status: 204, body: '')
      stub_request(:get, "#{webhook_api}/55").to_return(healthy)
      trigger.provision
      expect(delete).to have_been_requested.once
      expect(trigger.store.read('webhook')[:replaces]).to be_nil
    end

    it 'registers the replacement when Jira no longer has the old webhook' do
      seed_stored_webhook(id: '54', jql: 'project = "OLD"')
      stub_request(:delete, "#{webhook_api}/54")
        .to_return(status: 404, body: { messages: [{ key: 'Webhook with ID 54 does not exist.' }] }.to_json)
      stub_request(:post, webhook_api).to_return(registered(55))
      trigger.provision
      expect(trigger.store.read('webhook')[:id]).to eq('55')
    end

    it 'registers again when the connection moves to another Jira site' do
      stub_request(:post, webhook_api).to_return(registered(55))
      trigger.provision
      WebMock.reset!
      stub_trigger_projects
      stub_request(:get, 'https://acme.atlassian.net/_edge/tenant_info')
        .to_return(status: 200, body: { cloudId: 'cloud-1' }.to_json)
      stub_request(:get, 'https://beta.atlassian.net/_edge/tenant_info')
        .to_return(status: 200, body: { cloudId: 'cloud-2' }.to_json)
      outbound_connection.config[:site] = 'beta.atlassian.net'
      delete = stub_request(:delete, "#{webhook_api}/55").to_return(status: 204, body: '')
      create = stub_request(:post, 'https://api.atlassian.com/ex/jira/cloud-2/rest/webhooks/1.0/webhook')
               .to_return(registered(56))
      stub_webhook_list(url: 'https://api.atlassian.com/ex/jira/cloud-2/rest/webhooks/1.0/webhook')
      trigger.provision
      expect(delete).to have_been_requested.once
      expect(create).to have_been_requested.once
    end
  end

  describe 'respond_with' do
    before { allow(runbook).to receive(:trigger_output).and_return(nil) }

    it 'answers 503 with Retry-After when iPaaS dropped the event for the concurrency limit, so Jira sends it again' do
      response = trigger.respond_with(nil, nil, {}, { error: IPaaS::Job::DiscardTriggerEvent.new })
      expect(response[:status]).to eq(503)
      expect(response[:headers]['Retry-After']).to eq('60')
    end

    it 'answers 200 when the trigger itself discarded the event' do
      error = IPaaS::Job::DiscardTriggerEvent.new('Invalid Jira webhook signature')
      expect(trigger.respond_with(nil, nil, {}, { error: error })[:status]).to eq(200)
    end

    it 'answers 200 when iPaaS started a job' do
      job = double('job', uuid: 'job-1')
      expect(trigger.respond_with(nil, job, {}, {})[:status]).to eq(200)
    end
  end

  describe 'parse' do
    before { seed_stored_webhook }

    it 'accepts a correctly signed payload and reports the event' do
      output = signed_post(issue_payload, 'X-Atlassian-Webhook-Identifier' => 'id-1')
      expect(output[:result]).to be_nil
      expect(output[:webhook_event]).to eq('jira:issue_created')
      expect(output[:issue_key]).to eq('KAN-1')
      expect(output[:summary]).to eq('Build it')
      expect(output[:actor]).to include(account_id: 'acc-1', display_name: 'Bot')
      expect(output[:deduplication_id]).to eq('id-1')
      expect(runbook).to have_received(:store_job_context_identifier).with('KAN-1')
    end

    it 'names the status category as Get Issue does, though the webhook names it New' do
      status = { name: 'To Do', statusCategory: { key: 'new', name: 'New' } }
      output = signed_post(issue_payload.deep_merge(issue: { fields: { status: status } }))
      expect(output[:status_category]).to eq('To Do')
    end

    it 'keeps the name Jira sent for a status category it does not know' do
      status = { name: 'Parked', statusCategory: { key: 'parked', name: 'Parked' } }
      output = signed_post(issue_payload.deep_merge(issue: { fields: { status: status } }))
      expect(output[:status_category]).to eq('Parked')
    end

    it 'falls back to a synthesised deduplication id when Jira omits the header' do
      output = signed_post(issue_payload)
      expect(output[:deduplication_id]).to eq('jira:issue_created-1-1792000000000')
    end

    it 'discards a payload signed with the wrong secret' do
      body = issue_payload.to_json
      output = post_trigger(issue_payload,
                            headers: { 'X-Hub-Signature' => hub_signature(body, 'wrong-secret') })
      expect(output[:result]).to eq('Discarded')
    end

    it 'discards a payload carrying no signature at all' do
      output = post_trigger(issue_payload, headers: {})
      expect(output[:result]).to eq('Discarded')
    end

    it 'discards a body that is not JSON' do
      output = post_trigger('not json',
                            headers: { 'X-Hub-Signature' => hub_signature('not json') })
      expect(output[:result]).to eq('Discarded')
    end

    it 'discards an event the trigger did not subscribe to' do
      output = signed_post(issue_payload.merge(webhookEvent: 'comment_deleted'))
      expect(output[:result]).to eq('Discarded')
    end

    it 'discards an update when only Created is picked under Fire on' do
      output = signed_post(issue_payload.merge(webhookEvent: 'jira:issue_updated'))
      expect(output[:result]).to eq('Discarded')
    end

    it 'drops a signed delivery of an event that Jira sent more than a day ago' do
      old_time = (event_time - 2.days).to_i * 1000
      output = signed_post(issue_payload.merge(timestamp: old_time))
      expect(output[:result]).to eq('Discarded')
    end

    it 'reports the content type of each attachment on the issue' do
      attachment = { id: '10000', filename: 'report.csv', size: 12, mimeType: 'text/csv' }
      output = signed_post(issue_payload.deep_merge(issue: { fields: { attachment: [attachment] } }))
      expect(output[:attachments].first).to include(attachment_id: '10000', filename: 'report.csv',
                                                    content_type: 'text/csv')
    end

    it 'discards a payload with no webhookEvent' do
      output = signed_post(issue_payload.except(:webhookEvent))
      expect(output[:result]).to eq('Discarded')
    end

    it 'discards a delivery with an empty body' do
      output = post_trigger('', headers: { 'X-Hub-Signature' => hub_signature('') })
      expect(output[:result]).to eq('Discarded')
    end

    it 'drops an event of a webhook registered for another project, as after a refused re-registration' do
      seed_stored_webhook(jql: 'project = "OPS"')
      expect(signed_post(issue_payload)[:result]).to eq('Discarded')
    end

    context 'when the stored webhook has no secret' do
      before { trigger.store.write('webhook', { 'id' => '99', 'signature' => 'seeded' }) }

      it 'discards a delivery signed with an empty key instead of trusting the route' do
        output = post_signed_with('')
        expect(output[:result]).to eq('Discarded')
      end
    end

    it 'reports the changed fields and the event type of an update' do
      change = { field: 'priority', fieldId: 'priority', from: '3', fromString: 'Medium', to: '2', toString: 'High' }
      payload = issue_payload.merge(webhookEvent: 'jira:issue_updated', issue_event_type_name: 'issue_assigned',
                                    changelog: { id: '10301', items: [change] })
      allow(trigger).to receive(:config).and_return({ project_key: 'KAN', fire_on: ['jira:issue_updated'] })
      output = signed_post(payload)
      expect(output[:issue_event_type_name]).to eq('issue_assigned')
      expect(output[:changelog]).to eq([{ field: 'priority', field_id: 'priority', from: '3', from_string: 'Medium',
                                          to: '2', to_string: 'High', }])
    end

    context 'when the issue has a description' do
      let(:payload) { issue_payload.deep_merge(issue: { fields: { description: 'Hello *world*' } }) }
      let(:description_url) { "#{api}/issue/1?fields=description" }

      before { outbound_connection.store.write('cloud_id:acme.atlassian.net', 'cloud-1') }

      it 'reports the description as plain text read from Jira instead of the wiki markup Jira sent' do
        words = [{ type: 'text', text: 'Hello ' }, { type: 'text', text: 'world', marks: [{ type: 'strong' }] }]
        adf = { type: 'doc', content: [{ type: 'paragraph', content: words }] }
        stub_request(:get, description_url).to_return(status: 200, body: { fields: { description: adf } }.to_json)
        output = signed_post(payload)
        expect(output[:description]).to eq('Hello world')
        expect(output[:text_unavailable_reason]).to be_nil
      end

      it 'leaves the description empty and names the reason when the account cannot see the issue' do
        stub_request(:get, description_url).to_return(status: 404, body: { errorMessages: ['Not found'] }.to_json)
        output = signed_post(payload)
        expect(output[:issue_key]).to eq('KAN-1')
        expect(output[:description]).to be_nil
        expect(output[:text_unavailable_reason]).to eq('not_visible')
      end

      it 'keeps the description Jira sent out of Fields when the account cannot see the issue' do
        stub_request(:get, description_url).to_return(status: 404, body: { errorMessages: ['Not found'] }.to_json)
        output = signed_post(payload)
        expect(output[:fields]).to include(summary: 'Build it')
        expect(output[:fields]).not_to have_key(:description)
      end

      it 'delivers the text Jira sent, turned from wiki markup into plain text, when Jira rejects the credentials' do
        stub_request(:get, description_url).to_return(status: 401, body: { code: 401, message: 'Unauthorized' }.to_json)
        output = signed_post(payload)
        expect(output).to include(issue_key: 'KAN-1', description: 'Hello world',
                                  text_unavailable_reason: 'fetch_failed')
      end

      it 'delivers the text Jira sent when Jira answers with a page that is not JSON' do
        stub_request(:get, description_url).to_return(status: 200, body: '<html>maintenance</html>')
        output = signed_post(payload)
        expect(output).to include(description: 'Hello world', text_unavailable_reason: 'fetch_failed')
      end

      it 'delivers the text Jira sent when Jira limits the rate, rather than refusing an event it may not resend' do
        stub_request(:get, description_url).to_return(status: 429, headers: { 'Retry-After' => '30' }, body: '')
        output = trigger.parse_request(signed_request(payload))
        expect(output).to include(description: 'Hello world', text_unavailable_reason: 'fetch_failed')
      end

      it 'delivers the text Jira sent when the connection has no API token, as Jira resends no refused event' do
        outbound_connection.config[:api_token] = nil
        output = signed_post(payload)
        expect(output).to include(description: 'Hello world', text_unavailable_reason: 'fetch_failed')
      end

      it 'delivers the text Jira sent when Jira does not answer in time' do
        stub_request(:get, description_url).to_timeout
        output = trigger.parse_request(signed_request(payload))
        expect(output).to include(description: 'Hello world', text_unavailable_reason: 'fetch_failed')
      end

      it 'delivers the text Jira sent without calling Jira when the cloud ID of the site is not known yet' do
        outbound_connection.store.delete('cloud_id:acme.atlassian.net')
        output = signed_post(payload)
        expect(output).to include(description: 'Hello world', text_unavailable_reason: 'fetch_failed')
        expect(a_request(:get, description_url)).not_to have_been_made
        expect(a_request(:get, tenant_info_url)).not_to have_been_made
      end
    end
  end
end
