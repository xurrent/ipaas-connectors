require 'spec_helper'

describe 'Xurrent IMR List Services Action', :action, :xurrent_imr do
  let(:action_template_id) { '019d6d9a-3230-76c3-99c4-2bdace47066c' }

  let(:api_endpoint) { 'https://www.zenduty.com' }
  let(:team_id) { 'team-uuid-001' }
  let(:services_url) { "#{api_endpoint}/api/account/teams/#{team_id}/services/" }
  let(:action_input) { { team_id: team_id } }

  let(:services_response) do
    [
      {
        unique_id: 'svc-uuid-001',
        name: 'Production API',
        team: 'team-uuid-001',
        status: 1,
        escalation_policy: 'ep-uuid-001',
        summary: 'Main production API service',
        description: 'Handles all production API traffic',
        creation_date: '2026-01-15T08:00:00Z',
      },
      {
        unique_id: 'svc-uuid-002',
        name: 'Background Workers',
        team: 'team-uuid-001',
        status: 1,
        escalation_policy: 'ep-uuid-002',
        summary: 'Background job processing service',
        description: 'Handles async jobs',
        creation_date: '2026-02-01T09:00:00Z',
      },
    ]
  end

  describe 'input_schema' do
    it 'defines team_id as required string' do
      field = action.input_schema.field(:team_id)
      expect(field.type).to eq(:string)
      expect(field.required).to be(true)
    end
  end

  describe 'output_schema' do
    let(:schema) { action.output_schema.first }

    it 'defines services as nested array with expected fields' do
      services_field = schema.field(:services)
      expect(services_field.type).to eq(:nested)
      expect(services_field.array).to be(true)
      expect(services_field.field(:unique_id).type).to eq(:string)
      expect(services_field.field(:name).type).to eq(:string)
      expect(services_field.field(:team).type).to eq(:string)
      expect(services_field.field(:status).type).to eq(:integer)
      expect(services_field.field(:escalation_policy).type).to eq(:string)
      expect(services_field.field(:summary).type).to eq(:string)
    end
  end

  describe 'run' do
    describe 'successful retrieval' do
      it 'returns all services with mapped fields' do
        stub_request(:get, services_url)
          .with(headers: { 'Authorization' => 'Token test-api-key', 'Content-Type' => 'application/json' })
          .to_return(status: 200, body: services_response.to_json)

        output = run_action
        services = output[:services]
        expect(services.length).to eq(2)

        expect(services.first[:unique_id]).to eq('svc-uuid-001')
        expect(services.first[:name]).to eq('Production API')
        expect(services.first[:team]).to eq('team-uuid-001')
        expect(services.first[:status]).to eq(1)
        expect(services.first[:escalation_policy]).to eq('ep-uuid-001')
        expect(services.first[:summary]).to eq('Main production API service')

        expect(services.second[:unique_id]).to eq('svc-uuid-002')
        expect(services.second[:name]).to eq('Background Workers')
      end

      it 'returns empty array when no services exist' do
        stub_request(:get, services_url)
          .to_return(status: 200, body: [].to_json)

        output = run_action
        expect(output[:services]).to eq([])
      end
    end

    describe 'error handling' do
      let(:rate_limit_url) { services_url }
      let(:rate_limit_http_method) { :get }
      let(:rate_limit_input) { nil }

      it_behaves_like 'xurrent_imr rate limiting'

      it 'fails on 401 unauthorized' do
        stub_request(:get, services_url)
          .to_return(status: 401, body: { detail: 'Authentication credentials were not provided.' }.to_json)

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /Xurrent IMR API error \(HTTP 401\)/)
      end

      it 'fails on 404 not found' do
        stub_request(:get, services_url)
          .to_return(status: 404, body: { detail: 'Not found.' }.to_json)

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /Xurrent IMR API error \(HTTP 404\)/)
      end
    end
  end
end
