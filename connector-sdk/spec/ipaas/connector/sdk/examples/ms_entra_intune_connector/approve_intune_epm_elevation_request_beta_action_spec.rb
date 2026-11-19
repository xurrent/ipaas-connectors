require 'spec_helper'

describe 'Microsoft Intune Approve EPM Elevation Request (Beta) Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-2563-7631-aafc-803389571093' }
  let(:request_id) { '3df245af-45af-3df2-af45-f23daf45f23d' }
  let(:approve_url) { "#{beta}/deviceManagement/elevationRequests/#{request_id}/approve" }
  let(:elevation_request) do
    {
      '@odata.type' => '#microsoft.graph.privilegeManagementElevationRequest',
      'id' => request_id,
      'requestedByUserId' => user_id,
      'requestedOnDeviceId' => device_id,
      'requestedByUserPrincipalName' => 'adele.vance@contoso.com',
      'deviceName' => 'CONTOSO-LT-0042',
      'requestCreatedDateTime' => '2026-11-10T08:15:00Z',
      'requestLastModifiedDateTime' => '2026-11-10T08:30:00Z',
      'requestJustification' => 'Need to install the VPN client',
      'applicationDetail' => {
        '@odata.type' => 'microsoft.graph.elevationRequestApplicationDetail',
        'fileHash' => '4c5d6e7f', 'fileName' => 'vpnclient.exe', 'filePath' => 'C:\\Users\\adele\\Downloads',
        'fileDescription' => 'VPN client installer', 'publisherName' => 'Contoso Ltd',
        'publisherCert' => 'CN=Contoso Ltd', 'productName' => 'Contoso VPN', 'productInternalName' => 'vpnclient',
        'productVersion' => '5.2.1',
      },
      'status' => 'approved',
      'reviewCompletedByUserId' => '5b2a1c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
      'reviewCompletedByUserPrincipalName' => 'it.admin@contoso.com',
      'reviewCompletedDateTime' => '2026-11-10T08:30:00Z',
      'requestExpiryDateTime' => '2026-11-11T08:15:00Z',
      'reviewerJustification' => 'Approved in request 70123',
    }
  end
  let(:expected_output) do
    {
      'elevation_request_id' => request_id, 'status' => 'approved', 'requested_by_user_id' => user_id,
      'requested_by_user_principal_name' => 'adele.vance@contoso.com', 'requested_on_device_id' => device_id,
      'device_name' => 'CONTOSO-LT-0042', 'request_justification' => 'Need to install the VPN client',
      'request_created_date_time' => '2026-11-10T08:15:00Z',
      'request_last_modified_date_time' => '2026-11-10T08:30:00Z',
      'request_expiry_date_time' => '2026-11-11T08:15:00Z',
      'review_completed_by_user_id' => '5b2a1c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
      'review_completed_by_user_principal_name' => 'it.admin@contoso.com',
      'review_completed_date_time' => '2026-11-10T08:30:00Z',
      'reviewer_justification' => 'Approved in request 70123',
      'application_detail' => {
        'file_hash' => '4c5d6e7f', 'file_name' => 'vpnclient.exe', 'file_path' => 'C:\\Users\\adele\\Downloads',
        'file_description' => 'VPN client installer', 'publisher_name' => 'Contoso Ltd',
        'publisher_cert' => 'CN=Contoso Ltd', 'product_name' => 'Contoso VPN',
        'product_internal_name' => 'vpnclient', 'product_version' => '5.2.1',
      },
    }
  end

  def stub_approve(status: 200, body: { value: elevation_request }.to_json)
    stub_request(:post, approve_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def approve_input
    { elevation_request_id: request_id, reviewer_justification: ' Approved in request 70123 ' }
  end

  describe 'input_schema' do
    it 'requires the elevation request id and takes an optional justification' do
      expect(action.input_schema.field(:elevation_request_id).required).to be_truthy
      expect(action.input_schema.field(:reviewer_justification).required).to be_falsey
    end
  end

  describe 'output_schema' do
    it 'returns the request id and the nested application detail' do
      schema = action.output_schema.first
      expect(schema.field(:elevation_request_id).required).to be_truthy
      expect(schema.field(:application_detail).type).to eq(:nested)
      expect(schema.field(:application_detail).field(:file_name).type).to eq(:string)
    end
  end

  describe 'run' do
    it 'posts the trimmed justification to the beta approve endpoint and maps the request Graph wraps in value' do
      stub_approve
      expect(run_action(approve_input)).to eq(expected_output)
      expect(@sent).to eq('reviewerJustification' => 'Approved in request 70123')
    end

    it 'maps a request that Graph returns at the top level and sends an empty justification when none is given' do
      stub_approve(body: elevation_request.to_json)
      expect(run_action({ elevation_request_id: request_id })).to eq(expected_output)
      expect(@sent).to eq('reviewerJustification' => '')
    end

    it 'returns an empty application detail when Graph sends none' do
      stub_approve(body: { value: elevation_request.except('applicationDetail') }.to_json)
      expect(run_action(approve_input)['application_detail']).to eq({})
    end

    it 'fails when Graph answers with something that is not an object' do
      stub_approve(body: '[]')
      expect { run_action(approve_input) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned a value that is not an object.')
    end

    it 'fails when Graph answers with something that is not JSON' do
      stub_approve(body: 'approved')
      expect { run_action(approve_input) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned a response that is not JSON.')
    end

    it 'fails naming DeviceManagementConfiguration.ReadWrite.All on 403' do
      stub_approve(status: 403, body: access_denied)
      expect { run_action(approve_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        access_denied_failure('DeviceManagementConfiguration.ReadWrite.All'))
    end

    it 'fails with no request when the elevation request id is a dot segment' do
      expect { run_action({ elevation_request_id: '..' }) }
        .to raise_error(IPaaS::Job::FailJob, "Elevation request ID '..' is not a valid id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    context 'when the Graph API endpoint does not end in /v1.0' do
      let(:outbound_connection_config) { super().merge(environment: { graph_endpoint: endpoint_outside_v1 }) }

      it 'fails before calling Microsoft' do
        expect { run_action(approve_input) }.to raise_error(IPaaS::Job::FailJob, beta_refusal)
        expect(a_request(:post, /graph\./)).not_to have_been_made
      end
    end
  end
end
