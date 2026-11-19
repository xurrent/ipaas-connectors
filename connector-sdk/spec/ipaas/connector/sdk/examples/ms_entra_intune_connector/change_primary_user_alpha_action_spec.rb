require 'spec_helper'

describe 'Microsoft Intune Change Primary User (Alpha) Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-2473-712a-8d3d-318cb91d8fba' }
  let(:users_ref_url) { "#{beta}/deviceManagement/managedDevices/#{device_id}/users/$ref" }
  let(:user_reference) { { '@odata.id' => "#{beta}/users/#{user_id}" } }

  def stub_change(status: 204, body: '')
    stub_request(:post, users_ref_url)
      .with(body: user_reference.to_json, headers: { 'Content-Type' => 'application/json' })
      .to_return(status: status, body: body)
  end

  def change_input
    { device_id: device_id, user_id: user_id }
  end

  describe 'input_schema' do
    it 'requires the Intune device id and the user id' do
      expect(action.input_schema.field(:device_id).required).to be_truthy
      expect(action.input_schema.field(:user_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the required device id and user id' do
      schema = action.output_schema.first
      expect(schema.field(:device_id).required).to be_truthy
      expect(schema.field(:user_id).required).to be_truthy
    end
  end

  describe 'run' do
    it 'posts the beta user reference to the users $ref of the device and returns both ids on 204' do
      stub_change
      expect(run_action(change_input)).to eq('device_id' => device_id, 'user_id' => user_id)
      expect(a_request(:post, users_ref_url).with(body: user_reference.to_json)).to have_been_made.once
    end

    it 'accepts a 200 answer as well' do
      stub_change(status: 200, body: '{}')
      expect(run_action(change_input)).to eq('device_id' => device_id, 'user_id' => user_id)
    end

    it 'fails naming DeviceManagementManagedDevices.ReadWrite.All, the permission Microsoft names, on 403' do
      stub_change(status: 403, body: access_denied)
      expect { run_action(change_input) }
        .to raise_error(IPaaS::Job::FailJob, access_denied_failure('DeviceManagementManagedDevices.ReadWrite.All'))
    end

    it 'fails with no request when the user id is not a GUID' do
      expect { run_action({ device_id: device_id, user_id: 'adele.vance@contoso.com' }) }
        .to raise_error(IPaaS::Job::FailJob, "User ID 'adele.vance@contoso.com' is not a valid id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails with no request when the device id is a dot segment' do
      expect { run_action({ device_id: '..', user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob, "Intune device ID '..' is not a valid id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    context 'when the Graph API endpoint does not end in /v1.0' do
      let(:outbound_connection_config) { super().merge(environment: { graph_endpoint: endpoint_outside_v1 }) }

      it 'fails before calling Microsoft' do
        expect { run_action(change_input) }.to raise_error(IPaaS::Job::FailJob, beta_refusal)
        expect(a_request(:post, /graph\./)).not_to have_been_made
      end
    end
  end
end
