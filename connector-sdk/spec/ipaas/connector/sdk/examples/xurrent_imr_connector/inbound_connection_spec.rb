require 'spec_helper'

describe 'Xurrent IMR Inbound Connection', :trigger do
  let(:connector_id) { '019d6d9a-3230-7355-9268-3ec5c9ce502c' }
  let(:trigger_template_id) { '019d6d9a-3230-708c-91d2-fac5a18ac9d0' }

  describe 'validators' do
    it 'includes basic_auth validator' do
      expect(connector.inbound_connection.validators).to include(:basic_auth)
    end
  end

  describe 'config_schema' do
    it 'has optional webhook_secret field' do
      expect(connector.inbound_connection.config_schema.field(:webhook_secret).required).to be_falsey
      expect(connector.inbound_connection.config_schema.field(:webhook_secret).type).to eq(:secret_string)
    end
  end

  describe 'HMAC signature validation' do
    let(:trigger_config) { {} }
    let(:webhook_secret) { 'test-secret' }
    let(:inbound_connection_config) { { webhook_secret: make_secret_string(webhook_secret) } }

    let(:webhook_payload) do
      {
        payload: {
          event_type: 'triggered',
          incident: {
            summary: 'Test incident',
            incident_number: 1,
            creation_date: '2026-04-08T10:00:00Z',
            status: 1,
            unique_id: 'test-uid',
            title: 'Test',
            incident_key: 'test-key',
            priority: 1,
            urgency: 1,
            resolved_date: nil,
            acknowledged_date: nil,
            assigned_to: { username: 'user', first_name: 'A', last_name: 'B', email: 'a@b.com' },
            service: {
              name: 'Svc', unique_id: 'svc-uid', escalation_policy: 'ep',
              team: 'team', status: 1, summary: 's', description: 'd',
            },
          },
        },
      }
    end

    def hmac_signature(body, secret: webhook_secret)
      Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', secret, body))
    end

    it 'accepts a valid signature' do
      signature = hmac_signature(webhook_payload.to_json)
      output = post_trigger(webhook_payload, headers: { 'X-SIGNATURE' => signature })
      expect(output[:event_type]).to eq('triggered')
    end

    it 'rejects an invalid signature' do
      output = post_trigger(webhook_payload, headers: { 'X-SIGNATURE' => 'bad-signature' })
      expect(output).to eq({ error: 'Invalid webhook signature.' })
    end

    it 'rejects a missing X-SIGNATURE header' do
      output = post_trigger(webhook_payload)
      expect(output).to eq({ error: 'Missing X-SIGNATURE header.' })
    end
  end

  describe 'basic auth validation' do
    let(:trigger_config) { {} }
    let(:outbound_connection_config) do
      { credentials: { api_key: make_secret_string('test-api-key') } }
    end
    let(:inbound_connection_config) do
      {
        basic_auth: {
          username: 'webhook-user',
          password: make_secret_string('webhook-pass'),
        },
      }
    end

    let(:webhook_payload) do
      {
        payload: {
          event_type: 'triggered',
          incident: {
            summary: 'Test incident',
            incident_number: 1,
            creation_date: '2026-04-08T10:00:00Z',
            status: 1,
            unique_id: 'test-uid',
            title: 'Test',
            incident_key: 'test-key',
            priority: 1,
            urgency: 1,
            resolved_date: nil,
            acknowledged_date: nil,
            assigned_to: { username: 'user', first_name: 'A', last_name: 'B', email: 'a@b.com' },
            service: {
              name: 'Svc', unique_id: 'svc-uid', escalation_policy: 'ep',
              team: 'team', status: 1, summary: 's', description: 'd',
            },
          },
        },
      }
    end

    it 'accepts valid basic auth credentials' do
      expect(runbook).to receive(:store_job_context_identifier).with('test-uid')
      output = post_trigger(webhook_payload, basic_auth: %w[webhook-user webhook-pass])
      expect(output[:event_type]).to eq('triggered')
      expect(output[:unique_id]).to eq('test-uid')
    end

    it 'rejects missing basic auth header' do
      output = post_trigger(webhook_payload)
      expect(output).to eq({ error: 'Missing basic authentication header.' })
    end

    it 'rejects invalid basic auth credentials' do
      output = post_trigger(webhook_payload, basic_auth: %w[webhook-user wrong-pass])
      expect(output).to eq({ error: 'Invalid basic authentication header.' })
    end
  end
end
