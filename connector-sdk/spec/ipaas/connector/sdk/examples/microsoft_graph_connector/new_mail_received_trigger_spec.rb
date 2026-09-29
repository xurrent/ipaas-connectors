require 'spec_helper'

describe 'Microsoft Graph New Mail Received Trigger', :trigger, :microsoft_graph do
  let(:trigger_template_id) { '019ff9e8-8af5-7641-b431-cff496f653ae' }
  let(:trigger_config) { { mailbox_user_id: 'jane@contoso.com' } }

  describe 'config_schema' do
    it 'requires mailbox_user_id' do
      expect(trigger.config_schema.field(:mailbox_user_id).required).to be_truthy
    end

    it 'defaults folder to inbox' do
      expect(trigger.config_schema.field(:folder).default).to eq('inbox')
    end
  end

  describe 'provision' do
    let(:subscribe_url) { 'https://graph.microsoft.com/v1.0/subscriptions' }

    before { stub_graph_token }

    it 'creates a Microsoft Graph subscription on the inbox and stores the id and client state' do
      stub = stub_request(:post, subscribe_url)
             .with(body: hash_including(
               'changeType' => 'created',
               'notificationUrl' => trigger.endpoint,
               'resource' => "users/jane@contoso.com/mailFolders('inbox')/messages"
             ))
             .to_return(status: 201, body: { id: 'sub-1' }.to_json)

      trigger.provision

      expect(stub).to have_been_requested.once
      expect(outbound_connection.store.read("graph_mail_subscription_id-#{trigger.runbook.uuid}")).to eq('sub-1')
      expect(outbound_connection.store.read("graph_mail_client_state-#{trigger.runbook.uuid}")).to be_present
    end

    context 'with a custom folder configured' do
      let(:trigger_config) { { mailbox_user_id: 'jane@contoso.com', folder: 'archive' } }

      it 'subscribes to the configured folder' do
        stub = stub_request(:post, subscribe_url)
               .with(body: hash_including('resource' => "users/jane@contoso.com/mailFolders('archive')/messages"))
               .to_return(status: 201, body: { id: 'sub-1' }.to_json)

        trigger.provision

        expect(stub).to have_been_requested.once
      end
    end

    it 'fails when Microsoft Graph rejects the subscription' do
      stub_request(:post, subscribe_url)
        .to_return(status: 400, body: { error: { code: 'InvalidRequest', message: 'Invalid resource.' } }.to_json)

      expect { trigger.provision }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [InvalidRequest]: Invalid resource.')
    end
  end

  describe 'deprovision' do
    before { stub_graph_token }

    it 'deletes the stored subscription' do
      outbound_connection.store.write("graph_mail_subscription_id-#{trigger.runbook.uuid}", 'sub-1')
      stub = stub_request(:delete, 'https://graph.microsoft.com/v1.0/subscriptions/sub-1').to_return(status: 204)

      trigger.deprovision

      expect(stub).to have_been_requested.once
    end

    it 'does nothing when no subscription has been stored' do
      expect { trigger.deprovision }.not_to raise_error
    end
  end

  describe 'parse request' do
    it 'answers the Microsoft Graph validation handshake and creates no job' do
      output = post_trigger(nil, params: { validationToken: 'abc-token' })
      expect(output).to eq({ result: 'Discarded' })
    end

    it 'fails when the notification contains no items' do
      output = post_trigger({ value: [] })
      expect(output[:error]).to eq('Microsoft Graph notification contained no items.')
    end

    it 'fails when a notification is missing a message id' do
      output = post_trigger({ value: [{ subscriptionId: 'sub-1' }] })
      expect(output[:error]).to eq('Microsoft Graph notification did not include a message id.')
    end

    context 'with a stored client state' do
      let(:message_url) { 'https://graph.microsoft.com/v1.0/users/jane@contoso.com/messages/msg-1' }

      before do
        outbound_connection.store.write("graph_mail_client_state-#{trigger.runbook.uuid}", 'expected-state')
        stub_graph_token
      end

      it 'fetches and maps the new message' do
        stub_request(:get, message_url).to_return(status: 200, body: {
          id: 'msg-1',
          subject: 'Hello',
          bodyPreview: 'Hi there',
          from: { emailAddress: { address: 'bob@contoso.com', name: 'Bob' } },
          receivedDateTime: '2026-08-01T00:00:00Z',
          hasAttachments: false,
          importance: 'normal',
          webLink: 'https://outlook.office.com/mail/msg-1',
        }.to_json)

        output = post_trigger({
          value: [{ subscriptionId: 'sub-1', clientState: 'expected-state', resourceData: { id: 'msg-1' } }],
        })

        expect(output[:message_id]).to eq('msg-1')
        expect(output[:subject]).to eq('Hello')
        expect(output[:body_preview]).to eq('Hi there')
        expect(output[:from_address]).to eq('bob@contoso.com')
        expect(output[:from_name]).to eq('Bob')
        expect(output[:has_attachments]).to eq(false)
      end

      it 'fails when clientState does not match the stored value' do
        output = post_trigger({
          value: [{ subscriptionId: 'sub-1', clientState: 'wrong-state', resourceData: { id: 'msg-1' } }],
        })

        expect(output[:error]).to match(/clientState did not match/)
      end

      it 'processes only the first notification when several arrive in one call' do
        stub_request(:get, message_url).to_return(status: 200, body: { id: 'msg-1', subject: 'First' }.to_json)

        output = post_trigger({
          value: [
            { subscriptionId: 'sub-1', clientState: 'expected-state', resourceData: { id: 'msg-1' } },
            { subscriptionId: 'sub-1', clientState: 'expected-state', resourceData: { id: 'msg-2' } },
          ],
        })

        expect(output[:message_id]).to eq('msg-1')
      end
    end
  end

  describe 'respond_with' do
    before do
      allow(runbook).to receive(:trigger_output).and_return({})
    end

    it 'echoes back the validationToken as plain text, bypassing the default response' do
      request = double.tap { |r| allow(r).to receive(:params).and_return({ 'validationToken' => 'abc-token' }) }

      result = trigger.respond_with(request, nil, {})

      expect(result[:status]).to eq(200)
      expect(result[:headers]['content-type']).to eq('text/plain; charset=utf-8')
      expect(result[:body]).to eq('abc-token')
    end

    it 'leaves the default response untouched for normal notifications' do
      request = double.tap { |r| allow(r).to receive(:params).and_return({}) }
      job = double(uuid: 'job-1')

      result = trigger.respond_with(request, job, {})

      expect(result[:status]).to eq(200)
      expect(result[:body]).to eq('{"job_uuid":"job-1"}')
    end
  end
end
