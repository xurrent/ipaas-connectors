require 'spec_helper'

describe 'Microsoft Outlook New Shared Mailbox Email Received Trigger', :trigger, :microsoft_outlook do
  let(:trigger_template_id) { '07305bda-b00d-49c7-ac3f-00dd31eebdaf' }
  let(:shared_mailbox) { 'helpdesk@contoso.com' }
  let(:trigger_config) { { shared_mailbox_address: shared_mailbox } }
  let(:subscribe_url) { 'https://graph.microsoft.com/v1.0/subscriptions' }
  let(:inbox_url) { "https://graph.microsoft.com/v1.0/users/#{shared_mailbox}/mailFolders/inbox" }
  let(:message_url) { "https://graph.microsoft.com/v1.0/users/#{shared_mailbox}/messages/msg-1" }

  describe 'config_schema' do
    it 'requires shared_mailbox_address' do
      expect(trigger.config_schema.field(:shared_mailbox_address).required).to be_truthy
    end

    it 'defaults folder to inbox' do
      expect(trigger.config_schema.field(:folder).default).to eq('inbox')
    end
  end

  describe 'provision' do
    before do
      stub_graph_token
      stub_request(:get, inbox_url).to_return(status: 200, body: { id: 'inbox-id' }.to_json)
    end

    it 'creates a subscription on the shared mailbox after the preflight access check' do
      stub = stub_request(:post, subscribe_url)
             .with(body: hash_including(
               'resource' => "users/#{shared_mailbox}/mailFolders('inbox')/messages",
             ))
             .to_return(status: 201, body: { id: 'sub-1' }.to_json)

      trigger.provision

      expect(stub).to have_been_requested.once
      expect(outbound_connection.store.read("outlook_mail_subscription_id-#{trigger.runbook.uuid}")).to eq('sub-1')
    end

    it 'fails with a clear message when the connection lacks access to the shared mailbox' do
      stub_request(:get, inbox_url).to_return(status: 403, body: '')

      expect { trigger.provision }
        .to raise_error(IPaaS::Job::FailJob, "This connection does not have access to #{shared_mailbox}.")
    end
  end

  describe 'deprovision' do
    before { stub_graph_token }

    it 'deletes the stored subscription' do
      outbound_connection.store.write("outlook_mail_subscription_id-#{trigger.runbook.uuid}", 'sub-1')
      stub = stub_request(:delete, "#{subscribe_url}/sub-1").to_return(status: 204)

      trigger.deprovision

      expect(stub).to have_been_requested.once
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
      outbound_connection.store.write("outlook_mail_client_state-#{trigger.runbook.uuid}", 'expected-state')
      output = post_trigger({ value: [{ clientState: 'expected-state' }] })
      expect(output[:error]).to eq('Microsoft Graph notification did not include a message id.')
    end

    context 'with a stored client state' do
      before do
        outbound_connection.store.write("outlook_mail_client_state-#{trigger.runbook.uuid}", 'expected-state')
        stub_graph_token
      end

      it 'fetches and maps the new message from the shared mailbox' do
        stub_request(:get, message_url).to_return(status: 200, body: { id: 'msg-1', subject: 'Hello' }.to_json)

        output = post_trigger({ value: [{ clientState: 'expected-state', resourceData: { id: 'msg-1' } }] })

        expect(output[:message_id]).to eq('msg-1')
        expect(output[:subject]).to eq('Hello')
      end

      it 'fails when clientState does not match the stored value' do
        output = post_trigger({ value: [{ clientState: 'wrong-state', resourceData: { id: 'msg-1' } }] })
        expect(output[:error]).to match(/clientState did not match/)
      end

      it 'processes only the first notification when several arrive in one call' do
        stub_request(:get, message_url).to_return(status: 200, body: { id: 'msg-1', subject: 'First' }.to_json)

        output = post_trigger({
          value: [
            { clientState: 'expected-state', resourceData: { id: 'msg-1' } },
            { clientState: 'expected-state', resourceData: { id: 'msg-2' } },
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
