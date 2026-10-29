require 'spec_helper'

describe 'Microsoft Outlook New Email Received Trigger', :trigger do
  let(:trigger_template_id) { '5e6feeca-3703-414d-bcf6-2be3aa66ae50' }
  let(:tenant_id) { '9c46a35a-b7cd-42ef-9ce5-9ea1481d40f1' }
  let(:mailbox) { 'adele@contoso.com' }
  let(:subscription_id) { '0fc0f4a5-3f6e-4bc5-9d1a-52e2c5b81e0c' }
  let(:client_state) { 'ca1fe1f8-4a51-4a45-9d2a-8b1a1de0b7c2' }
  let(:renewed_subscription_id) { '7a1c2b3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d' }
  let(:renewed_client_state) { 'd2c4e6f8-1a3b-4c5d-8e7f-0a1b2c3d4e5f' }
  let(:renewed_expiry) { '2026-10-22T09:00:00Z' }
  let(:token_url) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token" }
  let(:subscription_url) { "https://graph.microsoft.com/v1.0/subscriptions/#{subscription_id}" }
  let(:other_endpoint) { 'https://ipaas.example.com/inbound/1/solution/another-runbook' }
  let(:other_row) do
    { 'resource' => 'users/bob@contoso.com/mailFolders/inbox/messages', 'mailbox' => 'bob@contoso.com',
      'folder' => 'inbox', 'endpoint' => other_endpoint, 'id' => 'b6b2b0d1-6f1a-4a1e-9a01-7c3e0f9a55aa', }
  end

  let(:outbound_connection_config) do
    {
      credentials: {
        tenant_id: tenant_id,
        client_id: 'client-abc',
        client_secret: make_secret_string('secret-def'),
      },
      cloud: 'Global',
      default_mailbox: 'someone-else@contoso.com',
    }
  end

  let(:trigger_config) { { mailbox: mailbox, folder: 'inbox' } }

  def notification(overrides = {})
    {
      subscriptionId: subscription_id,
      changeType: 'created',
      resource: "users/#{mailbox}/mailFolders/inbox/messages",
      clientState: client_state,
      resourceData: { id: 'AAMkAGQz=' },
    }.merge(overrides)
  end

  def graph_request(body, query: '', content_type: 'application/json')
    env = Rack::MockRequest.env_for("/inbound?#{query}", method: 'POST', input: body,
                                                         'CONTENT_TYPE' => content_type)
    Rack::Request.new(env)
  end

  def store_rows(rows)
    trigger.outbound_connection.store.write(MicrosoftOutlookConnector::SUBSCRIPTIONS_STORE_KEY, rows)
  end

  def key
    trigger.runbook.uuid
  end

  def watch(folder = 'inbox', mailbox: self.mailbox)
    { 'resource' => "users/#{mailbox}/mailFolders/#{folder}/messages", 'mailbox' => mailbox, 'folder' => folder,
      'endpoint' => trigger.endpoint, }
  end

  def legacy_watch(folder = 'inbox')
    watch(folder).except('endpoint')
  end

  def subscribed(row, id: subscription_id, secret: client_state)
    row.merge('id' => id, 'client_state' => make_secret_string(secret).to_s)
  end

  def store_subscription(folder: 'inbox', others: {})
    store_rows(others.merge(key => subscribed(watch(folder))))
  end

  def store_legacy_subscription(others: {})
    store_rows(others.merge(trigger.endpoint => subscribed(legacy_watch)))
  end

  def store_between_provision_reads(row)
    reads = 0
    allow(trigger.outbound_connection.store).to receive(:read).and_wrap_original do |read, *arguments|
      reads += 1
      store_rows(key => row) if reads == 2
      read.call(*arguments)
    end
    -> { reads }
  end

  def stored_rows
    trigger.outbound_connection.store.read(MicrosoftOutlookConnector::SUBSCRIPTIONS_STORE_KEY) || {}
  end

  def stored_row
    stored_rows[key]
  end

  def stub_delete(status: 204, body: '')
    stub_request(:delete, subscription_url).to_return(status: status, body: body)
  end

  before(:each) do
    stub_request(:post, token_url)
      .to_return(status: 200, body: { access_token: 'outlook-token', expires_in: 3599 }.to_json)
  end

  describe 'provision' do
    it 'records what to watch, and the address Microsoft calls, under the runbook of this trigger' do
      trigger.provision
      expect(stored_row).to eq(watch)
    end

    it 'records the trigger mailbox, not the connection default mailbox' do
      trigger.provision
      expect(stored_row['mailbox']).to eq(mailbox)
    end

    it 'calls Microsoft for nothing, so deploying needs no answer from this endpoint' do
      trigger.provision
      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'keeps the watch Microsoft already holds when nothing about the trigger changed' do
      store_subscription
      trigger.provision
      expect(stored_row['id']).to eq(subscription_id)
      expect(new_secret_string(stored_row['client_state']).decrypt).to eq(client_state)
    end

    it 'deletes the watch Microsoft holds, and forgets it, when the folder changed' do
      store_subscription
      stub_delete
      trigger.config[:folder] = 'archive'
      trigger.provision
      expect(a_request(:delete, subscription_url)).to have_been_made.once
      expect(stored_row).to eq(watch('archive'))
    end

    it 'deletes the watch Microsoft holds, and forgets it, when the mailbox changed' do
      store_subscription
      stub_delete
      trigger.config[:mailbox] = 'bob@contoso.com'
      trigger.provision
      expect(a_request(:delete, subscription_url)).to have_been_made.once
      expect(stored_row).to eq(watch(mailbox: 'bob@contoso.com'))
    end

    it 'keeps the row, and its id, when Microsoft refuses to delete the watch the change replaces' do
      store_subscription
      stub_delete(status: 403, body: { error: { code: 'ErrorAccessDenied', message: 'Access is denied.' } }.to_json)
      trigger.config[:folder] = 'archive'
      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /ErrorAccessDenied/)
      expect(stored_row['id']).to eq(subscription_id)
      expect(stored_row['folder']).to eq('inbox')
    end

    it 'leaves the rows of other triggers on the connection alone' do
      store_rows(other_endpoint => other_row)
      trigger.provision
      expect(stored_rows).to eq(other_endpoint => other_row, key => watch)
    end

    it 'takes over a row an earlier version filed under the trigger address, with its watch and its client state' do
      store_legacy_subscription
      trigger.provision
      expect(stored_rows.keys).to eq([key])
      expect(stored_row['id']).to eq(subscription_id)
      expect(stored_row['endpoint']).to eq(trigger.endpoint)
      expect(new_secret_string(stored_row['client_state']).decrypt).to eq(client_state)
      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'writes nothing when nothing about the trigger changed' do
      store_subscription
      expect(trigger.outbound_connection.store).not_to receive(:write)
      trigger.provision
    end

    it 'deletes the watch Microsoft holds, and records afresh, when the address Microsoft calls changed' do
      store_rows(key => watch.merge('endpoint' => 'https://old.example.com/inbound/1/solution/runbook',
                                    'id' => subscription_id))
      stub_delete
      trigger.provision
      expect(a_request(:delete, subscription_url)).to have_been_made.once
      expect(stored_row).to eq(watch)
    end

    it 'keeps a row another trigger recorded while Microsoft was deleting the watch the change replaces' do
      store_subscription
      stub_request(:delete, subscription_url).to_return do
        store_rows(stored_rows.merge(other_endpoint => other_row))
        { status: 204, body: '' }
      end
      trigger.config[:folder] = 'archive'
      trigger.provision
      expect(stored_rows).to eq(other_endpoint => other_row, key => watch('archive'))
    end

    it 'keeps the subscription a renew run stored while provision ran, when nothing about the trigger changed' do
      store_subscription
      renewed = subscribed(watch, id: renewed_subscription_id, secret: renewed_client_state)
                .merge('expires_at' => renewed_expiry)
      reads = store_between_provision_reads(renewed)
      trigger.provision
      expect(reads.call).to eq(2)
      expect(stored_rows.keys).to eq([key])
      expect(stored_row['id']).to eq(renewed_subscription_id)
      expect(stored_row['expires_at']).to eq(renewed_expiry)
      expect(new_secret_string(stored_row['client_state']).decrypt).to eq(renewed_client_state)
    end

    it 'writes only its own watch when the row watches another folder by the time provision writes' do
      store_subscription
      reads = store_between_provision_reads(subscribed(watch('drafts'), id: renewed_subscription_id))
      trigger.provision
      expect(reads.call).to eq(2)
      expect(stored_rows).to eq(key => watch)
    end

    it 'records the new watch, and no subscription, when a renew run stored one while Microsoft was deleting the old' do
      store_subscription
      stub_request(:delete, subscription_url).to_return do
        store_rows(key => subscribed(watch, id: renewed_subscription_id, secret: renewed_client_state))
        { status: 204, body: '' }
      end
      trigger.config[:folder] = 'archive'
      trigger.provision
      expect(stored_row).to eq(watch('archive'))
    end

    it 'refuses a folder that is a display name rather than a well-known name or a folder id' do
      trigger.config[:folder] = 'Sent Items'
      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /is not a well-known name/)
      expect(stored_row).to be_nil
    end

    it 'refuses a URL postfix, because it would move the address the row is filed under' do
      trigger.config[:url_postfix] = 'extra'
      expect { trigger.provision }
        .to raise_error(IPaaS::Job::FailJob, /takes no URL postfix.*Clear URL postfix and try again/)
      expect(stored_rows).to eq({})
      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'refuses an empty URL postfix too, because an empty postfix still ends the address with a slash' do
      trigger.config[:url_postfix] = ''
      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /takes no URL postfix/)
      expect(stored_rows).to eq({})
    end
  end

  describe 'deprovision' do
    it 'deletes the watch and removes the row' do
      store_subscription
      stub_delete
      trigger.deprovision
      expect(a_request(:delete, subscription_url)).to have_been_made
      expect(stored_row).to be_nil
    end

    it 'treats a 404 as already gone and still removes the row' do
      store_subscription
      stub_delete(status: 404,
                  body: { error: { code: 'ResourceNotFound', message: 'The object was not found.' } }.to_json)
      trigger.deprovision
      expect(stored_row).to be_nil
    end

    it 'removes a row that holds no watch yet, and calls Microsoft for nothing' do
      trigger.provision
      trigger.deprovision
      expect(stored_row).to be_nil
      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'sends nothing and raises nothing when this trigger has no row' do
      expect { trigger.deprovision }.not_to raise_error
      expect(a_request(:delete, %r{/subscriptions/})).not_to have_been_made
    end

    it 'writes nothing when this trigger has no row, so the rows of other triggers are never rewritten for it' do
      store_rows(other_endpoint => other_row)
      expect(trigger.outbound_connection.store).not_to receive(:write)
      trigger.deprovision
    end

    it 'keeps the row when Microsoft refuses the delete' do
      store_subscription
      stub_delete(status: 403, body: { error: { code: 'AccessDenied', message: 'Forbidden.' } }.to_json)
      expect { trigger.deprovision }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned HTTP 403 AccessDenied: Forbidden.')
      expect(stored_row['id']).to eq(subscription_id)
    end

    it 'refuses a URL postfix and leaves the row and the subscription in place' do
      store_subscription
      trigger.config[:url_postfix] = 'extra'
      expect { trigger.deprovision }.to raise_error(IPaaS::Job::FailJob, /takes no URL postfix/)
      expect(stored_row['id']).to eq(subscription_id)
      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'leaves the rows of other triggers on the connection alone' do
      store_subscription(others: { other_endpoint => other_row })
      stub_delete
      trigger.deprovision
      expect(stored_rows).to eq(other_endpoint => other_row)
    end

    it 'deletes the watches of its own row and of a row an earlier version filed under the trigger address' do
      store_subscription(others: { trigger.endpoint => subscribed(legacy_watch, id: other_row['id']) })
      stub_delete
      stub_request(:delete, "https://graph.microsoft.com/v1.0/subscriptions/#{other_row['id']}").to_return(status: 204)
      trigger.deprovision
      expect(a_request(:delete, subscription_url)).to have_been_made.once
      expect(a_request(:delete, %r{/subscriptions/#{other_row['id']}})).to have_been_made.once
      expect(stored_rows).to eq({})
    end

    it 'keeps a row another trigger recorded while Microsoft was deleting the watch' do
      store_subscription
      stub_request(:delete, subscription_url).to_return do
        store_rows(stored_rows.merge(other_endpoint => other_row))
        { status: 204, body: '' }
      end
      trigger.deprovision
      expect(stored_rows).to eq(other_endpoint => other_row)
    end
  end

  describe 'the ownership handshake' do
    before(:each) { allow(runbook).to receive(:trigger_output).and_return({}) }

    it 'echoes back the exact validation token Microsoft sent, as text/plain' do
      request = graph_request('', query: "validationToken=#{CGI.escape('tok:en with spaces')}")
      captured = nil
      begin
        trigger.parse_request(request)
      rescue IPaaS::Job::DiscardTriggerEvent => e
        captured = e
      end
      expect(captured).not_to be_nil

      response = trigger.respond_with(request, nil, {}, { error: captured })
      expect(response[:status]).to eq(200)
      expect(response[:headers]['content-type']).to eq('text/plain')
      expect(response[:body]).to eq('tok:en with spaces')
    end

    it 'answers the handshake before it reads the body or the store, which is when Microsoft sends it' do
      request = graph_request('', query: 'validationToken=abc')
      expect { trigger.parse_request(request) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'graph-validation:abc')
    end

    it 'reads the token from the query string only, never from a body that carries one' do
      request = graph_request('validationToken=from-body', content_type: 'application/x-www-form-urlencoded')
      expect { trigger.parse_request(request) }
        .to raise_error(IPaaS::Job::FailJob, /This endpoint answers Microsoft Graph, which sends JSON/)
    end

    it 'echoes a token exactly as long as the cap' do
      token = 'a' * MicrosoftOutlookConnector::MAX_VALIDATION_TOKEN_LENGTH
      request = graph_request('', query: "validationToken=#{token}")
      expect { trigger.parse_request(request) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, "graph-validation:#{token}")
    end

    it 'discards a token longer than Microsoft sends instead of echoing it' do
      long_token = 'a' * (MicrosoftOutlookConnector::MAX_VALIDATION_TOKEN_LENGTH + 1)
      request = graph_request('', query: "validationToken=#{long_token}")
      expect { trigger.parse_request(request) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'A validation token longer than Microsoft sends')
    end

    it 'echoes a validation discard and answers every other discard with the default response' do
      request = graph_request('{}')
      echoed = trigger.respond_with(request, nil, {},
                                    { error: IPaaS::Job::DiscardTriggerEvent.new('graph-validation:tok') })
      ignored = trigger.respond_with(request, nil, {},
                                     { error: IPaaS::Job::DiscardTriggerEvent.new('forged clientState') })
      expect(echoed[:body]).to eq('tok')
      expect(ignored).to eq(trigger.respond_with(request, nil, {}, {}))
    end
  end

  describe 'parse' do
    it 'discards every request, naming the URL postfix, while the trigger carries one' do
      store_subscription
      trigger.config[:url_postfix] = 'extra'
      expect { trigger.parse_request(graph_request({ value: [notification] }.to_json)) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, /takes no URL postfix.*Clear URL postfix and try again/)
    end

    it 'maps a notification onto every declared output field' do
      store_subscription
      output = trigger.parse_request(graph_request({ value: [notification] }.to_json))
      expect(output.to_h).to eq({
        'messages' => [{ 'message_id' => 'AAMkAGQz=' }],
        'mailbox' => mailbox,
        'folder' => 'inbox',
        'subscription_id' => subscription_id,
      })
    end

    it 'reads the row under its runbook before a row an earlier version filed under the trigger address' do
      store_subscription(others: { trigger.endpoint => subscribed(legacy_watch, id: other_row['id'], secret: 'old') })
      output = trigger.parse_request(graph_request({ value: [notification] }.to_json))
      expect(output[:subscription_id]).to eq(subscription_id)
    end

    it 'reports every message in a batch, not only the first' do
      store_subscription
      batch = [notification(resourceData: { id: 'first=' }),
               notification(resourceData: { id: 'second=' }),
               notification(resourceData: { id: 'third=' }),]
      output = trigger.parse_request(graph_request({ value: batch }.to_json))
      expect(output[:messages].map { |message| message[:message_id] }).to eq(['first=', 'second=', 'third='])
    end

    it 'discards the whole batch when one notification carries the wrong client state' do
      store_subscription
      batch = [notification, notification(clientState: 'someone-elses-secret')]
      expect { trigger.parse_request(graph_request({ value: batch }.to_json)) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent,
                        'A notification carried a client state this trigger did not set')
    end

    it 'reports the folder the subscription watches, not the folder the notification names' do
      store_subscription(folder: 'archive')
      output = trigger.parse_request(graph_request({ value: [notification] }.to_json))
      expect(output[:folder]).to eq('archive')
    end

    it 'reads its own row, not the row of another trigger on the connection' do
      bobs_row = other_row.merge('client_state' => make_secret_string('bobs').to_s)
      store_subscription(others: { other_endpoint => bobs_row })
      request = graph_request({ value: [notification(clientState: 'bobs')] }.to_json)
      expect { trigger.parse_request(request) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent,
                        'A notification carried a client state this trigger did not set')
    end

    it 'discards a notification whose client state is not the one this trigger set' do
      store_subscription
      request = graph_request({ value: [notification(clientState: 'guessed')] }.to_json)
      expect { trigger.parse_request(request) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent,
                        'A notification carried a client state this trigger did not set')
    end

    it 'discards a notification that carries no client state at all' do
      store_subscription
      request = graph_request({ value: [notification.except(:clientState)] }.to_json)
      expect { trigger.parse_request(request) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent,
                        'A notification carried a client state this trigger did not set')
    end

    it 'discards every notification while no subscription is stored' do
      request = graph_request({ value: [notification(clientState: '')] }.to_json)
      expect { trigger.parse_request(request) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent,
                        'A notification carried a client state this trigger did not set')
    end

    it 'discards every notification while the watch has been recorded but not yet created' do
      trigger.provision
      request = graph_request({ value: [notification(clientState: '')] }.to_json)
      expect { trigger.parse_request(request) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent,
                        'A notification carried a client state this trigger did not set')
    end

    it 'starts no workflow for a request that carries only subscription housekeeping' do
      store_subscription
      housekeeping = notification(lifecycleEvent: 'reauthorizationRequired').except(:resourceData)
      expect { trigger.parse_request(graph_request({ value: [housekeeping] }.to_json)) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'A request to this endpoint carried no new mail')
    end

    it 'ignores a query string Rack cannot parse and still reads the body' do
      store_subscription
      request = graph_request('{}', query: '%')
      expect { trigger.parse_request(request) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent,
                        'A request to this endpoint carried no Microsoft change notification')
    end

    it 'discards a request that carries no change notification' do
      store_subscription
      expect { trigger.parse_request(graph_request('{"value":[]}')) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent,
                        'A request to this endpoint carried no Microsoft change notification')
    end

    it 'fails the job, naming the reason, when the body is empty' do
      store_subscription
      expect { trigger.parse_request(graph_request('')) }
        .to raise_error(IPaaS::Job::FailJob, /This endpoint answers Microsoft Graph, which sends JSON/)
    end

    it 'fails the job, naming the reason, when the body is form encoded' do
      store_subscription
      request = graph_request('a=b', content_type: 'application/x-www-form-urlencoded')
      expect { trigger.parse_request(request) }
        .to raise_error(IPaaS::Job::FailJob, /This endpoint answers Microsoft Graph, which sends JSON/)
    end

    it 'names the size of a body it could not read, never the body itself' do
      store_subscription
      body = '<script>marker-12345</script>'
      expect { trigger.parse_request(graph_request(body)) }
        .to raise_error(IPaaS::Job::FailJob) do |error|
          expect(error.message).to include("#{body.bytesize} byte")
          expect(error.message).not_to include('marker-12345')
        end
    end

    it 'raises when a trusted notification carries no message id' do
      store_subscription
      request = graph_request({ value: [notification(resourceData: {})] }.to_json)
      expect { trigger.parse_request(request) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph sent a change notification with no message id')
    end
  end
end
