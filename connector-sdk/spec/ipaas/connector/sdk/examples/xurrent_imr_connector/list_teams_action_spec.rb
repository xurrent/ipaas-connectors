require 'spec_helper'

describe 'Xurrent IMR List Teams Action', :action, :xurrent_imr do
  let(:action_template_id) { '019d6d9a-3230-79a4-82e0-6e399b045498' }

  let(:api_endpoint) { 'https://www.zenduty.com' }
  let(:teams_url) { "#{api_endpoint}/api/account/teams/" }
  let(:teams_response) do
    [
      {
        unique_id: 'team-uuid-001',
        name: 'Platform Team',
        owner: 'admin',
        creation_date: '2026-01-15T08:00:00Z',
        account: 'account-uuid',
        members: [],
      },
      {
        unique_id: 'team-uuid-002',
        name: 'SRE Team',
        owner: 'sre-lead',
        creation_date: '2026-02-20T10:00:00Z',
        account: 'account-uuid',
        members: [],
      },
    ]
  end

  describe 'output_schema' do
    let(:schema) { action.output_schema.first }

    it 'defines teams as nested array with expected fields' do
      teams_field = schema.field(:teams)
      expect(teams_field.type).to eq(:nested)
      expect(teams_field.array).to be(true)
      expect(teams_field.field(:unique_id).type).to eq(:string)
      expect(teams_field.field(:name).type).to eq(:string)
      expect(teams_field.field(:owner).type).to eq(:string)
      expect(teams_field.field(:creation_date).type).to eq(:string)
    end
  end

  describe 'run' do
    describe 'successful retrieval' do
      it 'returns all teams with mapped fields' do
        stub_request(:get, teams_url)
          .with(headers: { 'Authorization' => 'Token test-api-key', 'Content-Type' => 'application/json' })
          .to_return(status: 200, body: teams_response.to_json)

        output = run_action
        teams = output[:teams]
        expect(teams.length).to eq(2)

        expect(teams.first[:unique_id]).to eq('team-uuid-001')
        expect(teams.first[:name]).to eq('Platform Team')
        expect(teams.first[:owner]).to eq('admin')
        expect(teams.first[:creation_date]).to eq('2026-01-15T08:00:00Z')

        expect(teams.second[:unique_id]).to eq('team-uuid-002')
        expect(teams.second[:name]).to eq('SRE Team')
      end

      it 'returns empty array when no teams exist' do
        stub_request(:get, teams_url)
          .to_return(status: 200, body: [].to_json)

        output = run_action
        expect(output[:teams]).to eq([])
      end
    end

    describe 'error handling' do
      let(:rate_limit_url) { teams_url }
      let(:rate_limit_http_method) { :get }
      let(:rate_limit_input) { nil }

      it_behaves_like 'xurrent_imr rate limiting'

      it 'fails on 401 unauthorized' do
        stub_request(:get, teams_url)
          .to_return(status: 401, body: { detail: 'Authentication credentials were not provided.' }.to_json)

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /Xurrent IMR API error \(HTTP 401\)/)
      end

      it 'fails on 500 server error' do
        stub_request(:get, teams_url)
          .to_return(status: 500, body: 'Internal Server Error')

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /Xurrent IMR API error \(HTTP 500\)/)
      end
    end
  end
end
