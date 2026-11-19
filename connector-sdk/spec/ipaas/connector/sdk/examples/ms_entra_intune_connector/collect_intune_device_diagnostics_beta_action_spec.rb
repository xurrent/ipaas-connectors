require 'spec_helper'

describe 'Microsoft Intune Collect Device Diagnostics (Beta) Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-2807-7459-8434-7edcfd84a9d1' }
  let(:collect_url) { "#{beta}/deviceManagement/managedDevices/#{device_id}/createDeviceLogCollectionRequest" }
  let(:log_request) do
    {
      '@odata.type' => '#microsoft.graph.deviceLogCollectionResponse',
      'id' => "#{tenant_id}_#{device_id}_05fb97dc-97dc-05fb-dc97-fb05dc97fb05",
      'status' => 'pending',
      'managedDeviceId' => device_id,
      'errorCode' => 0,
      'requestedDateTimeUTC' => '2026-11-10T09:00:00Z',
      'receivedDateTimeUTC' => '2026-11-10T09:05:00Z',
      'initiatedByUserPrincipalName' => 'it.admin@contoso.com',
      'expirationDateTimeUTC' => '2026-12-10T09:00:00Z',
      'size' => 2.5,
      'sizeInKB' => 2.5,
      'enrolledByUser' => 'adele.vance@contoso.com',
    }
  end

  def stub_collect(status: 200, body: { value: log_request }.to_json)
    stub_request(:post, collect_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'defines a required Intune device id string' do
      expect(action.input_schema.field(:device_id).type).to eq(:string)
      expect(action.input_schema.field(:device_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the log collection request with its sizes as floats and its error code as an integer' do
      schema = action.output_schema.first
      expect(schema.field(:request_id).type).to eq(:string)
      expect(schema.field(:size_in_kb).type).to eq(:float)
      expect(schema.field(:size).type).to eq(:float)
      expect(schema.field(:error_code).type).to eq(:integer)
    end
  end

  describe 'run' do
    it 'posts the predefined template on beta and maps the request Graph wraps in value' do
      stub_collect
      expect(run_action({ device_id: device_id })).to eq(
        'request_id' => "#{tenant_id}_#{device_id}_05fb97dc-97dc-05fb-dc97-fb05dc97fb05", 'status' => 'pending',
        'managed_device_id' => device_id, 'requested_date_time_utc' => '2026-11-10T09:00:00Z',
        'received_date_time_utc' => '2026-11-10T09:05:00Z', 'expiration_date_time_utc' => '2026-12-10T09:00:00Z',
        'initiated_by_user_principal_name' => 'it.admin@contoso.com', 'enrolled_by_user' => 'adele.vance@contoso.com',
        'size_in_kb' => 2.5, 'error_code' => 0, 'size' => 2.5
      )
      expect(@sent).to eq('templateType' => { '@odata.type' => 'microsoft.graph.deviceLogCollectionRequest',
                                              'templateType' => 'predefined', })
    end

    it 'returns a whole number size as a float and a null received time as nil for a pending request' do
      stub_collect(body: log_request.merge('sizeInKB' => 0, 'receivedDateTimeUTC' => nil).to_json)
      output = run_action({ device_id: device_id })
      expect(output['size_in_kb']).to eql(0.0)
      expect(output['received_date_time_utc']).to be_nil
    end

    it 'fails when Graph wraps a null value' do
      stub_collect(body: { value: nil }.to_json)
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned a value that is not an object.')
    end

    it 'fails when Graph wraps an array value' do
      stub_collect(body: { value: [log_request] }.to_json)
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned a value that is not an object.')
    end

    it 'fails when Graph wraps a string value' do
      stub_collect(body: { value: 'pending' }.to_json)
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned a value that is not an object.')
    end

    it 'fails with the response body when Graph answers 502 with no error object' do
      stub_collect(status: 502, body: 'Bad gateway')
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned HTTP 502 : Bad gateway')
    end

    it 'fails naming DeviceManagementManagedDevices.ReadWrite.All on 403' do
      stub_collect(status: 403, body: access_denied)
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        access_denied_failure('DeviceManagementManagedDevices.ReadWrite.All'))
    end

    it 'fails asking for the Intune device id on 404' do
      stub_collect(status: 404, body: graph_error('ResourceNotFound', 'Device not found.'))
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 404 ResourceNotFound: Device not found. Check that the ID is ' \
                        'the Intune device ID: the id of the managed device, which Managed devices from Intune ' \
                        'returns as device_id.')
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
