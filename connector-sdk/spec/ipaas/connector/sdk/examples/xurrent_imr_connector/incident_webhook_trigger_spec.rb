require 'spec_helper'

describe 'Xurrent IMR Incident Webhook Trigger', :trigger do
  let(:trigger_template_id) { '019d6d9a-3230-708c-91d2-fac5a18ac9d0' }
  let(:webhook_secret) { 'test-secret' }
  let(:trigger_config) { {} }
  let(:inbound_connection_config) { { webhook_secret: make_secret_string(webhook_secret) } }

  let(:incident_payload) do
    {
      payload: {
        event_type: 'triggered',
        incident: {
          summary: 'High CPU usage on production server',
          incident_number: 42,
          creation_date: '2026-04-08T10:30:00Z',
          status: 1,
          unique_id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
          title: 'High CPU Alert',
          incident_key: 'cpu-alert-prod-001',
          priority: 1,
          urgency: 1,
          resolved_date: nil,
          acknowledged_date: nil,
          assigned_to: {
            username: 'jdoe',
            first_name: 'John',
            last_name: 'Doe',
            email: 'jdoe@example.com',
          },
          service: {
            name: 'Production API',
            unique_id: 'b2c3d4e5-f6a7-8901-bcde-f23456789012',
            escalation_policy: 'c3d4e5f6-a7b8-9012-cdef-345678901234',
            team: 'd4e5f6a7-b8c9-0123-defa-456789012345',
            status: 1,
            summary: 'Main production API service',
            description: 'Handles all production API traffic',
          },
        },
      },
    }
  end

  def hmac_signature(body, secret: webhook_secret)
    Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', secret, body))
  end

  def post_with_signature(payload, secret: webhook_secret)
    body = payload.to_json
    signature = hmac_signature(body, secret: secret)
    post_trigger(payload, headers: { 'X-SIGNATURE' => signature })
  end

  describe 'output_schema' do
    it 'defines expected field types' do
      schema = trigger.output_schema
      expect(schema.field(:event_type).type).to eq(:string)
      expect(schema.field(:event_type).required).to be_truthy
      expect(schema.field(:incident_number).type).to eq(:integer)
      expect(schema.field(:incident_number).required).to be_truthy
      expect(schema.field(:unique_id).type).to eq(:string)
      expect(schema.field(:unique_id).required).to be_truthy
      expect(schema.field(:title).type).to eq(:string)
      expect(schema.field(:summary).type).to eq(:string)
      expect(schema.field(:incident_key).type).to eq(:string)
      expect(schema.field(:status).type).to eq(:integer)
      expect(schema.field(:priority).type).to eq(:integer)
      expect(schema.field(:urgency).type).to eq(:integer)
      expect(schema.field(:creation_date).type).to eq(:string)
      expect(schema.field(:resolved_date).type).to eq(:string)
      expect(schema.field(:acknowledged_date).type).to eq(:string)
      expect(schema.field(:merged_with).type).to eq(:string)
      expect(schema.field(:context_window_start).type).to eq(:string)
      expect(schema.field(:context_window_end).type).to eq(:string)
    end

    it 'defines nested assigned_to fields' do
      assigned_to = trigger.output_schema.field(:assigned_to)
      expect(assigned_to.type).to eq(:nested)
      expect(assigned_to.fields.map(&:id)).to contain_exactly(:username, :first_name, :last_name, :email)
    end

    it 'defines nested service fields' do
      service = trigger.output_schema.field(:service)
      expect(service.type).to eq(:nested)
      expect(service.fields.map(&:id)).to contain_exactly(
        :name, :unique_id, :escalation_policy, :team, :status, :summary, :description,
        :creation_date, :auto_resolve_timeout, :acknowledgement_timeout, :created_by
      )
    end
  end

  describe 'parse' do
    describe 'event types' do
      it 'parses a triggered event' do
        expect(runbook).to receive(:store_job_context_identifier)
          .with('a1b2c3d4-e5f6-7890-abcd-ef1234567890')
        output = post_with_signature(incident_payload)
        expect(output[:event_type]).to eq('triggered')
        expect(output[:incident_number]).to eq(42)
        expect(output[:unique_id]).to eq('a1b2c3d4-e5f6-7890-abcd-ef1234567890')
        expect(output[:title]).to eq('High CPU Alert')
        expect(output[:summary]).to eq('High CPU usage on production server')
        expect(output[:incident_key]).to eq('cpu-alert-prod-001')
        expect(output[:status]).to eq(1)
        expect(output[:priority]).to eq(1)
        expect(output[:urgency]).to eq(1)
        expect(output[:creation_date]).to eq('2026-04-08T10:30:00Z')
        expect(output[:resolved_date]).to be_nil
        expect(output[:acknowledged_date]).to be_nil
        expect(output[:assigned_to]).to eq(
          username: 'jdoe', first_name: 'John', last_name: 'Doe', email: 'jdoe@example.com'
        )
        expect(output[:service]).to include(
          name: 'Production API',
          unique_id: 'b2c3d4e5-f6a7-8901-bcde-f23456789012'
        )
      end

      it 'parses an acknowledged event' do
        payload = incident_payload.deep_dup
        payload[:payload][:event_type] = 'acknowledged'
        payload[:payload][:incident][:status] = 2
        payload[:payload][:incident][:acknowledged_date] = '2026-04-08T10:35:00Z'

        output = post_with_signature(payload)
        expect(output[:event_type]).to eq('acknowledged')
        expect(output[:status]).to eq(2)
        expect(output[:acknowledged_date]).to eq('2026-04-08T10:35:00Z')
      end

      it 'parses a resolved event' do
        payload = incident_payload.deep_dup
        payload[:payload][:event_type] = 'resolved'
        payload[:payload][:incident][:status] = 3
        payload[:payload][:incident][:resolved_date] = '2026-04-08T11:00:00Z'

        output = post_with_signature(payload)
        expect(output[:event_type]).to eq('resolved')
        expect(output[:status]).to eq(3)
        expect(output[:resolved_date]).to eq('2026-04-08T11:00:00Z')
      end
    end

    describe 'error cases' do
      it 'fails on empty body' do
        output = post_trigger(nil, headers: { 'X-SIGNATURE' => 'irrelevant' })
        expect(output).to eq({ error: 'Request has no body.' })
      end

      it 'fails on invalid JSON' do
        body = 'not json'
        signature = hmac_signature(body)
        uri = URI.parse(
          "http://127.0.0.1:#{TriggerServer::TRIGGER_SERVER_PORT}/inbound/#{trigger.runbook.uuid}"
        )
        response = Faraday.post(uri) do |req|
          req.body = body
          req.headers['X-SIGNATURE'] = signature
          req.headers['Content-Type'] = 'application/json'
        end
        result = JSON.parse(response.body).deep_symbolize_keys
        expect(result[:error]).to include('Invalid JSON in request body:')
      end

      it 'fails when incident data is missing' do
        payload = { payload: { event_type: 'triggered' } }
        output = post_with_signature(payload)
        expect(output).to eq({ error: 'Missing incident data in webhook payload.' })
      end
    end

    describe 'HMAC signature validation' do
      it 'accepts a valid signature' do
        output = post_with_signature(incident_payload)
        expect(output[:event_type]).to eq('triggered')
      end

      it 'rejects an invalid signature' do
        output = post_trigger(incident_payload, headers: { 'X-SIGNATURE' => 'bad-signature' })
        expect(output).to eq({ error: 'Invalid webhook signature.' })
      end

      it 'rejects a missing X-SIGNATURE header' do
        output = post_trigger(incident_payload)
        expect(output).to eq({ error: 'Missing X-SIGNATURE header.' })
      end

      context 'without webhook_secret configured' do
        let(:inbound_connection_config) { {} }

        it 'accepts any request without HMAC validation' do
          output = post_trigger(incident_payload)
          expect(output[:event_type]).to eq('triggered')
          expect(output[:incident_number]).to eq(42)
        end
      end
    end

    describe 'basic auth (alternative to HMAC)' do
      let(:inbound_connection_config) do
        {
          basic_auth: {
            username: 'webhook-user',
            password: make_secret_string('webhook-pass'),
          },
        }
      end

      it 'accepts a request with valid basic auth credentials' do
        expect(runbook).to receive(:store_job_context_identifier)
          .with('a1b2c3d4-e5f6-7890-abcd-ef1234567890')
        output = post_trigger(incident_payload, basic_auth: %w[webhook-user webhook-pass])
        expect(output[:event_type]).to eq('triggered')
        expect(output[:incident_number]).to eq(42)
        expect(output[:unique_id]).to eq('a1b2c3d4-e5f6-7890-abcd-ef1234567890')
      end

      it 'rejects a request with invalid basic auth credentials' do
        output = post_trigger(incident_payload, basic_auth: %w[webhook-user wrong-pass])
        expect(output).to eq({ error: 'Invalid basic authentication header.' })
      end

      it 'rejects a request without a basic auth header' do
        output = post_trigger(incident_payload)
        expect(output).to eq({ error: 'Missing basic authentication header.' })
      end
    end

    describe 'job_context_identifier' do
      it 'sets job_context_identifier to incident unique_id' do
        expect(runbook).to receive(:store_job_context_identifier)
          .with('a1b2c3d4-e5f6-7890-abcd-ef1234567890')
        post_with_signature(incident_payload)
      end
    end
  end
end
