require 'spec_helper'
require_relative 'shared/app_offering_blueprint_specs'

describe 'Installation Changed Trigger', :trigger do
  let(:trigger_template_id) { '01947404-86a5-7db4-aac3-ab54573f9b6d' }

  let(:trigger_config) do
    {
      event: 'app_instance.create',
    }
  end

  let(:outbound_connection_config) do
    {
      credentials: {
        account_id: 'wdc',
        client_id: 'abc',
        client_secret: make_secret_string('def'),
      },
      environment: {
        stage: 'Demo',
        graphql_endpoint: 'https://graphql.example.com/graphql',
      },
    }
  end

  let(:es256_pem) { JwtTestPem::ES256 }

  def store_provider_webhook_policy(issuer: 'https://wdc.test.host')
    trigger.outbound_connection.store.write('provider_webhook_policy',
                                            {
                                              'algorithm' => 'ES256',
                                              'audience' => 'public',
                                              'id' => 'provider-webhook-policy-id',
                                              'issuer' => issuer,
                                              'public_key_pem' => es256_pem[:public],
                                            }.to_json)
  end

  def app_instance_webhook_id_key
    "app_instance_webhook_id-#{runbook.uuid}"
  end

  def store_app_instance_webhook
    trigger.inbound_connection.store.write(app_instance_webhook_id_key, 'app-instance-webhook-id')
  end

  def not_found_graphql_response(mutation_name)
    { errors: [{ message: 'Not Found', locations: [{ line: 1, column: 22 }], path: [mutation_name] }] }.to_json
  end

  describe 'configuration validation' do
    it 'does not require app_reference or discard_filter' do
      expect(trigger.config).to be_valid
    end

    it 'validates discard_filter' do
      trigger_config[:discard_filter] = 'ENV["a"] == "a"'
      @trigger = nil
      expect(trigger.config).not_to be_valid

      trigger_config[:discard_filter] = 'output[:discard] = input.dig(:webhook) == "a"'
      @trigger = nil
      expect(trigger.config).to be_valid
    end

    describe 'configuration_uri_template' do
      it 'does not require configuration_uri_template' do
        trigger_config[:app_reference] = 'my_app'
        @trigger = nil
        expect(trigger.config).to be_valid
      end

      it 'only allows configuration_uri_template if app_reference is set' do
        trigger_config[:app_reference] = 'my_app'
        trigger_config[:configuration_uri_template] = 'https://wdc.test.host'
        @trigger = nil
        expect(trigger.config).to be_valid

        trigger_config.delete(:app_reference)
        @trigger = nil
        expect(trigger.config).not_to be_valid
      end

      it 'checks configuration_uri_template starts with https://' do
        trigger_config[:app_reference] = 'my_app'
        trigger_config[:configuration_uri_template] = 'https://wdc.test.host'
        @trigger = nil
        expect(trigger.config).to be_valid

        trigger_config[:configuration_uri_template] = 'http://wdc.test.host'
        @trigger = nil
        expect(trigger.config).not_to be_valid
      end

      it 'allows {account} placeholder in configuration_uri_template' do
        trigger_config[:app_reference] = 'my_app'
        trigger_config[:configuration_uri_template] = 'https://wdc.test.host?a={account}'
        @trigger = nil
        expect(trigger.config).to be_valid
      end
    end
  end

  describe 'output schema' do
    it 'has nested webhook field' do
      output_schema = trigger.output_schema
      expect(output_schema.field(:webhook).type).to eq(:nested)
    end
  end

  describe 'provision' do
    before(:each) do
      stub_xurrent_oauth2_token(outbound_connection_config)
    end

    let(:endpoint) do
      outbound_connection_config[:environment][:graphql_endpoint]
    end

    let(:enable_webhook_policy_query) do
      <<~END_OF_GRAPHQL
        mutation($id: ID!) {
          webhookPolicyUpdate(
            input: {
              id: $id,
              disabled: false
            }
          ) {
            webhookPolicy { id }
            errors {
              path
              message
            }
          }
        }
      END_OF_GRAPHQL
    end

    let(:enable_webhook_policy_response) do
      {
        webhookPolicyUpdate: {
          webhookPolicy: {
            id: 'provider-webhook-policy-id',
          },
        },
      }.with_indifferent_access
    end

    let(:create_provider_webhook_policy_query) do
      <<~END_OF_GRAPHQL
        mutation {
          webhookPolicyCreate(
            input: {
              jwtAlg: "es256"
            }
          ) {
            errors {
              path
              message
            }
            webhookPolicy {
              id
              jwtAlg
              jwtAudience
              publicKeyPem
              account { url }
            }
          }
        }
      END_OF_GRAPHQL
    end

    let(:create_provider_webhook_policy_response) do
      {
        webhookPolicyCreate: {
          webhookPolicy: {
            id: 'provider-webhook-policy-id',
            jwtAlg: 'es256',
            publicKeyPem: 'public-key-pem',
            account: { id: 'wdc' },
            jwtAudience: 'public',
          },
        },
      }.with_indifferent_access
    end

    def enable_app_instance_webhook_query
      <<~END_OF_GRAPHQL
        mutation($id: ID!, $event: WebhookEvent!, $references: [String!]) {
          webhookUpdate(
            input: {
              id: $id,
              disabled: false,
              event: $event,
              appOfferingReferences: $references
            }
          ) {
            webhook { id }
            errors {
              path
              message
            }
          }
        }
      END_OF_GRAPHQL
    end

    let(:enable_app_instance_webhook_response) do
      {
        webhookUpdate: {
          webhook: {
            id: 'app-instance-webhook-id',
          },
        },
      }.with_indifferent_access
    end

    def create_app_instance_webhook_query
      <<~END_OF_GRAPHQL
        mutation($event: WebhookEvent!, $uri: String!, $name: String!, $description: String!, $policyId: ID!, $references: [String!]) {
          webhookCreate(
            input: {
              event: $event,
              uri: $uri,
              name: $name,
              description: $description,
              webhookPolicyId: $policyId,
              appOfferingReferences: $references
            }
          ) {
            errors {
              path
              message
            }
            webhook {
              id
            }
          }
        }
      END_OF_GRAPHQL
    end

    let(:create_app_instance_webhook_response) do
      {
        webhookCreate: {
          webhook: {
            id: 'app-instance-webhook-id',
          },
        },
      }.with_indifferent_access
    end

    let(:enable_provider_webhook_policy_stub) do
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(enable_webhook_policy_query, variables: { id: 'provider-webhook-policy-id' }))
        .to_return(body: { data: enable_webhook_policy_response }.to_json)
    end

    let(:create_provider_webhook_policy_stub) do
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(create_provider_webhook_policy_query))
        .to_return(body: { data: create_provider_webhook_policy_response }.to_json)
    end

    def enable_provider_app_instance_webhook_stub(event: 'app_instance.create')
      variables = {
        id: 'app-instance-webhook-id',
        event: event,
        references: [],
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(enable_app_instance_webhook_query, variables: variables))
        .to_return(body: { data: enable_app_instance_webhook_response }.to_json)
    end

    def not_found_provider_webhook_policy_stub(id: 'provider-webhook-policy-id')
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(enable_webhook_policy_query, variables: { id: id }))
        .to_return(body: not_found_graphql_response('webhookPolicyUpdate'))
    end

    def not_found_provider_app_instance_webhook_stub(id: 'app-instance-webhook-id', event: 'app_instance.create')
      variables = {
        id: id,
        event: event,
        references: [],
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(enable_app_instance_webhook_query, variables: variables))
        .to_return(body: not_found_graphql_response('webhookUpdate'))
    end

    # rubocop:disable Metrics/MethodLength
    def create_provider_app_instance_webhook_stub(event: 'app_instance.create', app_reference: nil)
      variables = {
        event: event || 'app_instance.create',
        uri: trigger.endpoint,
        name: "iPaaS - #{event}#{" [#{app_reference}]" if app_reference} - #{runbook.uuid}",
        policyId: 'provider-webhook-policy-id',
        references: app_reference ? [app_reference] : [],
        description: "DO NOT DELETE!\n\nUsed by iPaaS.",
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(create_app_instance_webhook_query, variables: variables))
        .to_return(body: { data: create_app_instance_webhook_response }.to_json)
    end
    # rubocop:enable Metrics/MethodLength

    it 'should create the provider webhook policy and app-instance webhook' do
      create_provider_webhook_policy_stub
      create_provider_app_instance_webhook_stub

      trigger.provision

      expect(create_provider_webhook_policy_stub).to have_been_requested.once
      expect(create_provider_app_instance_webhook_stub).to have_been_requested.once

      stored_provider_policy = JSON.parse(trigger.outbound_connection.store.read('provider_webhook_policy'))
      expect(stored_provider_policy).to eq(
        {
          'algorithm' => 'ES256',
          'audience' => 'public',
          'id' => 'provider-webhook-policy-id',
          'issuer' => nil,
          'public_key_pem' => 'public-key-pem',
        }
      )
      app_instance_webhook_id = trigger.inbound_connection.store.read(app_instance_webhook_id_key)
      expect(app_instance_webhook_id).to eq('app-instance-webhook-id')
    end

    it 'should enable the webhook policy if it was created before and is still available' do
      store_provider_webhook_policy

      enable_provider_webhook_policy_stub
      create_provider_app_instance_webhook_stub

      trigger.provision

      expect(create_provider_webhook_policy_stub).not_to have_been_requested
      expect(enable_provider_webhook_policy_stub).to have_been_requested.once
      expect(create_provider_app_instance_webhook_stub).to have_been_requested.once

      stored_provider_policy = JSON.parse(trigger.outbound_connection.store.read('provider_webhook_policy'))
      expect(stored_provider_policy['id']).to eq('provider-webhook-policy-id')
      app_instance_webhook_id = trigger.inbound_connection.store.read(app_instance_webhook_id_key)
      expect(app_instance_webhook_id).to eq('app-instance-webhook-id')
    end

    it 'should enable the webhook if it was created before and is still available' do
      store_provider_webhook_policy
      store_app_instance_webhook

      enable_provider_webhook_policy_stub
      enable_provider_app_instance_webhook_stub

      trigger.provision

      expect(enable_provider_webhook_policy_stub).to have_been_requested.once
      expect(create_provider_app_instance_webhook_stub).not_to have_been_requested
      expect(enable_provider_app_instance_webhook_stub).to have_been_requested.once

      stored_provider_policy = JSON.parse(trigger.outbound_connection.store.read('provider_webhook_policy'))
      expect(stored_provider_policy['id']).to eq('provider-webhook-policy-id')
      app_instance_webhook_id = trigger.inbound_connection.store.read(app_instance_webhook_id_key)
      expect(app_instance_webhook_id).to eq('app-instance-webhook-id')
    end

    context 'app_instance-updated event' do
      before(:each) do
        trigger.config[:event] = 'app_instance.update'
      end

      it 'should use the event from the config' do
        store_provider_webhook_policy

        enable_provider_webhook_policy_stub
        create_provider_app_instance_webhook_stub(event: 'app_instance.update')

        trigger.provision

        expect(create_provider_webhook_policy_stub).not_to have_been_requested
        expect(enable_provider_webhook_policy_stub).to have_been_requested.once
        expect(create_provider_app_instance_webhook_stub(event: 'app_instance.update')).to have_been_requested.once

        stored_provider_policy = JSON.parse(trigger.outbound_connection.store.read('provider_webhook_policy'))
        expect(stored_provider_policy['id']).to eq('provider-webhook-policy-id')
        app_instance_webhook_id = trigger.inbound_connection.store.read(app_instance_webhook_id_key)
        expect(app_instance_webhook_id).to eq('app-instance-webhook-id')
      end

      it 'should update the webhook event when it has changed' do
        store_provider_webhook_policy
        store_app_instance_webhook

        enable_provider_webhook_policy_stub
        enable_provider_app_instance_webhook_stub(event: 'app_instance.update')

        trigger.provision

        expect(enable_provider_webhook_policy_stub).to have_been_requested.once
        expect(create_provider_app_instance_webhook_stub).not_to have_been_requested
        expect(enable_provider_app_instance_webhook_stub(event: 'app_instance.update')).to have_been_requested.once

        stored_provider_policy = JSON.parse(trigger.outbound_connection.store.read('provider_webhook_policy'))
        expect(stored_provider_policy['id']).to eq('provider-webhook-policy-id')
        app_instance_webhook_id = trigger.inbound_connection.store.read(app_instance_webhook_id_key)
        expect(app_instance_webhook_id).to eq('app-instance-webhook-id')
      end
    end

    it 'should create a new webhook policy when the existing one no longer exists' do
      trigger.outbound_connection.store.write('provider_webhook_policy',
                                              { 'id' => 'old-policy-id', 'algorithm' => 'ES256',
                                                'audience' => 'public', 'issuer' => 'https://wdc.test.host',
                                                'public_key_pem' => es256_pem[:public], }.to_json)

      not_found_provider_webhook_policy_stub(id: 'old-policy-id')
      create_provider_webhook_policy_stub
      create_provider_app_instance_webhook_stub

      trigger.provision

      expect(create_provider_webhook_policy_stub).to have_been_requested.once
      expect(create_provider_app_instance_webhook_stub).to have_been_requested.once

      stored_provider_policy = JSON.parse(trigger.outbound_connection.store.read('provider_webhook_policy'))
      expect(stored_provider_policy['id']).to eq('provider-webhook-policy-id')
      app_instance_webhook_id = trigger.inbound_connection.store.read(app_instance_webhook_id_key)
      expect(app_instance_webhook_id).to eq('app-instance-webhook-id')
    end

    it 'should create a new app instance webhook when the existing one no longer exists' do
      store_provider_webhook_policy
      trigger.inbound_connection.store.write(app_instance_webhook_id_key, 'old-webhook-id')

      enable_provider_webhook_policy_stub
      not_found_provider_app_instance_webhook_stub(id: 'old-webhook-id')
      create_provider_app_instance_webhook_stub

      trigger.provision

      expect(enable_provider_webhook_policy_stub).to have_been_requested.once
      expect(create_provider_app_instance_webhook_stub).to have_been_requested.once

      app_instance_webhook_id = trigger.inbound_connection.store.read(app_instance_webhook_id_key)
      expect(app_instance_webhook_id).to eq('app-instance-webhook-id')
    end

    context 'blueprint' do
      before(:each) do
        create_provider_webhook_policy_stub
        create_provider_app_instance_webhook_stub(app_reference: 'yoda')
      end

      include AppOfferingBlueprintSpecs
    end
  end

  describe 'deprovision' do
    before(:each) do
      stub_xurrent_oauth2_token(outbound_connection_config)
    end

    let(:endpoint) do
      outbound_connection_config[:environment][:graphql_endpoint]
    end

    def disable_app_instance_webhook_query
      <<~END_OF_GRAPHQL
        mutation($id: ID!, $event: WebhookEvent!, $references: [String!]) {
          webhookUpdate(
            input: {
              id: $id,
              disabled: true,
              event: $event,
              appOfferingReferences: $references
            }
          ) {
            webhook { id }
            errors {
              path
              message
            }
          }
        }
      END_OF_GRAPHQL
    end

    let(:disable_app_instance_webhook_response) do
      {
        webhookUpdate: {
          webhook: {
            id: 'app-instance-webhook-id',
          },
        },
      }.with_indifferent_access
    end

    let(:disable_app_instance_webhook_stub) do
      variables = {
        id: 'app-instance-webhook-id',
        event: 'app_instance.create',
        references: [],
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(disable_app_instance_webhook_query, variables: variables))
        .to_return(body: { data: disable_app_instance_webhook_response }.to_json)
    end

    it 'should disable the webhook' do
      store_provider_webhook_policy
      store_app_instance_webhook

      disable_app_instance_webhook_stub

      trigger.deprovision

      expect(disable_app_instance_webhook_stub).to have_been_requested.once
    end

    it 'should not fail when the webhook no longer exists' do
      store_provider_webhook_policy
      store_app_instance_webhook

      variables = {
        id: 'app-instance-webhook-id',
        event: 'app_instance.create',
        references: [],
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(disable_app_instance_webhook_query, variables: variables))
        .to_return(body: not_found_graphql_response('webhookUpdate'))

      expect { trigger.deprovision }.not_to raise_error
    end
  end

  let(:event_headers) do
    {
      'accept' => '*/*',
      'content-type' => 'application/json; charset=utf-8',
      'link' => '<https://wdc.xurrent-demo.com/app_instances/1>; rel="canonical", ' \
                '<https://api.xurrent-demo.com/v1/app_instances/1>; rel="resource"',
      'user-agent' => 'xurrent/1.0 (https://developer.xurrent.com/v1/webhooks)',
      'x-xurrent-delivery' => '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a',
    }
  end

  def post_webhook(body)
    post_trigger(body, headers: event_headers)
  end

  def encoded_webhook(body)
    payload = IPaaS::Job::JWT.make_jwt_payload(issuer_claim: 'https://wdc.test.host',
                                               subject_claim: 'abc',
                                               audience_claim: 'public',
                                               data: body)
    token = IPaaS::Job::JWT.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
    { jwt: token }
  end

  def post_encoded_webhook(body)
    post_webhook(encoded_webhook(body))
  end

  describe 'parse request' do
    let(:trigger_config) do
      {
        event: 'app_instance.create',
        app_reference: 'weu_it_phone',
      }
    end

    before(:each) do
      store_provider_webhook_policy
      store_app_instance_webhook
    end

    it 'should fail when incoming body is cannot be parsed as JSON' do
      output = post_trigger(nil)
      expect(output).to eq({ error: 'Unable to parse incoming request' })
    end

    it 'should fail when incoming body does not contain a JWT token' do
      output = post_trigger({})
      expect(output).to eq({ error: 'Request does not contain jwt property' })
    end

    it 'should fail when webhook policy is not configured' do
      trigger.outbound_connection.store.delete('provider_webhook_policy')

      output = post_encoded_webhook({})
      expect(output).to eq({ error: 'Webhook policy not configured' })
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

      it 'should call external site and discard trigger event' do
        verification_stub = stub_request(:get, webhook_body.dig('payload', 'callback'))
                            .with(headers: { 'User-Agent' => 'Xurrent iPaaS' })
                            .to_return(body: '')

        output = post_encoded_webhook(webhook_body)
        expect(output).to eq({ result: 'Discarded' })
        expect(verification_stub).to have_been_requested.once
      end

      it 'should handle error from external site and discard trigger event' do
        stub_request(:get, webhook_body.dig('payload', 'callback'))
          .with(headers: { 'User-Agent' => 'Xurrent iPaaS' })
          .to_return(body: 'error', status: 500)

        output = post_encoded_webhook(webhook_body)
        expect(output).to eq({ error: "Unable to verify webhook Mock webhook (mocknodeID).\n500: error" })
      end

      it 'rejects calls with invalid signature' do
        store_provider_webhook_policy(issuer: 'https://another_account.test.host')

        output = post_encoded_webhook(webhook_body)
        expect(output).to eq(
          {
            error: <<~TEXT.strip,
              Unable to validate request: Unable to decode JWT: Invalid issuer. Expected ["https://another_account.test.host"], received https://wdc.test.host
            TEXT
          }
        )
      end
    end

    context 'parse incoming webhook' do
      let(:webhook_body) do
        JSON.parse(<<~JSON)
          {
            "name": "Mock webhook",
            "webhook_nodeID": "mocknodeID",
            "event": "app_instance.create",
            "person_id": 5689,
            "person_nodeID": "AeHV",
            "person_name": "Tom Katers",
            "payload": {
              "app_offering": {
                "reference": "weu_it_phone",
                "id": 2,
                "nodeID": "dGVzdC5ob3N0L0FwcE9mZmVyaW5nLzI",
                "updated": true
              },
              "customer_account_id": "wdc",
              "disabled": false,
              "enabled_by_customer": true,
              "suspended": false,
              "customer_representative": {
                "id": 568,
                "disabled": false,
                "name": "Tom Waters",
                "account": {
                  "id": "widget",
                  "name": "Widget International"
                },
                "sourceID": "87123",
                "nodeID": "eHVycmVudC1kZXYuY29tL1BlcnNvbi81Njg"
              }
            }
          }
        JSON
      end

      it 'should return the webhook output' do
        expect(runbook).to receive(:store_job_context_identifier).with('wdc')
        output = post_encoded_webhook(webhook_body)
        expect(output).to eq(
          {
            webhook: {
              event: 'app_instance.create',
              delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a',
              person: {
                id: 5689,
                name: 'Tom Katers',
                nodeID: 'AeHV',
              },
            },
            customer_account_id: 'wdc',
            app_reference: 'weu_it_phone',
            disabled: false,
            enabled_by_customer: true,
            suspended: false,
            customer_representative: {
              id: 568,
              disabled: false,
              name: 'Tom Waters',
              account: { id: 'widget', name: 'Widget International' },
              sourceID: '87123',
              nodeID: 'eHVycmVudC1kZXYuY29tL1BlcnNvbi81Njg',
            },
            app_offering: {
              reference: 'weu_it_phone',
              id: 2,
              nodeID: 'dGVzdC5ob3N0L0FwcE9mZmVyaW5nLzI',
              updated: true,
            },
          }
        )
      end

      it 'should include the delivery origin in the output if it was present' do
        event_headers['x-xurrent-delivery-origin'] = 'origin_delivery'

        output = post_encoded_webhook(webhook_body)
        expect(output).to eq(
          {
            webhook: {
              event: 'app_instance.create',
              delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a',
              delivery_origin: 'origin_delivery',
              person: {
                id: 5689,
                name: 'Tom Katers',
                nodeID: 'AeHV',
              },
            },
            customer_account_id: 'wdc',
            app_reference: 'weu_it_phone',
            disabled: false,
            enabled_by_customer: true,
            suspended: false,
            customer_representative: {
              id: 568,
              disabled: false,
              name: 'Tom Waters',
              account: { id: 'widget', name: 'Widget International' },
              sourceID: '87123',
              nodeID: 'eHVycmVudC1kZXYuY29tL1BlcnNvbi81Njg',
            },
            app_offering: {
              reference: 'weu_it_phone',
              id: 2,
              nodeID: 'dGVzdC5ob3N0L0FwcE9mZmVyaW5nLzI',
              updated: true,
            },
          }
        )
      end

      it 'should discard trigger event when app_reference in trigger config does not match the webhook event' do
        body = webhook_body
        body['payload']['app_offering']['reference'] = 'foo'
        output = post_encoded_webhook(body)
        expect(output).to eq(
          { result: 'Discarded' }
        )
      end

      context 'without app_reference configuration' do
        let(:trigger_config) do
          {
            event: 'app_instance.create',
          }
        end

        it 'should return the webhook output' do
          expect(runbook).to receive(:store_job_context_identifier).with('weu_it_phone@wdc')
          output = post_encoded_webhook(webhook_body)
          expect(output).to eq(
            {
              webhook: {
                event: 'app_instance.create',
                delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a',
                person: {
                  id: 5689,
                  name: 'Tom Katers',
                  nodeID: 'AeHV',
                },
              },
              customer_account_id: 'wdc',
              app_reference: 'weu_it_phone',
              disabled: false,
              enabled_by_customer: true,
              suspended: false,
              customer_representative: {
                id: 568,
                disabled: false,
                name: 'Tom Waters',
                account: { id: 'widget', name: 'Widget International' },
                sourceID: '87123',
                nodeID: 'eHVycmVudC1kZXYuY29tL1BlcnNvbi81Njg',
              },
              app_offering: {
                reference: 'weu_it_phone',
                id: 2,
                nodeID: 'dGVzdC5ob3N0L0FwcE9mZmVyaW5nLzI',
                updated: true,
              },
            }
          )
        end
      end

      describe 'discard filter' do
        it 'should discard a trigger event if filter returns true' do
          expect(runbook).to receive(:store_job_context_identifier).with('wdc')
          trigger_config[:discard_filter] = "output[:discard] = input.dig(:webhook, :person, :name) == 'Tom Katers'"
          @trigger = nil
          output = post_encoded_webhook(webhook_body)
          expect(output).to eq(
            { result: 'Discarded' }
          )
        end

        it 'should not discard a trigger event if filter returns false' do
          trigger_config[:discard_filter] = 'output[:discard] = false'
          @trigger = nil
          output = post_encoded_webhook(webhook_body)
          expect(output.key?(:webhook)).to eq(true)
          expect(output.key?(:result)).to eq(false)
        end
      end
    end
  end

  describe 'respond_with' do
    before(:each) do
      store_provider_webhook_policy
      store_app_instance_webhook
    end

    it 'gives a plain text response on webhook verification' do
      expect(runbook).to receive(:trigger_output).and_return({ abc: :foo })
      default_headers = { 'default-header': 'my default value', 'header-to-remove': 'please remove me' }

      error = IPaaS::Job::DiscardTriggerEvent.new('Webhook verification handled automatically: 123')

      request = double
      result = trigger.respond_with(request, nil, default_headers, { error: error })
      expect(result[:status]).to eq(200)
      expect(result[:headers].key?('x-job-uuid')).to eq(false)
      expect(result[:body]).to eq(error.message)
      expect(result[:headers]['default-header']).to eq('my default value')
    end

    it 'returns job_uuid for other messages' do
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
