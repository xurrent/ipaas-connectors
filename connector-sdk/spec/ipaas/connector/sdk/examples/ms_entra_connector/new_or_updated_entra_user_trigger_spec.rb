require 'spec_helper'

describe 'Microsoft Entra New or Updated User Trigger', :ms_entra, :trigger do
  let(:trigger_template_id) { '01a1a1c8-debd-736f-9cab-7df55db8b836' }
  let(:store_key) { MsEntraConnector::SUBSCRIPTIONS_STORE_KEY }
  let(:trigger_config) { {} }
  let(:subscription_id) { '0fc0f4a5-3f6e-4bc5-9d1a-52e2c5b81e0c' }
  let(:client_state) { 'ca1fe1f8-4a51-4a45-9d2a-8b1a1de0b7c2' }
  let(:subscription_url) { "#{graph}/subscriptions/#{subscription_id}" }
  let(:second_user_id) { '5b1e0c8a-2f6d-4c3a-9e71-0d4b8a6f2c19' }

  def notification(overrides = {})
    {
      subscriptionId: subscription_id,
      changeType: 'updated',
      resource: "Users/#{user_id}",
      clientState: client_state,
      resourceData: { '@odata.type': '#Microsoft.Graph.User', id: user_id },
    }.merge(overrides)
  end

  def graph_request(body, query: '')
    env = Rack::MockRequest.env_for("/inbound?#{query}", method: 'POST', input: body,
                                                         'CONTENT_TYPE' => 'application/json')
    Rack::Request.new(env)
  end

  def watch(resource: 'users', change_type: 'updated')
    { 'resource' => resource, 'change_type' => change_type, 'endpoint' => trigger.endpoint }
  end

  def store_subscription(row = watch)
    trigger.outbound_connection.store.write(
      store_key,
      trigger.runbook.uuid => row.merge('id' => subscription_id,
                                        'client_state' => make_secret_string(client_state).to_s)
    )
  end

  def store_subscription_after_recreate(previous_state)
    trigger.outbound_connection.store.write(
      store_key,
      trigger.runbook.uuid => watch.merge('id' => subscription_id,
                                          'client_state' => make_secret_string('a-newer-client-state').to_s,
                                          'previous_client_state' => make_secret_string(previous_state).to_s)
    )
  end

  def stored_row
    (trigger.outbound_connection.store.read(store_key) || {})[trigger.runbook.uuid]
  end

  def discard_of(request)
    trigger.parse_request(request)
    nil
  rescue IPaaS::Job::DiscardTriggerEvent => e
    e
  end

  describe 'provision' do
    it 'records the resource, the change type and the endpoint under the runbook of this trigger' do
      trigger.provision
      expect(stored_row).to eq('resource' => 'users', 'change_type' => 'updated', 'endpoint' => trigger.endpoint)
    end

    it 'calls Microsoft Graph for nothing' do
      trigger.provision
      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'deletes the old subscription before it writes the new row when the resource changed' do
      store_subscription(watch(resource: 'groups'))
      row_at_delete = nil
      stub_request(:delete, subscription_url).to_return do
        row_at_delete = stored_row
        { status: 204, body: '' }
      end
      trigger.provision
      expect(row_at_delete['resource']).to eq('groups')
      expect(stored_row).to eq(watch)
    end

    it 'deletes the old subscription before it writes the new row when the change type changed' do
      store_subscription(watch(change_type: 'deleted'))
      row_at_delete = nil
      stub_request(:delete, subscription_url).to_return do
        row_at_delete = stored_row
        { status: 204, body: '' }
      end
      trigger.provision
      expect(row_at_delete['change_type']).to eq('deleted')
      expect(stored_row).to eq(watch)
    end

    it 'keeps the watch Microsoft already holds when nothing about the trigger changed' do
      store_subscription
      trigger.provision
      expect(stored_row['id']).to eq(subscription_id)
      expect(new_secret_string(stored_row['client_state']).decrypt).to eq(client_state)
    end

    it 'writes nothing when nothing about the trigger changed' do
      store_subscription
      expect(trigger.outbound_connection.store).not_to receive(:write)
      trigger.provision
    end

    it 'refuses a URL postfix and records nothing' do
      trigger.config[:url_postfix] = 'extra'
      expect { trigger.provision }.to raise_error(IPaaS::Job::FailJob, /take no URL postfix/)
      expect(stored_row).to be_nil
    end
  end

  describe 'deprovision' do
    it 'deletes the subscription and the row' do
      store_subscription
      stub_request(:delete, subscription_url).to_return(status: 204, body: '')
      trigger.deprovision
      expect(a_request(:delete, subscription_url)).to have_been_made.once
      expect(stored_row).to be_nil
    end

    it 'still removes the row when Microsoft answers the delete with 404' do
      store_subscription
      stub_request(:delete, subscription_url)
        .to_return(status: 404, body: graph_error('ResourceNotFound', 'The object was not found.'))
      trigger.deprovision
      expect(stored_row).to be_nil
    end

    it 'refuses a URL postfix and deletes nothing' do
      store_subscription
      trigger.config[:url_postfix] = 'extra'
      expect { trigger.deprovision }.to raise_error(IPaaS::Job::FailJob, MsEntraConnector::URL_POSTFIX_REFUSED)
      expect(a_request(:delete, subscription_url)).not_to have_been_made
      expect(stored_row['id']).to eq(subscription_id)
    end
  end

  describe 'respond_with' do
    before(:each) { allow(runbook).to receive(:trigger_output).and_return({}) }

    it 'echoes the exact validation token from the query as status 200 and text/plain' do
      request = graph_request('', query: "validationToken=#{CGI.escape('tok:en with spaces')}")
      captured = discard_of(request)
      response = trigger.respond_with(request, nil, {}, { error: captured })
      expect(response[:status]).to eq(200)
      expect(response[:headers]['content-type']).to eq('text/plain')
      expect(response[:body]).to eq('tok:en with spaces')
    end

    it 'echoes the validation token with nosniff, so a browser never reads the echo as HTML' do
      request = graph_request('', query: "validationToken=#{CGI.escape('<b>x</b>')}")
      response = trigger.respond_with(request, nil, {}, { error: discard_of(request) })
      expect(response[:headers]['x-content-type-options']).to eq('nosniff')
    end

    it 'discards a validation token longer than 1024 characters instead of echoing it' do
      expect { trigger.parse_request(graph_request('', query: "validationToken=#{'a' * 1025}")) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'A validation token longer than Microsoft sends')
    end

    it 'answers a graph-retry discard with status 503' do
      request = graph_request('{}')
      error = IPaaS::Job::DiscardTriggerEvent.new('graph-retry: Microsoft Graph was slow.')
      expect(trigger.respond_with(request, nil, {}, { error: error })[:status]).to eq(503)
    end

    it 'keeps the default status for a plain discard' do
      request = graph_request('{}')
      error = IPaaS::Job::DiscardTriggerEvent.new('No notification carried the client state this trigger set')
      expect(trigger.respond_with(request, nil, {}, { error: error })[:status])
        .to eq(trigger.respond_with(request, nil, {}, {})[:status])
    end
  end

  describe 'parse' do
    it 'emits the ids from resourceData and the subscription id for a valid batch' do
      store_subscription
      batch = [notification, notification(resourceData: { id: second_user_id })]
      output = trigger.parse_request(graph_request({ value: batch }.to_json))
      expect(output.to_h).to eq('users' => [{ 'user_id' => user_id }, { 'user_id' => second_user_id }],
                                'subscription_id' => subscription_id)
    end

    it 'discards a request whose notification list is empty' do
      store_subscription
      expect { trigger.parse_request(graph_request({ value: [] }.to_json)) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent,
                        'A request to this endpoint carried no Microsoft change notification')
    end

    it 'discards a request when the trigger has a URL postfix' do
      store_subscription
      trigger.config[:url_postfix] = 'extra'
      expect { trigger.parse_request(graph_request({ value: [notification] }.to_json)) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, MsEntraConnector::URL_POSTFIX_REFUSED)
    end

    it 'logs no ignored notification when every notification carries the client state' do
      store_subscription
      allow(trigger).to receive(:log)
      trigger.parse_request(graph_request({ value: [notification] }.to_json))
      expect(trigger).not_to have_received(:log).with(/client state this trigger did not set/)
    end

    it 'drops a lifecycle event and keeps the changes beside it' do
      store_subscription
      lifecycle = notification(lifecycleEvent: 'reauthorizationRequired').except(:resourceData)
      output = trigger.parse_request(graph_request({ value: [lifecycle, notification] }.to_json))
      expect(output.to_h['users']).to eq([{ 'user_id' => user_id }])
    end

    it 'discards a batch that carries only a lifecycle event' do
      store_subscription
      lifecycle = notification(lifecycleEvent: 'missed').except(:resourceData)
      expect { trigger.parse_request(graph_request({ value: [lifecycle] }.to_json)) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'A request to this endpoint carried no directory change')
    end

    it 'emits only the notification that carries the client state this trigger set' do
      store_subscription
      batch = [notification, notification(clientState: 'guessed', resourceData: { id: second_user_id })]
      output = trigger.parse_request(graph_request({ value: batch }.to_json))
      expect(output.to_h['users']).to eq([{ 'user_id' => user_id }])
    end

    it 'refuses the batch when every notification carries the wrong client state' do
      store_subscription
      batch = [notification(clientState: 'guessed'), notification(clientState: 'also-guessed')]
      expect { trigger.parse_request(graph_request({ value: batch }.to_json)) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'No notification carried the client state this trigger set')
    end

    it 'refuses a notification that carries no client state' do
      store_subscription
      expect { trigger.parse_request(graph_request({ value: [notification.except(:clientState)] }.to_json)) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'No notification carried the client state this trigger set')
    end

    it 'refuses a notification with no client state while the trigger has no subscription yet' do
      trigger.outbound_connection.store.write(store_key, trigger.runbook.uuid => watch)
      expect { trigger.parse_request(graph_request({ value: [notification.except(:clientState)] }.to_json)) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'No notification carried the client state this trigger set')
    end

    it 'emits a user once when Microsoft notifies about it twice in one batch' do
      store_subscription
      output = trigger.parse_request(graph_request({ value: [notification, notification] }.to_json))
      expect(output.to_h['users']).to eq([{ 'user_id' => user_id }])
    end

    it 'skips a notification with no resourceData id and emits the others' do
      store_subscription
      nameless = notification(resourceData: { '@odata.type': '#Microsoft.Graph.User' })
      batch = [nameless, notification(resourceData: { id: second_user_id })]
      output = trigger.parse_request(graph_request({ value: batch }.to_json))
      expect(output.to_h['users']).to eq([{ 'user_id' => second_user_id }])
    end

    it 'refuses the batch when no notification names a directory object' do
      store_subscription
      batch = [notification.except(:resourceData)]
      expect { trigger.parse_request(graph_request({ value: batch }.to_json)) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'No notification named a directory object')
    end
  end

  it 'accepts a notification signed with the client state of the subscription it replaced' do
    store_subscription_after_recreate(client_state)
    output = trigger.parse_request(graph_request({ value: [notification] }.to_json))
    expect(output.to_h['users']).to eq([{ 'user_id' => user_id }])
  end

  it 'emits the object id in lower case when Microsoft sends it in upper case' do
    store_subscription
    upper = notification(resourceData: { '@odata.type': '#Microsoft.Graph.User', id: user_id.upcase })
    output = trigger.parse_request(graph_request({ value: [upper] }.to_json))
    expect(output.to_h['users']).to eq([{ 'user_id' => user_id }])
  end
end
