require 'spec_helper'

describe 'Logic Monitor Fetch Devices CMDB Action', :action do
  let(:connector_id) { '0199a9a6-ac42-7ad1-a22e-26a05ff5d538' }
  let(:action_template_id) { '0199a9a7-cdb4-7c91-a382-79e30c4d572f' }

  describe 'input_schema' do
    it 'should define the Account field' do
      action.input_schema.field(:account).tap do |field|
        expect(field.label).to eq('Account')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
        expect(field.visibility).to eq('visible')
      end
    end

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
        expect(field.max).to eq(1000)
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

      it 'should define the total field' do
        page_schema.field(:total).tap do |field|
          expect(field.label).to eq('Total')
          expect(field.type).to eq(:integer)
        end
      end

      it 'should define the has_next_page field' do
        page_schema.field(:has_next_page).tap do |field|
          expect(field.label).to eq('Has next page')
          expect(field.type).to eq(:boolean)
          expect(field.required).to be_truthy
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
          expect(field.type).to eq(:integer)
          expect(field.required).to be_truthy
        end

        devices_field.field(:name).tap do |field|
          expect(field.label).to eq('Name')
          expect(field.type).to eq(:string)
        end

        devices_field.field(:display_name).tap do |field|
          expect(field.label).to eq('Display name')
          expect(field.type).to eq(:string)
        end

        system_props_field = devices_field.field(:system_properties).tap do |field|
          expect(field.label).to eq('System properties')
          expect(field.type).to eq(:nested)
          expect(field.array).to eq(true)
        end

        system_props_field.field(:name).tap do |field|
          expect(field.label).to eq('Name')
          expect(field.type).to eq(:string)
        end

        system_props_field.field(:value).tap do |field|
          expect(field.label).to eq('Value')
          expect(field.type).to eq(:string)
        end
      end
    end
  end

  describe 'iteration_state_schema' do
    it 'should define the offset field' do
      action.iteration_state_schema.field(:offset).tap do |field|
        expect(field.label).to eq('Offset')
        expect(field.type).to eq(:integer)
        expect(field.required).to be_truthy
        expect(field.visibility).to eq('visible')
      end
    end
  end

  describe 'run' do
    let(:endpoint) { 'https://xurrent.logicmonitor.com/santaba/rest' }

    let(:outbound_connection_config) do
      {
        bearer: {
          bearer_token: make_secret_string('valid-bearer-token'),
        },
      }
    end

    let(:query) do
      {
        'fields' => 'id,name,displayName,systemProperties',
        'size' => '100',
        'offset' => '0',
      }
    end

    def lm_fetch_device_url
      "#{endpoint}/device/devices"
    end

    def trigger_action(account: 'xurrent', last_sync: nil, page_size: nil)
      run_action({ account: account, last_sync: last_sync, page_size: page_size })
    end

    describe 'returns devices' do
      it 'gets values for devices' do
        stub = stub_request(:get, lm_fetch_device_url)
               .with(query: query)
               .to_return(body: {
                 data: {
                   total: 2,
                   items: [
                     {
                       id: 1,
                       name: 'LMAWSACCOUNT-17',
                       displayName: 'DevOps Account',
                       systemProperties: [
                         {
                           name: 'system.device.provider',
                           value: 'AWS',
                         },
                         {
                           name: 'system.hostname',
                           value: 'LMAWSACCOUNT-17',
                         },
                       ],
                     },
                     {
                       id: 2,
                       name: 'SERVER-01',
                       displayName: 'Production Server 01',
                       systemProperties: [
                         {
                           name: 'system.device.provider',
                           value: 'Azure',
                         },
                       ],
                     },
                   ],
                 },
               }.to_json)

        output = trigger_action
        expect(output[:total]).to eq(2)
        expect(output[:has_next_page]).to eq(false)
        devices = output[:devices]
        expect(devices.length).to eq(2)
        expect(devices.pluck(:device_id)).to contain_exactly(1, 2)
        expect(devices.pluck(:name)).to contain_exactly('LMAWSACCOUNT-17', 'SERVER-01')
        expect(devices.pluck(:display_name)).to contain_exactly('DevOps Account', 'Production Server 01')
        expect(stub).to have_been_requested.once

        first_device = devices.find { |d| d[:device_id] == 1 }
        expect(first_device[:system_properties]).to eq([
          { 'name' => 'system.device.provider', 'value' => 'AWS' },
          { 'name' => 'system.hostname', 'value' => 'LMAWSACCOUNT-17' },
        ])
      end

      it 'uses page_size' do
        stub = stub_request(:get, lm_fetch_device_url)
               .with(query: query.merge({ 'size' => '55' }))
               .to_return(body: { data: { total: 0, items: [] } }.to_json)

        trigger_action(page_size: 55)
        expect(stub).to have_been_requested.once
      end

      it 'uses last sync' do
        last_synced = DateTime.parse('Wed, 20 Jul 2025 08:20:02 +01:00')
        timestamp = last_synced.to_i

        stub = stub_request(:get, lm_fetch_device_url)
               .with(query: query.merge({ 'filter' => "updatedOn>#{timestamp}" }))
               .to_return(body: { data: { total: 0, items: [] } }.to_json)

        trigger_action(last_sync: last_synced)
        expect(stub).to have_been_requested.once
      end

      describe 'iteration state handling' do
        it 'clears iteration_state_value when items are empty' do
          stub = stub_request(:get, lm_fetch_device_url)
                 .with(query: query)
                 .to_return(body: { data: { total: 0, items: [] } }.to_json)

          expect(action(account: 'xurrent', last_sync: nil)).to receive(:iteration_state_value=).with(nil)

          output = trigger_action
          expect(output[:has_next_page]).to eq(false)
          expect(stub).to have_been_requested.once
        end

        it 'stores iteration_state_value when items are present' do
          stub = stub_request(:get, lm_fetch_device_url)
                 .with(query: query.merge({ 'size' => '2' }))
                 .to_return(body: {
                   data: {
                     total: 10,
                     items: [
                       {
                         id: 1,
                         name: 'DEVICE-01',
                         displayName: 'Device 01',
                         systemProperties: [],
                       },
                       {
                         id: 2,
                         name: 'DEVICE-02',
                         displayName: 'Device 02',
                         systemProperties: [],
                       },
                     ],
                   },
                 }.to_json)

          expect(action(account: 'xurrent', last_sync: nil, page_size: 2)).to receive(:iteration_state_value=)
            .with({ offset: 2 })
            .and_call_original

          output = trigger_action(page_size: 2)
          expect(output[:has_next_page]).to eq(true)
          expect(output[:devices].pluck(:device_id)).to contain_exactly(1, 2)
          expect(stub).to have_been_requested.once
        end

        it 'uses iteration_state_value' do
          old_offset = 2
          stub = stub_request(:get, lm_fetch_device_url)
                 .with(query: query.merge({ 'offset' => '2', 'size' => '2' }))
                 .to_return(body: {
                   data: {
                     total: 10,
                     items: [
                       {
                         id: 3,
                         name: 'DEVICE-03',
                         displayName: 'Device 03',
                         systemProperties: [],
                       },
                       {
                         id: 4,
                         name: 'DEVICE-04',
                         displayName: 'Device 04',
                         systemProperties: [],
                       },
                     ],
                   },
                 }.to_json)

          action(account: 'xurrent', last_sync: nil, page_size: 2).send(:iteration_state_value=, { offset: old_offset })

          output = trigger_action(page_size: 2)
          expect(output[:has_next_page]).to eq(true)
          expect(output[:devices].pluck(:device_id)).to contain_exactly(3, 4)
          expect(stub).to have_been_requested.once
        end
      end
    end

    describe 'error handling' do
      describe 'temporary errors' do
        describe 'without retry-after' do
          it 'handles 429' do
            stub = stub_request(:get, lm_fetch_device_url)
                   .with(query: query)
                   .to_return(status: 429, body: 'Rate limit exceeded')

            Timecop.freeze do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                "LogicMonitor API rate limit hit. 'Rate limit exceeded'") do |e|
                expect(e.reschedule_after).to eq(1.minute.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles 503' do
            stub = stub_request(:get, lm_fetch_device_url)
                   .with(query: query)
                   .to_return(status: 503, body: 'Service Unavailable')

            Timecop.freeze do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                "LogicMonitor API not available. 'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(1.minute.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end
        end

        describe 'with retry-after' do
          it 'handles 429' do
            stub = stub_request(:get, lm_fetch_device_url)
                   .with(query: query)
                   .to_return(status: 429, body: 'Wait 2 seconds', headers: { 'retry-after' => 2 })

            Timecop.freeze do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                "LogicMonitor API rate limit hit (retry after: 2). 'Wait 2 seconds'") do |e|
                expect(e.reschedule_after).to eq(2.seconds.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles 503' do
            stub = stub_request(:get, lm_fetch_device_url)
                   .with(query: query)
                   .to_return(status: 503,
                              body: 'Service Unavailable',
                              headers: { 'retry-after' => 'Wed, 21 Oct 2015 07:28:00 GMT' })

            Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 +01:00')) do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                'LogicMonitor API not available (retry after: Wed, 21 Oct 2015 07:28:00 GMT). ' \
                                "'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(8.minutes.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end
        end
      end

      it 'handles 401' do
        stub = stub_request(:get, lm_fetch_device_url)
               .with(query: query)
               .to_return(status: 401, body: '{"message":"Unauthorized"}')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(Authentication error from Logic Monitor API: 401 '{"message":"Unauthorized"}'))
        expect(stub).to have_been_requested.once
      end

      it 'handles 403' do
        stub = stub_request(:get, lm_fetch_device_url)
               .with(query: query)
               .to_return(status: 403, body: '{"message":"Forbidden"}')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(Authentication error from Logic Monitor API: 403 '{"message":"Forbidden"}'))
        expect(stub).to have_been_requested.once
      end

      it 'handles 500' do
        stub = stub_request(:get, lm_fetch_device_url)
               .with(query: query)
               .to_return(status: 500, body: '{"message":"Internal Server Error"}')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(HTTP error from Logic Monitor API: 500 '{"message":"Internal Server Error"}'))
        expect(stub).to have_been_requested.once
      end

      it 'handles error in body' do
        json = {
          data: nil,
          errmsg: 'Authentication failed',
          status: 1401,
        }.to_json

        stub = stub_request(:get, lm_fetch_device_url)
               .with(query: query)
               .to_return(body: json)

        expect { trigger_action }.to raise_error(IPaaS::Job::FailJob) do |error|
          message = error.message
          expect(message).to start_with('Error from Logic Monitor API: ')
          expect(message).to include('Authentication failed')
        end

        expect(stub).to have_been_requested.once
      end

      it 'handles invalid JSON response' do
        stub = stub_request(:get, lm_fetch_device_url)
               .with(query: query)
               .to_return(body: 'Invalid JSON')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(Logic Monitor API response was not JSON: 'Invalid JSON'))

        expect(stub).to have_been_requested.once
      end

      it 'handles invalid items in response' do
        stub = stub_request(:get, lm_fetch_device_url)
               .with(query: query)
               .to_return(body: {
                 data: {
                   total: 2,
                   items: 'invalid-type',
                 },
               }.to_json)

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(Expected items to be an array from Logic Monitor))

        expect(stub).to have_been_requested.once
      end

      it 'handles invalid total in response' do
        stub = stub_request(:get, lm_fetch_device_url)
               .with(query: query)
               .to_return(body: {
                 data: {
                   total: 'two',
                   items: [],
                 },
               }.to_json)

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(Expected total to be an integer from Logic Monitor))

        expect(stub).to have_been_requested.once
      end
    end
  end
end
