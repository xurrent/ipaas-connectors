require 'spec_helper'

describe 'Raynet Fetch Operating Systems By Device IDs Action', :action do
  let(:connector_id) { '019e2b9d-de23-7092-94c3-1125dfc31d59' }
  let(:action_template_id) { '019e2b9d-de23-755d-bac7-0f52597c1bd1' }

  let(:outbound_connection_config) do
    {
      instance: 'xurrent-demo-01',
      api_key: make_secret_string('5cf76a53-c347-4ec7-bc7f-4f720eb49680'),
    }
  end

  let(:base_url) { 'https://xurrent-demo-01.raynetone.com/api/v1' }
  let(:os_url) { "#{base_url}/OperatingSystems/ByManyDeviceIds" }

  let(:windows_device_id) { '019aee57-6d0f-7eef-9ca9-504d44b78630' }
  let(:linux_device_id)   { '019aee57-4e37-7857-bcea-77aa4dc83e8e' }
  let(:stub_device_id)    { '019aee57-49f1-7089-9b1b-97b0e892009d' }

  let(:windows_os_record) do
    {
      '$id' => '1',
      'name' => 'Windows Server 2016',
      'caption' => 'Windows Server 2016',
      'manufacturer' => 'Microsoft Corporation',
      'architecture' => '64-bit',
      'edition' => 'Standard',
      'osLanguage' => '1033',
      'version' => '10.0.14393',
      'type' => 'Windows',
      'systemDirectory' => 'C:\\WINDOWS\\system32',
      'serialNumber' => '00377-60000-00000-AA934',
      'deviceId' => windows_device_id,
      'id' => '019aee70-db5d-78a7-a392-9bcf2814a923',
    }
  end

  let(:linux_os_record) do
    {
      '$id' => '2',
      'name' => 'Red Hat Enterprise Linux Server',
      'caption' => 'Red Hat Enterprise Linux Server 7.9 (Maipo)',
      'manufacturer' => 'Red Hat',
      'architecture' => '64-bit',
      'version' => '7.9',
      'type' => 'Linux',
      'deviceId' => linux_device_id,
      'id' => '019aee76-0d3a-77f4-9fcc-36c734ce72cf',
    }
  end

  describe 'input_schema' do
    context 'device_ids field' do
      let(:field) { action.input_schema.field(:device_ids) }

      it { expect(field.label).to eq('Device IDs') }
      it { expect(field.type).to eq(:string) }
      it { expect(field.array).to eq(true) }
      it { expect(field.required).to be_truthy }
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

      context 'operating_systems field' do
        let(:os_field) { page_schema.field(:operating_systems) }

        it { expect(os_field.label).to eq('Operating systems') }
        it { expect(os_field.type).to eq(:nested) }
        it { expect(os_field.array).to eq(true) }

        it 'requires id and device_id' do
          expect(os_field.field(:id).required).to be_truthy
          expect(os_field.field(:device_id).required).to be_truthy
        end

        it 'defines core OS fields' do
          expect(os_field.field(:name).type).to eq(:string)
          expect(os_field.field(:caption).type).to eq(:string)
          expect(os_field.field(:manufacturer).type).to eq(:string)
          expect(os_field.field(:architecture).type).to eq(:string)
          expect(os_field.field(:edition).type).to eq(:string)
          expect(os_field.field(:version).type).to eq(:string)
          expect(os_field.field(:type).type).to eq(:string)
          expect(os_field.field(:install_date).type).to eq(:date_time)
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
    def trigger_action(device_ids: [windows_device_id], count: nil)
      run_action({ device_ids: device_ids, count: count })
    end

    context 'with a single-page response' do
      before do
        stub_request(:post, os_url)
          .with(query: { count: '100' }, body: { guids: [windows_device_id, linux_device_id] }.to_json)
          .to_return(body: [windows_os_record, linux_os_record].to_json)
      end

      it 'returns OS records with snake_case keys and clears iteration state' do
        expect(action(device_ids: [windows_device_id, linux_device_id]))
          .to receive(:iteration_state_value=).with(nil)

        output = trigger_action(device_ids: [windows_device_id, linux_device_id])
        expect(output[:has_next_page]).to eq(false)
        expect(output[:operating_systems].size).to eq(2)

        windows = output[:operating_systems].first
        expect(windows[:id]).to eq(windows_os_record['id'])
        expect(windows[:device_id]).to eq(windows_device_id)
        expect(windows[:name]).to eq('Windows Server 2016')
        expect(windows[:os_language]).to eq('1033')
        expect(windows[:system_directory]).to eq('C:\\WINDOWS\\system32')
        expect(windows[:serial_number]).to eq('00377-60000-00000-AA934')
      end

      it 'strips the $id ReferenceLoopHandling artifact from OS records' do
        output = trigger_action(device_ids: [windows_device_id, linux_device_id])
        output[:operating_systems].each do |os|
          expect(os).not_to have_key(:$id)
          expect(os).not_to have_key('$id')
        end
      end
    end

    context 'when device_ids includes a stub with no OS record' do
      before do
        stub_request(:post, os_url)
          .with(query: { count: '100' },
                body: { guids: [windows_device_id, linux_device_id, stub_device_id] }.to_json)
          .to_return(body: [windows_os_record, linux_os_record].to_json)
      end

      it 'returns only the populated OS records (stub is silently omitted by the API)' do
        output = trigger_action(device_ids: [windows_device_id, linux_device_id, stub_device_id])
        expect(output[:operating_systems].pluck(:device_id))
          .to contain_exactly(windows_device_id, linux_device_id)
      end
    end

    describe 'cursor pagination' do
      context 'when a full page is returned' do
        before do
          stub_request(:post, os_url)
            .with(query: { count: '2' }, body: { guids: [windows_device_id, linux_device_id] }.to_json)
            .to_return(body: [windows_os_record, linux_os_record].to_json)
        end

        it 'sets iteration state with the last OS record id and signals more pages' do
          expect(action(device_ids: [windows_device_id, linux_device_id], count: 2))
            .to receive(:iteration_state_value=)
            .with({ last_id: linux_os_record['id'] })
            .and_call_original

          output = trigger_action(device_ids: [windows_device_id, linux_device_id], count: 2)
          expect(output[:has_next_page]).to eq(true)
          expect(output[:operating_systems].pluck(:id))
            .to contain_exactly(windows_os_record['id'], linux_os_record['id'])
        end
      end

      context 'when resuming from a previous LastId' do
        before do
          action(device_ids: [windows_device_id, linux_device_id], count: 2)
            .send(:iteration_state_value=, { last_id: windows_os_record['id'] })

          stub_request(:post, os_url)
            .with(query: { count: '2', LastId: windows_os_record['id'] },
                  body: { guids: [windows_device_id, linux_device_id] }.to_json)
            .to_return(body: [linux_os_record].to_json)
        end

        it 'sends the stored LastId and clears state on a partial page' do
          output = trigger_action(device_ids: [windows_device_id, linux_device_id], count: 2)
          expect(output[:has_next_page]).to eq(false)
          expect(output[:operating_systems].pluck(:id)).to contain_exactly(linux_os_record['id'])
        end
      end
    end

    describe 'error handling' do
      let(:body) { { guids: [windows_device_id] }.to_json }
      let(:default_query) { { count: '100' } }

      context 'when API returns 401' do
        before do
          stub_request(:post, os_url).with(query: default_query, body: body).to_return(status: 401,
                                                                                       body: 'Unauthorized')
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Raynet authentication error: 401/) }
      end

      context 'when API returns 403' do
        before do
          stub_request(:post, os_url).with(query: default_query, body: body).to_return(status: 403, body: 'Forbidden')
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Raynet authentication error: 403/) }
      end

      context 'when API returns 500' do
        before do
          stub_request(:post, os_url).with(query: default_query, body: body).to_return(status: 500,
                                                                                       body: 'Internal Server Error')
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Raynet HTTP error: 500/) }
      end

      context 'when API returns 503' do
        before do
          stub_request(:post, os_url).with(query: default_query, body: body).to_return(status: 503,
                                                                                       body: 'Service Unavailable')
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
          stub_request(:post, os_url).with(query: default_query, body: body)
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
          stub_request(:post, os_url).with(query: default_query, body: body).to_return(body: 'Not JSON')
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /not valid JSON/) }
      end

      context 'when API returns 404 (no OS records match the given device IDs)' do
        before do
          stub_request(:post, os_url).with(query: default_query, body: body)
                                     .to_return(
                                       status: 404,
                                       body: { '$id' => '1', 'title' => 'Not Found', 'status' => 404 }.to_json,
                                       headers: { 'Content-Type' => 'application/problem+json' },
                                     )
        end

        it 'returns an empty page — does not fail the job' do
          output = trigger_action
          expect(output[:has_next_page]).to eq(false)
          expect(output[:operating_systems]).to eq([])
        end
      end

      context 'when API returns 400 with RFC 7807 application/problem+json error body' do
        let(:problem_body) do
          {
            '$id' => '1',
            'type' => 'https://tools.ietf.org/html/rfc9110#section-15.5.1',
            'title' => 'Bad Request',
            'detail' => 'guids must contain at least one device id',
            'status' => 400,
            'traceId' => '00-abcdef-00',
          }.to_json
        end

        let(:problem_headers) { { 'Content-Type' => 'application/problem+json; charset=utf-8' } }

        before do
          stub_request(:post, os_url).with(query: default_query, body: body)
                                     .to_return(status: 400,
                                                body: problem_body,
                                                headers: problem_headers)
        end

        it 'extracts the title/detail and omits the raw JSON envelope' do
          expected = /Raynet HTTP error: 400 Bad Request - guids must contain at least one device id/
          expect { trigger_action }
            .to raise_error(IPaaS::Job::FailJob) { |e|
              expect(e.message).to match(expected)
              expect(e.message).not_to include('$id')
              expect(e.message).not_to include('traceId')
            }
        end
      end
    end

    describe 'authentication header' do
      before do
        stub_request(:post, os_url)
          .with(query: { count: '100' }, body: { guids: [windows_device_id] }.to_json)
          .to_return(body: '[]')
      end

      it 'sends ApiKey header from the connection config' do
        trigger_action
        expect(WebMock).to have_requested(:post, os_url)
          .with(query: { count: '100' },
                body: { guids: [windows_device_id] }.to_json,
                headers: { 'ApiKey' => '5cf76a53-c347-4ec7-bc7f-4f720eb49680' })
      end
    end
  end
end
