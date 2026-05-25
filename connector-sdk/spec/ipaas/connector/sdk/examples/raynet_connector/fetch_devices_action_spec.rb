require 'spec_helper'

describe 'Raynet Fetch Devices Action', :action do
  let(:connector_id) { '019e2b9d-de23-7092-94c3-1125dfc31d59' }
  let(:action_template_id) { '019e2b9d-de23-7917-a4de-3f30b50fd211' }

  let(:outbound_connection_config) do
    {
      instance: 'xurrent-demo-01',
      api_key: make_secret_string('5cf76a53-c347-4ec7-bc7f-4f720eb49680'),
    }
  end

  let(:base_url) { 'https://xurrent-demo-01.raynetone.com/api/v1' }
  let(:devices_url) { "#{base_url}/Devices/by-inventory" }

  let(:device_one) do
    {
      '$id' => '426',
      'name' => 'srv_4cb1f',
      'creationDate' => '2025-12-05T11:48:18.319Z',
      'model' => 'VMware Virtual Platform',
      'manufacturer' => 'VMware, Inc.',
      'numberOfLogicalProcessors' => 6,
      'numberOfProcessors' => 6,
      'totalPhysicalMemory' => 17_179_869_184,
      'physicalMemory' => 17_179_869_184,
      'uuid' => '2c983a42-2b40-4890-22b0-7fc24b314822',
      'detectedOsType' => 'Windows',
      'lastSucessfulInventoryRun' => '2025-12-04T00:02:17.639Z',
      'isVirtual' => false,
      'source' => 'MECM,ActiveDirectory',
      'id' => '019aee57-6d0f-7eef-9ca9-504d44b78630',
    }
  end

  let(:device_two) do
    {
      '$id' => '427',
      'name' => 'srv_f5a12',
      'creationDate' => '2025-12-05T11:48:10.423Z',
      'numberOfLogicalProcessors' => 0,
      'numberOfProcessors' => 0,
      'totalPhysicalMemory' => 0,
      'physicalMemory' => 0,
      'detectedOsType' => 'Unix',
      'lastSucessfulInventoryRun' => '2025-12-05T11:51:42.500Z',
      'isVirtual' => false,
      'source' => 'Raynet',
      'id' => '019aee57-4e37-7857-bcea-77aa4dc83e8e',
    }
  end

  describe 'input_schema' do
    context 'inventory_date_later_then field' do
      let(:field) { action.input_schema.field(:inventory_date_later_then) }

      it { expect(field.label).to eq('Inventory date later then') }
      it { expect(field.type).to eq(:date_time) }
      it { expect(field.required).to be_falsey }
      it { expect(field.visibility).to eq('optional') }
    end

    context 'count field' do
      let(:field) { action.input_schema.field(:count) }

      it { expect(field.label).to eq('Count') }
      it { expect(field.type).to eq(:integer) }
      it { expect(field.required).to be_falsey }
      it { expect(field.visibility).to eq('optional') }
      it { expect(field.min).to eq(1) }
      it { expect(field.max).to eq(1000) }
      it { expect(field.default).to eq(100) }
    end
  end

  describe 'output_schema' do
    it { expect(action.output_schema.map(&:reference)).to contain_exactly('page') }

    describe 'page schema' do
      let(:page_schema) { action.output_schema.first }

      context 'page level' do
        it { expect(page_schema.field(:has_next_page).type).to eq(:boolean) }
        it { expect(page_schema.field(:has_next_page).required).to be_truthy }
      end

      context 'devices field' do
        let(:devices_field) { page_schema.field(:devices) }

        it { expect(devices_field.label).to eq('Devices') }
        it { expect(devices_field.type).to eq(:nested) }
        it { expect(devices_field.array).to eq(true) }

        it 'defines the id field as required' do
          devices_field.field(:id).tap do |field|
            expect(field.label).to eq('ID')
            expect(field.type).to eq(:string)
            expect(field.required).to be_truthy
          end
        end

        it 'defines the name field' do
          expect(devices_field.field(:name).type).to eq(:string)
        end

        it 'defines the creation_date field as date_time' do
          expect(devices_field.field(:creation_date).type).to eq(:date_time)
        end

        it 'defines the detected_os_type field as string' do
          expect(devices_field.field(:detected_os_type).type).to eq(:string)
        end

        it 'preserves the Sucessful misspelling in last_sucessful_inventory_run' do
          expect(devices_field.field(:last_sucessful_inventory_run).type).to eq(:date_time)
        end

        it 'defines the is_virtual field as boolean' do
          expect(devices_field.field(:is_virtual).type).to eq(:boolean)
        end

        it 'defines the source field as string (not array)' do
          field = devices_field.field(:source)
          expect(field.type).to eq(:string)
          expect(field.array).to be_falsey
        end

        it 'defines the total_physical_memory field as integer' do
          expect(devices_field.field(:total_physical_memory).type).to eq(:integer)
        end

        it 'defines the corporate_ownership field as boolean' do
          expect(devices_field.field(:corporate_ownership).type).to eq(:boolean)
        end
      end
    end
  end

  describe 'iteration_state_schema' do
    context 'last_id field' do
      let(:field) { action.iteration_state_schema.field(:last_id) }

      it { expect(field.label).to eq('Last ID') }
      it { expect(field.type).to eq(:string) }
    end
  end

  describe 'run' do
    def trigger_action(input = {})
      run_action(input)
    end

    describe 'instance config normalization' do
      [
        'xurrent-demo-01',
        'xurrent-demo-01.raynetone.com',
        'https://xurrent-demo-01.raynetone.com',
        'https://xurrent-demo-01.raynetone.com/',
        'HTTPS://xurrent-demo-01.raynetone.com',
        'https://xurrent-demo-01.RAYNETONE.com',
      ].each do |instance_value|
        context "when instance is #{instance_value.inspect}" do
          let(:outbound_connection_config) do
            { instance: instance_value, api_key: make_secret_string('5cf76a53-c347-4ec7-bc7f-4f720eb49680') }
          end

          before do
            stub_request(:get, devices_url).with(query: { count: '100' }).to_return(body: '[]')
          end

          it 'resolves to the canonical base URL' do
            trigger_action
            expect(WebMock).to have_requested(:get, devices_url).with(query: { count: '100' })
          end
        end
      end
    end

    context 'with a single-page response' do
      before do
        stub_request(:get, devices_url)
          .with(query: { count: '100' })
          .to_return(body: [device_one].to_json)
      end

      it 'returns devices with snake_case keys' do
        output = trigger_action
        expect(output[:has_next_page]).to eq(false)
        expect(output[:devices].size).to eq(1)
        device = output[:devices].first
        expect(device[:id]).to eq('019aee57-6d0f-7eef-9ca9-504d44b78630')
        expect(device[:name]).to eq('srv_4cb1f')
        expect(device[:number_of_logical_processors]).to eq(6)
        expect(device[:total_physical_memory]).to eq(17_179_869_184)
        expect(device[:detected_os_type]).to eq('Windows')
        expect(device[:is_virtual]).to eq(false)
        expect(device[:source]).to eq('MECM,ActiveDirectory')
      end

      it 'preserves the lastSucessfulInventoryRun misspelling after snake-casing' do
        device = trigger_action[:devices].first
        expect(device).to have_key(:last_sucessful_inventory_run)
        expect(device[:last_sucessful_inventory_run]).to eq('2025-12-04T00:02:17.639Z')
      end

      it 'strips the $id ReferenceLoopHandling artifact from device records' do
        device = trigger_action[:devices].first
        expect(device).not_to have_key(:$id)
        expect(device).not_to have_key('$id')
      end

      it 'clears iteration state when fewer devices returned than count' do
        expect(action({})).to receive(:iteration_state_value=).with(nil)
        trigger_action
      end
    end

    context 'with inventory_date_later_then input' do
      before do
        stub_request(:get, devices_url)
          .with(query: { count: '100', inventoryDateLaterThen: '2026-05-14T00:00:00Z' })
          .to_return(body: [device_one].to_json)
      end

      it 'passes inventoryDateLaterThen as a query param serialized in ISO 8601' do
        output = trigger_action(inventory_date_later_then: '2026-05-14T00:00:00Z')
        expect(output[:devices].size).to eq(1)
      end

      it 'normalizes non-UTC offsets to UTC before serializing' do
        trigger_action(inventory_date_later_then: '2026-05-14T02:30:00+02:30')
        expect(WebMock).to have_requested(:get, devices_url)
          .with(query: { count: '100', inventoryDateLaterThen: '2026-05-14T00:00:00Z' })
      end
    end

    describe 'cursor pagination' do
      context 'when a full page is returned' do
        before do
          stub_request(:get, devices_url)
            .with(query: { count: '2' })
            .to_return(body: [device_one, device_two].to_json)
        end

        it 'sets iteration state with the last device id and signals more pages' do
          expect(action(count: 2)).to receive(:iteration_state_value=)
            .with({ last_id: device_two['id'] })
            .and_call_original

          output = trigger_action(count: 2)
          expect(output[:has_next_page]).to eq(true)
          expect(output[:devices].pluck(:id))
            .to contain_exactly(device_one['id'], device_two['id'])
        end
      end

      context 'when resuming from a previous lastId' do
        before do
          action(count: 2).send(:iteration_state_value=, { last_id: device_one['id'] })

          stub_request(:get, devices_url)
            .with(query: { count: '2', lastId: device_one['id'] })
            .to_return(body: [device_two].to_json)
        end

        it 'sends the stored lastId and clears state on a partial page' do
          output = trigger_action(count: 2)
          expect(output[:has_next_page]).to eq(false)
          expect(output[:devices].pluck(:id)).to contain_exactly(device_two['id'])
        end
      end
    end

    context 'when response is an empty array' do
      before do
        stub_request(:get, devices_url).with(query: { count: '100' }).to_return(body: '[]')
      end

      it 'returns no devices and clears iteration state' do
        output = trigger_action
        expect(output[:has_next_page]).to eq(false)
        expect(output[:devices]).to eq([])
      end
    end

    describe 'error handling' do
      let(:default_query) { { count: '100' } }

      context 'when API returns 401' do
        before do
          stub_request(:get, devices_url).with(query: default_query)
                                         .to_return(status: 401, body: 'Unauthorized')
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Raynet authentication error: 401/) }
      end

      context 'when API returns 403' do
        before do
          stub_request(:get, devices_url).with(query: default_query)
                                         .to_return(status: 403, body: 'Forbidden')
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Raynet authentication error: 403/) }
      end

      context 'when API returns 500' do
        before do
          stub_request(:get, devices_url).with(query: default_query)
                                         .to_return(status: 500, body: 'Internal Server Error')
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Raynet HTTP error: 500/) }
      end

      context 'when API returns 503' do
        before do
          stub_request(:get, devices_url).with(query: default_query)
                                         .to_return(status: 503, body: 'Service Unavailable')
        end

        it 'reschedules with backoff' do
          Timecop.freeze do
            expect { trigger_action }
              .to raise_error(IPaaS::Job::RescheduleJob) { |e| expect(e.reschedule_after).to eq(60.seconds.from_now) }
          end
        end
      end

      context 'when API returns 429 with Retry-After' do
        before do
          stub_request(:get, devices_url).with(query: default_query)
                                         .to_return(status: 429, headers: { 'Retry-After' => '30' })
        end

        it 'reschedules with the Retry-After value' do
          Timecop.freeze do
            expect { trigger_action }
              .to raise_error(IPaaS::Job::RescheduleJob) { |e| expect(e.reschedule_after).to eq(30.seconds.from_now) }
          end
        end
      end

      context 'when response is invalid JSON' do
        before do
          stub_request(:get, devices_url).with(query: default_query).to_return(body: 'Not JSON')
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /not valid JSON/) }
      end

      context 'when API returns 404 (no records match)' do
        before do
          stub_request(:get, devices_url).with(query: default_query)
                                         .to_return(
                                           status: 404,
                                           body: { '$id' => '1', 'title' => 'Not Found', 'status' => 404 }.to_json,
                                           headers: { 'Content-Type' => 'application/problem+json' },
                                         )
        end

        it 'returns an empty page and clears iteration state — does not fail the job' do
          expect(action({})).to receive(:iteration_state_value=).with(nil)
          output = trigger_action
          expect(output[:has_next_page]).to eq(false)
          expect(output[:devices]).to eq([])
        end
      end

      context 'when API returns 400 with RFC 7807 application/problem+json error body' do
        let(:problem_body) do
          {
            '$id' => '1',
            'type' => 'https://tools.ietf.org/html/rfc9110#section-15.5.1',
            'title' => 'Bad Request',
            'detail' => 'count must be a positive integer',
            'status' => 400,
            'traceId' => '00-abcdef-00',
          }.to_json
        end

        let(:problem_headers) { { 'Content-Type' => 'application/problem+json; charset=utf-8' } }

        before do
          stub_request(:get, devices_url).with(query: default_query)
                                         .to_return(status: 400,
                                                    body: problem_body,
                                                    headers: problem_headers)
        end

        it 'extracts the title/detail and omits the raw JSON envelope' do
          expect { trigger_action }
            .to raise_error(IPaaS::Job::FailJob) { |e|
              expect(e.message).to match(/Raynet HTTP error: 400 Bad Request - count must be a positive integer/)
              expect(e.message).not_to include('$id')
              expect(e.message).not_to include('traceId')
            }
        end
      end
    end

    describe 'authentication header' do
      before do
        stub_request(:get, devices_url).with(query: { count: '100' }).to_return(body: '[]')
      end

      it 'sends ApiKey header from the connection config' do
        trigger_action
        expect(WebMock).to have_requested(:get, devices_url)
          .with(query: { count: '100' },
                headers: { 'ApiKey' => '5cf76a53-c347-4ec7-bc7f-4f720eb49680' })
      end
    end
  end
end
