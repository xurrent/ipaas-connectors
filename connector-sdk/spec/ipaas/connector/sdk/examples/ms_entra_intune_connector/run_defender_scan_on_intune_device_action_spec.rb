require 'spec_helper'

describe 'Microsoft Intune Run Defender Scan Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-2388-77a4-bf27-883d6b8746d1' }
  let(:scan_url) { "#{graph}/deviceManagement/managedDevices/#{device_id}/windowsDefenderScan" }

  def stub_scan(status: 204, body: '')
    stub_request(:post, scan_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'requires the Intune device id and defaults quick scan to true' do
      expect(action.input_schema.field(:device_id).required).to be_truthy
      expect(action.input_schema.field(:quick_scan).type).to eq(:boolean)
      expect(action.input_schema.field(:quick_scan).default).to be(true)
    end
  end

  describe 'output_schema' do
    it 'returns the required device id and quick scan' do
      schema = action.output_schema.first
      expect(schema.field(:device_id).required).to be_truthy
      expect(schema.field(:quick_scan).required).to be_truthy
    end
  end

  describe 'run' do
    it 'posts a quick scan when quick scan is not set' do
      stub_scan
      expect(run_action({ device_id: device_id })).to eq('device_id' => device_id, 'quick_scan' => true)
      expect(@sent).to eq('quickScan' => true)
    end

    it 'posts a full scan when quick scan is false' do
      stub_scan
      expect(run_action({ device_id: device_id, quick_scan: false }))
        .to eq('device_id' => device_id, 'quick_scan' => false)
      expect(@sent).to eq('quickScan' => false)
    end

    it 'fails naming DeviceManagementManagedDevices.PrivilegedOperations.All on 403' do
      stub_scan(status: 403, body: access_denied)
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        access_denied_failure('DeviceManagementManagedDevices.PrivilegedOperations.All'))
    end

    it 'fails with no request when the device id is a dot segment' do
      expect { run_action({ device_id: '.' }) }
        .to raise_error(IPaaS::Job::FailJob, "Intune device ID '.' is not a valid id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end
  end
end
