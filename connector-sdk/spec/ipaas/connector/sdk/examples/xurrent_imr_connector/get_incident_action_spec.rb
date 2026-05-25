require 'spec_helper'

describe 'Xurrent IMR Get Incident Action', :action, :xurrent_imr do
  let(:action_template_id) { '019d6d9a-3230-7bdc-b7f8-c8edb073f0dd' }

  let(:incident_number) { 42 }
  let(:incident_url) { "#{base_url}/api/incidents/#{incident_number}/" }
  let(:sample_response) do
    {
      unique_id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      incident_number: incident_number,
      title: 'High CPU Alert',
      summary: 'High CPU usage on production server',
      status: 1,
      creation_date: '2026-04-08T10:30:00Z',
      urgency: 1,
      assigned_to: 'jdoe',
      assigned_to_name: 'John Doe',
      incident_key: 'cpu-alert-prod-001',
      service: 'b2c3d4e5-f6a7-8901-bcde-f23456789012',
      escalation_policy: 'c3d4e5f6-a7b8-9012-cdef-345678901234',
      service_object: { name: 'Production API', unique_id: 'b2c3d4e5-f6a7-8901-bcde-f23456789012' },
      escalation_policy_object: { unique_id: 'c3d4e5f6-a7b8-9012-cdef-345678901234', name: 'Default EP' },
      resolved_date: nil,
      acknowledged_date: nil,
      tags: [],
      sla: nil,
      sla_object: nil,
      merged_with: nil,
      team_priority: nil,
      team_priority_object: nil,
    }
  end

  let(:action_input) do
    { incident_number: incident_number }
  end

  describe 'input_schema' do
    context 'incident_number field' do
      let(:field) { action.input_schema.field(:incident_number) }

      it { expect(field.type).to eq(:integer) }
      it { expect(field.required).to be_truthy }
    end
  end

  describe 'output_schema' do
    let(:schema) { action.output_schema.first }

    it { expect(schema.field(:unique_id).type).to eq(:string) }
    it { expect(schema.field(:unique_id).required).to be_truthy }
    it { expect(schema.field(:incident_number).type).to eq(:integer) }
    it { expect(schema.field(:incident_number).required).to be_truthy }
    it { expect(schema.field(:title).type).to eq(:string) }
    it { expect(schema.field(:summary).type).to eq(:string) }
    it { expect(schema.field(:status).type).to eq(:integer) }
    it { expect(schema.field(:creation_date).type).to eq(:string) }
    it { expect(schema.field(:urgency).type).to eq(:integer) }
    it { expect(schema.field(:assigned_to).type).to eq(:string) }
    it { expect(schema.field(:assigned_to_name).type).to eq(:string) }
    it { expect(schema.field(:incident_key).type).to eq(:string) }
  end

  describe 'run' do
    context 'when retrieval is successful' do
      it 'fetches incident with correct headers' do
        stub = stub_request(:get, incident_url)
               .with(
                 headers: {
                   'Authorization' => 'Token test-api-key',
                   'Content-Type' => 'application/json',
                 }
               )
               .to_return(status: 200, body: sample_response.to_json)

        output = run_action

        expect(output[:unique_id]).to eq('a1b2c3d4-e5f6-7890-abcd-ef1234567890')
        expect(output[:incident_number]).to eq(42)
        expect(output[:title]).to eq('High CPU Alert')
        expect(output[:summary]).to eq('High CPU usage on production server')
        expect(output[:status]).to eq(1)
        expect(output[:creation_date]).to eq('2026-04-08T10:30:00Z')
        expect(output[:urgency]).to eq(1)
        expect(output[:assigned_to]).to eq('jdoe')
        expect(output[:assigned_to_name]).to eq('John Doe')
        expect(output[:incident_key]).to eq('cpu-alert-prod-001')
        expect(stub).to have_been_requested.once
      end
    end

    context 'when an error occurs' do
      let(:rate_limit_url) { incident_url }
      let(:rate_limit_http_method) { :get }
      let(:rate_limit_input) { nil }

      it_behaves_like 'xurrent_imr rate limiting'

      it 'fails on 401 authentication error' do
        stub_request(:get, incident_url)
          .to_return(status: 401, body: 'Unauthorized')

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /401/)
      end

      it 'fails on 500 server error' do
        stub_request(:get, incident_url)
          .to_return(status: 500, body: 'Internal Server Error')

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /500/)
      end

      it 'fails on invalid JSON response' do
        stub_request(:get, incident_url)
          .to_return(status: 200, body: 'not json')

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /not valid JSON/)
      end
    end
  end
end
