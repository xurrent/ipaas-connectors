require 'spec_helper'
require_relative 'shared/app_offering_blueprint_specs'

describe 'Automation Webhook Trigger', :trigger do
  let(:trigger_template_id) { '01946f8e-ade1-7251-8638-1834d7b8382c' }

  let(:trigger_config) do
    {
      app_reference: 'weu_it_phone',
      payload_schema: [
        { id: 'foo', label: 'Foo', type: 'string' },
        { id: 'bar', label: 'Bar', type: 'integer' },
      ],
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

  def store_customer_webhook_policy(issuer: 'https://wdc.test.host')
    customer_policy = {
      'id' => 'dGVzdC5ob3N0L1dlYmhvb2tQb2xpY3kvMQ',
      'algorithm' => 'ES256',
      'public_key_pem' => es256_pem[:public],
      'issuer' => issuer,
      'audience' => nil,
    }
    trigger.outbound_connection.store.write('customer_webhook_policy/wdc/weu_it_phone', customer_policy.to_json)
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
      stub_xurrent_oauth2_token(outbound_connection_config)
    end

    let(:endpoint) do
      outbound_connection_config[:environment][:graphql_endpoint]
    end

    let(:find_app_offering_response) do
      {
        appOfferings: {
          nodes: [
            { id: 'weu_it_phone' },
          ],
        },
      }.with_indifferent_access
    end

    let(:update_app_offering_webhook_uri_query) do
      <<~END_OF_GRAPHQL
        mutation($input: AppOfferingUpdateInput!) {
          appOfferingUpdate(input: $input) {
            appOffering { id }
            errors {
              path
              message
            }
          }
        }
      END_OF_GRAPHQL
    end

    let(:update_weu_it_phone_app_offering_webhook_uri_response) do
      {
        appOfferingUpdate: {
          appOffering: {
            id: 'weu_it_phone',
          },
        },
      }.with_indifferent_access
    end

    let(:find_app_offering_query) do
      <<~END_OF_GRAPHQL
        query($reference: String, $published: Boolean) {
          appOfferings(first: 1, filter: { published: $published, reference: { values: [$reference] } } ) {
            nodes {
             id
            }
          }
        }
      END_OF_GRAPHQL
    end

    let(:find_weu_it_phone_app_offering_id_stub) do
      variables = { reference: 'weu_it_phone', published: false }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(find_app_offering_query, variables: variables))
        .to_return(body: { data: find_app_offering_response }.to_json)
    end

    let(:update_weu_it_phone_app_offering_webhook_uri_stub) do
      variables = {
        input: {
          id: 'weu_it_phone',
          webhookUriTemplate: "#{trigger.endpoint}?customer_account_id={account}",
        },
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(update_app_offering_webhook_uri_query, variables: variables))
        .to_return(body: { data: update_weu_it_phone_app_offering_webhook_uri_response }.to_json)
    end

    it 'should update the app offering url' do
      find_weu_it_phone_app_offering_id_stub
      update_weu_it_phone_app_offering_webhook_uri_stub

      trigger.provision

      expect(find_weu_it_phone_app_offering_id_stub).to have_been_requested.once
      expect(update_weu_it_phone_app_offering_webhook_uri_stub).to have_been_requested.once
    end

    context 'blueprint' do
      include AppOfferingBlueprintSpecs
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
    post_trigger(body, headers: event_headers, params: { customer_account_id: 'wdc' })
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
      store_customer_webhook_policy
    end

    it 'fails when customer_account_id parameter is not provided' do
      output = post_trigger({ jwt: 'irrelevant' }, headers: event_headers, params: {})
      expect(output).to eq({ error: 'Missing customer_account_id parameter' })
    end

    it 'fails when customer_account_id parameter is blank' do
      output = post_trigger({ jwt: 'irrelevant' }, headers: event_headers, params: { customer_account_id: '' })
      expect(output).to eq({ error: 'Missing customer_account_id parameter' })
    end

    it 'should fail when incoming body is cannot be parsed as JSON' do
      output = post_trigger(nil, params: { customer_account_id: 'wdc' })
      expect(output).to eq({ error: 'Unable to parse incoming request' })
    end

    it 'should fail when incoming body does not contain a JWT token' do
      output = post_trigger({}, params: { customer_account_id: 'wdc' })
      expect(output).to eq({ error: 'Request does not contain jwt property' })
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
        store_customer_webhook_policy(issuer: 'https://another_account.test.host')

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
            "person_id": 123,
            "person_nodeID": "ABC",
            "person_name": "Tom Katers",
            "payload": {
              "app_offering": {
                "reference": "weu_it_phone",
                "id": 2,
                "nodeID": "dGVzdC5ob3N0L0FwcE9mZmVyaW5nLzI",
                "updated": true
              },
              "customer_account_id": "wdc",
              "foo": "data from the AR",
              "bar": 42
            }
          }
        JSON
      end

      it 'should return the webhook output' do
        expect(runbook).to receive(:store_job_context_identifier).with('wdc')
        output = post_encoded_webhook(webhook_body)
        expect(output).to eq(
          {
            customer_account_id: 'wdc',
            app_reference: 'weu_it_phone',
            payload: {
              foo: 'data from the AR',
              bar: 42,
            },
            webhook: {
              delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a',
              event: 'app_instance.create',
              person: {
                id: 123,
                name: 'Tom Katers',
                nodeID: 'ABC',
              },
            },
          }
        )
      end
    end
  end

  describe 'respond_with' do
    before(:each) do
      store_customer_webhook_policy
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
