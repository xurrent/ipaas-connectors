require 'spec_helper'

describe 'Microsoft Intune Managed Devices Action', :action do
  let(:connector_id) { '01983ca8-546f-7610-93c9-c6cc164300fc' }
  let(:action_template_id) { '01983cb5-865f-7219-9799-67d526948e7c' }

  describe 'input_schema' do
    it 'should define the Last sync field' do
      action.input_schema.field(:last_sync).tap do |field|
        expect(field.label).to eq('Last sync')
        expect(field.type).to eq(:date_time)
        expect(field.required).to be_falsey
        expect(field.visibility).to eq('visible')
      end
    end

    it 'should define the page_size field' do
      action.input_schema.field(:page_size).tap do |field|
        expect(field.label).to eq('Page size')
        expect(field.type).to eq(:integer)
        expect(field.required).to be_falsey
        expect(field.visibility).to eq('optional')
        expect(field.min).to eq(1)
        expect(field.max).to eq(999)
        expect(field.default).to eq(100)
      end
    end
  end

  describe 'output_schema' do
    it 'should only have page output schema' do
      expect(action.output_schema.map(&:reference)).to contain_exactly('page')
    end

    describe 'page schema' do
      let(:page_schema) { action.output_schema.first }

      it 'should define the OData count field' do
        page_schema.field(:odata_count).tap do |field|
          expect(field.label).to eq('OData count')
          expect(field.type).to eq(:integer)
        end
      end

      it 'should define the has_next_page field' do
        page_schema.field(:has_next_page).tap do |field|
          expect(field.label).to eq('Has next page')
          expect(field.type).to eq(:boolean)
        end
      end

      it 'should define the devices field' do
        devices_field = page_schema.field(:devices).tap do |field|
          expect(field.label).to eq('Devices')
          expect(field.type).to eq(:nested)
          expect(field.array).to eq(true)
        end

        devices_field.field(:device_id).tap do |field|
          expect(field.label).to eq('Device ID')
          expect(field.type).to eq(:string)
          expect(field.required).to be_truthy
        end

        devices_field.field(:manufacturer).tap do |field|
          expect(field.label).to eq('Manufacturer')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:model).tap do |field|
          expect(field.label).to eq('Model')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:device_name).tap do |field|
          expect(field.label).to eq('Device name')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:serial_number).tap do |field|
          expect(field.label).to eq('Serial number')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:last_sync_date_time).tap do |field|
          expect(field.label).to eq('Last sync date time')
          expect(field.type).to eq(:date_time)
        end
        devices_field.field(:operating_system).tap do |field|
          expect(field.label).to eq('Operating system')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:os_version).tap do |field|
          expect(field.label).to eq('Operating system version')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:user_id).tap do |field|
          expect(field.label).to eq('User ID')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:email_address).tap do |field|
          expect(field.label).to eq('Email address')
          expect(field.type).to eq(:secret_string)
        end
        devices_field.field(:physical_memory_in_bytes).tap do |field|
          expect(field.label).to eq('Physical memory in bytes')
          expect(field.type).to eq(:integer)
        end
        devices_field.field(:azure_ad_registered).tap do |field|
          expect(field.label).to eq('Azure AD registered')
          expect(field.type).to eq(:boolean)
        end
        devices_field.field(:azure_ad_device_id).tap do |field|
          expect(field.label).to eq('Azure AD device ID')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:jail_broken).tap do |field|
          expect(field.label).to eq('Jail broken')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:enrolled_date_time).tap do |field|
          expect(field.label).to eq('Enrolled date time')
          expect(field.type).to eq(:date_time)
        end
        devices_field.field(:device_enrollment_type).tap do |field|
          expect(field.label).to eq('Device enrollment type')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:managed_device_owner_type).tap do |field|
          expect(field.label).to eq('Managed device owner type')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:is_encrypted).tap do |field|
          expect(field.label).to eq('Is encrypted')
          expect(field.type).to eq(:boolean)
        end
        devices_field.field(:compliance_state).tap do |field|
          expect(field.label).to eq('Compliance state')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:user_principal_name).tap do |field|
          expect(field.label).to eq('User Principal Name')
          expect(field.type).to eq(:secret_string)
        end
        devices_field.field(:phone_number).tap do |field|
          expect(field.label).to eq('Phone Number')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:wi_fi_mac_address).tap do |field|
          expect(field.label).to eq('WiFi Mac Address')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:ethernet_mac_address).tap do |field|
          expect(field.label).to eq('Ethernet Mac Address')
          expect(field.type).to eq(:string)
        end
        devices_field.field(:total_storage_space_in_bytes).tap do |field|
          expect(field.label).to eq('Total Storage Space In Bytes')
          expect(field.type).to eq(:integer)
        end
        devices_field.field(:free_storage_space_in_bytes).tap do |field|
          expect(field.label).to eq('Free Storage Space In Bytes')
          expect(field.type).to eq(:integer)
        end
      end
    end
  end

  describe 'iteration_state_schema' do
    it 'should define the OData next link field' do
      action.iteration_state_schema.field(:odata_nextLink).tap do |field|
        expect(field.label).to eq('OData next link')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
        expect(field.visibility).to eq('visible')
      end
    end
  end

  describe 'run' do
    let(:endpoint) do
      outbound_connection_config[:environment][:graph_endpoint]
    end

    let(:outbound_connection_config) do
      {
        credentials: {
          tenant_id: 'wdc',
          client_id: 'abc',
          client_secret: make_secret_string('def'),
        },
        environment: {
          graph_endpoint: 'https://graph.example.com/v1',
        },
      }
    end

    def fill_authorization_cache
      url = outbound_connection_config[:environment][:oauth2_endpoint]
      url ||= "https://login.microsoftonline.com/#{outbound_connection_config[:credentials][:tenant_id]}/oauth2/v2.0/token"

      body = {
        client_id: outbound_connection_config[:credentials][:client_id],
        client_secret: encryptor.decrypt(outbound_connection_config[:credentials][:client_secret]),
        grant_type: 'client_credentials',
        scope: 'https://graph.microsoft.com/.default',
      }
      store_oauth2_header(url, body)
    end

    before(:each) do
      fill_authorization_cache
    end

    def generate_expected_url
      "#{endpoint}/deviceManagement/managedDevices"
    end

    def expected_select
      { '$select': 'id,userId,operatingSystem,osVersion,manufacturer,model,deviceName,serialNumber,azureADDeviceId,' \
                   'lastSyncDateTime,emailAddress,physicalMemoryInBytes,azureADRegistered,jailBroken,' \
                   'enrolledDateTime,deviceEnrollmentType,managedDeviceOwnerType,isEncrypted,complianceState,' \
                   'userPrincipalName,phoneNumber,wiFiMacAddress,ethernetMacAddress,totalStorageSpaceInBytes,' \
                   'freeStorageSpaceInBytes' }
    end

    def trigger_action(last_sync: nil, page_size: nil)
      run_action({ last_sync: last_sync, page_size: page_size })
    end

    describe 'returns devices' do
      it 'gets values for devices' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100 }.merge(expected_select))
               .to_return(body: {
                 value: [
                   {
                     id: '49b',
                     userId: 'ca5',
                     operatingSystem: 'Android',
                     osVersion: '14.0',
                     manufacturer: 'samsung',
                     model: 'SM-M346B',
                     deviceName: 'bla.shi_AndroidForWork_5/8/2025_11:51 AM',
                     serialNumber: '0',
                     azureADDeviceId: 'a06',
                     lastSyncDateTime: '2025-05-17T10:02:33Z',
                     emailAddress: 'bla.shi@xurrent.com',
                     physicalMemoryInBytes: 0,
                     azureADRegistered: true,
                     jailBroken: 'false',
                     enrolledDateTime: '2025-05-08T11:51:04Z',
                     deviceEnrollmentType: 'userEnrollment',
                     managedDeviceOwnerType: 'personal',
                     isEncrypted: true,
                     complianceState: 'noncompliant',
                     userPrincipalName: 'bla.shi@xurrent.com',
                     phoneNumber: '+1234567890',
                     wiFiMacAddress: '00:11:22:33:44:55',
                     ethernetMacAddress: 'AA:BB:CC:DD:EE:FF',
                     totalStorageSpaceInBytes: 128_849_018_880,
                     freeStorageSpaceInBytes: 64_424_509_440,
                   },
                   {
                     id: 'bdc',
                     userId: '',
                     operatingSystem: 'Windows',
                     osVersion: '10.0.19045.5371',
                     manufacturer: 'Microsoft Corporation',
                     model: 'Virtual Machine',
                     deviceName: 'PC-VM-002',
                     serialNumber: '2053-47',
                     azureADDeviceId: '089',
                     lastSyncDateTime: '2025-02-07T13:43:33Z',
                     emailAddress: '',
                     physicalMemoryInBytes: 0,
                     azureADRegistered: true,
                     jailBroken: 'Unknown',
                     enrolledDateTime: '2025-02-07T11:25:22Z',
                     deviceEnrollmentType: 'windowsAzureADJoin',
                     managedDeviceOwnerType: 'company',
                     isEncrypted: false,
                     complianceState: 'noncompliant',
                     userPrincipalName: '',
                     phoneNumber: '********909',
                     wiFiMacAddress: '',
                     ethernetMacAddress: '',
                     totalStorageSpaceInBytes: 123,
                     freeStorageSpaceInBytes: 213_213,
                   },
                   {
                     id: 'xyz',
                     userId: '',
                     operatingSystem: 'Apple',
                     osVersion: '10.0.19045.5371',
                     manufacturer: 'Apple',
                     model: 'Virtual Machine',
                     deviceName: 'PC-VM-0002',
                     serialNumber: '2053-487',
                     azureADDeviceId: '0089',
                     lastSyncDateTime: '2025-02-07T13:43:33Z',
                     emailAddress: nil,
                     physicalMemoryInBytes: 0,
                     azureADRegistered: true,
                     jailBroken: 'Unknown',
                     enrolledDateTime: '2025-03-07T11:25:22Z',
                     deviceEnrollmentType: 'Apple1',
                     managedDeviceOwnerType: 'company',
                     isEncrypted: false,
                     complianceState: 'noncompliant',
                     userPrincipalName: 'user@example.com',
                     phoneNumber: '+9876543210',
                     wiFiMacAddress: '11:22:33:44:55:66',
                     ethernetMacAddress: nil,
                     totalStorageSpaceInBytes: 256_000_000_000,
                     freeStorageSpaceInBytes: 128_000_000_000,
                   },
                 ],
               }.to_json)

        output = trigger_action
        expect(output[:has_next_page]).to eq(false)
        devices = output[:devices]
        expect(devices.pluck(:device_id)).to contain_exactly('49b', 'bdc', 'xyz')
        expect(devices.pluck(:operating_system)).to contain_exactly('Android', 'Windows', 'Apple')
        expect(devices.pluck(:last_sync_date_time)).to contain_exactly('2025-02-07T13:43:33Z', '2025-02-07T13:43:33Z',
                                                                       '2025-05-17T10:02:33Z')
        expect(stub).to have_been_requested.once
        first_device = devices.find { |d| d[:device_id] == '49b' }
        second_device = devices.find { |d| d[:device_id] == 'bdc' }
        third_device = devices.find { |d| d[:device_id] == 'xyz' }
        expect(first_device[:email_address]).to be_a(IPaaS::Encryption::SecretString)
        expect(action.decrypt_secret_string(first_device[:email_address])).to eq('bla.shi@xurrent.com')
        expect(action.decrypt_secret_string(second_device[:email_address])).to eq('')
        expect(action.decrypt_secret_string(third_device[:email_address])).to eq('')
        expect(first_device[:user_principal_name]).to be_a(IPaaS::Encryption::SecretString)
        expect(action.decrypt_secret_string(first_device[:user_principal_name])).to eq('bla.shi@xurrent.com')
        expect(first_device[:phone_number]).to eq('+1234567890')
        expect(first_device[:wi_fi_mac_address]).to eq('00:11:22:33:44:55')
        expect(first_device[:ethernet_mac_address]).to eq('AA:BB:CC:DD:EE:FF')
        expect(first_device[:total_storage_space_in_bytes]).to eq(128_849_018_880)
        expect(first_device[:free_storage_space_in_bytes]).to eq(64_424_509_440)
        expect(second_device[:user_principal_name]).to be_a(IPaaS::Encryption::SecretString)
        expect(action.decrypt_secret_string(second_device[:user_principal_name])).to eq('')
      end

      it 'uses page_size' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 55 }.merge(expected_select))
               .to_return(body: { value: [] }.to_json)

        trigger_action(page_size: '55')
        expect(stub).to have_been_requested.once
      end

      it 'uses last sync' do
        last_synced = DateTime.parse('Wed, 20 Jul 2025 08:20:02 +01:00')
        Timecop.freeze(last_synced + 2.hours)

        date_formatted = last_synced.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100, '$filter': "lastSyncDateTime ge #{date_formatted}" }
                              .merge(expected_select))
               .to_return(body: { value: [] }.to_json)

        trigger_action(last_sync: last_synced)
        expect(stub).to have_been_requested.once
      end

      describe 'iteration state handling' do
        it 'clears iteration_state_value when next link is absent' do
          stub = stub_request(:get, generate_expected_url)
                 .with(query: { '$top': 100 }.merge(expected_select))
                 .to_return(body: { value: [] }.to_json)

          expect(action(last_sync: nil)).to receive(:iteration_state_value=).with(nil)

          output = trigger_action
          expect(output[:has_next_page]).to eq(false)
          expect(stub).to have_been_requested.once
        end

        it 'stores iteration_state_value when next link is present' do
          stub = stub_request(:get, generate_expected_url)
                 .with(query: { '$top': 100 }.merge(expected_select))
                 .to_return(body: {
                   '@odata.nextLink': 'https://foo/bar',
                   value: [
                     {
                       '@odata.type': '#microsoft.graph.device',
                       id: '1d6',
                       deviceId: 'xyz',
                     },
                   ],
                 }.to_json)

          expect(action(last_sync: nil)).to receive(:iteration_state_value=)
            .with({ odata_nextLink: 'https://foo/bar' })
            .and_call_original

          output = run_action
          expect(output[:has_next_page]).to eq(true)
          expect(output[:devices].pluck(:device_id)).to contain_exactly('1d6')
          expect(stub).to have_been_requested.once
        end

        it 'uses iteration_state_value' do
          old_next_link = 'https://foo/baz'
          stub = stub_request(:get, old_next_link)
                 .with(query: nil)
                 .to_return(body: {
                   value: [
                     {
                       '@odata.type': '#microsoft.graph.device',
                       id: '2d6',
                       deviceId: 'xyz',
                     },
                   ],
                 }.to_json)

          action(last_sync: nil).send(:iteration_state_value=, { odata_nextLink: old_next_link })

          output = run_action
          expect(output[:has_next_page]).to eq(false)
          expect(output[:devices].pluck(:device_id)).to contain_exactly('2d6')
          expect(stub).to have_been_requested.once
        end
      end
    end

    describe 'error handling' do
      describe 'temporary errors' do
        describe 'without retry-after' do
          it 'handles 429' do
            stub = stub_request(:get, generate_expected_url)
                   .with(query: { '$top': 100 }.merge(expected_select))
                   .to_return(status: 429, body: 'Wait 10 seconds')

            Timecop.freeze do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob, "Microsoft API rate limit hit. 'Wait 10 seconds'") do |e|
                expect(e.reschedule_after).to eq(1.minute.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles 503' do
            stub = stub_request(:get, generate_expected_url)
                   .with(query: { '$top': 100 }.merge(expected_select))
                   .to_return(status: 503, body: 'Service Unavailable')

            Timecop.freeze do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                %(Microsoft API not available. 'Service Unavailable')) do |e|
                expect(e.reschedule_after).to eq(1.minute.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end
        end

        describe 'with retry-after' do
          it 'handles 429' do
            stub = stub_request(:get, generate_expected_url)
                   .with(query: { '$top': 100 }.merge(expected_select))
                   .to_return(status: 429, body: 'Wait 2 seconds', headers: { 'retry-after' => 2 })

            Timecop.freeze do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                "Microsoft API rate limit hit (retry after: 2). 'Wait 2 seconds'") do |e|
                expect(e.reschedule_after).to eq(2.seconds.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles 503' do
            stub = stub_request(:get, generate_expected_url)
                   .with(query: { '$top': 100 }.merge(expected_select))
                   .to_return(status: 503,
                              body: 'Service Unavailable',
                              headers: { 'retry-after' => 'Wed, 21 Oct 2015 07:28:00 GMT' })

            Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 +01:00')) do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                'Microsoft API not available (retry after: Wed, 21 Oct 2015 07:28:00 GMT). ' \
                                "'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(8.minutes.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles retry after header in the past in 503' do
            stub = stub_request(:get, generate_expected_url)
                   .with(query: { '$top': 100 }.merge(expected_select))
                   .to_return(status: 503,
                              body: 'Service Unavailable',
                              headers: { 'retry-after' => 'Wed, 21 Oct 2015 07:19:00 GMT' })

            Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 +01:00')) do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                'Microsoft API not available (retry after: Wed, 21 Oct 2015 07:19:00 GMT). ' \
                                "'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(1.minutes.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles invalid retry after header in 503' do
            stub = stub_request(:get, generate_expected_url)
                   .with(query: { '$top': 100 }.merge(expected_select))
                   .to_return(status: 503,
                              body: 'Service Unavailable',
                              headers: { 'retry-after' => '642 Bla 2015 07:28:00 GMT' })

            Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 CET')) do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                'Microsoft API not available (retry after: 642 Bla 2015 07:28:00 GMT). ' \
                                "'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(1.minutes.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end
        end
      end

      it 'handles 401' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100 }.merge(expected_select))
               .to_return(status: 401, body: '{"message":"Unauthorized"}')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(HTTP error from Microsoft Graph API: 401 '{"message":"Unauthorized"}'))
        expect(stub).to have_been_requested.once
      end

      it 'handles 500' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100 }.merge(expected_select))
               .to_return(status: 500, body: '{"message":"Internal Server Error"}')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(HTTP error from Microsoft Graph API: 500 '{"message":"Internal Server Error"}'))
        expect(stub).to have_been_requested.once
      end

      it 'handles complex error in body' do
        json = {
          error: {
            code: 'Request_UnsupportedQuery',
            message: "Property 'a' does not exist as a declared property or extension property.",
            innerError: {
              date: '2025-07-25T08:54:06',
              'request-id': '42fc-9905-b911303df336',
              'client-request-id': '42fc-9905-b911303df336',
            },
          },
        }.to_json

        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100 }.merge(expected_select))
               .to_return(body: json)

        expect { trigger_action }.to raise_error(IPaaS::Job::FailJob) do |error|
          message = error.message
          expect(message).to start_with('Error from Microsoft Graph API: ')
          expect(message).to end_with(JSON.parse(json)['error'].to_json)
        end

        expect(stub).to have_been_requested.once
      end

      it 'ignores empty error in body' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100 }.merge(expected_select))
               .to_return(body: { error: [],
                                  value: [], }.to_json)

        output = trigger_action
        expect(output[:devices]).to eq([])

        expect(stub).to have_been_requested.once
      end

      it 'handles missing value' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100 }.merge(expected_select))
               .to_return(body: { boo: :ba }.to_json)

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob, %(No value in Microsoft Graph API response: '{"boo":"ba"}'))

        expect(stub).to have_been_requested.once
      end
    end
  end
end
