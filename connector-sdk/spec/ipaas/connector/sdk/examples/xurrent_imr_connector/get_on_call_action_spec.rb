require 'spec_helper'

describe 'Xurrent IMR Get On-Call Action', :action, :xurrent_imr do
  let(:action_template_id) { '019d6d9a-3230-7255-96c5-194b12acb53d' }

  let(:api_endpoint) { 'https://www.zenduty.com' }
  let(:team_id) { 'team-uuid-001' }
  let(:oncall_url) { "#{api_endpoint}/api/v2/account/teams/#{team_id}/oncall/" }
  let(:action_input) { { team_id: team_id } }

  let(:oncall_response) do
    [
      {
        unique_id: 'ep-uuid-001',
        name: 'Primary Escalation Policy',
        oncalls: [
          {
            ep_rule: 'rule-uuid-001',
            position: 1,
            delay: 0,
            oncalls: [
              {
                username: 'jdoe',
                first_name: 'John',
                last_name: 'Doe',
                email: 'jdoe@example.com',
              },
            ],
          },
        ],
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

    it 'defines escalation_policies as nested array' do
      ep_field = schema.field(:escalation_policies)
      expect(ep_field.type).to eq(:nested)
      expect(ep_field.array).to be(true)
      expect(ep_field.field(:unique_id).type).to eq(:string)
      expect(ep_field.field(:name).type).to eq(:string)
    end

    it 'defines nested oncall rules with users' do
      rules_field = schema.field(:escalation_policies).field(:oncalls)
      expect(rules_field.type).to eq(:nested)
      expect(rules_field.array).to be(true)
      expect(rules_field.field(:position).type).to eq(:integer)
      expect(rules_field.field(:delay).type).to eq(:integer)

      users_field = rules_field.field(:oncalls)
      expect(users_field.type).to eq(:nested)
      expect(users_field.array).to be(true)
      expect(users_field.field(:username).type).to eq(:string)
      expect(users_field.field(:first_name).type).to eq(:string)
      expect(users_field.field(:last_name).type).to eq(:string)
      expect(users_field.field(:email).type).to eq(:string)
    end
  end

  describe 'run' do
    describe 'successful retrieval' do
      it 'returns on-call escalation policies' do
        stub_request(:get, oncall_url)
          .with(headers: { 'Authorization' => 'Token test-api-key', 'Content-Type' => 'application/json' })
          .to_return(status: 200, body: oncall_response.to_json)

        output = run_action
        policies = output[:escalation_policies]
        expect(policies.length).to eq(1)
        expect(policies.first[:unique_id]).to eq('ep-uuid-001')
        expect(policies.first[:name]).to eq('Primary Escalation Policy')

        rule = policies.first[:oncalls].first
        expect(rule[:position]).to eq(1)
        expect(rule[:delay]).to eq(0)

        user = rule[:oncalls].first
        expect(user[:username]).to eq('jdoe')
        expect(user[:email]).to eq('jdoe@example.com')
      end

      it 'returns empty array when no escalation policies exist' do
        stub_request(:get, oncall_url)
          .to_return(status: 200, body: [].to_json)

        output = run_action
        expect(output[:escalation_policies]).to eq([])
      end
    end

    describe 'error handling' do
      let(:rate_limit_url) { oncall_url }
      let(:rate_limit_http_method) { :get }
      let(:rate_limit_input) { nil }

      it_behaves_like 'xurrent_imr rate limiting'

      it 'fails on 401 unauthorized' do
        stub_request(:get, oncall_url)
          .to_return(status: 401, body: { detail: 'Authentication credentials were not provided.' }.to_json)

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /Xurrent IMR API error \(HTTP 401\)/)
      end

      it 'fails on 404 not found' do
        stub_request(:get, oncall_url)
          .to_return(status: 404, body: { detail: 'Not found.' }.to_json)

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /Xurrent IMR API error \(HTTP 404\)/)
      end
    end
  end
end
