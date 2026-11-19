require 'spec_helper'

describe 'Microsoft Entra New or Updated Group Trigger', :ms_entra, :trigger do
  let(:trigger_template_id) { '01a1a1c8-debd-7198-a231-55393b18083d' }
  let(:store_key) { MsEntraConnector::SUBSCRIPTIONS_STORE_KEY }
  let(:trigger_config) { {} }
  let(:subscription_id) { '0fc0f4a5-3f6e-4bc5-9d1a-52e2c5b81e0c' }
  let(:client_state) { 'ca1fe1f8-4a51-4a45-9d2a-8b1a1de0b7c2' }
  let(:second_group_id) { '6c2f1d9b-3a7e-4d4b-8f82-1e5c9b7a3d20' }

  def notification(id)
    { subscriptionId: subscription_id, changeType: 'updated', resource: "Groups/#{id}",
      clientState: client_state, resourceData: { '@odata.type': '#Microsoft.Graph.Group', id: id }, }
  end

  def graph_request(ids)
    body = { value: ids.map { |id| notification(id) } }.to_json
    env = Rack::MockRequest.env_for('/inbound', method: 'POST', input: body, 'CONTENT_TYPE' => 'application/json')
    Rack::Request.new(env)
  end

  def stored_row
    trigger.outbound_connection.store.read(store_key)[trigger.runbook.uuid]
  end

  it 'records the groups resource and the updated change type' do
    trigger.provision
    expect(stored_row).to eq('resource' => 'groups', 'change_type' => 'updated', 'endpoint' => trigger.endpoint)
  end

  it 'emits the ids of the changed groups and the subscription id' do
    row = { 'resource' => 'groups', 'change_type' => 'updated', 'endpoint' => trigger.endpoint,
            'id' => subscription_id, 'client_state' => make_secret_string(client_state).to_s, }
    trigger.outbound_connection.store.write(store_key, trigger.runbook.uuid => row)
    output = trigger.parse_request(graph_request([group_id, second_group_id]))
    expect(output.to_h).to eq('groups' => [{ 'group_id' => group_id }, { 'group_id' => second_group_id }],
                              'subscription_id' => subscription_id)
    expect(a_request(:get, /graph\.microsoft\.com/)).not_to have_been_made
  end
end
