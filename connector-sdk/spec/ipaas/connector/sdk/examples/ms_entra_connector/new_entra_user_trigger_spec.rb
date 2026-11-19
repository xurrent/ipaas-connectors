require 'spec_helper'

describe 'Microsoft Entra New User Trigger', :ms_entra, :trigger do
  let(:trigger_template_id) { '01a1a1c8-debd-7086-8378-07dda2914300' }
  let(:store_key) { MsEntraConnector::SUBSCRIPTIONS_STORE_KEY }
  let(:trigger_config) { {} }
  let(:subscription_id) { '0fc0f4a5-3f6e-4bc5-9d1a-52e2c5b81e0c' }
  let(:client_state) { 'ca1fe1f8-4a51-4a45-9d2a-8b1a1de0b7c2' }
  let(:second_user_id) { '5b1e0c8a-2f6d-4c3a-9e71-0d4b8a6f2c19' }
  let(:third_user_id) { '9d3c2b1a-0e4f-4a6b-8c7d-1f2e3a4b5c6d' }
  let(:now) { Time.utc(2026, 11, 3, 10, 0, 0) }
  let(:batch_url) { "#{graph}/$batch" }
  let(:subscription_url) { "#{graph}/subscriptions/#{subscription_id}" }

  def notification(id)
    { subscriptionId: subscription_id, changeType: 'updated', resource: "Users/#{id}",
      clientState: client_state, resourceData: { '@odata.type': '#Microsoft.Graph.User', id: id }, }
  end

  def graph_request(ids)
    body = { value: ids.map { |id| notification(id) } }.to_json
    env = Rack::MockRequest.env_for('/inbound', method: 'POST', input: body, 'CONTENT_TYPE' => 'application/json')
    Rack::Request.new(env)
  end

  def store_subscription
    row = { 'resource' => 'users', 'change_type' => 'updated', 'endpoint' => trigger.endpoint,
            'id' => subscription_id, 'client_state' => make_secret_string(client_state).to_s, }
    trigger.outbound_connection.store.write(store_key, trigger.runbook.uuid => row)
  end

  def guids(count)
    Array.new(count) { |index| format('00000000-0000-4000-8000-%012d', index) }
  end

  def lookup_url(ids)
    query = URI.encode_www_form('$filter' => "id in (#{ids.map { |id| "'#{id}'" }.join(',')})",
                                '$select' => 'id,createdDateTime', '$top' => '15')
    "/users?#{query}"
  end

  def lookup_batch(*slices)
    { requests: slices.each_with_index.map { |ids, index| { id: index.to_s, method: 'GET', url: lookup_url(ids) } } }
  end

  def not_found
    { error: { code: 'Request_ResourceNotFound', message: 'Gone.' } }
  end

  def answer(id, users, status: 200)
    { id: id, status: status, body: { value: users } }
  end

  def created(id, minutes_ago)
    { id: id, createdDateTime: (now - (minutes_ago * 60)).utc.iso8601 }
  end

  def stub_batch(batch, answers)
    stub_request(:post, batch_url).with(body: batch)
                                  .to_return(status: 200, body: { responses: answers }.to_json)
  end

  def stub_lookup(ids, users)
    stub_batch(lookup_batch(ids), [answer('0', users)])
  end

  def deleted_batch(ids)
    query = URI.encode_www_form('$filter' => "id in (#{ids.map { |id| "'#{id}'" }.join(',')})",
                                '$select' => 'id', '$top' => '15')
    { requests: [{ id: '0', method: 'GET', url: "/directory/deletedItems/microsoft.graph.user?#{query}" }] }
  end

  def stub_deleted(ids, deleted_ids)
    stub_batch(deleted_batch(ids), [answer('0', deleted_ids.map { |id| { id: id } })])
  end

  def reported_key
    "#{MsEntraConnector::REPORTED_STORE_PREFIX}#{trigger.runbook.uuid}"
  end

  def unseen_key
    "#{MsEntraConnector::UNSEEN_STORE_PREFIX}#{trigger.runbook.uuid}"
  end

  before(:each) do
    Timecop.freeze(now)
    store_subscription
  end

  after(:each) { Timecop.return }

  it 'asks Microsoft Graph in one batch for the ids, selecting id and createdDateTime' do
    stub_lookup([user_id], [created(user_id, 5)])
    trigger.parse_request(graph_request([user_id]))
    url = "/users?%24filter=id+in+%28%27#{user_id}%27%29&%24select=id%2CcreatedDateTime&%24top=15"
    expect(a_request(:post, batch_url).with(body: { requests: [{ id: '0', method: 'GET', url: url }] }))
      .to have_been_made.once
  end

  it 'drops a user whose creation time does not parse and still reports the others' do
    stub_lookup([user_id, second_user_id], [{ id: user_id, createdDateTime: 'not a time' }, created(second_user_id, 5)])
    output = trigger.parse_request(graph_request([user_id, second_user_id]))
    expect(output.to_h['users'].map { |user| user['user_id'] }).to eq([second_user_id])
  end

  it 'drops a user that has no creation time without logging it as a time that does not parse' do
    allow(trigger).to receive(:log)
    stub_lookup([user_id, second_user_id], [{ id: user_id, createdDateTime: nil }, created(second_user_id, 5)])
    output = trigger.parse_request(graph_request([user_id, second_user_id]))
    expect(output.to_h['users'].map { |user| user['user_id'] }).to eq([second_user_id])
    expect(trigger).not_to have_received(:log).with(/creation time that is not a time/)
  end

  it 'reports the lower case id when Microsoft Graph returns the user id in upper case' do
    stub_lookup([user_id], [created(user_id.upcase, 5)])
    output = trigger.parse_request(graph_request([user_id]))
    expect(output.to_h['users'].map { |user| user['user_id'] }).to eq([user_id])
  end

  it 'writes nothing to the reported list when every user in the batch was already reported' do
    trigger.outbound_connection.store.write(reported_key, user_id => created(user_id, 30)[:createdDateTime])
    stub_lookup([user_id], [created(user_id, 30)])
    allow(trigger.outbound_connection.store).to receive(:write).and_call_original
    expect { trigger.parse_request(graph_request([user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'Every user in these notifications was already reported')
    expect(trigger.outbound_connection.store).not_to have_received(:write).with(reported_key, anything)
  end

  it 'matches an upper case id from Microsoft to the lower case id Graph returns' do
    stub_lookup([user_id], [created(user_id, 5)])
    output = trigger.parse_request(graph_request([user_id.upcase]))
    expect(output.to_h['users'].map { |user| user['user_id'] }).to eq([user_id])
  end

  it 'keeps a user created 59 minutes ago and drops one created 61 minutes ago' do
    stub_lookup([user_id, second_user_id], [created(user_id, 59), created(second_user_id, 61)])
    output = trigger.parse_request(graph_request([user_id, second_user_id]))
    expect(output.to_h['users'].map { |user| user['user_id'] }).to eq([user_id])
    expect(output.to_h['subscription_id']).to eq(subscription_id)
  end

  it 'reports a new user once, even when Microsoft Graph notifies about it again within the hour' do
    trigger.outbound_connection.store.write(reported_key, user_id => created(user_id, 30)[:createdDateTime])
    stub_lookup([user_id, second_user_id], [created(user_id, 30), created(second_user_id, 5)])
    output = trigger.parse_request(graph_request([user_id, second_user_id]))
    expect(output.to_h['users'].map { |user| user['user_id'] }).to eq([second_user_id])
  end

  it 'discards the event as already reported when the only recent user was reported before' do
    trigger.outbound_connection.store.write(reported_key, user_id => created(user_id, 30)[:createdDateTime])
    stub_lookup([user_id], [created(user_id, 30)])
    expect { trigger.parse_request(graph_request([user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'Every user in these notifications was already reported')
  end

  it 'forgets a reported user once it is older than the hour' do
    trigger.outbound_connection.store.write(reported_key,
                                            second_user_id => created(second_user_id, 90)[:createdDateTime])
    stub_lookup([user_id], [created(user_id, 5)])
    trigger.parse_request(graph_request([user_id]))
    expect(trigger.outbound_connection.store.read(reported_key).keys).to eq([user_id])
  end

  it 'discards the event when no user was created recently' do
    stub_lookup([user_id], [created(user_id, 61)])
    expect { trigger.parse_request(graph_request([user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'No user in these notifications could be reported as new')
  end

  it 'sends only the GUID ids to Microsoft Graph' do
    stub_lookup([user_id], [created(user_id, 5)])
    trigger.parse_request(graph_request(['not-a-guid', user_id]))
    expect(a_request(:post, batch_url).with(body: lookup_batch([user_id]))).to have_been_made.once
  end

  it 'sends no request and discards the event when no id is a GUID' do
    expect { trigger.parse_request(graph_request(['not-a-guid'])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'No notification named a directory object by a GUID')
    expect(a_request(:post, batch_url)).not_to have_been_made
  end

  it 'sends 16 ids as two requests in one batch' do
    ids = guids(16)
    stub_batch(lookup_batch(ids.first(15), ids.last(1)),
               [answer('0', ids.first(15).map { |id| created(id, 90) }), answer('1', [created(ids.last, 5)])])
    output = trigger.parse_request(graph_request(ids))
    expect(a_request(:post, batch_url)).to have_been_made.once
    expect(output.to_h['users'].map { |user| user['user_id'] }).to eq([ids.last])
  end

  it 'checks only the first 300 of 301 ids, in one batch of 20 requests, and still reports a new one' do
    ids = guids(301)
    slices = ids.first(300).each_slice(15).to_a
    answers = slices.each_with_index.map do |slice, index|
      answer(index.to_s, slice.map { |id| created(id, index.zero? && id == slice.first ? 5 : 90) })
    end
    stub_batch(lookup_batch(*slices), answers)
    output = trigger.parse_request(graph_request(ids))
    expect(a_request(:post, batch_url)).to have_been_made.once
    expect(output.to_h['users'].map { |user| user['user_id'] }).to eq([ids.first])
  end

  it 'asks Microsoft to send again when the batch answers 500' do
    stub_request(:post, batch_url).with(body: lookup_batch([user_id]))
                                  .to_return(status: 500, body: graph_error('InternalServerError', 'Boom.'))
    expect { trigger.parse_request(graph_request([user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent,
                      /\Agraph-retry: Could not check which objects are new\. Microsoft Graph returned HTTP 500 /)
  end

  it 'discards the event, and logs the id as deleted, when the lookup of one id answers 404 and it is deleted' do
    allow(trigger).to receive(:log)
    stub_batch(lookup_batch([user_id]), [{ id: '0', status: 404, body: not_found }])
    stub_deleted([user_id], [user_id])
    expect { trigger.parse_request(graph_request([user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'No user in these notifications could be reported as new')
    expect(trigger).to have_received(:log)
      .with("These changed objects are deleted, so they are not reported: #{user_id}")
  end

  it 'asks Microsoft to send again when the lookup of one id answers 404 with another code' do
    stub_batch(lookup_batch([user_id]),
               [{ id: '0', status: 404, body: { error: { code: 'UnknownError', message: 'Not found.' } } }])
    expect { trigger.parse_request(graph_request([user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent,
                      /\Agraph-retry: Could not check which objects are new\. Microsoft Graph returned HTTP 404 /)
  end

  it 'asks Microsoft to send again when the lookup of two ids answers 404' do
    stub_batch(lookup_batch([user_id, second_user_id]), [{ id: '0', status: 404, body: not_found }])
    expect { trigger.parse_request(graph_request([user_id, second_user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent,
                      /\Agraph-retry: Could not check which objects are new\. Microsoft Graph returned HTTP 404 /)
  end

  it 'asks Microsoft to send again when the batch times out' do
    stub_request(:post, batch_url).with(body: lookup_batch([user_id])).to_timeout
    expect { trigger.parse_request(graph_request([user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, /\Agraph-retry: Could not check which objects are new\./)
  end

  it 'asks Microsoft to send again, with no request, when the deadline passed before the batch' do
    allow(trigger.outbound_connection.store).to receive(:read).and_wrap_original do |original, key|
      Timecop.freeze(now + 1.5) if key == store_key
      original.call(key)
    end
    expect { trigger.parse_request(graph_request([user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, /\Agraph-retry: There was no time left/)
    expect(a_request(:post, batch_url)).not_to have_been_made
  end

  it 'asks deleted items only for the ids Microsoft Graph did not return, selecting id' do
    stub_lookup([user_id, second_user_id], [created(user_id, 5)])
    stub_deleted([second_user_id], [second_user_id])
    trigger.parse_request(graph_request([user_id, second_user_id]))
    url = '/directory/deletedItems/microsoft.graph.user?' \
          "%24filter=id+in+%28%27#{second_user_id}%27%29&%24select=id&%24top=15"
    expect(a_request(:post, batch_url).with(body: { requests: [{ id: '0', method: 'GET', url: url }] }))
      .to have_been_made.once
  end

  it 'reports the users Microsoft Graph returns and logs the ids that are deleted' do
    allow(trigger).to receive(:log)
    stub_lookup([user_id, second_user_id], [created(user_id, 5)])
    stub_deleted([second_user_id], [second_user_id])
    output = trigger.parse_request(graph_request([user_id, second_user_id]))
    expect(output.to_h['users'].map { |user| user['user_id'] }).to eq([user_id])
    expect(trigger).to have_received(:log)
      .with("These changed objects are deleted, so they are not reported: #{second_user_id}")
  end

  it 'discards the event, and asks Microsoft for nothing again, when every id is deleted' do
    stub_lookup([user_id, second_user_id], [])
    stub_deleted([user_id, second_user_id], [user_id, second_user_id])
    expect { trigger.parse_request(graph_request([user_id, second_user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'No user in these notifications could be reported as new')
  end

  it 'asks Microsoft to send again when the one missing id is not in deleted items either' do
    stub_lookup([user_id, second_user_id], [created(user_id, 5)])
    stub_batch(deleted_batch([second_user_id]), [{ id: '0', status: 404, body: not_found }])
    expect { trigger.parse_request(graph_request([user_id, second_user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, /\Agraph-retry: Microsoft Graph does not show 1 changed/)
  end

  it 'holds only the id that is neither returned nor deleted, and stores when it first saw it' do
    stub_lookup([user_id, second_user_id, third_user_id], [created(user_id, 5)])
    stub_deleted([second_user_id, third_user_id], [second_user_id])
    expect { trigger.parse_request(graph_request([user_id, second_user_id, third_user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, /\Agraph-retry: Microsoft Graph does not show 1 changed/)
    expect(trigger.outbound_connection.store.read(unseen_key)).to eq(third_user_id => now.iso8601)
  end

  it 'still asks Microsoft to send again for an unseen id first seen 4 minutes ago' do
    trigger.outbound_connection.store.write(unseen_key, second_user_id => (now - 240).iso8601)
    stub_lookup([user_id, second_user_id], [created(user_id, 5)])
    stub_deleted([second_user_id], [])
    expect { trigger.parse_request(graph_request([user_id, second_user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, /\Agraph-retry: Microsoft Graph does not show 1 changed/)
  end

  it 'reports the users beside an unseen id first seen 6 minutes ago, and logs that id' do
    allow(trigger).to receive(:log)
    trigger.outbound_connection.store.write(unseen_key, second_user_id => (now - 360).iso8601)
    stub_lookup([user_id, second_user_id], [created(user_id, 5)])
    stub_deleted([second_user_id], [])
    output = trigger.parse_request(graph_request([user_id, second_user_id]))
    expect(output.to_h['users'].map { |user| user['user_id'] }).to eq([user_id])
    expect(trigger).to have_received(:log)
      .with('Microsoft Graph did not show these changed objects within 5 minutes, ' \
            "so they are not reported: #{second_user_id}")
  end

  it 'discards the event when the only id is unseen and was first seen 6 minutes ago' do
    trigger.outbound_connection.store.write(unseen_key, user_id => (now - 360).iso8601)
    stub_lookup([user_id], [])
    stub_deleted([user_id], [])
    expect { trigger.parse_request(graph_request([user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'No user in these notifications could be reported as new')
  end

  it 'holds the missing id without asking deleted items when the first lookup left no time' do
    stub_request(:post, batch_url).with(body: lookup_batch([user_id, second_user_id])).to_return do
      Timecop.freeze(now + 1.5)
      { status: 200, body: { responses: [answer('0', [created(user_id, 5)])] }.to_json }
    end
    expect { trigger.parse_request(graph_request([user_id, second_user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, /\Agraph-retry: Microsoft Graph does not show 1 changed/)
    expect(a_request(:post, batch_url).with(body: deleted_batch([second_user_id]))).not_to have_been_made
  end

  it 'holds the missing id, and logs why, when the deleted-items lookup answers 500' do
    allow(trigger).to receive(:log)
    stub_lookup([user_id, second_user_id], [created(user_id, 5)])
    stub_request(:post, batch_url).with(body: deleted_batch([second_user_id]))
                                  .to_return(status: 500, body: graph_error('InternalServerError', 'Boom.'))
    expect { trigger.parse_request(graph_request([user_id, second_user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, /\Agraph-retry: Microsoft Graph does not show 1 changed/)
    expect(trigger.outbound_connection.store.read(unseen_key)).to eq(second_user_id => now.iso8601)
    expect(trigger).to have_received(:log)
      .with('Could not check which changed objects are deleted, so they are held like objects that Microsoft Graph ' \
            'does not show yet. Microsoft Graph returned HTTP 500 InternalServerError: Boom.')
  end

  it 'reports the users beside an id first seen 6 minutes ago when the deleted-items lookup answers 500' do
    trigger.outbound_connection.store.write(unseen_key, second_user_id => (now - 360).iso8601)
    stub_lookup([user_id, second_user_id], [created(user_id, 5)])
    stub_request(:post, batch_url).with(body: deleted_batch([second_user_id]))
                                  .to_return(status: 500, body: graph_error('InternalServerError', 'Boom.'))
    output = trigger.parse_request(graph_request([user_id, second_user_id]))
    expect(output.to_h['users'].map { |user| user['user_id'] }).to eq([user_id])
  end

  it 'keeps a user it reported before in the store when it reports a new one' do
    trigger.outbound_connection.store.write(reported_key, user_id => created(user_id, 30)[:createdDateTime])
    stub_lookup([second_user_id], [created(second_user_id, 5)])
    trigger.parse_request(graph_request([second_user_id]))
    expect(trigger.outbound_connection.store.read(reported_key).keys).to contain_exactly(user_id, second_user_id)
  end

  it 'keeps the first-seen time of an id it already waits for when a new unseen id arrives' do
    trigger.outbound_connection.store.write(unseen_key, second_user_id => (now - 240).iso8601)
    stub_lookup([third_user_id], [])
    stub_deleted([third_user_id], [])
    expect { trigger.parse_request(graph_request([third_user_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, /\Agraph-retry: Microsoft Graph does not show 1 changed/)
    expect(trigger.outbound_connection.store.read(unseen_key))
      .to eq(second_user_id => (now - 240).iso8601, third_user_id => now.iso8601)
  end

  it 'reports the creation time Microsoft Graph gives for a new user' do
    stub_lookup([user_id], [created(user_id, 5)])
    output = trigger.parse_request(graph_request([user_id]))
    expect(output.to_h['users'])
      .to eq([{ 'user_id' => user_id, 'created_date_time' => created(user_id, 5)[:createdDateTime] }])
  end

  it 'gives the lookup batch the time left before the deadline as its read timeout' do
    allow(trigger.outbound_connection.store).to receive(:read).and_wrap_original do |original, key|
      Timecop.freeze(now + 0.5) if key == store_key
      original.call(key)
    end
    stub_lookup([user_id], [created(user_id, 5)])
    expect(trigger).to receive(:http_post)
      .with(anything, anything, anything, open_timeout: MsEntraConnector::LOOKUP_OPEN_TIMEOUT_SECONDS, timeout: 1.5)
      .and_call_original
    trigger.parse_request(graph_request([user_id]))
  end

  it 'forgets the users it reported when the trigger is removed' do
    trigger.outbound_connection.store.write(reported_key, user_id => now.iso8601)
    stub_request(:delete, subscription_url).to_return(status: 204, body: '')
    trigger.deprovision
    expect(trigger.outbound_connection.store.read(reported_key)).to eq({})
  end

  it 'forgets the ids it waits for when the trigger is removed' do
    trigger.outbound_connection.store.write(unseen_key, user_id => now.iso8601)
    stub_request(:delete, subscription_url).to_return(status: 204, body: '')
    trigger.deprovision
    expect(trigger.outbound_connection.store.read(unseen_key)).to eq({})
  end
end
