require 'spec_helper'

describe 'Microsoft Intune Assign Autopilot Device To User Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-24ea-7dcb-97d4-28050033021b' }
  let(:autopilot_id) { '4f3c2a1b-5d6e-4f70-8a9b-0c1d2e3f4a5b' }
  let(:update_url) do
    "#{graph}/deviceManagement/windowsAutopilotDeviceIdentities/#{autopilot_id}/updateDeviceProperties"
  end

  def stub_update(status: 204, body: '')
    stub_request(:post, update_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'requires the Autopilot device id and the user principal name' do
      schema = action.input_schema
      expect(schema.field(:autopilot_device_id).required).to be_truthy
      expect(schema.field(:user_principal_name).required).to be_truthy
      expect(schema.field(:addressable_user_name).required).to be_falsey
    end
  end

  describe 'output_schema' do
    it 'returns the required Autopilot device id and user principal name' do
      schema = action.output_schema.first
      expect(schema.field(:autopilot_device_id).required).to be_truthy
      expect(schema.field(:user_principal_name).required).to be_truthy
    end
  end

  describe 'run' do
    it 'posts the user principal name and greeting name to updateDeviceProperties on v1.0' do
      stub_update
      output = run_action({ autopilot_device_id: autopilot_id, user_principal_name: ' adele.vance@contoso.com ',
                            addressable_user_name: 'Adele Vance', })
      expect(output).to eq('autopilot_device_id' => autopilot_id, 'user_principal_name' => 'adele.vance@contoso.com')
      expect(@sent).to eq('userPrincipalName' => 'adele.vance@contoso.com', 'addressableUserName' => 'Adele Vance')
    end

    it 'leaves the greeting name out when it is blank' do
      stub_update
      run_action({ autopilot_device_id: autopilot_id, user_principal_name: 'adele.vance@contoso.com',
                   addressable_user_name: ' ', })
      expect(@sent).to eq('userPrincipalName' => 'adele.vance@contoso.com')
    end

    it 'fails naming DeviceManagementServiceConfig.ReadWrite.All on 403' do
      stub_update(status: 403, body: access_denied)
      expect { run_action({ autopilot_device_id: autopilot_id, user_principal_name: 'adele.vance@contoso.com' }) }
        .to raise_error(IPaaS::Job::FailJob,
                        access_denied_failure('DeviceManagementServiceConfig.ReadWrite.All'))
    end

    it 'fails with no request when the Autopilot device id is a dot segment' do
      expect { run_action({ autopilot_device_id: '..', user_principal_name: 'adele.vance@contoso.com' }) }
        .to raise_error(IPaaS::Job::FailJob, "Autopilot device ID '..' is not a valid id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end
  end
end
