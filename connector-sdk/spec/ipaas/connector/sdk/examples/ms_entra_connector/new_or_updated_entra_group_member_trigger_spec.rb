require 'spec_helper'

describe 'Microsoft Entra New or Updated Group Member Trigger', :ms_entra, :trigger do
  let(:trigger_template_id) { '01a1a1c8-debd-7d82-85a7-58459994a3ed' }
  let(:store_key) { MsEntraConnector::SUBSCRIPTIONS_STORE_KEY }
  let(:trigger_config) { { group_id: group_id } }
  let(:subscription_id) { '0fc0f4a5-3f6e-4bc5-9d1a-52e2c5b81e0c' }
  let(:client_state) { 'ca1fe1f8-4a51-4a45-9d2a-8b1a1de0b7c2' }
  let(:member_resource) { "groups/#{group_id}/members" }
  let(:removed_member_id) { '5b1c7d0e-6f4a-4c2b-9e8d-3a2f1b0c9d8e' }
  let(:other_group_id) { 'c3a1e5f7-2b4d-4f6a-8c0e-1d3b5a7f9e2c' }

  def notification(members_delta, notified_group_id = group_id)
    { subscriptionId: subscription_id, changeType: 'updated', resource: "Groups/#{notified_group_id}",
      clientState: client_state,
      resourceData: { '@odata.type': '#Microsoft.Graph.Group', '@odata.id': "Groups/#{notified_group_id}",
                      id: notified_group_id, 'members@delta': members_delta, }.compact, }
  end

  def graph_request(*notifications)
    env = Rack::MockRequest.env_for('/inbound', method: 'POST', input: { value: notifications }.to_json,
                                                'CONTENT_TYPE' => 'application/json')
    Rack::Request.new(env)
  end

  def store_subscription
    row = { 'resource' => member_resource, 'change_type' => 'updated',
            'endpoint' => trigger.endpoint, 'id' => subscription_id,
            'client_state' => make_secret_string(client_state).to_s, }
    trigger.outbound_connection.store.write(store_key, trigger.runbook.uuid => row)
  end

  def stored_rows
    trigger.outbound_connection.store.read(store_key) || {}
  end

  it 'records the members resource of the configured group and the updated change type' do
    trigger.provision
    expect(stored_rows[trigger.runbook.uuid])
      .to eq('resource' => member_resource, 'change_type' => 'updated', 'endpoint' => trigger.endpoint)
  end

  it 'fails provision for a group id that is not a GUID and records nothing' do
    trigger.config[:group_id] = 'Finance team'
    expect { trigger.provision }
      .to raise_error(IPaaS::Job::FailJob, "Group ID 'Finance team' is not a Microsoft Entra object id (a GUID).")
    expect(stored_rows).to eq({})
  end

  it 'emits one change per member in members@delta, removed true only for the member Microsoft marks removed' do
    store_subscription
    members_delta = [{ id: user_id }, { id: removed_member_id, '@removed': 'deleted' }]
    output = trigger.parse_request(graph_request(notification(members_delta)))
    expect(output.to_h).to eq(
      'group_id' => group_id,
      'changes' => [{ 'member_id' => user_id, 'removed' => false },
                    { 'member_id' => removed_member_id, 'removed' => true },],
      'subscription_id' => subscription_id
    )
  end

  it 'discards a notification that names no member who joined or left' do
    store_subscription
    expect { trigger.parse_request(graph_request(notification(nil))) }
      .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'No notification named a member who joined or left the group')
  end

  it 'leaves out a member entry that has no id' do
    store_subscription
    output = trigger.parse_request(graph_request(notification([{ id: user_id }, { '@removed': 'deleted' }])))
    expect(output.to_h['changes']).to eq([{ 'member_id' => user_id, 'removed' => false }])
  end

  it 'leaves out a notification about a group other than the one the trigger watches' do
    store_subscription
    request = graph_request(notification([{ id: removed_member_id }], other_group_id), notification([{ id: user_id }]))
    expect(trigger.parse_request(request).to_h['changes']).to eq([{ 'member_id' => user_id, 'removed' => false }])
  end

  it 'keeps the members of a notification that names the watched group in upper case' do
    store_subscription
    request = graph_request(notification([{ id: user_id }], group_id.upcase))
    expect(trigger.parse_request(request).to_h['changes']).to eq([{ 'member_id' => user_id, 'removed' => false }])
  end
end
