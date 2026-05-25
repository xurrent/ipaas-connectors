require 'spec_helper'

describe 'Virima Fetch Devices Action', :action do
  let(:connector_id) { '019b91f0-cfe4-7648-9d97-3854c4c0e0f0' }
  let(:action_template_id) { '019b91f1-7f30-7861-8c1a-b055f865f89a' }

  let(:api_endpoint) { 'https://login.virima.com' }
  let(:devices_url) { "#{api_endpoint}/www_em/rest/get-records/get-all/0/100" }

  let(:outbound_connection_config) do
    {
      credentials: {
        api_key: make_secret_string('test-api-key'),
        tenant_id: 'test-tenant-id',
      },
      api_endpoint: api_endpoint,
    }
  end

  let(:sample_device) do
    {
      id: 1,
      recordId: '3d778a6a-a75f-4cd7-995f-07d5fc037087',
      isProcessing: false,
      patternScanRunning: false,
      isChanged: false,
      isAWSImport: false,
      isEditable: false,
      hasChangeRequest: false,
      createdOn: 0,
      lastModifiedOn: 1_762_932_754_348,
      blueprint: {
        id: 11,
        name: 'Windows Server',
        icon: 'windows-server.png',
        component: false,
        configureMainPage: '[]',
      },
      privatePropertyVisibility: false,
      isTemporaryAccessGiven: false,
      hardwareAsset: {
        stringobj: '',
      },
      lastSeen: 0,
      missingComponents: false,
      isMoved: 'False',
      cherwellSync: 'False',
      jiraSync: 'False',
      properties: [
        {
          groupName: 'Asset Primary Information',
          propertyName: 'Asset Name',
          propertyValue: 'ADSERVERLD @ 10.14.80.36',
          mandatory: 'true',
          type: 'text',
          privateProperty: false,
        },
        {
          groupName: 'Asset Primary Information',
          propertyName: 'Host Name',
          propertyValue: 'ADSERVERLD Test1',
          mandatory: 'true',
          type: 'text',
          privateProperty: false,
        },
        {
          groupName: 'Asset Primary Information',
          propertyName: 'Last Scanned On',
          propertyValue: '',
          mandatory: '',
          type: 'bigint',
          privateProperty: false,
        },
        {
          groupName: 'Device Details',
          propertyName: 'Device Object ID',
          propertyValue: '',
          mandatory: '',
          type: 'text',
          privateProperty: false,
        },
        {
          groupName: 'Hardware and Network',
          propertyName: 'IP Address',
          propertyValue: '10.14.80.36',
          mandatory: 'true',
          type: 'text',
          privateProperty: false,
        },
        {
          groupName: 'Asset Primary Information',
          propertyName: 'Asset ID',
          propertyValue: 'AST000001',
          mandatory: '',
          type: 'text',
          privateProperty: false,
        },
        {
          groupName: 'Hardware and Network',
          propertyName: 'Hardware Model',
          propertyValue: '',
          mandatory: '',
          type: 'text',
          privateProperty: false,
        },
        {
          groupName: 'Installed Software Details',
          propertyName: 'Software Name',
          propertyValue: '',
          mandatory: 'true',
          type: 'text',
          privateProperty: false,
        },
        {
          groupName: 'Installed Software Details',
          propertyName: 'Software Publisher',
          propertyValue: '',
          mandatory: 'true',
          type: 'text',
          privateProperty: false,
        },
        {
          groupName: 'Device Details',
          propertyName: 'Missing Components',
          propertyValue: '',
          mandatory: '',
          type: 'text',
          privateProperty: false,
        },
      ],
      selectedCIs: [],
      groups: [],
    }
  end

  describe 'input_schema' do
    it 'defines optional last_sync_at field' do
      action.input_schema.field(:last_sync_at).tap do |field|
        expect(field.type).to eq(:date_time)
        expect(field.required).to be_falsey
      end
    end

    it 'defines optional page_size field' do
      action.input_schema.field(:page_size).tap do |field|
        expect(field.type).to eq(:integer)
        expect(field.default).to eq(100)
        expect(field.required).to be_falsey
      end
    end
  end

  describe 'output_schema' do
    let(:page_schema) { action.output_schema.first }
    let(:devices_field) { page_schema.field(:devices) }

    it 'defines page level fields' do
      expect(page_schema.field(:total).type).to eq(:integer)
      expect(page_schema.field(:has_next_page).type).to eq(:boolean)
      expect(page_schema.field(:has_next_page).required).to be_truthy
    end

    it 'defines devices array with required fields' do
      expect(devices_field.array).to be_truthy
      expect(devices_field.field(:id).type).to eq(:integer)
      expect(devices_field.field(:id).required).to be_truthy
      expect(devices_field.field(:record_id).type).to eq(:string)
      expect(devices_field.field(:record_id).required).to be_truthy
    end

    it 'defines device boolean fields' do
      expect(devices_field.field(:is_processing).type).to eq(:boolean)
      expect(devices_field.field(:pattern_scan_running).type).to eq(:boolean)
      expect(devices_field.field(:is_changed).type).to eq(:boolean)
      expect(devices_field.field(:is_aws_import).type).to eq(:boolean)
      expect(devices_field.field(:is_editable).type).to eq(:boolean)
      expect(devices_field.field(:has_change_request).type).to eq(:boolean)
      expect(devices_field.field(:private_property_visibility).type).to eq(:boolean)
      expect(devices_field.field(:is_temporary_access_given).type).to eq(:boolean)
      expect(devices_field.field(:missing_components).type).to eq(:boolean)
    end

    it 'defines device timestamp fields as date_time' do
      expect(devices_field.field(:created_on).type).to eq(:date_time)
      expect(devices_field.field(:last_modified_on).type).to eq(:date_time)
      expect(devices_field.field(:last_seen).type).to eq(:date_time)
    end

    it 'defines device string fields' do
      expect(devices_field.field(:is_moved).type).to eq(:string)
      expect(devices_field.field(:cherwell_sync).type).to eq(:string)
      expect(devices_field.field(:jira_sync).type).to eq(:string)
    end

    it 'defines blueprint nested field' do
      blueprint_field = devices_field.field(:blueprint)
      expect(blueprint_field.type).to eq(:nested)
      expect(blueprint_field.field(:id).type).to eq(:integer)
      expect(blueprint_field.field(:name).type).to eq(:string)
      expect(blueprint_field.field(:icon).type).to eq(:string)
      expect(blueprint_field.field(:component).type).to eq(:boolean)
      expect(blueprint_field.field(:configure_main_page).type).to eq(:string)
    end

    it 'defines hardware_asset nested field' do
      hardware_asset_field = devices_field.field(:hardware_asset)
      expect(hardware_asset_field.type).to eq(:nested)
      expect(hardware_asset_field.field(:stringobj).type).to eq(:string)
    end

    it 'defines properties array field' do
      properties_field = devices_field.field(:properties)
      expect(properties_field.type).to eq(:nested)
      expect(properties_field.array).to be_truthy
      expect(properties_field.field(:group_name).type).to eq(:string)
      expect(properties_field.field(:property_name).type).to eq(:string)
      expect(properties_field.field(:property_value).type).to eq(:string)
      expect(properties_field.field(:mandatory).type).to eq(:string)
      expect(properties_field.field(:type).type).to eq(:string)
      expect(properties_field.field(:private_property).type).to eq(:boolean)
    end

    it 'defines selected_cis and groups array fields' do
      expect(devices_field.field(:selected_cis).type).to eq(:nested)
      expect(devices_field.field(:selected_cis).array).to be_truthy
      expect(devices_field.field(:groups).type).to eq(:nested)
      expect(devices_field.field(:groups).array).to be_truthy
    end
  end

  describe 'iteration_state_schema' do
    it 'defines offset field' do
      expect(action.iteration_state_schema.field(:offset).type).to eq(:integer)
    end
  end

  describe 'run' do
    describe 'successful fetch' do
      it 'fetches devices with correct headers' do
        stub = stub_request(:post, devices_url)
               .with(
                 headers: {
                   'Api-Key' => 'test-api-key',
                   'Tenant-Id' => 'test-tenant-id',
                   'Content-Type' => 'application/json',
                 },
                 body: hash_including(className: 'CmdbCi')
               )
               .to_return(
                 status: 200,
                 body: {
                   totalResults: 1,
                   responseList: [sample_device].to_json,
                 }.to_json
               )

        output = run_action({})

        expect(output[:total]).to eq(1)
        expect(output[:devices].first[:record_id]).to eq('3d778a6a-a75f-4cd7-995f-07d5fc037087')
        expect(stub).to have_been_requested.once
      end

      it 'converts device data to snake_case and transforms timestamps' do
        stub_request(:post, devices_url)
          .to_return(body: {
            totalResults: 1,
            responseList: [sample_device].to_json,
          }.to_json)

        output = run_action({})
        device = output[:devices].first

        expect(device[:blueprint][:name]).to eq('Windows Server')
        expect(device[:blueprint][:id]).to eq(11)
        expect(device[:last_modified_on]).to be_a(DateTime)
        expect(device[:created_on]).to be_a(DateTime)
        expect(device[:created_on]).to eq(Time.at(0).utc.to_datetime)
        expect(device[:last_seen]).to be_a(DateTime)
        expect(device[:last_seen]).to eq(Time.at(0).utc.to_datetime)
        expect(device[:is_processing]).to eq(false)
        expect(device[:properties].first[:property_name]).to eq('Asset Name')
      end

      it 'converts nil timestamps to nil' do
        device_with_nil_timestamps = sample_device.merge(createdOn: nil, lastModifiedOn: nil, lastSeen: nil)
        stub_request(:post, devices_url)
          .to_return(body: {
            totalResults: 1,
            responseList: [device_with_nil_timestamps].to_json,
          }.to_json)

        output = run_action({})
        device = output[:devices].first

        expect(device[:created_on]).to be_nil
        expect(device[:last_modified_on]).to be_nil
        expect(device[:last_seen]).to be_nil
      end

      it 'returns empty devices array when no devices exist' do
        stub_request(:post, devices_url)
          .to_return(body: {
            totalResults: 0,
            responseList: [].to_json,
          }.to_json)

        output = run_action({})

        expect(output[:total]).to eq(0)
        expect(output[:has_next_page]).to eq(false)
        expect(output[:devices]).to eq([])
      end
    end

    describe 'pagination' do
      it 'sets iteration state when more pages available' do
        stub_request(:post, devices_url)
          .to_return(body: {
            totalResults: 200,
            responseList: Array.new(100) { sample_device }.to_json,
          }.to_json)

        expect(action(page_size: 100))
          .to receive(:iteration_state_value=)
          .with({ offset: 100 })
          .and_call_original

        output = run_action({ page_size: 100 })
        expect(output[:has_next_page]).to eq(true)
      end

      it 'clears iteration state on last page' do
        stub_request(:post, devices_url)
          .to_return(body: {
            totalResults: 50,
            responseList: Array.new(50) { sample_device }.to_json,
          }.to_json)

        expect(action(page_size: 100))
          .to receive(:iteration_state_value=)
          .with(nil)
          .and_call_original

        output = run_action({ page_size: 100 })
        expect(output[:has_next_page]).to eq(false)
      end

      it 'uses offset from iteration state in URL' do
        second_page_url = "#{api_endpoint}/www_em/rest/get-records/get-all/100/100"
        stub = stub_request(:post, second_page_url)
               .to_return(body: {
                 totalResults: 150,
                 responseList: Array.new(50) { sample_device }.to_json,
               }.to_json)

        action(page_size: 100).send(:iteration_state_value=, { offset: 100 })
        run_action({ page_size: 100 })

        expect(stub).to have_been_requested.once
      end

      it 'has_next_page is false when devices count equals total' do
        stub_request(:post, devices_url)
          .to_return(body: {
            totalResults: 100,
            responseList: Array.new(100) { sample_device }.to_json,
          }.to_json)

        output = run_action({ page_size: 100 })
        expect(output[:has_next_page]).to eq(false)
      end
    end

    describe 'incremental sync' do
      let(:recent_device) { sample_device.merge(lastModifiedOn: Time.now.to_i * 1000) }
      let(:older_device) { sample_device.merge(lastModifiedOn: 2.hours.ago.to_i * 1000) }
      let(:oldest_device) { sample_device.merge(lastModifiedOn: 3.hours.ago.to_i * 1000) }

      it 'returns only devices modified after last_sync_at' do
        stub_request(:post, devices_url)
          .to_return(body: {
            totalResults: 3,
            responseList: [recent_device, older_device, oldest_device].to_json,
          }.to_json)

        output = run_action({ last_sync_at: 1.hour.ago.iso8601 })

        expect(output[:devices].size).to eq(1)
        expect(output[:has_next_page]).to eq(false)
      end

      it 'returns all devices on page when all are newer than last_sync_at' do
        stub_request(:post, devices_url)
          .to_return(body: {
            totalResults: 200,
            responseList: Array.new(100) { recent_device }.to_json,
          }.to_json)

        output = run_action({ page_size: 100, last_sync_at: 2.hours.ago.iso8601 })

        expect(output[:devices].size).to eq(100)
        expect(output[:has_next_page]).to eq(true)
      end

      it 'returns empty devices when first device is older than last_sync_at' do
        stub_request(:post, devices_url)
          .to_return(body: {
            totalResults: 100,
            responseList: [oldest_device, oldest_device].to_json,
          }.to_json)

        output = run_action({ last_sync_at: 1.hour.ago.iso8601 })

        expect(output[:devices]).to eq([])
        expect(output[:has_next_page]).to eq(false)
      end

      it 'fetches all devices when last_sync_at is not provided' do
        stub_request(:post, devices_url)
          .to_return(body: {
            totalResults: 3,
            responseList: [recent_device, older_device, oldest_device].to_json,
          }.to_json)

        output = run_action({})

        expect(output[:devices].size).to eq(3)
      end
    end

    describe 'error handling' do
      it 'fails on 403 session expired error' do
        stub_request(:post, devices_url)
          .to_return(
            status: 403,
            body: {
              code: 'ERRUSR003',
              text: 'USER Session Expired',
              message: 'User Session Expired',
            }.to_json
          )

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /ERRUSR003.*Session Expired/)
      end

      it 'fails on 401 authentication error' do
        stub_request(:post, devices_url)
          .to_return(
            status: 401,
            body: {
              code: 'ERRUSR005',
              text: 'AUTHENTICATION_ERROR',
              message: 'This User Name is not recognized.',
            }.to_json
          )

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /ERRUSR005/)
      end

      it 'fails on authentication error code in body even with 200 status' do
        stub_request(:post, devices_url)
          .to_return(
            status: 200,
            body: {
              code: 'ERRUSR003',
              message: 'User Session Expired',
            }.to_json
          )

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, %r{authentication/permission error.*ERRUSR003})
      end

      it 'fails on permission error code in body even with 200 status' do
        stub_request(:post, devices_url)
          .to_return(
            status: 200,
            body: {
              code: 'ERRPMT001',
              message: 'Permission denied',
            }.to_json
          )

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, %r{authentication/permission error.*ERRPMT001})
      end

      it 'backs off on 429 rate limit' do
        stub_request(:post, devices_url)
          .to_return(status: 429, headers: { 'Retry-After' => '60' })

        Timecop.freeze do
          expect { run_action({}) }
            .to raise_error(IPaaS::Job::RescheduleJob) do |error|
              expect(error.reschedule_after).to eq(60.seconds.from_now)
            end
        end
      end

      it 'fails on 500 server error' do
        stub_request(:post, devices_url)
          .to_return(status: 500, body: { message: 'Internal Server Error' }.to_json)

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /HTTP error: 500/)
      end

      it 'backs off on 503 service unavailable' do
        stub_request(:post, devices_url)
          .to_return(status: 503)

        Timecop.freeze do
          expect { run_action({}) }
            .to raise_error(IPaaS::Job::RescheduleJob, /Virima API not available/) do |error|
              expect(error.reschedule_after).to eq(60.seconds.from_now)
            end
        end
      end

      it 'fails on 502 bad gateway' do
        stub_request(:post, devices_url)
          .to_return(status: 502, body: { message: 'Bad Gateway' }.to_json)

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /HTTP error: 502/)
      end

      it 'fails on invalid JSON response body' do
        stub_request(:post, devices_url)
          .to_return(status: 200, body: 'not json')

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /HTTP error/)
      end

      it 'fails when responseList is not valid JSON' do
        stub_request(:post, devices_url)
          .to_return(
            status: 200,
            body: {
              totalResults: 1,
              responseList: 'invalid json [',
            }.to_json
          )

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /Failed to parse responseList/)
      end

      it 'fails when responseList is not an array' do
        stub_request(:post, devices_url)
          .to_return(
            status: 200,
            body: {
              totalResults: 1,
              responseList: { notAnArray: true }.to_json,
            }.to_json
          )

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /Failed to parse responseList.*Not an Array/)
      end

      it 'fails when responseList is missing from response' do
        stub_request(:post, devices_url)
          .to_return(
            status: 200,
            body: {
              totalResults: 1,
            }.to_json
          )

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /responseList is missing/)
      end

      it 'fails on API error with code' do
        stub_request(:post, devices_url)
          .to_return(
            status: 400,
            body: {
              code: 'ERRGEN006',
              text: 'BAD_REQUEST',
              message: 'BAD Request mandatory fields are missing',
            }.to_json
          )

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /ERRGEN006/)
      end

      it 'fails on non-200 status without error code' do
        stub_request(:post, devices_url)
          .to_return(
            status: 404,
            body: { message: 'Not found' }.to_json
          )

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /HTTP error: 404/)
      end
    end
  end
end
