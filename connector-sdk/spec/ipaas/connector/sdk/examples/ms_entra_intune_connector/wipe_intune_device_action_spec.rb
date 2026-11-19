require 'spec_helper'

describe 'Microsoft Intune Wipe Device Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-22a2-7b4d-bb27-edc74a5afe29' }
  let(:wipe_url) { "#{graph}/deviceManagement/managedDevices/#{device_id}/wipe" }

  def stub_wipe(status: 204, body: '')
    stub_request(:post, wipe_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'takes only the declared v1.0 wipe options, requires the device id and keeps the unlock code secret' do
      schema = action.input_schema
      expect(schema.field(:device_id).required).to be_truthy
      expect(schema.fields.map(&:id).select { |id| schema.field(id).required }).to eq([:device_id])
      expect(schema.field(:mac_os_unlock_code).type).to eq(:secret_string)
      expect(schema.fields.map(&:id))
        .to eq([:device_id, :keep_enrollment_data, :keep_user_data, :mac_os_unlock_code, :persist_esim_data_plan])
    end
  end

  describe 'output_schema' do
    it 'returns the required Intune device id' do
      expect(action.output_schema.first.field(:device_id).required).to be_truthy
    end
  end

  describe 'run' do
    it 'posts every option that is set, with the unlock code decrypted, and returns the device id' do
      stub_wipe
      output = run_action({ device_id: device_id, keep_enrollment_data: true, keep_user_data: false,
                            mac_os_unlock_code: make_secret_string('123456'), persist_esim_data_plan: true, })
      expect(output).to eq('device_id' => device_id)
      expect(@sent).to eq('keepEnrollmentData' => true, 'keepUserData' => false, 'macOsUnlockCode' => '123456',
                          'persistEsimDataPlan' => true)
    end

    it 'does not send obliterationBehavior, which the v1.0 metadata does not declare, even when the input has it' do
      stub_wipe
      run_action({ device_id: device_id, obliteration_behavior: 'doNotObliterate' })
      expect(@sent).to eq({})
    end

    it 'sends no unlock code when the unlock code is empty' do
      stub_wipe
      run_action({ device_id: device_id, mac_os_unlock_code: make_secret_string('') })
      expect(@sent).to eq({})
    end

    it 'posts an empty body when no option is set' do
      stub_wipe
      run_action({ device_id: device_id })
      expect(@sent).to eq({})
    end

    it 'fails naming DeviceManagementManagedDevices.PrivilegedOperations.All on 403' do
      stub_wipe(status: 403, body: access_denied)
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
