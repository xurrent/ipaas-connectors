# Shared by the Xurrent connectors whose config_tester verifies the connection
# by introspecting the OAuth2 token (xurrent, xurrent-app, xurrent-graphql).
#
# The context provides the connection config and the webmock stubs, with the
# stub URLs derived from the config's oauth2_endpoint. Include it directly for
# connector-specific examples that need the same stubs.
RSpec.shared_context 'xurrent config tester' do
  # config.valid? (called by Connection#config_tester) clears and re-resolves the
  # config from the mapping, so the environment must come from the config itself
  # rather than a post-parse mutation.
  let(:outbound_connection_config) do
    {
      credentials: {
        account_id: 'wdc',
        client_id: 'abc',
        client_secret: make_secret_string('def'),
      },
      environment: {
        oauth2_endpoint: 'https://oauth.xurrent-test.com/token',
        graphql_endpoint: 'https://graphql.xurrent-test.com/',
      },
    }
  end

  let(:oauth_token_url) { outbound_connection_config.dig(:environment, :oauth2_endpoint) }
  let(:introspect_url) { "#{oauth_token_url.delete_suffix('/token')}/introspect" }

  def stub_oauth_token_request(url = oauth_token_url)
    stub_request(:post, url)
      .to_return(status: 200, body: { access_token: 'test-token', token_type: 'bearer' }.to_json)
  end

  def stub_introspect(status:, body: nil, url: introspect_url)
    stub_request(:get, url)
      .with(headers: { 'Authorization' => 'Bearer test-token', 'X-Xurrent-Account' => 'wdc' })
      .to_return(status: status, body: body)
  end
end

