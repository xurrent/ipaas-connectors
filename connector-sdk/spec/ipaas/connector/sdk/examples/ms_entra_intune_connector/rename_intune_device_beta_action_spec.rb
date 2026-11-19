require 'spec_helper'

describe 'Microsoft Intune Rename Device (Beta) Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-2402-7ed0-9856-803cb578712c' }
  let(:rename_url) { "#{beta}/deviceManagement/managedDevices/#{device_id}/setDeviceName" }

  def stub_rename(status: 204, body: '')
    stub_request(:post, rename_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body)
  end

  def rename_input
    { device_id: device_id, device_name: ' CONTOSO-LT-0042 ' }
  end

  describe 'input_schema' do
    it 'requires the Intune device id and the new device name' do
      expect(action.input_schema.field(:device_id).required).to be_truthy
      expect(action.input_schema.field(:device_name).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the required device id and device name' do
      schema = action.output_schema.first
      expect(schema.field(:device_id).required).to be_truthy
      expect(schema.field(:device_name).required).to be_truthy
    end
  end

  describe 'run' do
    it 'posts the trimmed device name to the beta setDeviceName endpoint and returns it' do
      stub_rename
      expect(run_action(rename_input)).to eq('device_id' => device_id, 'device_name' => 'CONTOSO-LT-0042')
      expect(@sent).to eq('deviceName' => 'CONTOSO-LT-0042')
    end

    it 'fails naming DeviceManagementManagedDevices.PrivilegedOperations.All on 403' do
      stub_rename(status: 403, body: access_denied)
      expect { run_action(rename_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        access_denied_failure('DeviceManagementManagedDevices.PrivilegedOperations.All'))
    end

    it 'fails with no request when the device id is a dot segment' do
      expect { run_action({ device_id: '..', device_name: 'CONTOSO-LT-0042' }) }
        .to raise_error(IPaaS::Job::FailJob, "Intune device ID '..' is not a valid id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    context 'when the Graph API endpoint ends in /v1.0/' do
      let(:outbound_connection_config) { super().merge(environment: { graph_endpoint: "#{graph}/" }) }

      it 'still calls the beta endpoint' do
        stub_rename
        run_action(rename_input)
        expect(a_request(:post, rename_url)).to have_been_made.once
      end
    end

    context 'when the Graph API endpoint ends in /V1.0 with several slashes' do
      let(:outbound_connection_config) do
        super().merge(environment: { graph_endpoint: 'https://graph.microsoft.com/V1.0//' })
      end

      it 'still calls the beta endpoint' do
        stub_rename
        run_action(rename_input)
        expect(a_request(:post, rename_url)).to have_been_made.once
      end
    end

    context 'when the Graph API endpoint already ends in /beta' do
      let(:outbound_connection_config) { super().merge(environment: { graph_endpoint: "#{beta}/" }) }

      it 'calls that endpoint as it is' do
        stub_rename
        run_action(rename_input)
        expect(a_request(:post, rename_url)).to have_been_made.once
      end
    end

    context 'when the Graph API endpoint does not end in /v1.0' do
      let(:outbound_connection_config) { super().merge(environment: { graph_endpoint: endpoint_outside_v1 }) }

      it 'fails before calling Microsoft' do
        expect { run_action(rename_input) }.to raise_error(IPaaS::Job::FailJob, beta_refusal)
        expect(a_request(:post, /graph\./)).not_to have_been_made
      end
    end
  end
end
