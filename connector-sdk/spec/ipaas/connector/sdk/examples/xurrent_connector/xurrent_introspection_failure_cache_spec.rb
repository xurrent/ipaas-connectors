require 'spec_helper'
require 'digest'

describe 'Xurrent Introspection Failure Cache', :action do
  include XurrentIntrospectionHelper

  let(:action_template_id) { '019ce240-76c9-75d1-beac-8c07b2325e76' }
  let(:outbound_connection_config) { xurrent_outbound_connection_config }
  let(:graphql_endpoint) { xurrent_graphql_endpoint }
  let(:action_input) { { object: 'people' } }

  # Captures the exact key the connector writes to the negative cache during a
  # run, so key assertions exercise production code instead of a spec-side mirror.
  # The negative cache is connection-scoped, so the spy sits on the outbound
  # connection where the connector now writes it.
  def capture_written_failure_key
    captured = nil
    allow(@action.outbound_connection).to receive(:cache_write).and_wrap_original do |orig, key, *args|
      captured ||= key if key.to_s.include?('introspection_failure_')
      orig.call(key, *args)
    end
    attempt_run
    captured
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
    # for the client-credential examples) so the action resolves cleanly, then clear
    # the schema cache and advance the bundle generation past the bundles just built,
    # so each example controls the introspection outcome: the warm bundle is never read
    # (a refresh-driven bump stays ahead of it too), so run takes the cold introspection
    # path these examples exercise.
    stub_request(:post, /oauth\./).to_return(status: 200, body: { access_token: 'tok', token_type: 'bearer' }.to_json,
                                             headers: { 'content-type' => 'application/json' })
    stub_introspection
    stub_introspection(endpoint: 'https://graphql.xurrent-oauth-test.com/')
    @action = action(action_input)
    @action.outbound_connection.cache_clear('gql_schema')
    current_gen = @action.outbound_connection.cache_read('gql_bundle_gen').to_i
    @action.outbound_connection.cache_write('gql_bundle_gen', current_gen + 1, 3600)
    WebMock.reset!
  end

  describe 'negative cache hit' do
    before(:each) do
      stub_introspection_failure(status: 400, body: 'Invalid x-xurrent-account header')
    end

    it 'caches a failed introspection so a later load is served without re-attempting' do
      attempt_run # first load hits the API, gets 400, and our code caches the failure
      expect(introspection_request_count).to eq(1)

      WebMock.reset!
      stub_introspection_failure(status: 400, body: 'Invalid x-xurrent-account header')

      expect { @action.run }.to raise_error(IPaaS::Job::FailJob, /Invalid x-xurrent-account header/)
      expect(introspection_request_count).to eq(0) # served from the cache our code wrote
    end
  end

  describe 'negative cache miss' do
    it 'attempts introspection once when no failure is cached' do
      stub_introspection_failure(status: 400, body: 'Invalid x-xurrent-account header')

      expect { @action.run }.to raise_error(IPaaS::Job::FailJob, /400/)
      expect(introspection_request_count).to eq(1)
    end

    context 'when an authorization element changes after a prior failure' do
      before(:each) do
        stub_introspection_failure(status: 400, body: 'Invalid x-xurrent-account header')
        attempt_run # first load caches the failure under the current authorization key (via our code)
        WebMock.reset!
        stub_introspection_failure(status: 400, body: 'Invalid x-xurrent-account header')
      end

      it 're-attempts when the account header changes' do
        @action.outbound_connection.config[:credentials][:account_id] = 'corrected-account'

        attempt_run
        expect(introspection_request_count).to eq(1)
      end

      it 're-attempts when the client id changes' do
        @action.outbound_connection.config[:credentials][:client_id] = 'corrected-client'

        attempt_run
        expect(introspection_request_count).to eq(1)
      end

      it 're-attempts when the personal access token changes' do
        @action.outbound_connection.config[:credentials][:personal_access_token] =
          @action.make_secret_string('corrected-token')

        attempt_run
        expect(introspection_request_count).to eq(1)
      end

      it 're-attempts against the new endpoint when the region/environment changes' do
        @action.outbound_connection.config[:environment][:stage] = 'QA'
        @action.outbound_connection.config[:environment][:region] = 'au'
        stub_introspection_failure(status: 400, body: 'denied', endpoint: 'https://graphql.au.xurrent.qa')

        attempt_run
        expect(introspection_request_count).to eq(1)
      end
    end
  end

  describe 'cache key composition' do
    before(:each) do
      stub_introspection_failure(status: 400, body: 'Invalid x-xurrent-account header')
    end

    # Element participation in the key is proven behaviourally by the
    # "authorization element changes" / OAuth re-attempt examples; here we only
    # guard that the key the connector writes never contains a plaintext secret.
    it 'never embeds a secret in the key the connector writes' do
      key = capture_written_failure_key
      expect(key).to start_with('introspection_failure_')
      expect(key).not_to include('test-api-key')
    end

    context 'with a blank-account connection' do
      let(:outbound_connection_config) do
        { credentials: { personal_access_token: make_secret_string('test-api-key') }, environment: { stage: 'Demo' } }
      end

      it 'caches and serves a hit (guards the system_account_id fallback in the key)' do
        stub_introspection_failure(status: 400, body: 'Invalid x-xurrent-account header')

        attempt_run # first load caches under the blank-account fallback key
        expect(introspection_request_count).to eq(1)

        WebMock.reset!
        stub_introspection_failure(status: 400, body: 'Invalid x-xurrent-account header')

        attempt_run
        expect(introspection_request_count).to eq(0) # served from cache => write and read agree on the fallback key
      end
    end
  end

  describe 'refresh schema' do
    let(:action_input) { { object: 'people', refresh_schema: true } }

    it 'clears the negative cache so a prior failure does not suppress re-attempt' do
      stub_introspection_failure(status: 400, body: 'Invalid x-xurrent-account header')
      attempt_run # first load caches the failure
      expect(introspection_request_count).to eq(1)

      WebMock.reset!
      stub_introspection_failure(status: 400, body: 'Invalid x-xurrent-account header')

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
      stub_introspection_failure(status: 400, body: 'Invalid x-xurrent-account header')
      attempt_run # a 4xx is cached with the long deterministic TTL by our code
      WebMock.reset!
      stub_introspection_failure(status: 400, body: 'Invalid x-xurrent-account header')
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
      stub_introspection
      stub_graphql_query(/people/, {
        'people' => { 'nodes' => [], 'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil }, 'totalCount' => 0 },
      })

      expect { @action.run }.not_to raise_error
      expect(introspection_request_count).to eq(1)
    end
  end

  describe 'OAuth client-credential token failure' do
    let(:oauth_endpoint) { 'https://oauth.xurrent-oauth-test.com/token' }
    let(:graphql_endpoint) { 'https://graphql.xurrent-oauth-test.com/' }
    let(:outbound_connection_config) do
      {
        credentials: {
          account_id: 'oauth-account',
          client_id: 'client-1',
          client_secret: make_secret_string('secret-1'),
        },
        environment: { oauth2_endpoint: oauth_endpoint, graphql_endpoint: graphql_endpoint },
      }
    end

    def stub_oauth_failure
      stub_request(:post, oauth_endpoint).to_return(
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
      stub_introspection(endpoint: graphql_endpoint)
    end

    it 'negative-caches the auth failure so a second load makes zero outbound attempts' do
      attempt_run # first load makes exactly the one OAuth token call, which fails and is cached
      expect(outbound_attempt_count).to eq(1)
      expect(introspection_request_count).to eq(0)

      WebMock.reset!
      stub_oauth_failure
      stub_introspection(endpoint: graphql_endpoint)

      attempt_run # second load must be served from the cache our code wrote, with no outbound calls
      expect(outbound_attempt_count).to eq(0)
      attempt_run # third load must be served from the cache our code wrote, with no outbound calls
      expect(outbound_attempt_count).to eq(0)

      @action.outbound_connection.config[:credentials][:client_secret] = @action.make_secret_string('secret-2')

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
    # a different key and re-attempt (one fresh OAuth token call). This connection
    # uses explicit endpoints, so the region/endpoint key element is the graphql
    # endpoint.
    {
      'account' => ->(act) { act.outbound_connection.config[:credentials][:account_id] = 'corrected-account' },
      'client id' => ->(act) { act.outbound_connection.config[:credentials][:client_id] = 'corrected-client' },
      'graphql endpoint' => ->(act) do
        act.outbound_connection.config[:environment][:graphql_endpoint] = 'https://graphql.au.xurrent.qa/'
      end,
    }.each do |element, change|
      it "re-attempts when the #{element} changes" do
        attempt_run # first load caches the failure under the current authorization key
        expect(outbound_attempt_count).to eq(1)
        attempt_run # 2nd run served from cache
        expect(outbound_attempt_count).to eq(1)
        expect(introspection_request_count).to eq(0)

        WebMock.reset!
        stub_oauth_failure
        stub_introspection(endpoint: graphql_endpoint)
        expect(outbound_attempt_count).to eq(0)
        change.call(@action)

        attempt_run
        expect(outbound_attempt_count).to eq(1)
        expect(introspection_request_count).to eq(0)
      end
    end

    # The OAuth token endpoint is an authorization determinant for client
    # credentials, so a cached failure must not be reused after it changes.
    it 're-attempts when the oauth endpoint changes' do
      attempt_run # first load caches the failure
      expect(outbound_attempt_count).to eq(1)
      attempt_run # 2nd run served from cache
      expect(outbound_attempt_count).to eq(1)
      expect(introspection_request_count).to eq(0)

      WebMock.reset!
      new_oauth = 'https://oauth.au.xurrent.qa/token'
      @action.outbound_connection.config[:environment][:oauth2_endpoint] = new_oauth
      stub_request(:post, new_oauth).to_return(status: 401, body: { error: 'invalid_client' }.to_json,
                                               headers: { 'content-type' => 'application/json' })
      stub_introspection(endpoint: graphql_endpoint)
      expect(outbound_attempt_count).to eq(0)

      attempt_run # different oauth endpoint => different key => re-attempts against the new token endpoint
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
      stub_introspection(endpoint: graphql_endpoint)

      attempt_run # one token call (500) => IPaaS::Error => transient cache
      expect(outbound_attempt_count).to eq(1)
      attempt_run # served from cache within the TTL
      expect(outbound_attempt_count).to eq(1)

      Timecop.travel(Time.now.utc + 31.seconds) do
        attempt_run # transient TTL expired => re-attempts (would stay cached if mis-classified deterministic)
        expect(outbound_attempt_count).to eq(2)
      end
    end
  end
end
