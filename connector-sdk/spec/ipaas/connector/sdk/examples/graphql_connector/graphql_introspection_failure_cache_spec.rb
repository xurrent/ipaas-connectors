require 'spec_helper'
require 'digest'

describe 'GraphQL Introspection Failure Cache', :action do
  include GraphqlIntrospectionHelper

  let(:action_template_id) { 'eb80d943-e0a3-44c7-97aa-640e243f9320' }
  let(:outbound_connection_config) { graphql_connector_outbound_connection_config }
  let(:graphql_endpoint) { graphql_connector_endpoint }
  let(:action_input) { { object: 'users' } }

  # Captures the exact key the connector writes to the negative cache during a
  # run, so key assertions exercise production code instead of a spec-side mirror.
  def capture_written_failure_key
    captured = nil
    allow(@action).to receive(:cache_write).and_wrap_original do |orig, key, *args|
      captured ||= key if key.to_s.include?('introspection_failure_')
      orig.call(key, *args)
    end
    attempt_run
    captured
  end

  def introspection_request_count
    WebMock::RequestRegistry.instance.requested_signatures.hash
                            .select { |signature, _count| signature.body.to_s.include?('__schema') }
                            .values.sum
  end

  def stub_introspection_failure(status:, body: 'failure', endpoint: graphql_endpoint)
    stub_request(:post, endpoint)
      .with { |req| req.body.include?('__schema') }
      .to_return(status: status, body: body, headers: { 'content-type' => 'application/json' })
  end

  # The introspection failure surfaces as a FailJob out of #run; the negative
  # cache behaviour under test is the number of HTTP attempts, not the raise.
  def attempt_run
    @action.run
  rescue IPaaS::Job::FailJob
    nil
  end

  before(:each) do
    # Build with a successful introspection (and a permissive OAuth token endpoint
    # for the client-credential examples) so the action resolves cleanly, then
    # clear the positive cache so each example controls the introspection outcome.
    stub_request(:post, /oauth\./).to_return(status: 200, body: { access_token: 'tok', token_type: 'bearer' }.to_json,
                                             headers: { 'content-type' => 'application/json' })
    stub_graphql_connector_introspection
    @action = action(action_input)
    @action.cache_clear('gql_schema')
    @action.cache_clear('_schema_present')
    WebMock.reset!
  end

  describe 'negative cache hit' do
    before(:each) do
      stub_introspection_failure(status: 400, body: 'Bad request')
    end

    it 'caches a failed introspection so a later load is served without re-attempting' do
      attempt_run # first load hits the API, gets 400, and our code caches the failure
      expect(introspection_request_count).to eq(1)

      WebMock.reset!
      stub_introspection_failure(status: 400, body: 'Bad request')

      expect { @action.run }.to raise_error(IPaaS::Job::FailJob, /Bad request/)
      expect(introspection_request_count).to eq(0) # served from the cache our code wrote
    end
  end

  describe 'negative cache miss' do
    it 'attempts introspection once when no failure is cached' do
      stub_introspection_failure(status: 400, body: 'Bad request')

      expect { @action.run }.to raise_error(IPaaS::Job::FailJob, /400/)
      expect(introspection_request_count).to eq(1)
    end
  end

  describe 'authorization element change re-attempts' do
    # Each lambda mutates one authorization determinant after a prior cached
    # failure; the changed key must miss the cache and re-attempt exactly once.
    # Changes that keep the same endpoint reuse the existing stub; those needing
    # a different endpoint get their own example below.
    {
      'bearer token' => ->(act) do
        act.outbound_connection.config[:bearer_token][:token] = act.make_secret_string('new-token')
      end,
    }.each do |element, change|
      it "re-attempts when the #{element} changes" do
        stub_introspection_failure(status: 400, body: 'Bad request')
        attempt_run # first load caches the failure under the current authorization key
        expect(introspection_request_count).to eq(1)

        WebMock.reset!
        stub_introspection_failure(status: 400, body: 'Bad request')
        change.call(@action)

        attempt_run
        expect(introspection_request_count).to eq(1)
      end
    end

    it 're-attempts against the new endpoint when the graphql endpoint changes' do
      stub_introspection_failure(status: 400, body: 'Bad request')
      attempt_run # first load caches the failure under the current endpoint key
      expect(introspection_request_count).to eq(1)

      WebMock.reset!
      new_endpoint = 'https://api.other.example.com/graphql'
      @action.outbound_connection.config[:graphql_endpoint] = new_endpoint
      stub_introspection_failure(status: 400, body: 'Bad request', endpoint: new_endpoint)

      attempt_run
      expect(introspection_request_count).to eq(1)
    end

    context 'with an api-key-header connection' do
      let(:outbound_connection_config) do
        {
          graphql_endpoint: graphql_endpoint,
          auth_type: 'api_key_header',
          api_key_header: { header_name: 'X-API-Key', header_value: make_secret_string('secret-key') },
          schema_source: 'introspection',
        }
      end

      it 're-attempts when the api-key header value changes' do
        stub_introspection_failure(status: 400, body: 'Bad request')
        attempt_run # first load caches the failure under the current header-value key
        expect(introspection_request_count).to eq(1)

        WebMock.reset!
        stub_introspection_failure(status: 400, body: 'Bad request')
        @action.outbound_connection.config[:api_key_header][:header_value] = @action.make_secret_string('rotated-key')

        attempt_run
        expect(introspection_request_count).to eq(1)
      end
    end
  end

  describe 'cache key composition' do
    before(:each) do
      stub_introspection_failure(status: 400, body: 'Bad request')
    end

    # Element participation in the key is proven behaviourally by the
    # "authorization element change" examples; here we only guard that the key
    # the connector writes never contains a plaintext secret.
    it 'never embeds the bearer token in the key the connector writes' do
      key = capture_written_failure_key
      expect(key).to start_with('introspection_failure_')
      expect(key).not_to include('test-token')
    end

    context 'with an api-key-header connection' do
      let(:outbound_connection_config) do
        {
          graphql_endpoint: graphql_endpoint,
          auth_type: 'api_key_header',
          api_key_header: { header_name: 'X-API-Key', header_value: make_secret_string('secret-key') },
          schema_source: 'introspection',
        }
      end

      it 'never embeds the api-key header value in the key the connector writes' do
        key = capture_written_failure_key
        expect(key).to start_with('introspection_failure_')
        expect(key).not_to include('secret-key')
      end
    end
  end

  describe 'refresh schema' do
    let(:action_input) { { object: 'users', refresh_schema: true } }

    it 'clears the negative cache so a prior failure does not suppress re-attempt' do
      stub_introspection_failure(status: 400, body: 'Bad request')
      attempt_run # first load caches the failure
      expect(introspection_request_count).to eq(1)

      WebMock.reset!
      stub_introspection_failure(status: 400, body: 'Bad request')

      # refresh_schema clears the negative cache, so the second load re-attempts
      # (it is NOT served from the cached failure, unlike the 'negative cache hit' case)
      attempt_run
      expect(introspection_request_count).to eq(1)
    end
  end

  describe 'transient failure TTL' do
    before(:each) do
      stub_introspection_failure(status: 500, body: 'Internal Server Error')
      attempt_run # a 5xx is cached with the short transient TTL by our code
      WebMock.reset!
      stub_introspection_failure(status: 500, body: 'Internal Server Error')
    end

    it 'serves the cached failure shortly before the transient TTL expires' do
      Timecop.travel(Time.now.utc + 20.seconds) do
        attempt_run
        expect(introspection_request_count).to eq(0)
      end
    end

    it 're-attempts once the short transient TTL has expired' do
      Timecop.travel(Time.now.utc + 31.seconds) do
        attempt_run
        expect(introspection_request_count).to eq(1)
      end
    end
  end

  describe 'deterministic failure TTL' do
    before(:each) do
      stub_introspection_failure(status: 400, body: 'Bad request')
      attempt_run # a 4xx is cached with the long deterministic TTL by our code
      WebMock.reset!
      stub_introspection_failure(status: 400, body: 'Bad request')
    end

    it 'still serves the cached failure well past the transient TTL but before the deterministic one' do
      Timecop.travel(Time.now.utc + 300.seconds) do
        attempt_run
        expect(introspection_request_count).to eq(0)
      end
    end

    it 're-attempts once the deterministic TTL has expired' do
      Timecop.travel(Time.now.utc + 601.seconds) do
        attempt_run
        expect(introspection_request_count).to eq(1)
      end
    end
  end

  describe 'successful introspection (positive contrast)' do
    it 'does not raise and makes a single introspection attempt when nothing is cached' do
      stub_graphql_connector_introspection
      stub_graphql_connector_query(/users/, {
        'users' => { 'nodes' => [], 'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil }, 'totalCount' => 0 },
      })

      expect { @action.run }.not_to raise_error
      expect(introspection_request_count).to eq(1)
    end
  end

  describe 'manual schema source (not blocked by a cached introspection failure)' do
    it 'serves the pasted schema with no introspection call even after a prior failure under the same auth key' do
      # First, fail introspection so our code caches a failure under this
      # connection's authorization key (the key does not depend on schema_source).
      stub_introspection_failure(status: 400, body: 'Bad request')
      attempt_run
      expect(introspection_request_count).to eq(1)

      WebMock.reset!

      # Switch the same connection to manual and paste the schema. The cached
      # failure shares this connection's auth key, yet manual mode must not be
      # blocked by it and must make no introspection HTTP call.
      @action.outbound_connection.config[:schema_source] = 'manual'
      @action.outbound_connection.config[:full_schema] = { __schema: graphql_connector_introspection_schema }.to_json
      stub_graphql_connector_query(/users/, {
        'users' => { 'nodes' => [], 'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil }, 'totalCount' => 0 },
      })

      expect { @action.run }.not_to raise_error
      expect(introspection_request_count).to eq(0) # manual mode makes no introspection call
    end
  end

  describe 'OAuth client-credential token failure' do
    let(:oauth_endpoint) { 'https://oauth.example.com/token' }
    let(:outbound_connection_config) do
      {
        graphql_endpoint: graphql_endpoint,
        auth_type: 'oauth2',
        oauth2: {
          token_endpoint: oauth_endpoint,
          client_id: 'client-1',
          client_secret: make_secret_string('secret-1'),
        },
        schema_source: 'introspection',
      }
    end

    def stub_oauth_failure(endpoint: oauth_endpoint)
      stub_request(:post, endpoint).to_return(
        status: 401,
        body: { error: 'invalid_client' }.to_json,
        headers: { 'content-type' => 'application/json' },
      )
    end

    def outbound_attempt_count
      WebMock::RequestRegistry.instance.requested_signatures.hash.values.sum
    end

    before(:each) do
      stub_oauth_failure
      stub_graphql_connector_introspection
    end

    it 'negative-caches the auth failure so a second load makes zero outbound attempts' do
      attempt_run # first load makes exactly the one OAuth token call, which fails and is cached
      expect(outbound_attempt_count).to eq(1)
      expect(introspection_request_count).to eq(0)

      WebMock.reset!
      stub_oauth_failure
      stub_graphql_connector_introspection

      attempt_run # second load must be served from the cache our code wrote, with no outbound calls
      expect(outbound_attempt_count).to eq(0)

      @action.outbound_connection.config[:oauth2][:client_secret] = @action.make_secret_string('secret-2')

      attempt_run # a different secret yields a different key, so it re-attempts with one fresh token call
      expect(outbound_attempt_count).to eq(1)

      Timecop.travel(Time.now.utc + 300.seconds) do
        attempt_run # within the 10-min TTL => served from cache
        expect(outbound_attempt_count).to eq(1)
      end
      Timecop.travel(Time.now.utc + 601.seconds) do
        attempt_run # deterministic TTL expired => re-attempts
        expect(outbound_attempt_count).to eq(2)
      end

      expect(introspection_request_count).to eq(0)
    end

    # Each authorization element, changed after a prior cached failure, must yield
    # a different key and re-attempt (one fresh OAuth token call).
    {
      'client id' => ->(act) { act.outbound_connection.config[:oauth2][:client_id] = 'corrected-client' },
    }.each do |element, change|
      it "re-attempts when the #{element} changes" do
        attempt_run # first load caches the failure under the current authorization key
        expect(outbound_attempt_count).to eq(1)

        WebMock.reset!
        stub_oauth_failure
        stub_graphql_connector_introspection
        change.call(@action)

        attempt_run
        expect(outbound_attempt_count).to eq(1)
        expect(introspection_request_count).to eq(0)
      end
    end

    # The OAuth token endpoint is an authorization determinant for client
    # credentials, so a cached failure must not be reused after it changes — this
    # exact omission was a real bug in the Xurrent template.
    it 're-attempts when the oauth token endpoint changes' do
      attempt_run # first load caches the failure
      expect(outbound_attempt_count).to eq(1)
      expect(introspection_request_count).to eq(0)

      WebMock.reset!
      new_oauth = 'https://oauth.other.example.com/token'
      @action.outbound_connection.config[:oauth2][:token_endpoint] = new_oauth
      stub_oauth_failure(endpoint: new_oauth)
      stub_graphql_connector_introspection

      attempt_run # different token endpoint => different key => re-attempts against the new endpoint
      expect(outbound_attempt_count).to eq(1)
      expect(introspection_request_count).to eq(0)
    end

    it 'never embeds the client secret in the key it writes' do
      key = capture_written_failure_key
      expect(key).to start_with('introspection_failure_')
      expect(key).not_to include('secret-1')
    end

    # A 5xx from the token endpoint is transient (CustomerCredentialsError is only
    # raised for 401/403/known-400), so it must use the short TTL, not the 10-min one.
    it 'caches a token-endpoint 5xx as transient (re-attempts after the short TTL)' do
      WebMock.reset!
      stub_request(:post, oauth_endpoint).to_return(status: 500, body: 'upstream error',
                                                    headers: { 'content-type' => 'application/json' })
      stub_graphql_connector_introspection

      attempt_run # one token call (500) => IPaaS::Error => transient cache
      expect(outbound_attempt_count).to eq(1)
      attempt_run # served within the TTL
      expect(outbound_attempt_count).to eq(1)

      Timecop.travel(Time.now.utc + 31.seconds) do
        attempt_run # transient TTL expired => re-attempts
        expect(outbound_attempt_count).to eq(2)
      end
    end
  end
end
