require 'spec_helper'

describe 'Microsoft Intune Delete Device Record Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-279c-75e3-8838-16c5c30519a5' }
  let(:device_url) { "#{graph}/deviceManagement/managedDevices/#{device_id}" }

  def stub_delete(status: 204, body: '')
    stub_request(:delete, device_url).to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'defines a required Intune device id string' do
      expect(action.input_schema.field(:device_id).type).to eq(:string)
      expect(action.input_schema.field(:device_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the required device id and existed boolean' do
      schema = action.output_schema.first
      expect(schema.field(:device_id).required).to be_truthy
      expect(schema.field(:existed).type).to eq(:boolean)
    end
  end

  describe 'run' do
    it 'deletes the managed device on v1.0 and reports that it existed' do
      stub_delete
      expect(run_action({ device_id: device_id })).to eq('device_id' => device_id, 'existed' => true)
      expect(a_request(:delete, device_url)).to have_been_made.once
    end

    it 'reports that the device did not exist on 404' do
      stub_delete(status: 404, body: graph_error('ResourceNotFound', 'Not found'))
      expect(run_action({ device_id: device_id })).to eq('device_id' => device_id, 'existed' => false)
    end

    it 'fails naming DeviceManagementManagedDevices.ReadWrite.All on 403' do
      stub_delete(status: 403, body: access_denied)
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        access_denied_failure('DeviceManagementManagedDevices.ReadWrite.All'))
    end

    it 'fails with no request when the device id is a dot segment' do
      expect { run_action({ device_id: '..' }) }
        .to raise_error(IPaaS::Job::FailJob, "Intune device ID '..' is not a valid id (a GUID).")
      expect(a_request(:delete, /graph\.microsoft\.com/)).not_to have_been_made
    end
  end
end
