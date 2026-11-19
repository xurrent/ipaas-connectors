require 'spec_helper'

describe 'Microsoft Intune Rotate Local Admin Password (Beta) Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-2645-718c-96a4-02cff20a3f5f' }
  let(:rotate_url) { "#{beta}/deviceManagement/managedDevices/#{device_id}/rotateLocalAdminPassword" }

  def stub_rotate(status: 204, body: '')
    stub_request(:post, rotate_url)
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
    it 'posts rotateLocalAdminPassword on beta with no body and returns the device id' do
      stub_rotate
      expect(run_action({ device_id: device_id })).to eq('device_id' => device_id)
      expect(@sent_body.to_s).to eq('')
    end

    it 'fails naming DeviceManagementManagedDevices.PrivilegedOperations.All on 403' do
      stub_rotate(status: 403, body: access_denied)
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        access_denied_failure('DeviceManagementManagedDevices.PrivilegedOperations.All'))
    end

    it 'fails with no request when the device id is a dot segment' do
      expect { run_action({ device_id: '.' }) }
        .to raise_error(IPaaS::Job::FailJob, "Intune device ID '.' is not a valid id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    context 'when the Graph API endpoint does not end in /v1.0' do
      let(:outbound_connection_config) { super().merge(environment: { graph_endpoint: endpoint_outside_v1 }) }

      it 'fails before calling Microsoft' do
        expect { run_action({ device_id: device_id }) }.to raise_error(IPaaS::Job::FailJob, beta_refusal)
        expect(a_request(:post, /graph\./)).not_to have_been_made
      end
    end
  end
end
