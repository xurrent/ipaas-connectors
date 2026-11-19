require 'spec_helper'

describe 'Microsoft Intune Fresh Start Device Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-230f-7920-b44f-ae0546793092' }
  let(:clean_url) { "#{graph}/deviceManagement/managedDevices/#{device_id}/cleanWindowsDevice" }

  def stub_clean(status: 204, body: '')
    stub_request(:post, clean_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'requires the Intune device id and takes an optional keep user data boolean' do
      expect(action.input_schema.field(:device_id).required).to be_truthy
      expect(action.input_schema.field(:keep_user_data).type).to eq(:boolean)
      expect(action.input_schema.field(:keep_user_data).required).to be_falsey
    end
  end

  describe 'output_schema' do
    it 'returns the required device id and keep user data' do
      schema = action.output_schema.first
      expect(schema.field(:device_id).required).to be_truthy
      expect(schema.field(:keep_user_data).required).to be_truthy
    end
  end

  describe 'run' do
    it 'posts keepUserData true when it is set and returns it' do
      stub_clean
      expect(run_action({ device_id: device_id, keep_user_data: true }))
        .to eq('device_id' => device_id, 'keep_user_data' => true)
      expect(@sent).to eq('keepUserData' => true)
    end

    it 'posts keepUserData false when it is not set' do
      stub_clean
      expect(run_action({ device_id: device_id })).to eq('device_id' => device_id, 'keep_user_data' => false)
      expect(@sent).to eq('keepUserData' => false)
    end

    it 'fails naming DeviceManagementManagedDevices.PrivilegedOperations.All on 403' do
      stub_clean(status: 403, body: access_denied)
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        access_denied_failure('DeviceManagementManagedDevices.PrivilegedOperations.All'))
    end

    it 'fails with no request when the device id is not a GUID' do
      expect { run_action({ device_id: ' not-a-guid ' }) }
        .to raise_error(IPaaS::Job::FailJob, "Intune device ID 'not-a-guid' is not a valid id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end
  end
end
