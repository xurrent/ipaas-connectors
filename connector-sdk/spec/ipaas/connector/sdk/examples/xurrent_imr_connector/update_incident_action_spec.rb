require 'spec_helper'

describe 'Xurrent IMR Update Incident Action', :action, :xurrent_imr do
  let(:action_template_id) { '019d6d9a-3230-7ca5-b963-a4363fda7dc1' }

  let(:incident_id) { 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' }
  let(:incident_url) { "#{base_url}/api/incidents/#{incident_id}/" }
  let(:sample_response) do
    {
      unique_id: incident_id,
      incident_number: 42,
      title: 'Updated CPU Alert',
      summary: 'Updated summary',
      status: 2,
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
      acknowledged_date: '2026-04-08T10:35:00Z',
      tags: [],
      sla: nil,
      sla_object: nil,
      merged_with: nil,
      team_priority: nil,
      team_priority_object: nil,
    }
  end

  let(:action_input) do
    {
      unique_id: incident_id,
      title: 'Updated CPU Alert',
      summary: 'Updated summary',
      status: 2,
    }
  end

  describe 'input_schema' do
    context 'required fields' do
      it { expect(action.input_schema.field(:unique_id).type).to eq(:string) }
      it { expect(action.input_schema.field(:unique_id).required).to be_truthy }
    end

    context 'optional fields' do
      it { expect(action.input_schema.field(:title).type).to eq(:string) }
      it { expect(action.input_schema.field(:title).required).to be_falsey }
      it { expect(action.input_schema.field(:summary).type).to eq(:string) }
      it { expect(action.input_schema.field(:summary).required).to be_falsey }
      it { expect(action.input_schema.field(:assigned_to).type).to eq(:string) }
      it { expect(action.input_schema.field(:escalation_policy_id).type).to eq(:string) }
      it { expect(action.input_schema.field(:priority_id).type).to eq(:string) }
      it { expect(action.input_schema.field(:urgency).type).to eq(:integer) }
    end

    context 'status enumeration' do
      let(:field) { action.input_schema.field(:status) }

      it { expect(field.type).to eq(:integer) }

      it 'enumerates status values' do
        expect(field.enumeration.map { |e| e[:id] }).to contain_exactly(1, 2, 3)
      end
    end

    context 'urgency enumeration' do
      let(:field) { action.input_schema.field(:urgency) }

      it 'enumerates urgency values' do
        expect(field.enumeration.map { |e| e[:id] }).to contain_exactly(0, 1)
      end
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
    context 'when update is successful' do
      it 'updates incident with correct payload and headers' do
        stub = stub_request(:patch, incident_url)
               .with(
                 body: {
                   title: 'Updated CPU Alert',
                   summary: 'Updated summary',
                   status: 2,
                 }.to_json,
                 headers: {
                   'Authorization' => 'Token test-api-key',
                   'Content-Type' => 'application/json',
                 }
               )
               .to_return(status: 200, body: sample_response.to_json)

        output = run_action

        expect(output[:unique_id]).to eq(incident_id)
        expect(output[:incident_number]).to eq(42)
        expect(output[:title]).to eq('Updated CPU Alert')
        expect(output[:summary]).to eq('Updated summary')
        expect(output[:status]).to eq(2)
        expect(output[:creation_date]).to eq('2026-04-08T10:30:00Z')
        expect(output[:urgency]).to eq(1)
        expect(output[:assigned_to]).to eq('jdoe')
        expect(output[:assigned_to_name]).to eq('John Doe')
        expect(output[:incident_key]).to eq('cpu-alert-prod-001')
        expect(stub).to have_been_requested.once
      end

      it 'omits nil fields from payload' do
        stub = stub_request(:patch, incident_url)
               .with(body: { status: 3 }.to_json)
               .to_return(status: 200, body: sample_response.to_json)

        run_action({ unique_id: incident_id, status: 3 })

        expect(stub).to have_been_requested.once
      end
    end

    context 'when an error occurs' do
      let(:rate_limit_url) { incident_url }
      let(:rate_limit_http_method) { :patch }
      let(:rate_limit_input) { nil }

      it_behaves_like 'xurrent_imr rate limiting'

      it 'fails on 401 authentication error' do
        stub_request(:patch, incident_url)
          .to_return(status: 401, body: 'Unauthorized')

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /401/)
      end

      it 'fails on 500 server error' do
        stub_request(:patch, incident_url)
          .to_return(status: 500, body: 'Internal Server Error')

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /500/)
      end

      it 'fails on invalid JSON response' do
        stub_request(:patch, incident_url)
          .to_return(status: 200, body: 'not json')

        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, /not valid JSON/)
      end
    end
  end
end
