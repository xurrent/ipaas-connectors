require 'spec_helper'
require_relative 'shared/webhook_trigger_specs'

describe 'Xurrent Webhook Trigger', :trigger do
  include WebhookTriggerSpecs

  describe 'config_schema' do
    let(:policy_field) { trigger.config_schema.field(:policy) }

    it 'defines the top-level policy field as optional nested' do
      expect(policy_field.label).to eq('Webhook Policy')
      expect(policy_field.hint).not_to be_nil
      expect(policy_field.visibility).to eq('optional')
      expect(policy_field.fields.size).to eq(4)
    end

    it 'defines the account_url sub-field as optional string labelled Issuer' do
      field = policy_field.field(:account_url)
      expect(field.label).to eq('Issuer')
      expect(field.type).to eq(:string)
      expect(field.required).to be_falsey
      expect(field.visibility).to eq('optional')
    end

    it 'defines the algorithm sub-field with signing algorithm options as optional' do
      field = policy_field.field(:algorithm)
      expect(field.label).to eq('Algorithm')
      expect(field.type).to eq(:string)
      expect(field.required).to be_falsey
      expect(field.visibility).to eq('optional')
      expect(field.enumeration.pluck(:id)).to eq(%w[RS256 RS384 RS512 ES256 ES384 ES512])
    end

    it 'defines the public_key_pem sub-field as optional string' do
      field = policy_field.field(:public_key_pem)
      expect(field.label).to eq('Public key PEM')
      expect(field.type).to eq(:string)
      expect(field.required).to be_falsey
      expect(field.visibility).to eq('optional')
    end

    it 'defines the audience sub-field as optional string' do
      field = policy_field.field(:audience)
      expect(field.label).to eq('Audience')
      expect(field.type).to eq(:string)
      expect(field.required).to be_falsey
    end
  end

  describe 'output_schema' do
    it 'has the expected top-level fields' do
      field_ids = trigger_template.output_schema.fields.map(&:id)
      expect(field_ids).to include(
        :webhook_id, :webhook_nodeID, :account_id, :account,
        :event, :object_id, :object_nodeID,
        :person_id, :person_nodeID, :person_name,
        :payload, :delivery,
      )
    end

    it 'includes nested payload fields' do
      payload_field = trigger_template.output_schema.fields.detect { |f| f.id == :payload }
      payload_field_ids = payload_field.fields.map(&:id)
      expect(payload_field_ids).to include(
        :audit_line_id, :source, :status, :previous_status, :team, :member,
      )
    end

    it 'includes nested team fields inside payload' do
      payload_field = trigger_template.output_schema.fields.detect { |f| f.id == :payload }
      team_field = payload_field.fields.detect { |f| f.id == :team }

      expect(team_field).to be_present
      team_subfields = team_field.fields.map(&:id)
      expect(team_subfields).to include(:id, :nodeID, :name, :sourceID, :disabled, :account)
    end

    it 'generates output schema without payload_schema config' do
      expect(trigger({})).to be_valid
    end

    it 'adds configured payload_schema fields to the payload' do
      default_payload_fields = trigger({ payload_fields: [] })
                               .output_schema
                               .field(:payload)
                               .fields
                               .map(&:id)
      expect(default_payload_fields).not_to include(:callback)

      @trigger = nil # reset so new trigger will be created using :trigger_config

      payload_fields_for_trigger_config = trigger.output_schema.field(:payload).fields.map(&:id)
      expect(payload_fields_for_trigger_config).to include(:callback)
    end
  end

  describe 'policy validation' do
    shared_examples 'policy validator' do
      it 'accepts a fully populated policy with valid PEM' do
        configure_policy.call(policy_config)
        expect(validity.call).to eq(true)
      end

      it 'accepts a policy with only account_url set (OIDC mode)' do
        configure_policy.call(account_url: 'https://wdc.test.host')
        expect(validity.call).to eq(true)
      end

      it 'rejects a policy with only the algorithm set' do
        configure_policy.call(algorithm: 'ES256')
        expect(validity.call).to eq(false)
      end

      it 'rejects a policy with only the public_key_pem set' do
        configure_policy.call(public_key_pem: es256_pem[:public])
        expect(validity.call).to eq(false)
      end

      it 'rejects a policy with algorithm and invalid PEM' do
        configure_policy.call(account_url: 'https://wdc.test.host', algorithm: 'ES256', public_key_pem: 'abc')
        expect(validity.call).to eq(false)
      end
    end

    context 'on inbound connection' do
      let(:policy_under_test) { {} }
      let(:inbound_connection_config) { { policy: policy_under_test } }
      let(:configure_policy) { ->(policy) { policy_under_test.replace(policy) } }
      let(:validity) { -> { inbound_connection.valid? } }
      include_examples 'policy validator'
    end

    context 'on trigger' do
      let(:configure_policy) { ->(policy) { trigger_config[:policy] = policy } }
      let(:validity) { -> { trigger.valid? } }
      include_examples 'policy validator'
    end
  end

  describe 'parse request' do
    it 'returns error for invalid body' do
      output = post_trigger({ type: 'alert', status: 'test' })
      expect(output.keys).to contain_exactly(:error)
      expect(output[:error]).to eq("Output invalid: Field 'event' is required. Field 'delivery' is required.")
    end

    context 'webhook verification' do
      let(:webhook_body) do
        JSON.parse(<<~JSON)
          {
            "name": "Mock webhook",
            "webhook_nodeID": "mocknodeID",
            "event": "webhook.verify",
            "payload": {
              "callback": "https://wdc.test.host/webhooks/123/verify?code=abcd"
            }
          }
        JSON
      end

      it 'calls the callback URL and discards the event' do
        stub_request(:get, webhook_body.dig('payload', 'callback'))
          .with(headers: { 'User-Agent' => 'Xurrent iPaaS' })
          .to_return(body: '')

        output = post_trigger(webhook_body)
        expect(output).to eq({ result: 'Discarded' })
      end

      it 'returns error when callback fails' do
        stub_request(:get, webhook_body.dig('payload', 'callback'))
          .with(headers: { 'User-Agent' => 'Xurrent iPaaS' })
          .to_return(body: 'error', status: 500)

        output = post_trigger(webhook_body)
        expect(output).to eq({ error: "Unable to verify webhook Mock webhook (mocknodeID).\n500: error" })
      end

      describe 'with JWT policy' do
        def check_callback_url_called_and_trigger_discarded
          stub_request(:get, webhook_body.dig('payload', 'callback'))
            .with(headers: { 'User-Agent' => 'Xurrent iPaaS' })
            .to_return(body: '')

          output = post_encoded_webhook(webhook_body)
          expect(output).to eq({ result: 'Discarded' })
        end

        context 'using connection config' do
          let(:inbound_connection_config) do
            { policy: policy_config.dup }
          end

          it 'verifies JWT and calls the callback URL' do
            check_callback_url_called_and_trigger_discarded
          end

          it 'rejects calls with invalid issuer' do
            inbound_connection_config[:policy][:account_url] = 'https://another_account.test.host'
            expect_jwt_invalid_issuer_error('https://another_account.test.host')
          end
        end

        context 'using trigger config' do
          let(:trigger_config) do
            {
              policy: policy_config.dup,
              payload_schema: verification_payload_schema.dup,
            }
          end

          it 'verifies JWT and calls the callback URL' do
            check_callback_url_called_and_trigger_discarded
          end

          it 'rejects calls with invalid issuer' do
            trigger_config[:policy][:account_url] = 'https://another_account.test.host'
            expect_jwt_invalid_issuer_error('https://another_account.test.host')
          end
        end

        context 'trigger config overrides connection config' do
          let(:inbound_connection_config) do
            {
              policy: {
                account_url: 'https://wdc.test.host',
                algorithm: 'ES256',
                public_key_pem: 'abc',
              },
            }
          end

          let(:trigger_config) do
            {
              policy: policy_config,
              payload_schema: verification_payload_schema.dup,
            }
          end

          it 'uses the trigger policy over the invalid connection policy' do
            check_callback_url_called_and_trigger_discarded
          end
        end
      end
    end

    context 'standard webhook fields' do
      let(:trigger_config) do
        {
          payload_schema: [
            { id: 'pet', label: 'Pet', type: 'string' },
          ],
        }
      end

      it 'returns the parsed webhook body when valid' do
        output = post_webhook(webhook_body)
        expect(output).to eq({ delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a' }
                               .merge(webhook_body.deep_symbolize_keys))
      end

      it 'logs unexpected top-level fields and excludes them from output' do
        allow_any_instance_of(Logger).to receive(:info)
        expect_any_instance_of(Logger)
          .to receive(:info)
          .with("Ignored unexpected fields in webhook: 'pet' => 'Zuzu', 'car' => 'McQueen'")

        input_body = webhook_body
        input_body['pet'] = 'Zuzu'
        input_body['car'] = 'McQueen'
        output = post_webhook(input_body)
        expect(output).to eq({ delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a' }
                               .merge(input_body.except('pet', 'car').deep_symbolize_keys))
      end

      it 'accepts fields defined in the configured payload schema' do
        input_body = webhook_body
        input_body['payload']['pet'] = 'Zuzu'
        output = post_webhook(input_body)
        expect(output).to eq({ delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a' }
                               .merge(input_body.deep_symbolize_keys))
      end

      # raw_payload captures the full original payload for debugging when unrecognized fields are present
      it 'populates raw_payload when unexpected payload fields are present' do
        input_body = webhook_body
        expected_body = webhook_body.dup.deep_symbolize_keys
        input_body['payload']['cars'] = 'McQueen'
        output = post_webhook(input_body)
        expect(output).to eq({ delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a',
                               raw_payload: input_body['payload'].deep_symbolize_keys, }
                               .merge(expected_body))
      end

      # delivery_origin tracks re-delivered webhooks by preserving the original delivery ID
      it 'captures original delivery origin header' do
        event_headers['x_xurrent_delivery_origin'] = 'pqr'
        output = post_webhook(webhook_body)
        expect(output).to eq({ delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a',
                               delivery_origin: 'pqr', }
                               .merge(webhook_body.deep_symbolize_keys))
      end

      it 'returns error on invalid JSON' do
        output = post_webhook('{"invalid": json')
        expect(output).to eq(error: 'Unable to parse incoming webhook request')
      end

      context 'with JWT policy' do
        let(:inbound_connection_config) do
          { policy: policy_config.dup }
        end

        it 'decodes and outputs the JWT-wrapped body' do
          output = post_encoded_webhook(webhook_body)
          expect(output).to eq({ delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a' }
                                 .merge(webhook_body.deep_symbolize_keys))
        end
      end
    end
  end

  describe 'respond_with' do
    it 'returns plain text response on webhook verification' do
      expect(runbook).to receive(:trigger_output).and_return({ abc: :foo })
      default_headers = { 'default-header': 'my default value', 'header-to-remove': 'please remove me' }
      error = IPaaS::Job::DiscardTriggerEvent.new('Webhook verification handled: 123')

      result = trigger.respond_with(nil, nil, default_headers, { error: error })

      expect(result[:status]).to eq(200)
      expect(result[:headers].key?('x-job-uuid')).to eq(false)
      expect(result[:body]).to eq(error.message)
      expect(result[:headers]['default-header']).to eq('my default value')
    end

    it 'returns job_uuid for standard webhook events' do
      job = double(uuid: 2)
      expect(runbook).to receive(:trigger_output).and_return({ abc: :foo })
      default_headers = { 'default-header': 'my default value' }
      request = double

      result = trigger.respond_with(request, job, default_headers)

      expect(result[:status]).to eq(200)
      expect(result[:headers]['x-job-uuid']).to eq('2')
      expect(result[:body]).to eq('{"job_uuid":"2"}')
      expect(result[:headers]['default-header']).to eq('my default value')
    end
  end
end
