require 'spec_helper'

describe 'Secrets Changed Trigger', :trigger do
  PUBLIC_KEY = <<~END_OF_PUBLIC_KEY.freeze
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAow4jsMIwH5686IbPMzyi
    g9QjhJ2zzslaahTb23k3dQLX6kt+pax1hoNdjUPSxKaN+UQuZkqwga0j9BTZfzmE
    VP3hYg18SrN6P0hwTrsnAQ0ZRdE+hKoviiYszqPL2cwu2nHTO3VHRwk7XJGRUUGv
    wU/X7f2Gi9wU8hh9aecsAvx+0ppb8DflDbvyN/eqTGgxREAAKcc8n9RxlorvP8Q1
    n6NT+EUM4mJNIvRUE+4GIxxvNJcAoxcpTw5x4UrlXCR2VGJyIEZrPgdquZ58MOIoQ
    tn9WS09Cl3mFn3sZrpcnhoGPKYD6RizOZN9TSWFrqLcDR06rrUhxGQFSnsXkgRe7
    hwIDAQAB
    -----END PUBLIC KEY-----
  END_OF_PUBLIC_KEY

  let(:trigger_template_id) { '01946446-ceac-7bca-84a0-0a00db534678' }

  let(:trigger_config) do
    {}
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

  def store_provider_secrets_webhook
    trigger.outbound_connection.store.write('provider_secrets_webhook_id', 'provider-secrets-webhook-id')
  end

  def not_found_graphql_response(mutation_name)
    { errors: [{ message: 'Not Found', locations: [{ line: 1, column: 22 }], path: [mutation_name] }] }.to_json
  end

  describe 'configuration validation' do
    it 'does not require discard_filter' do
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
  end

  describe 'output schema' do
    it 'has nested webhook field' do
      output_schema = trigger.output_schema
      expect(output_schema.field(:webhook).type).to eq(:nested)
    end
  end

  describe 'provision' do
    before(:each) do
      outbound_connection.config[:environment][:stage] = 'QA' # for 100% code coverage
      stub_xurrent_oauth2_token(outbound_connection.config)
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

    let(:create_provider_webhook_policy_failure_response) do
      {
        webhookPolicyCreate: {
          errors: [
            { path: 'webhookPolicy.jwtAlg', message: 'Invalid JWT algorithm: FOO' },
          ],
        },
      }.with_indifferent_access
    end

    let(:enable_secrets_webhook_query) do
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

    let(:enable_secrets_webhook_response) do
      {
        webhookUpdate: {
          webhook: {
            id: 'provider-secrets-webhook-id',
          },
        },
      }.with_indifferent_access
    end

    let(:create_secrets_webhook_query) do
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

    let(:create_secrets_webhook_response) do
      {
        webhookCreate: {
          webhook: {
            id: 'provider-secrets-webhook-id',
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

    let(:failed_create_provider_webhook_policy_stub) do
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(create_provider_webhook_policy_query))
        .to_return(body: { data: create_provider_webhook_policy_failure_response }.to_json)
    end

    def enable_provider_secrets_webhook_stub(references: [])
      variables = {
        id: 'provider-secrets-webhook-id',
        event: 'app_instance.secrets-update',
        references: references,
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(enable_secrets_webhook_query, variables: variables))
        .to_return(body: { data: enable_secrets_webhook_response }.to_json)
    end

    def not_found_provider_webhook_policy_stub(id: 'provider-webhook-policy-id')
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(enable_webhook_policy_query, variables: { id: id }))
        .to_return(body: not_found_graphql_response('webhookPolicyUpdate'))
    end

    def not_found_provider_secrets_webhook_stub(id: 'provider-secrets-webhook-id', references: [])
      variables = {
        id: id,
        event: 'app_instance.secrets-update',
        references: references,
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(enable_secrets_webhook_query, variables: variables))
        .to_return(body: not_found_graphql_response('webhookUpdate'))
    end

    # rubocop:disable Metrics/MethodLength
    def create_provider_secrets_webhook_stub(references: [], name: 'iPaaS - Secrets Changed')
      variables = {
        event: 'app_instance.secrets-update',
        uri: trigger.endpoint,
        name: name,
        policyId: 'provider-webhook-policy-id',
        references: references,
        description: "DO NOT DELETE!\n\nUsed by iPaaS.",
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(create_secrets_webhook_query, variables: variables))
        .to_return(body: { data: create_secrets_webhook_response }.to_json)
    end
    # rubocop:enable Metrics/MethodLength

    it 'should create the provider webhook policy and secrets webhook' do
      create_provider_webhook_policy_stub
      create_provider_secrets_webhook_stub

      trigger.provision

      expect(create_provider_webhook_policy_stub).to have_been_requested.once
      expect(create_provider_secrets_webhook_stub).to have_been_requested.once

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
      secrets_webhook_id = trigger.outbound_connection.store.read('provider_secrets_webhook_id')
      expect(secrets_webhook_id).to eq('provider-secrets-webhook-id')
    end

    it 'should raise an exception when the creation fails' do
      failed_create_provider_webhook_policy_stub

      msg = %(Unable to create Webhook Policy: Invalid JWT algorithm: FOO)
      expect do
        trigger.provision
      end.to raise_error(IPaaS::Job::FailJob, msg)
    end

    it 'should set the appOfferingReferences in the webhook if configured' do
      create_provider_webhook_policy_stub
      create_webhook_stub = create_provider_secrets_webhook_stub(references: %w[foo bar],
                                                                 name: 'iPaaS - Secrets Changed [foo, bar]')

      trigger.config[:app_references] = %w[foo bar]
      trigger.provision

      expect(create_webhook_stub).to have_been_requested.once
    end

    it 'should enable the webhook policy if it was created before and is still available' do
      store_provider_webhook_policy

      enable_provider_webhook_policy_stub
      create_provider_secrets_webhook_stub

      trigger.provision

      expect(create_provider_webhook_policy_stub).not_to have_been_requested
      expect(enable_provider_webhook_policy_stub).to have_been_requested.once
      expect(create_provider_secrets_webhook_stub).to have_been_requested.once

      stored_provider_policy = JSON.parse(trigger.outbound_connection.store.read('provider_webhook_policy'))
      expect(stored_provider_policy['id']).to eq('provider-webhook-policy-id')
      secrets_webhook_id = trigger.outbound_connection.store.read('provider_secrets_webhook_id')
      expect(secrets_webhook_id).to eq('provider-secrets-webhook-id')
    end

    it 'should enable the webhook if it was created before and is still available' do
      store_provider_webhook_policy
      store_provider_secrets_webhook

      enable_provider_webhook_policy_stub
      enable_provider_secrets_webhook_stub

      trigger.provision

      expect(enable_provider_webhook_policy_stub).to have_been_requested.once
      expect(create_provider_secrets_webhook_stub).not_to have_been_requested
      expect(enable_provider_secrets_webhook_stub).to have_been_requested.once

      stored_provider_policy = JSON.parse(trigger.outbound_connection.store.read('provider_webhook_policy'))
      expect(stored_provider_policy['id']).to eq('provider-webhook-policy-id')
      secrets_webhook_id = trigger.outbound_connection.store.read('provider_secrets_webhook_id')
      expect(secrets_webhook_id).to eq('provider-secrets-webhook-id')
    end

    it 'should update the appOfferingReferences when enabled' do
      store_provider_webhook_policy
      store_provider_secrets_webhook

      enable_provider_webhook_policy_stub
      enable_webhook_stub = enable_provider_secrets_webhook_stub(references: %w[foo bar])

      trigger.config[:app_references] = %w[foo bar]
      trigger.provision

      expect(enable_webhook_stub).to have_been_requested.once
    end

    it 'should create a new webhook policy when the existing one no longer exists' do
      trigger.outbound_connection.store.write('provider_webhook_policy',
                                              { 'id' => 'old-policy-id', 'algorithm' => 'ES256',
                                                'audience' => 'public', 'issuer' => 'https://wdc.test.host',
                                                'public_key_pem' => es256_pem[:public], }.to_json)

      not_found_provider_webhook_policy_stub(id: 'old-policy-id')
      create_provider_webhook_policy_stub
      create_provider_secrets_webhook_stub

      trigger.provision

      expect(create_provider_webhook_policy_stub).to have_been_requested.once
      expect(create_provider_secrets_webhook_stub).to have_been_requested.once

      stored_provider_policy = JSON.parse(trigger.outbound_connection.store.read('provider_webhook_policy'))
      expect(stored_provider_policy['id']).to eq('provider-webhook-policy-id')
      secrets_webhook_id = trigger.outbound_connection.store.read('provider_secrets_webhook_id')
      expect(secrets_webhook_id).to eq('provider-secrets-webhook-id')
    end

    it 'should create a new secrets webhook when the existing one no longer exists' do
      store_provider_webhook_policy
      trigger.outbound_connection.store.write('provider_secrets_webhook_id', 'old-secrets-webhook-id')

      enable_provider_webhook_policy_stub
      not_found_provider_secrets_webhook_stub(id: 'old-secrets-webhook-id')
      create_provider_secrets_webhook_stub

      trigger.provision

      expect(enable_provider_webhook_policy_stub).to have_been_requested.once
      expect(create_provider_secrets_webhook_stub).to have_been_requested.once

      secrets_webhook_id = trigger.outbound_connection.store.read('provider_secrets_webhook_id')
      expect(secrets_webhook_id).to eq('provider-secrets-webhook-id')
    end

    it 'should fail when the GraphQL response contains Not Found mixed with other errors' do
      store_provider_webhook_policy

      mixed_errors = {
        errors: [
          { message: 'Not Found', locations: [{ line: 1, column: 22 }], path: ['webhookPolicyUpdate'] },
          { message: 'Unauthorized', locations: [{ line: 1, column: 22 }], path: ['webhookPolicyUpdate'] },
        ],
      }.to_json
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(enable_webhook_policy_query, variables: { id: 'provider-webhook-policy-id' }))
        .to_return(body: mixed_errors)

      expect { trigger.provision }.to raise_error(
        IPaaS::Job::FailJob,
        'Unable to enable Webhook Policy: Not Found; Unauthorized'
      )
    end

    describe 'GraphQL error context' do
      # Branch coverage for the `provider_graphql` error formatter (xurrent_app_connector.rb:1254-1284)
      # plus the dynamic `context:` strings built by toggle/create webhook helpers.

      # --- A-series: formatter branches reachable through `create_provider_webhook_policy` ---
      # (`create_provider_webhook_policy` does not pass `fail_not_found: false`, so every branch is reachable.)

      it 'wraps non-200 HTTP responses with the operation context' do
        stub_request(:post, endpoint)
          .with(body: graphql_request_body(create_provider_webhook_policy_query))
          .to_return(status: 500, body: 'boom')

        expect { trigger.provision }.to raise_error(
          IPaaS::Job::FailJob,
          "Unable to create Webhook Policy: HTTP error from Xurrent GraphQL API: 500 'boom'"
        )
      end

      it 'wraps HTTP 404 with the operation context when fail_not_found is true' do
        stub_request(:post, endpoint)
          .with(body: graphql_request_body(create_provider_webhook_policy_query))
          .to_return(status: 404, body: 'nope')

        expect { trigger.provision }.to raise_error(
          IPaaS::Job::FailJob,
          "Unable to create Webhook Policy: HTTP error from Xurrent GraphQL API: 404 'nope'"
        )
      end

      it 'returns false (no raise) on HTTP 404 when fail_not_found is false' do
        store_provider_webhook_policy

        # toggle_webhook_policy passes fail_not_found: false, so an actual HTTP 404 should fall through
        # to the create-policy branch instead of raising.
        stub_request(:post, endpoint)
          .with(body: graphql_request_body(enable_webhook_policy_query,
                                           variables: { id: 'provider-webhook-policy-id' }))
          .to_return(status: 404, body: '')
        create_provider_webhook_policy_stub
        create_provider_secrets_webhook_stub

        expect { trigger.provision }.not_to raise_error
        expect(create_provider_webhook_policy_stub).to have_been_requested.once
      end

      it 'joins multiple top-level GraphQL errors with semicolons' do
        stub_request(:post, endpoint)
          .with(body: graphql_request_body(create_provider_webhook_policy_query))
          .to_return(body: { errors: [{ message: 'first thing broke' }, { message: 'second thing broke' }] }.to_json)

        expect { trigger.provision }.to raise_error(
          IPaaS::Job::FailJob,
          'Unable to create Webhook Policy: first thing broke; second thing broke'
        )
      end

      it 'wraps the empty-data fallback message with the operation context' do
        stub_request(:post, endpoint)
          .with(body: graphql_request_body(create_provider_webhook_policy_query))
          .to_return(body: { data: {} }.to_json)

        expect { trigger.provision }.to raise_error(
          IPaaS::Job::FailJob,
          'Unable to create Webhook Policy: No data from Xurrent GraphQL API'
        )
      end

      it 'joins multiple nested mutation errors with semicolons' do
        stub_request(:post, endpoint)
          .with(body: graphql_request_body(create_provider_webhook_policy_query))
          .to_return(body: { data: { webhookPolicyCreate: { errors: [
            { path: 'webhookPolicy.jwtAlg', message: 'bad alg' },
            { path: 'webhookPolicy.jwtAudience', message: 'missing field' },
          ] } } }.to_json)

        expect { trigger.provision }.to raise_error(
          IPaaS::Job::FailJob,
          'Unable to create Webhook Policy: bad alg; missing field'
        )
      end

      # --- B-series: dynamic context builders for webhook helpers ---

      it 'includes the enable-policy context in errors raised by toggle_webhook_policy(true)' do
        store_provider_webhook_policy
        stub_request(:post, endpoint)
          .with(body: graphql_request_body(enable_webhook_policy_query,
                                           variables: { id: 'provider-webhook-policy-id' }))
          .to_return(body: { data: { webhookPolicyUpdate: {
            errors: [{ path: 'webhookPolicy', message: 'permission denied' }],
          } } }.to_json)

        expect { trigger.provision }.to raise_error(
          IPaaS::Job::FailJob,
          'Unable to enable Webhook Policy: permission denied'
        )
      end

      it 'includes the enable-webhook context in errors raised by toggle_webhook(true)' do
        store_provider_webhook_policy
        store_provider_secrets_webhook
        enable_provider_webhook_policy_stub
        stub_request(:post, endpoint)
          .with(body: graphql_request_body(enable_secrets_webhook_query,
                                           variables: {
                                             id: 'provider-secrets-webhook-id',
                                             event: 'app_instance.secrets-update',
                                             references: [],
                                           }))
          .to_return(body: { data: { webhookUpdate: {
            errors: [{ path: 'webhook', message: 'invalid uri' }],
          } } }.to_json)

        expect { trigger.provision }.to raise_error(
          IPaaS::Job::FailJob,
          'Unable to enable Webhook: invalid uri'
        )
      end

      it 'interpolates the webhook name into the create-webhook context' do
        # create_provider_webhook builds context "create Webhook '#{webhook_name}'"; the secrets webhook
        # uses the name 'iPaaS - Secrets Changed' (see create_provider_secrets_webhook_stub).
        create_provider_webhook_policy_stub
        variables = {
          event: 'app_instance.secrets-update',
          uri: trigger.endpoint,
          name: 'iPaaS - Secrets Changed',
          policyId: 'provider-webhook-policy-id',
          references: [],
          description: "DO NOT DELETE!\n\nUsed by iPaaS.",
        }
        stub_request(:post, endpoint)
          .with(body: graphql_request_body(create_secrets_webhook_query, variables: variables))
          .to_return(body: { data: { webhookCreate: {
            errors: [{ path: 'webhook.uri', message: 'uri taken' }],
          } } }.to_json)

        expect { trigger.provision }.to raise_error(
          IPaaS::Job::FailJob,
          "Unable to create Webhook 'iPaaS - Secrets Changed': uri taken"
        )
      end
    end
  end

  describe 'deprovision' do
    before(:each) do
      stub_xurrent_oauth2_token(outbound_connection_config)
    end

    let(:endpoint) do
      outbound_connection_config[:environment][:graphql_endpoint]
    end

    let(:disable_secrets_webhook_query) do
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

    let(:disable_secrets_webhook_response) do
      {
        webhookUpdate: {
          webhook: {
            id: 'provider-secrets-webhook-id',
          },
        },
      }.with_indifferent_access
    end

    let(:disable_provider_secrets_webhook_stub) do
      variables = {
        id: 'provider-secrets-webhook-id',
        event: 'app_instance.secrets-update',
        references: [],
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(disable_secrets_webhook_query, variables: variables))
        .to_return(body: { data: disable_secrets_webhook_response }.to_json)
    end

    it 'should disable the webhook' do
      store_provider_webhook_policy
      store_provider_secrets_webhook

      disable_provider_secrets_webhook_stub

      trigger.deprovision

      expect(disable_provider_secrets_webhook_stub).to have_been_requested.once
    end

    it 'should not fail when the webhook no longer exists' do
      store_provider_webhook_policy
      store_provider_secrets_webhook

      variables = {
        id: 'provider-secrets-webhook-id',
        event: 'app_instance.secrets-update',
        references: [],
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(disable_secrets_webhook_query, variables: variables))
        .to_return(body: not_found_graphql_response('webhookUpdate'))

      expect { trigger.deprovision }.not_to raise_error
    end

    it 'includes the disable-webhook context when toggle_webhook(false) raises' do
      store_provider_webhook_policy
      store_provider_secrets_webhook

      variables = {
        id: 'provider-secrets-webhook-id',
        event: 'app_instance.secrets-update',
        references: [],
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(disable_secrets_webhook_query, variables: variables))
        .to_return(body: { data: { webhookUpdate: {
          errors: [{ path: 'webhook', message: 'broken' }],
        } } }.to_json)

      expect { trigger.deprovision }.to raise_error(
        IPaaS::Job::FailJob,
        'Unable to disable Webhook: broken'
      )
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
    before(:each) do
      store_provider_webhook_policy
      store_provider_secrets_webhook
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

    it 'extracts job context identifier' do
      expect(runbook).to receive(:store_job_context_identifier).with('weu_it_phone@wdc')
      post_encoded_webhook(JSON.parse(<<~JSON))
        {
          "name": "Mock webhook",
          "webhook_nodeID": "mocknodeID",
          "event": "app_instance.secrets-update",
          "person_id": 123,
          "person_nodeID": "XYZ",
          "person_name": "Tom Katers",
          "payload": {
            "app_offering": {
              "reference": "weu_it_phone",
              "id": 2,
              "nodeID": "dGVzdC5ob3N0L0FwcE9mZmVyaW5nLzI"
            },
            "customer_account_id": "wdc"
          }
        }
      JSON
    end

    context 'with exactly one app_reference configured' do
      let(:trigger_config) do
        {
          app_references: ['weu_it_phone'],
        }
      end

      it 'extracts job context identifier' do
        expect(runbook).to receive(:store_job_context_identifier).with('wdc')
        post_encoded_webhook(JSON.parse(<<~JSON))
          {
            "name": "Mock webhook",
            "webhook_nodeID": "mocknodeID",
            "event": "app_instance.secrets-update",
            "person_id": 123,
            "person_nodeID": "XYZ",
            "person_name": "Tom Katers",
            "payload": {
              "app_offering": {
                "reference": "weu_it_phone",
                "id": 2,
                "nodeID": "dGVzdC5ob3N0L0FwcE9mZmVyaW5nLzI"
              },
              "customer_account_id": "wdc"
            }
          }
        JSON
      end
    end

    context 'customer client credentials token' do
      let(:webhook_body) do
        JSON.parse(<<~JSON)
          {
            "name": "Mock webhook",
            "webhook_nodeID": "mocknodeID",
            "event": "app_instance.secrets-update",
            "person_id": 123,
            "person_nodeID": "XYZ",
            "person_name": "Tom Katers",
            "payload": {
              "app_offering": {
                "reference": "weu_it_phone",
                "id": 2,
                "nodeID": "dGVzdC5ob3N0L0FwcE9mZmVyaW5nLzI"
              },
              "customer_account_id": "wdc",
              "application": {
                "nodeID": "dGVzdC5ob3N0L09hdXRoQXBwbGljYXRpb24vMQ",
                "client_id": "H3lzcY6Zgi80BbjIUbtyuzcI5j3wKmGavfDcOiS6vNiPbuxY",
                "client_secret": "7IocHHKQKXiGIyLGXZlwmYbAaBKg243AwbdsOV87gF0cvlO8W9657eNmU8btkTju"
              }
            }
          }
        JSON
      end

      it 'should extract the customer client credentials token' do
        output = post_encoded_webhook(webhook_body)
        expect(output)
          .to eq({
            customer_account_id: 'wdc',
            app_reference: 'weu_it_phone',
            webhook: {
              delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a',
              event: 'app_instance.secrets-update',
              person: {
                id: 123,
                name: 'Tom Katers',
                nodeID: 'XYZ',
              },
            },
          })

        customer_key = 'customer_client_credentials_token/wdc/weu_it_phone'
        client_credentials_token = JSON.parse(trigger.outbound_connection.store.read(customer_key))
        expect(client_credentials_token['oauth_application_nodeID']).to eq('dGVzdC5ob3N0L09hdXRoQXBwbGljYXRpb24vMQ')
        expect(client_credentials_token['client_id']).to eq('H3lzcY6Zgi80BbjIUbtyuzcI5j3wKmGavfDcOiS6vNiPbuxY')
        client_secret = '7IocHHKQKXiGIyLGXZlwmYbAaBKg243AwbdsOV87gF0cvlO8W9657eNmU8btkTju'
        encrypted_secret = trigger.new_secret_string(client_credentials_token['client_secret'])
        expect(trigger.decrypt_secret_string(encrypted_secret)).to eq(client_secret)
      end
    end

    context 'customer authorization code token' do
      let(:webhook_body) do
        JSON.parse(<<~JSON)
          {
            "name": "Mock webhook",
            "webhook_nodeID": "mocknodeID",
            "event": "app_instance.secrets-update",
            "person_id": 123,
            "person_nodeID": "XYZ",
            "person_name": "Tom Katers",
            "payload": {
              "app_offering": {
                "reference": "weu_it_phone",
                "id": 2,
                "nodeID": "dGVzdC5ob3N0L0FwcE9mZmVyaW5nLzI"
              },
              "customer_account_id": "wdc",
              "authorization_application": {
                "nodeID": "dGVzdC5ob3N0L09hdXRoQXBwbGljYXRpb24vMQ",
                "client_id": "H3lzcY6Zgi80BbjIUbtyuzcI5j3wKmGavfDcOiS6vNiPbuxY",
                "client_secret": "7IocHHKQKXiGIyLGXZlwmYbAaBKg243AwbdsOV87gF0cvlO8W9657eNmU8btkTju"
              }
            }
          }
        JSON
      end

      it 'should extract the customer authorization code token' do
        output = post_encoded_webhook(webhook_body)
        expect(output)
          .to eq({
            customer_account_id: 'wdc',
            app_reference: 'weu_it_phone',
            webhook: {
              delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a',
              event: 'app_instance.secrets-update',
              person: {
                id: 123,
                name: 'Tom Katers',
                nodeID: 'XYZ',
              },
            },
          })

        customer_key = 'customer_authorization_code_token/wdc/weu_it_phone'
        client_credentials_token = JSON.parse(trigger.outbound_connection.store.read(customer_key))
        expect(client_credentials_token['oauth_application_nodeID']).to eq('dGVzdC5ob3N0L09hdXRoQXBwbGljYXRpb24vMQ')
        expect(client_credentials_token['client_id']).to eq('H3lzcY6Zgi80BbjIUbtyuzcI5j3wKmGavfDcOiS6vNiPbuxY')
        client_secret = '7IocHHKQKXiGIyLGXZlwmYbAaBKg243AwbdsOV87gF0cvlO8W9657eNmU8btkTju'
        encrypted_secret = trigger.new_secret_string(client_credentials_token['client_secret'])
        expect(trigger.decrypt_secret_string(encrypted_secret)).to eq(client_secret)
      end
    end

    context 'customer webhook policy' do
      context 'default issuer' do
        let(:webhook_body) do
          JSON.parse(<<~JSON)
            {
              "name": "Mock webhook",
              "webhook_nodeID": "mocknodeID",
              "event": "app_instance.secrets-update",
              "person_id": 123,
              "person_nodeID": "XYZ",
              "person_name": "Tom Katers",
              "payload": {
                "app_offering": {
                  "reference": "weu_it_phone",
                  "id": 2,
                  "nodeID": "dGVzdC5ob3N0L0FwcE9mZmVyaW5nLzI"
                },
                "customer_account_id": "wdc",
                "policy": {
                  "nodeID": "dGVzdC5ob3N0L1dlYmhvb2tQb2xpY3kvMQ",
                  "audience": null,
                  "algorithm": "RS256",
                  "public_key": "#{PUBLIC_KEY.gsub("\n", '\\n')}"
                }
              }
            }
          JSON
        end

        it 'should extract the customer webhook policy' do
          output = post_encoded_webhook(webhook_body)
          expect(output)
            .to eq({
              customer_account_id: 'wdc',
              app_reference: 'weu_it_phone',
              webhook: {
                delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a',
                event: 'app_instance.secrets-update',
                person: {
                  id: 123,
                  name: 'Tom Katers',
                  nodeID: 'XYZ',
                },
              },
            })

          customer_key = 'customer_webhook_policy/wdc/weu_it_phone'
          client_credentials_token = JSON.parse(trigger.outbound_connection.store.read(customer_key))
          expect(client_credentials_token).to eq(
            {
              'id' => 'dGVzdC5ob3N0L1dlYmhvb2tQb2xpY3kvMQ',
              'algorithm' => 'RS256',
              'public_key_pem' => PUBLIC_KEY,
              'issuer' => 'https://wdc.xurrent-demo.com',
              'audience' => nil,
            }
          )
        end
      end

      context 'custom issuer' do
        let(:webhook_body) do
          JSON.parse(<<~JSON)
            {
              "name": "Mock webhook",
              "webhook_nodeID": "mocknodeID",
              "event": "app_instance.secrets-update",
              "person_id": 123,
              "person_nodeID": "XYZ",
              "person_name": "Tom Katers",
              "payload": {
                "app_offering": {
                  "reference": "weu_it_phone",
                  "id": 2,
                  "nodeID": "dGVzdC5ob3N0L0FwcE9mZmVyaW5nLzI"
                },
                "customer_account_id": "wdc",
                "policy": {
                  "nodeID": "dGVzdC5ob3N0L1dlYmhvb2tQb2xpY3kvMQ",
                  "audience": null,
                  "algorithm": "RS256",
                  "issuer": "https://my-custom-desk.com",
                  "public_key": "#{PUBLIC_KEY.gsub("\n", '\\n')}"
                }
              }
            }
          JSON
        end

        it 'should extract the customer webhook policy' do
          output = post_encoded_webhook(webhook_body)
          expect(output)
            .to eq({
              customer_account_id: 'wdc',
              app_reference: 'weu_it_phone',
              webhook: {
                delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a',
                event: 'app_instance.secrets-update',
                person: {
                  id: 123,
                  name: 'Tom Katers',
                  nodeID: 'XYZ',
                },
              },
            })

          customer_key = 'customer_webhook_policy/wdc/weu_it_phone'
          client_credentials_token = JSON.parse(trigger.outbound_connection.store.read(customer_key))
          expect(client_credentials_token).to eq(
            {
              'id' => 'dGVzdC5ob3N0L1dlYmhvb2tQb2xpY3kvMQ',
              'algorithm' => 'RS256',
              'public_key_pem' => PUBLIC_KEY,
              'issuer' => 'https://my-custom-desk.com',
              'audience' => nil,
            }
          )
        end
      end
    end

    context 'customer secrets' do
      SECRETS_WEBHOOK_JSON = <<~END_OF_JSON.freeze
        {
          "name": "Mock webhook",
          "webhook_nodeID": "mocknodeID",
          "event": "app_instance.secrets-update",
          "person_id": 123,
          "person_nodeID": "CDE",
          "person_name": "Tom Waters",
          "payload": {
            "app_offering": {
              "reference": "weu_it_phone",
              "id": 2,
              "nodeID": "dGVzdC5ob3N0L0FwcE9mZmVyaW5nLzI"
            },
            "customer_account_id": "wdc",
            "secrets": %<secrets>s
          }
        }
      END_OF_JSON

      def secrets_webhook_body(secrets)
        JSON.parse(format(SECRETS_WEBHOOK_JSON, secrets: secrets.to_json))
      end

      it 'should extract the customer secrets and merge it with the existing secrets' do
        output = post_encoded_webhook(secrets_webhook_body({ password: 'foo' }))
        expect(output)
          .to eq({
            customer_account_id: 'wdc',
            app_reference: 'weu_it_phone',
            webhook: {
              delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a',
              event: 'app_instance.secrets-update',
              person: {
                id: 123,
                name: 'Tom Waters',
                nodeID: 'CDE',
              },
            },
          })

        customer_secrets_key = 'customer_secrets/wdc/weu_it_phone'
        customer_secrets = JSON.parse(trigger.outbound_connection.store.read(customer_secrets_key))

        encrypted_password = trigger.new_secret_string(customer_secrets['password'])
        expect(trigger.decrypt_secret_string(encrypted_password)).to eq('foo')

        post_encoded_webhook(secrets_webhook_body({ secret: 'bar' }))
        customer_secrets = JSON.parse(trigger.outbound_connection.store.read(customer_secrets_key))

        encrypted_password = trigger.new_secret_string(customer_secrets['password'])
        expect(trigger.decrypt_secret_string(encrypted_password)).to eq('foo')

        encrypted_secret = trigger.new_secret_string(customer_secrets['secret'])
        expect(trigger.decrypt_secret_string(encrypted_secret)).to eq('bar')
      end
    end
  end

  describe 'respond_with' do
    before(:each) do
      store_provider_webhook_policy
      store_provider_secrets_webhook
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
