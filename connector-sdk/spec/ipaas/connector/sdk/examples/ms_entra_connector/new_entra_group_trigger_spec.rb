require 'spec_helper'

describe 'Microsoft Entra New Group Trigger', :ms_entra, :trigger do
  let(:trigger_template_id) { '01a1a1c8-debd-7633-926d-308136659fdd' }
  let(:store_key) { MsEntraConnector::SUBSCRIPTIONS_STORE_KEY }
  let(:trigger_config) { {} }
  let(:subscription_id) { '0fc0f4a5-3f6e-4bc5-9d1a-52e2c5b81e0c' }
  let(:client_state) { 'ca1fe1f8-4a51-4a45-9d2a-8b1a1de0b7c2' }
  let(:second_group_id) { '6c2f1d9b-3a7e-4d4b-8f82-1e5c9b7a3d20' }
  let(:now) { Time.utc(2026, 11, 3, 10, 0, 0) }
  let(:batch_url) { "#{graph}/$batch" }

  def notification(id)
    { subscriptionId: subscription_id, changeType: 'updated', resource: "Groups/#{id}",
      clientState: client_state, resourceData: { '@odata.type': '#Microsoft.Graph.Group', id: id }, }
  end

  def graph_request(ids)
    body = { value: ids.map { |id| notification(id) } }.to_json
    env = Rack::MockRequest.env_for('/inbound', method: 'POST', input: body, 'CONTENT_TYPE' => 'application/json')
    Rack::Request.new(env)
  end

  def store_subscription
    row = { 'resource' => 'groups', 'change_type' => 'updated', 'endpoint' => trigger.endpoint,
            'id' => subscription_id, 'client_state' => make_secret_string(client_state).to_s, }
    trigger.outbound_connection.store.write(store_key, trigger.runbook.uuid => row)
  end

  def stored_row
    trigger.outbound_connection.store.read(store_key)[trigger.runbook.uuid]
  end

  def lookup_url(ids)
    query = URI.encode_www_form('$filter' => "id in (#{ids.map { |id| "'#{id}'" }.join(',')})",
                                '$select' => 'id,createdDateTime', '$top' => '15')
    "/groups?#{query}"
  end

  def lookup_batch(ids)
    { requests: [{ id: '0', method: 'GET', url: lookup_url(ids) }] }
  end

  def created(id, minutes_ago)
    { id: id, createdDateTime: (now - (minutes_ago * 60)).utc.iso8601 }
  end

  def stub_lookup(ids, groups)
    answers = [{ id: '0', status: 200, body: { value: groups } }]
    stub_request(:post, batch_url).with(body: lookup_batch(ids))
                                  .to_return(status: 200, body: { responses: answers }.to_json)
  end

  def stub_deleted(ids, deleted_ids)
    query = URI.encode_www_form('$filter' => "id in (#{ids.map { |id| "'#{id}'" }.join(',')})",
                                '$select' => 'id', '$top' => '15')
    batch = { requests: [{ id: '0', method: 'GET', url: "/directory/deletedItems/microsoft.graph.group?#{query}" }] }
    answers = [{ id: '0', status: 200, body: { value: deleted_ids.map { |id| { id: id } } } }]
    stub_request(:post, batch_url).with(body: batch).to_return(status: 200, body: { responses: answers }.to_json)
  end

  before(:each) { Timecop.freeze(now) }

  after(:each) { Timecop.return }

  it 'records the groups resource and the updated change type' do
    trigger.provision
    expect(stored_row).to eq('resource' => 'groups', 'change_type' => 'updated', 'endpoint' => trigger.endpoint)
  end

  it 'asks Microsoft Graph in one batch on /groups for the ids, selecting id and createdDateTime' do
    store_subscription
    stub_lookup([group_id], [created(group_id, 5)])
    trigger.parse_request(graph_request([group_id]))
    url = "/groups?%24filter=id+in+%28%27#{group_id}%27%29&%24select=id%2CcreatedDateTime&%24top=15"
    expect(a_request(:post, batch_url).with(body: { requests: [{ id: '0', method: 'GET', url: url }] }))
      .to have_been_made.once
  end

  it 'keeps a group created 59 minutes ago and drops one created 61 minutes ago' do
    store_subscription
    stub_lookup([group_id, second_group_id], [created(group_id, 59), created(second_group_id, 61)])
    output = trigger.parse_request(graph_request([group_id, second_group_id]))
    expect(output.to_h['groups'].map { |group| group['group_id'] }).to eq([group_id])
    expect(output.to_h['subscription_id']).to eq(subscription_id)
  end

  it 'discards the event when no group was created recently' do
    store_subscription
    stub_lookup([group_id], [created(group_id, 61)])
    expect { trigger.parse_request(graph_request([group_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'No group in these notifications could be reported as new')
  end

  it 'reports the groups Microsoft Graph returns and logs the ids that are deleted, asking /groups deleted items' do
    store_subscription
    allow(trigger).to receive(:log)
    stub_lookup([group_id, second_group_id], [created(group_id, 5)])
    stub_deleted([second_group_id], [second_group_id])
    output = trigger.parse_request(graph_request([group_id, second_group_id]))
    expect(output.to_h['groups'].map { |group| group['group_id'] }).to eq([group_id])
    expect(trigger).to have_received(:log)
      .with("These changed objects are deleted, so they are not reported: #{second_group_id}")
  end

  it 'asks Microsoft to send again when a sent group id is neither returned nor deleted' do
    store_subscription
    stub_lookup([group_id, second_group_id], [created(group_id, 5)])
    stub_deleted([second_group_id], [])
    expect { trigger.parse_request(graph_request([group_id, second_group_id])) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, /\Agraph-retry: Microsoft Graph does not show 1 changed/)
  end
end
