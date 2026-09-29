require 'spec_helper'

describe 'Microsoft Outlook New Email Received Trigger', :trigger, :microsoft_outlook do
  let(:trigger_template_id) { 'b5822f83-0da0-4140-80c9-dfd814db980e' }
  let(:trigger_config) { {} }
  let(:subscribe_url) { 'https://graph.microsoft.com/v1.0/subscriptions' }
  let(:message_url) { "https://graph.microsoft.com/v1.0/users/#{default_mailbox}/messages/msg-1" }

  describe 'config_schema' do
    it 'defaults folder to inbox' do
      expect(trigger.config_schema.field(:folder).default).to eq('inbox')
    end

    it 'defaults include_html_body to true and the other toggles to false' do
      expect(trigger.config_schema.field(:include_html_body).default).to eq(true)
      expect(trigger.config_schema.field(:download_attachments).default).to eq(false)
      expect(trigger.config_schema.field(:mark_as_read).default).to eq(false)
    end
  end

  describe 'provision' do
    before { stub_graph_token }

    it 'creates a subscription on the Default mailbox inbox and stores the id and client state' do
      stub = stub_request(:post, subscribe_url)
             .with(body: hash_including(
               'changeType' => 'created',
               'notificationUrl' => trigger.endpoint,
               'resource' => "users/#{default_mailbox}/mailFolders('inbox')/messages",
             ))
             .to_return(status: 201, body: { id: 'sub-1' }.to_json)

      trigger.provision

      expect(stub).to have_been_requested.once
      expect(outbound_connection.store.read("outlook_mail_subscription_id-#{trigger.runbook.uuid}")).to eq('sub-1')
      expect(outbound_connection.store.read("outlook_mail_client_state-#{trigger.runbook.uuid}")).to be_present
    end

    context 'with a custom folder configured' do
      let(:trigger_config) { { folder: 'archive' } }

      it 'subscribes to the configured folder' do
        stub = stub_request(:post, subscribe_url)
               .with(body: hash_including('resource' => "users/#{default_mailbox}/mailFolders('archive')/messages"))
               .to_return(status: 201, body: { id: 'sub-1' }.to_json)

        trigger.provision

        expect(stub).to have_been_requested.once
      end
    end

    it 'deletes an existing stored subscription before creating a new one, avoiding an orphan' do
      outbound_connection.store.write("outlook_mail_subscription_id-#{trigger.runbook.uuid}", 'old-sub')
      delete_stub = stub_request(:delete, "#{subscribe_url}/old-sub").to_return(status: 204)
      create_stub = stub_request(:post, subscribe_url).to_return(status: 201, body: { id: 'new-sub' }.to_json)

      trigger.provision

      expect(delete_stub).to have_been_requested.once
      expect(create_stub).to have_been_requested.once
      expect(outbound_connection.store.read("outlook_mail_subscription_id-#{trigger.runbook.uuid}")).to eq('new-sub')
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

    it 'deletes the stored subscription and clears the store' do
      outbound_connection.store.write("outlook_mail_subscription_id-#{trigger.runbook.uuid}", 'sub-1')
      outbound_connection.store.write("outlook_mail_client_state-#{trigger.runbook.uuid}", 'state-1')
      stub = stub_request(:delete, "#{subscribe_url}/sub-1").to_return(status: 204)

      trigger.deprovision

      expect(stub).to have_been_requested.once
      expect(outbound_connection.store.read("outlook_mail_subscription_id-#{trigger.runbook.uuid}")).to be_blank
      expect(outbound_connection.store.read("outlook_mail_client_state-#{trigger.runbook.uuid}")).to be_blank
    end

    it 'tolerates an already-gone subscription (404 or 410)' do
      outbound_connection.store.write("outlook_mail_subscription_id-#{trigger.runbook.uuid}", 'sub-1')
      stub_request(:delete, "#{subscribe_url}/sub-1").to_return(status: 410)

      expect { trigger.deprovision }.not_to raise_error
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

    it 'fails on an empty request body instead of crashing' do
      output = post_trigger(nil)
      expect(output[:error]).to eq('Microsoft Graph notification contained no items.')
    end

    it 'fails when a notification is missing a message id' do
      outbound_connection.store.write("outlook_mail_client_state-#{trigger.runbook.uuid}", 'expected-state')
      output = post_trigger({ value: [{ subscriptionId: 'sub-1', clientState: 'expected-state' }] })
      expect(output[:error]).to eq('Microsoft Graph notification did not include a message id.')
    end

    it 'rejects the notification when no client state has ever been stored (fail closed)' do
      output = post_trigger({ value: [{ clientState: 'anything', resourceData: { id: 'msg-1' } }] })
      expect(output[:error]).to match(/clientState did not match/)
    end

    context 'with a stored client state' do
      before do
        outbound_connection.store.write("outlook_mail_client_state-#{trigger.runbook.uuid}", 'expected-state')
        stub_graph_token
      end

      it 'fetches and maps the new message' do
        stub_request(:get, message_url).to_return(status: 200, body: {
          id: 'msg-1', subject: 'Hello', hasAttachments: false,
          from: { emailAddress: { address: 'bob@contoso.com', name: 'Bob' } },
          body: { contentType: 'html', content: '<p>Hi</p>' },
        }.to_json)

        output = post_trigger({
          value: [{ subscriptionId: 'sub-1', clientState: 'expected-state', resourceData: { id: 'msg-1' } }],
        })

        expect(output[:message_id]).to eq('msg-1')
        expect(output[:subject]).to eq('Hello')
        expect(output[:from_address]).to eq('bob@contoso.com')
        expect(output[:html_body]).to eq('<p>Hi</p>')
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

      context 'with mark_as_read enabled' do
        let(:trigger_config) { { mark_as_read: true } }

        it 'marks the message as read after retrieving it' do
          stub_request(:get, message_url).to_return(status: 200, body: { id: 'msg-1' }.to_json)
          patch_stub = stub_request(:patch, message_url).with(body: { isRead: true }.to_json)
                                                        .to_return(status: 200, body: '{}')

          post_trigger({ value: [{ clientState: 'expected-state', resourceData: { id: 'msg-1' } }] })

          expect(patch_stub).to have_been_requested.once
        end
      end

      context 'with download_attachments enabled' do
        let(:trigger_config) { { download_attachments: true } }
        let(:attachments_url) { "#{message_url}/attachments" }

        it 'fetches attachment content when the message has attachments' do
          stub_request(:get, message_url).to_return(status: 200, body: { id: 'msg-1', hasAttachments: true }.to_json)
          stub_request(:get, attachments_url).to_return(status: 200, body: { value: [
            { id: 'att-1', name: 'file.pdf', contentBytes: 'abc123' },
          ] }.to_json)

          output = post_trigger({ value: [{ clientState: 'expected-state', resourceData: { id: 'msg-1' } }] })

          expect(output[:attachments]).to eq([{ attachment_id: 'att-1', name: 'file.pdf', size_in_bytes: nil,
                                                content_type: nil, is_inline: nil, content_bytes: 'abc123', }])
        end

        it 'does not fetch attachments when the message reports none' do
          stub_request(:get, message_url).to_return(status: 200, body: { id: 'msg-1', hasAttachments: false }.to_json)

          output = post_trigger({ value: [{ clientState: 'expected-state', resourceData: { id: 'msg-1' } }] })

          expect(output[:attachments]).to be_nil
        end
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
