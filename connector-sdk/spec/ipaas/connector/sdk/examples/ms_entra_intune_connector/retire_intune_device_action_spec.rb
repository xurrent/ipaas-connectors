require 'spec_helper'

describe 'Microsoft Intune Retire Device Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-2226-761e-ad75-9a6f29498827' }
  let(:command_url) { "#{graph}/deviceManagement/managedDevices/#{device_id}/retire" }

  def stub_command(status: 204, body: '')
    stub_request(:post, command_url)
      .with { |request| @sent_body = request.body }
      .to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'defines a required Intune device id string' do
      field = action.input_schema.field(:device_id)
      expect(field.type).to eq(:string)
      expect(field.required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the required Intune device id' do
      expect(action.output_schema.first.field(:device_id).required).to be_truthy
    end
  end

  describe 'run' do
    it 'posts retire on v1.0 with no body and returns the device id' do
      stub_command
      expect(run_action({ device_id: device_id })).to eq('device_id' => device_id)
      expect(@sent_body.to_s).to eq('')
    end

    it 'fails naming DeviceManagementManagedDevices.PrivilegedOperations.All on 403' do
      stub_command(status: 403, body: access_denied)
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        access_denied_failure('DeviceManagementManagedDevices.PrivilegedOperations.All'))
    end

    it 'fails with no request when the device id is a dot segment' do
      expect { run_action({ device_id: '..' }) }
        .to raise_error(IPaaS::Job::FailJob, "Intune device ID '..' is not a valid id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end
  end
end
