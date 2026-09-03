require 'spec_helper'

describe 'Microsoft Graph List Managed Devices Action', :action, :microsoft_graph do
  let(:action_template_id) { '019ff9e8-8af5-7c17-bc22-e10d57fb9bb4' }
  let(:devices_url) { 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices' }

  let(:sample_device) do
    {
      id: 'device-1',
      deviceName: 'JANES-LAPTOP',
      operatingSystem: 'Windows',
      osVersion: '10.0.19045',
      complianceState: 'compliant',
      managedDeviceOwnerType: 'company',
      userPrincipalName: 'jane@contoso.com',
      lastSyncDateTime: '2026-08-01T00:00:00Z',
      model: 'Latitude 5420',
      manufacturer: 'Dell',
      serialNumber: 'ABC123',
    }
  end

  before { stub_graph_token }

  it 'lists devices and maps fields to snake_case' do
    stub_request(:get, devices_url).with(query: { '$top' => '100' })
                                   .to_return(status: 200, body: { value: [sample_device] }.to_json)

    output = run_action({})

    expect(output[:has_next_page]).to eq(false)
    device = output[:devices].first
    expect(device[:id]).to eq('device-1')
    expect(device[:device_name]).to eq('JANES-LAPTOP')
    expect(device[:compliance_state]).to eq('compliant')
    expect(device[:serial_number]).to eq('ABC123')
  end

  it 'paginates via the next link' do
    next_link = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?$top=100&$skiptoken=xyz'
    stub_request(:get, devices_url).with(query: { '$top' => '100' })
                                   .to_return(status: 200, body: { value: [sample_device],
                                                                   '@odata.nextLink': next_link, }.to_json)

    output = run_action({})

    expect(output[:has_next_page]).to eq(true)
  end

  it 'fails when Microsoft Graph rejects the request' do
    stub_request(:get, devices_url).with(query: { '$top' => '100' })
                                   .to_return(status: 403, body: { error: { code: 'Forbidden',
                                                                            message: 'Missing permission.', } }.to_json)

    expect { run_action({}) }
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [Forbidden]: Missing permission.')
  end
end
