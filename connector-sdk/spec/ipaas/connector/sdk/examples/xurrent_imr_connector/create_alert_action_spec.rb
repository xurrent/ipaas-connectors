require 'spec_helper'

describe 'Xurrent IMR Create Alert Action', :action, :xurrent_imr do
  let(:action_template_id) { '019d6d9a-3230-7581-a1e0-0e8eae4bee91' }

  let(:api_endpoint) { 'https://www.zenduty.com' }
  let(:integration_key) { 'test-integration-key' }
  let(:alert_url) { "#{api_endpoint}/api/events/#{integration_key}/" }
  let(:action_input) do
    {
      integration_key: integration_key,
      message: 'High CPU usage detected',
      alert_type: 'critical',
    }
  end

  let(:alert_response) do
    {
      unique_id: 'alert-uuid-001',
      incident: 42,
      incident_created: true,
      entity_id: 'cpu-alert-prod',
      alert_type: 3,
      message: 'High CPU usage detected',
    }
  end

  describe 'input_schema' do
    it 'defines required fields' do
      schema = action.input_schema
      expect(schema.field(:integration_key).type).to eq(:string)
      expect(schema.field(:integration_key).required).to be(true)
      expect(schema.field(:message).type).to eq(:string)
      expect(schema.field(:message).required).to be(true)
      expect(schema.field(:alert_type).type).to eq(:string)
      expect(schema.field(:alert_type).required).to be(true)
    end

    it 'defines optional fields' do
      schema = action.input_schema
      expect(schema.field(:summary).type).to eq(:string)
      expect(schema.field(:summary).required).to be_falsey
      expect(schema.field(:entity_id).type).to eq(:string)
      expect(schema.field(:entity_id).required).to be_falsey
    end

    it 'defines alert_type enumeration' do
      field = action.input_schema.field(:alert_type)
      ids = field.enumeration.map { |e| e[:id] }
      expect(ids).to contain_exactly('critical', 'error', 'warning', 'info', 'acknowledged', 'resolved')
    end
  end

  describe 'output_schema' do
    let(:schema) { action.output_schema.first }

    it 'defines all output fields' do
      expect(schema.field(:unique_id).type).to eq(:string)
      expect(schema.field(:incident).type).to eq(:integer)
      expect(schema.field(:incident_created).type).to eq(:boolean)
      expect(schema.field(:entity_id).type).to eq(:string)
      expect(schema.field(:alert_type).type).to eq(:integer)
      expect(schema.field(:message).type).to eq(:string)
    end
  end

  describe 'run' do
    describe 'successful alert creation' do
      it 'creates an alert and returns the response' do
        stub_request(:post, alert_url)
          .with(
            body: { message: 'High CPU usage detected', alert_type: 'critical' },
            headers: { 'Authorization' => 'Token test-api-key', 'Content-Type' => 'application/json' }
          )
          .to_return(status: 201, body: alert_response.to_json)

        output = run_action
        expect(output[:unique_id]).to eq('alert-uuid-001')
        expect(output[:incident]).to eq(42)
        expect(output[:incident_created]).to be(true)
        expect(output[:entity_id]).to eq('cpu-alert-prod')
        expect(output[:alert_type]).to eq(3)
        expect(output[:message]).to eq('High CPU usage detected')
      end

      it 'includes optional fields when provided' do
        input = action_input.merge(summary: 'Detailed summary', entity_id: 'dedup-key-1')
        stub = stub_request(:post, alert_url)
               .with(body: hash_including(summary: 'Detailed summary', entity_id: 'dedup-key-1'))
               .to_return(status: 201, body: alert_response.to_json)

        run_action(input)
        expect(stub).to have_been_requested.once
      end

      it 'omits nil optional fields from request body' do
        stub = stub_request(:post, alert_url)
               .with do |req|
          body = JSON.parse(req.body)
          !body.key?('summary') && !body.key?('entity_id')
        end
               .to_return(status: 201, body: alert_response.to_json)

        run_action
        expect(stub).to have_been_requested.once
      end
    end

    describe 'error handling' do
      let(:rate_limit_url) { alert_url }
      let(:rate_limit_http_method) { :post }
      let(:rate_limit_input) { nil }

      it_behaves_like 'xurrent_imr rate limiting'

      it 'fails on 400 bad request' do
        stub_request(:post, alert_url)
          .to_return(status: 400, body: { error: 'Bad request' }.to_json)

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /Xurrent IMR API error \(HTTP 400\)/)
      end

      it 'fails on 401 unauthorized' do
        stub_request(:post, alert_url)
          .to_return(status: 401, body: { detail: 'Authentication credentials were not provided.' }.to_json)

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /Xurrent IMR API error \(HTTP 401\)/)
      end

      it 'fails on non-201 success status' do
        stub_request(:post, alert_url)
          .to_return(status: 200, body: alert_response.to_json)

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /Xurrent IMR API error \(HTTP 200\)/)
      end
    end
  end
end
