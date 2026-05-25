require 'spec_helper'

describe 'Async URLs Action', :action do
  let(:action_template_id) { '6dd92b76-9519-4f8f-b076-ceae9c429050' }

  let(:outbound_connection_config) do
    {
      credentials: {
        account_id: 'wdc',
        client_id: 'abc',
        client_secret: make_secret_string('def'),
      },
      environment: {
        stage: 'Demo',
      },
    }
  end

  before(:each) do
    stub_xurrent_oauth2_token(outbound_connection_config)
  end

  describe 'input_schema' do
    it 'should define the urls field' do
      field = action.input_schema.field(:urls)
      expect(field.label).to eq('URLs')
      expect(field.type).to eq(:string)
      expect(field.required).to be_falsey
      expect(field.array).to be_truthy
      expect(field.hint).to eq('Array of URLs to poll for data. Each URL will be checked in sequence.')
    end

    it 'should define the backoff_time field' do
      field = action.input_schema.field(:backoff_time)
      expect(field.label).to eq('Backoff Time')
      expect(field.type).to eq(:integer)
      expect(field.required).to be_falsey
      expect(field.hint).to eq('Time after which the job will be rescheduled')
      expect(field.default).to eq(60)
    end

    it 'should define the max_iterations field' do
      field = action.input_schema.field(:max_iterations)
      expect(field.label).to eq('Max Iterations')
      expect(field.type).to eq(:integer)
      expect(field.required).to be_falsey
      expect(field.hint).to eq('Maximum number of times the job can be rescheduled')
      expect(field.default).to eq(1000)
    end
  end

  describe 'output_schema' do
    it 'should define the result output schema' do
      expect(action.output_schema.map(&:reference)).to eq(['result'])

      result_schema = action.output_schema.first
      expect(result_schema.name).to eq('URL Result')

      url_field = result_schema.field(:url)
      expect(url_field.label).to eq('URL')
      expect(url_field.type).to eq(:string)
      expect(url_field.required).to be_truthy

      body_field = result_schema.field(:body)
      expect(body_field.label).to eq('Response Body')
      expect(body_field.type).to eq(:hash)
      expect(body_field.required).to be_truthy
      expect(body_field.hint).to eq('Parsed JSON response from the URL')
    end
  end

  describe 'iteration_state_schema' do
    it 'should define iteration state fields' do
      expect(action.iteration_state_schema.fields.map(&:id)).to eq([:index_to_skip, :iteration_count])

      index_field = action.iteration_state_schema.field(:index_to_skip)
      expect(index_field.label).to eq('Index to skip')
      expect(index_field.type).to eq(:integer)
      expect(index_field.array).to be_truthy
      expect(index_field.hint).to eq('Array of indices for URLs that have already been processed')

      count_field = action.iteration_state_schema.field(:iteration_count)
      expect(count_field.label).to eq('Iteration Count')
      expect(count_field.type).to eq(:integer)
      expect(count_field.hint).to eq('Number of times this action has been executed without finding')
    end
  end

  describe 'run' do
    let(:action_input) do
      {
        urls: [
          'https://api1.example.com/data',
          'https://api2.example.com/data',
          'https://api3.example.com/data',
        ],
        backoff_time: 30,
        max_iterations: 5,
      }
    end

    context 'when first URL returns data' do
      before(:each) do
        response1 = double('response1', status: 200, body: { result: 'data1', id: 1 }.to_json)
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)
      end

      it 'should return data from first URL and clear iteration state' do
        output = run_action(schema_reference: 'result')
        expect(output[:url]).to eq('https://api1.example.com/data')
        expect(output[:body]).to eq({ 'result' => 'data1', 'id' => 1 })
      end

      it 'should not call other URLs when first one succeeds' do
        run_action(schema_reference: 'result')

        expect(action).to have_received(:http_get).with('https://api1.example.com/data').once
        expect(action).not_to have_received(:http_get).with('https://api2.example.com/data')
        expect(action).not_to have_received(:http_get).with('https://api3.example.com/data')
      end
    end

    context 'when first URL is empty, second has data' do
      before(:each) do
        response1 = double('response1', status: 200, body: '{}')
        response2 = double('response2', status: 200, body: { result: 'data2', id: 2 }.to_json)
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)
        allow(action).to receive(:http_get).with('https://api2.example.com/data').and_return(response2)
      end

      it 'should skip first URL and return data from second URL' do
        output = run_action(schema_reference: 'result')
        expect(output[:url]).to eq('https://api2.example.com/data')
        expect(output[:body]).to eq({ 'result' => 'data2', 'id' => 2 })
      end

      it 'should not call third URL when second one succeeds' do
        run_action(schema_reference: 'result')

        expect(action).to have_received(:http_get).with('https://api1.example.com/data').once
        expect(action).to have_received(:http_get).with('https://api2.example.com/data').once
        expect(action).not_to have_received(:http_get).with('https://api3.example.com/data')
      end
    end

    context 'when first two URLs are empty, third has data' do
      before(:each) do
        response1 = double('response1', status: 200, body: '{}')
        response2 = double('response2', status: 200, body: '{}')
        response3 = double('response3', status: 200, body: { result: 'data3', id: 3 }.to_json)
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)
        allow(action).to receive(:http_get).with('https://api2.example.com/data').and_return(response2)
        allow(action).to receive(:http_get).with('https://api3.example.com/data').and_return(response3)
      end

      it 'should skip first two URLs and return data from third URL' do
        output = run_action(schema_reference: 'result')
        expect(output[:url]).to eq('https://api3.example.com/data')
        expect(output[:body]).to eq({ 'result' => 'data3', 'id' => 3 })
      end
    end

    context 'when all URLs are empty' do
      before(:each) do
        response1 = double('response1', status: 200, body: '{}')
        response2 = double('response2', status: 200, body: '{}')
        response3 = double('response3', status: 200, body: '{}')
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)
        allow(action).to receive(:http_get).with('https://api2.example.com/data').and_return(response2)
        allow(action).to receive(:http_get).with('https://api3.example.com/data').and_return(response3)
      end

      it 'should backoff and store iteration state' do
        expect do
          run_action
        end.to raise_error(IPaaS::Job::RescheduleJob, 'Data not available yet')

        expect(action.iteration_state_value[:iteration_count]).to eq(1)
        expect(action.iteration_state_value[:index_to_skip]).to eq([])
      end
    end

    context 'with iteration state from previous run' do
      let(:action_input) do
        {
          urls: [
            'https://api1.example.com/data',
            'https://api2.example.com/data',
            'https://api3.example.com/data',
          ],
          backoff_time: 30,
          max_iterations: 5,
        }
      end

      before(:each) do
        action.send(:iteration_state_value=, {
          index_to_skip: [0],
          iteration_count: 1,
        })

        response2 = double('response2', status: 200, body: { result: 'data2', id: 2 }.to_json)
        allow(action).to receive(:http_get).with('https://api2.example.com/data').and_return(response2)
      end

      it 'should skip previously processed URLs and return data from next available URL' do
        output = run_action(schema_reference: 'result')
        expect(output[:url]).to eq('https://api2.example.com/data')
        expect(output[:body]).to eq({ 'result' => 'data2', 'id' => 2 })
      end

      it 'should not call the first URL again' do
        run_action(schema_reference: 'result')

        expect(action).not_to have_received(:http_get).with('https://api1.example.com/data')
        expect(action).to have_received(:http_get).with('https://api2.example.com/data').once
      end
    end

    context 'when max iterations is reached' do
      let(:action_input) do
        {
          urls: ['https://api1.example.com/data'],
          backoff_time: 30,
          max_iterations: 2,
        }
      end

      before(:each) do
        action.send(:iteration_state_value=, {
          index_to_skip: [],
          iteration_count: 2,
        })

        response1 = double('response1', status: 200, body: '{}')
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)
      end

      it 'should fail the job when max iterations is reached' do
        expect do
          run_action
        end.to raise_error(IPaaS::Job::FailJob, 'Maximum iterations (2) reached without finding data')
      end
    end

    context 'HTTP error handling' do
      let(:action_input) do
        {
          urls: ['https://api1.example.com/data'],
          backoff_time: 30,
          max_iterations: 5,
        }
      end

      it 'should fail job on HTTP 404 error' do
        response1 = double('response1', status: 404, body: 'Not Found')
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)

        expect do
          run_action
        end.to raise_error(IPaaS::Job::FailJob, "HTTP Error 404: 'Not Found' for URL: 'https://api1.example.com/data'")
      end

      it 'should fail job on HTTP 500 error' do
        response1 = double('response1', status: 500, body: 'Internal Server Error')
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)

        expect do
          run_action
        end.to raise_error(IPaaS::Job::FailJob, "HTTP Error 500: 'Internal Server Error' for URL: 'https://api1.example.com/data'")
      end

      it 'should fail job on HTTP 403 error' do
        response1 = double('response1', status: 403, body: 'Forbidden')
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)

        expect do
          run_action
        end.to raise_error(IPaaS::Job::FailJob, "HTTP Error 403: 'Forbidden' for URL: 'https://api1.example.com/data'")
      end

      it 'should backoff on HTTP 429 error' do
        response1 = double('response1', status: 429, body: 'Rate Limited', headers: {})
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)

        Timecop.freeze do
          expect { run_action }
            .to raise_error(IPaaS::Job::RescheduleJob, "Xurrent API rate limit hit. 'Rate Limited'") do |e|
            expect(e.reschedule_after).to eq(60.seconds.from_now)
          end
        end
      end

      it 'should backoff on HTTP 503 error' do
        response1 = double('response1', status: 503, body: 'Service Unavailable', headers: {})
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)

        Timecop.freeze do
          expect { run_action }
            .to raise_error(IPaaS::Job::RescheduleJob, "Xurrent API not available. 'Service Unavailable'") do |e|
            expect(e.reschedule_after).to eq(60.seconds.from_now)
          end
        end
      end
    end

    context 'JSON parsing error handling' do
      let(:action_input) do
        {
          urls: ['https://api1.example.com/data'],
          backoff_time: 30,
          max_iterations: 5,
        }
      end

      it 'should fail job on invalid JSON' do
        response1 = double('response1', status: 200, body: 'invalid json {')
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)

        expect do
          run_action
        end.to raise_error(IPaaS::Job::FailJob,
                           "JSON Parser Error for URL 'https://api1.example.com/data': unexpected character: " \
                           "'invalid' at line 1 column 1. Response body: 'invalid json {'")
      end

      it 'should fail job on malformed JSON' do
        response1 = double('response1', status: 200, body: '{"incomplete": json')
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)

        expect do
          run_action
        end.to raise_error(
          IPaaS::Job::FailJob,
          %r{JSON Parser Error for URL 'https://api1\.example\.com/data': .*\. Response body: '\{"incomplete": json'}
        )
      end
    end

    context 'complex scenario: 3 URLs with 1 empty body' do
      let(:action_input) do
        {
          urls: [
            'https://api1.example.com/data',
            'https://api2.example.com/data',
            'https://api3.example.com/data',
          ],
          backoff_time: 30,
          max_iterations: 5,
        }
      end

      context 'when first URL is empty, second and third have data' do
        before(:each) do
          response1 = double('response1', status: 200, body: '{}')
          response2 = double('response2', status: 200, body: { result: 'data2', id: 2 }.to_json)
          response3 = double('response3', status: 200, body: { result: 'data3', id: 3 }.to_json)
          allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)
          allow(action).to receive(:http_get).with('https://api2.example.com/data').and_return(response2)
          allow(action).to receive(:http_get).with('https://api3.example.com/data').and_return(response3)
        end

        it 'should return data from second URL and update iteration state' do
          output = run_action(schema_reference: 'result')
          expect(output[:url]).to eq('https://api2.example.com/data')
          expect(output[:body]).to eq({ 'result' => 'data2', 'id' => 2 })

          expect(action.iteration_state_value[:index_to_skip]).to include(1)
          expect(action.iteration_state_value[:iteration_count]).to eq(0)
        end

        it 'should not call third URL when second one succeeds' do
          run_action(schema_reference: 'result')

          expect(action).to have_received(:http_get).with('https://api1.example.com/data').once
          expect(action).to have_received(:http_get).with('https://api2.example.com/data').once
          expect(action).not_to have_received(:http_get).with('https://api3.example.com/data')
        end
      end

      context 'when first and second URLs are empty, third has data' do
        before(:each) do
          response1 = double('response1', status: 200, body: '{}')
          response2 = double('response2', status: 200, body: '{}')
          response3 = double('response3', status: 200, body: { result: 'data3', id: 3 }.to_json)
          allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)
          allow(action).to receive(:http_get).with('https://api2.example.com/data').and_return(response2)
          allow(action).to receive(:http_get).with('https://api3.example.com/data').and_return(response3)
        end

        it 'should return data from third URL and clear iteration state' do
          output = run_action(schema_reference: 'result')
          expect(output[:url]).to eq('https://api3.example.com/data')
          expect(output[:body]).to eq({ 'result' => 'data3', 'id' => 3 })
        end
      end

      context 'when all URLs are empty on first iteration' do
        before(:each) do
          response1 = double('response1', status: 200, body: '{}')
          response2 = double('response2', status: 200, body: '{}')
          response3 = double('response3', status: 200, body: '{}')
          allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)
          allow(action).to receive(:http_get).with('https://api2.example.com/data').and_return(response2)
          allow(action).to receive(:http_get).with('https://api3.example.com/data').and_return(response3)
        end

        it 'should backoff and store iteration state with all URLs to be retried' do
          expect do
            run_action
          end.to raise_error(IPaaS::Job::RescheduleJob, 'Data not available yet')

          expect(action.iteration_state_value[:index_to_skip]).to eq([])
          expect(action.iteration_state_value[:iteration_count]).to eq(1)
        end
      end

      context 'when second URL has data on subsequent iteration' do
        before(:each) do
          action.send(:iteration_state_value=, {
            index_to_skip: [0],
            iteration_count: 1,
          })

          response2 = double('response2', status: 200, body: { result: 'data2', id: 2 }.to_json)
          response3 = double('response3', status: 200, body: { result: 'data3', id: 3 }.to_json)
          allow(action).to receive(:http_get).with('https://api2.example.com/data').and_return(response2)
          allow(action).to receive(:http_get).with('https://api3.example.com/data').and_return(response3)
        end

        it 'should skip first URL and return data from second URL' do
          output = run_action(schema_reference: 'result')
          expect(output[:url]).to eq('https://api2.example.com/data')
          expect(output[:body]).to eq({ 'result' => 'data2', 'id' => 2 })
        end

        it 'should verify iteration state is properly managed during subsequent iteration' do
          expect(action.iteration_state_value[:index_to_skip]).to include(0)
          expect(action.iteration_state_value[:iteration_count]).to eq(1)

          output = run_action(schema_reference: 'result')
          expect(output[:url]).to eq('https://api2.example.com/data')

          expect(action.iteration_state_value[:index_to_skip]).to include(0, 1)
          expect(action.iteration_state_value[:iteration_count]).to eq(1)
        end

        it 'should not call first URL again' do
          run_action(schema_reference: 'result')

          expect(action).not_to have_received(:http_get).with('https://api1.example.com/data')
          expect(action).to have_received(:http_get).with('https://api2.example.com/data').once
          expect(action).not_to have_received(:http_get).with('https://api3.example.com/data')
        end
      end
    end

    context 'iteration state management' do
      let(:action_input) do
        {
          urls: [
            'https://api1.example.com/data',
            'https://api2.example.com/data',
            'https://api3.example.com/data',
          ],
          backoff_time: 30,
          max_iterations: 5,
        }
      end

      it 'should store iteration state when not all URLs are processed' do
        response1 = double('response1', status: 200, body: '{}')
        response2 = double('response2', status: 200, body: '{}')
        response3 = double('response3', status: 200, body: '{}')
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)
        allow(action).to receive(:http_get).with('https://api2.example.com/data').and_return(response2)
        allow(action).to receive(:http_get).with('https://api3.example.com/data').and_return(response3)

        expect do
          run_action
        end.to raise_error(IPaaS::Job::RescheduleJob, 'Data not available yet')

        expect(action.iteration_state_value[:iteration_count]).to eq(1)
        expect(action.iteration_state_value[:index_to_skip]).to eq([])
      end

      it 'should clear iteration state when all URLs are processed' do
        expect(action.iteration_state_value).to eq(nil)

        response1 = double('response1', status: 200, body: { result: 'data1', id: 1 }.to_json)
        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)

        run_action(schema_reference: 'result')

        expect(action.iteration_state_value[:iteration_count]).to eq(0)
        expect(action.iteration_state_value[:index_to_skip]).to eq([0])

        response2 = double('response2', status: 200, body: { result: 'data2', id: 2 }.to_json)
        allow(action).to receive(:http_get).with('https://api2.example.com/data').and_return(response2)

        run_action(schema_reference: 'result')

        expect(action.iteration_state_value[:iteration_count]).to eq(0)
        expect(action.iteration_state_value[:index_to_skip]).to eq([0, 1])

        response3 = double('response3', status: 200, body: { result: 'data3', id: 3 }.to_json)
        allow(action).to receive(:http_get).with('https://api3.example.com/data').and_return(response3)

        run_action(schema_reference: 'result')

        expect(action.iteration_state_value).to eq(nil)
      end

      it 'uses correct retry_after when incrementing iteration count' do
        response1 = double('response1', status: 200, body: '{}')
        response2 = double('response2', status: 200, body: '{}')
        response3 = double('response3', status: 200, body: '{}')

        allow(action).to receive(:http_get).with('https://api1.example.com/data').and_return(response1)
        allow(action).to receive(:http_get).with('https://api2.example.com/data').and_return(response2)
        allow(action).to receive(:http_get).with('https://api3.example.com/data').and_return(response3)

        begin
          run_action
        rescue IPaaS::Job::RescheduleJob => e
          expect(e).not_to be_nil
          expect(e.reschedule_after).to be_within(1.second).of(Time.current + 30.seconds)
        end
      end
    end
  end
end