RSpec.shared_examples 'xurrent token introspection config tester' do
  include_context 'xurrent config tester'

  it 'provides the config_tester feature' do
    expect(outbound_connection.config_tester?).to be true
  end

  it 'returns success with the token scopes' do
    stub_oauth_token_request
    stub_introspect(status: 200, body: { active: true, scopes: %w[account-administration cmdb] }.to_json)
    expect(outbound_connection.config_tester)
      .to eq({ status: :success, message: 'Connection successful. Token scopes: account-administration, cmdb.' })
  end

  it 'returns failed when the token is valid but has no scopes' do
    # Contrast with 'returns success with the token scopes'.
    stub_oauth_token_request
    stub_introspect(status: 200, body: { active: true, scopes: [] }.to_json)
    expect(outbound_connection.config_tester)
      .to eq({ status: :failed, message: 'Token is valid but has no scopes.' })
  end

  it 'returns failed when the token is rejected (HTTP 401)' do
    stub_oauth_token_request
    stub_introspect(status: 401, body: '')
    expect(outbound_connection.config_tester)
      .to eq({ status: :failed, message: 'Xurrent rejected the credentials (HTTP 401).' })
  end

  it 'returns failed when access is forbidden (HTTP 403)' do
    stub_oauth_token_request
    stub_introspect(status: 403, body: '')
    expect(outbound_connection.config_tester)
      .to eq({ status: :failed, message: 'Xurrent rejected the credentials (HTTP 403).' })
  end

  it 'returns failed when account header is wrong (HTTP 400)' do
    stub_oauth_token_request
    stub_introspect(status: 400, body: %({"message":"Invalid x-xurrent-account header"}))
    expect(outbound_connection.config_tester)
      .to eq({ status: :failed, message: 'Invalid x-xurrent-account header' })
  end

  it 'returns failed with a generic message when the HTTP 400 body has no message' do
    # Contrast with 'returns failed when account header is wrong (HTTP 400)'.
    stub_oauth_token_request
    stub_introspect(status: 400, body: '{}')
    expect(outbound_connection.config_tester)
      .to eq({ status: :failed, message: 'Xurrent rejected the request (HTTP 400).' })
  end

  it 'returns error when the HTTP 400 body cannot be parsed' do
    stub_oauth_token_request
    stub_introspect(status: 400, body: '<html>')
    expect(outbound_connection.config_tester)
      .to eq({ status: :error, message: 'Token introspection returned an unparseable response (HTTP 400).' })
  end

  it 'returns error on an unexpected response (HTTP 500)' do
    # Contrast with the 401/403 cases: a server problem is :error, not :failed.
    stub_oauth_token_request
    stub_introspect(status: 500, body: 'boom')
    expect(outbound_connection.config_tester)
      .to eq({ status: :error, message: "Token introspection failed (HTTP 500): 'boom'" })
  end

  it 'returns error when the introspect response cannot be parsed' do
    stub_oauth_token_request
    stub_introspect(status: 200, body: '<html>')
    expect(outbound_connection.config_tester)
      .to eq({ status: :error, message: 'Token introspection returned an unparseable response (HTTP 200).' })
  end

  it 'returns error when the introspect response is valid JSON but not an object' do
    stub_oauth_token_request
    stub_introspect(status: 200, body: '[]')
    expect(outbound_connection.config_tester)
      .to eq({ status: :error, message: 'Token introspection returned an unparseable response (HTTP 200).' })
  end

  it 'returns error when the introspect call times out' do
    stub_oauth_token_request
    stub_request(:get, introspect_url).to_timeout
    # The timed-out message only comes from the timeout branch, proving it was
    # taken rather than another error branch.
    expect(outbound_connection.config_tester)
      .to eq({ status: :error, message: 'The connection test timed out.' })
  end

  it 'returns failed when the OAuth2 client credentials are rejected' do
    stub_request(:post, oauth_token_url)
      .to_return(status: 400,
                 body: { error: 'invalid_grant', error_description: 'Invalid client credentials' }.to_json)
    expect(outbound_connection.config_tester)
      .to eq({ status: :failed,
               message: 'Authentication to oauth.xurrent-test.com failed: ' \
                        'invalid_grant: Invalid client credentials', })
  end

  it 'exchanges client credentials for a token before introspecting' do
    token_stub = stub_oauth_token_request
    stub_introspect(status: 200, body: { active: true, scopes: ['cmdb'] }.to_json)
    expect(outbound_connection.config_tester)
      .to eq({ status: :success, message: 'Connection successful. Token scopes: cmdb.' })
    expect(token_stub).to have_been_requested.once
  end

  describe 'introspect URL derivation' do
    context 'with a custom oauth2_endpoint including a port' do
      let(:outbound_connection_config) do
        {
          credentials: {
            account_id: 'wdc',
            client_id: 'abc',
            client_secret: make_secret_string('def'),
          },
          environment: {
            oauth2_endpoint: 'https://oauth.custom-test.com:8443/token',
            graphql_endpoint: 'https://graphql.custom-test.com/',
          },
        }
      end

      it 'keeps scheme, host and port of the custom oauth2_endpoint' do
        stub_oauth_token_request
        stub_introspect(status: 200, body: { active: true, scopes: ['cmdb'] }.to_json)
        expect(outbound_connection.config_tester[:status]).to eq(:success)
        expect(WebMock).to have_requested(:get, 'https://oauth.custom-test.com:8443/introspect')
        expect(WebMock).not_to have_requested(:get, 'https://oauth.xurrent-test.com/introspect')
      end
    end

    context 'with a stage-based environment' do
      let(:outbound_connection_config) do
        {
          credentials: {
            account_id: 'wdc',
            client_id: 'abc',
            client_secret: make_secret_string('def'),
          },
          environment: { stage: 'Prod' },
        }
      end

      # The config has no oauth2_endpoint to derive the stubs from; the literal
      # URLs document the host the Prod stage must map to.
      let(:oauth_token_url) { 'https://oauth.xurrent.com/token' }

      it 'derives the introspect URL from the Prod stage' do
        stub_oauth_token_request
        stub_introspect(status: 200, body: { active: true, scopes: ['cmdb'] }.to_json)
        expect(outbound_connection.config_tester[:status]).to eq(:success)
        expect(WebMock).to have_requested(:get, 'https://oauth.xurrent.com/introspect')
        expect(WebMock).not_to have_requested(:get, 'https://oauth.xurrent-test.com/introspect')
      end
    end
  end
end

RSpec.shared_examples 'xurrent config tester with a personal access token' do
  include_context 'xurrent config tester'

  context 'with a personal access token' do
    let(:outbound_connection_config) do
      {
        credentials: {
          account_id: 'wdc',
          personal_access_token: make_secret_string('my-pat-token'),
        },
        environment: {
          oauth2_endpoint: 'https://oauth.xurrent-test.com/token',
          graphql_endpoint: 'https://graphql.xurrent-test.com/',
        },
      }
    end

    it 'tests via the PAT without calling the OAuth2 server' do
      stub_request(:get, introspect_url)
        .with(headers: { 'Authorization' => 'Bearer my-pat-token', 'X-Xurrent-Account' => 'wdc' })
        .to_return(status: 200, body: { active: true, scopes: ['cmdb'] }.to_json)
      expect(outbound_connection.config_tester)
        .to eq({ status: :success, message: 'Connection successful. Token scopes: cmdb.' })
      expect(WebMock).not_to have_requested(:post, oauth_token_url)
    end
  end
end
