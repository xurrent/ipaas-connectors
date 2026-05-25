require 'spec_helper'

describe 'Xurrent Outbound Connection', :outbound_connection do
  let(:connector_id) { '01930641-94f0-7d88-941f-cd0f542b75b9' }

  let(:outbound_connection_config) do
    {
      credentials: {
        account_id: 'wdc',
        client_id: 'abc',
        client_secret: make_secret_string('def'),
      },
      environment: {
        stage: 'Demo',
      },
    }
  end

  describe 'validation' do
    it 'is valid with OAuth2 credentials and Demo stage' do
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'is valid with only a personal access token (no client_id or client_secret)' do
      outbound_connection_config[:credentials] = {
        personal_access_token: make_secret_string('my-token'),
      }
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'is invalid without client_id, client_secret, or personal_access_token' do
      # Passing contrast provided by 'is valid with OAuth2 credentials and Demo stage'
      # and 'is valid with only a personal access token'.
      outbound_connection_config[:credentials] = { account_id: 'wdc' }
      expect(outbound_connection).not_to be_valid
    end

    it 'is valid without account_id' do
      outbound_connection_config[:credentials].delete(:account_id)
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'is valid without environment' do
      outbound_connection_config.delete(:environment)
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'is invalid with only region (no stage or endpoints)' do
      outbound_connection_config[:environment] = { region: 'us' }
      expect(outbound_connection).not_to be_valid
    end

    it 'is invalid with only graphql_endpoint (missing oauth2_endpoint)' do
      outbound_connection_config[:environment] = { graphql_endpoint: 'https://graphql.xurrent.com/' }
      expect(outbound_connection).not_to be_valid
    end

    it 'is invalid with only oauth2_endpoint (missing graphql_endpoint)' do
      outbound_connection_config[:environment] = { oauth2_endpoint: 'https://oauth.xurrent.com/token' }
      expect(outbound_connection).not_to be_valid
    end

    it 'is valid with explicit graphql and oauth2 endpoints' do
      outbound_connection.config[:environment] = {
        oauth2_endpoint: 'https://oauth.xurrent.com/token',
        graphql_endpoint: 'https://graphql.xurrent.com/',
      }
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    %w[Demo QA Prod].each do |stage|
      it "is valid with stage #{stage}" do
        outbound_connection_config[:environment][:stage] = stage
        expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
      end
    end

    stages = %w[QA Prod]
    %w[uk au ch us].each do |region|
      stages.each do |stage|
        it "is valid with region #{region} and stage #{stage}" do
          outbound_connection.config[:environment] = { stage: stage, region: region }
          expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
        end
      end
    end
  end

  describe 'config_schema' do
    it 'defines credentials as a required nested field with OAuth2 and PAT sub-fields' do
      credentials = outbound_connection.config_schema.field(:credentials)
      expect(credentials.type).to eq(:nested)
      expect(credentials.required).to be_truthy
      sub_ids = credentials.fields.map(&:id)
      expect(sub_ids).to eq([:account_id, :client_id, :client_secret, :personal_access_token])
    end

    it 'defines account_id as an optional string' do
      account_id = outbound_connection.config_schema.field(:credentials).fields.detect { |f| f.id == :account_id }
      expect(account_id.type).to eq(:string)
      expect(account_id.required).to be_falsey
      expect(account_id.visibility).to eq('optional')
    end

    it 'defines environment as an optional nested field with sub-fields' do
      env = outbound_connection.config_schema.field(:environment)
      expect(env.type).to eq(:nested)
      expect(env.required).to be_falsey
      expect(env.visibility).to eq('optional')
      sub_ids = env.fields.map(&:id)
      expect(sub_ids).to include(:stage, :region, :oauth2_endpoint, :graphql_endpoint)
    end
  end

  describe 'PAT presence toggling required on OAuth2 credentials' do
    def credentials_fields
      outbound_connection.config_schema.field(:credentials).fields
    end

    context 'when personal_access_token is absent (default)' do
      it 'keeps client_id and client_secret required and leaves personal_access_token optional' do
        expect(credentials_fields.detect { |f| f.id == :client_id }.required).to be true
        expect(credentials_fields.detect { |f| f.id == :client_secret }.required).to be true
        expect(credentials_fields.detect { |f| f.id == :personal_access_token }.required).to be_falsey
      end
    end

    context 'when personal_access_token is set' do
      let(:outbound_connection_config) do
        {
          credentials: {
            account_id: 'wdc',
            personal_access_token: make_secret_string('my-pat'),
          },
          environment: { stage: 'Demo' },
        }
      end

      it 'marks client_id and client_secret as not required and keeps personal_access_token optional' do
        expect(credentials_fields.detect { |f| f.id == :client_id }.required).to be false
        expect(credentials_fields.detect { |f| f.id == :client_secret }.required).to be false
        expect(credentials_fields.detect { |f| f.id == :personal_access_token }.required).to be_falsey
      end
    end
  end

  describe 'authenticate' do
    before(:each) do
      outbound_connection.config[:environment] = {
        oauth2_endpoint: 'https://oauth.xurrent-test.com/token',
        graphql_endpoint: 'https://graphql.xurrent-test.com/',
      }
    end

    let(:request) do
      Faraday::Request.create(:get) do |req|
        req.headers = {}
        req.params = {}
      end
    end

    def create_mock_oauth_server(url = nil)
      url ||= outbound_connection.config[:environment][:oauth2_endpoint]
      stub_request(:post, url)
        .with(body: create_expected_oauth2_body,
              headers: {
                'Accept' => 'application/json',
                'Content-Type' => 'application/x-www-form-urlencoded',
                'User-Agent' => 'Xurrent iPaaS',
              })
    end

    def create_expected_oauth2_body
      credentials_config = outbound_connection.config[:credentials]
      decrypted = outbound_connection.decrypt_secret_string(credentials_config[:client_secret])
      URI.encode_www_form({
        client_id: credentials_config[:client_id],
        client_secret: decrypted,
        grant_type: 'client_credentials',
      })
    end

    def setup_oauth_server(server_response, status: 200, url: nil)
      create_mock_oauth_server(url)
        .to_return(status: status, body: server_response.to_json, headers: { foo: :bar })
        .to_return(status: 401, body: 'No 2nd call expected', headers: {})
    end

    describe 'OAuth2 client credentials' do
      before(:each) do
        setup_oauth_server({ access_token: 'test-token', token_type: 'bearer' })
      end

      it 'adds the account and authorization headers' do
        outbound_connection.authenticate_request(request)
        expect(request.headers['X-Xurrent-Account']).to eq('wdc')
        expect(request.headers['Authorization']).to eq('Bearer test-token')
      end
    end

    describe 'personal access token' do
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

      it 'adds the account and authorization headers without calling OAuth2 server' do
        outbound_connection.authenticate_request(request)
        expect(request.headers['X-Xurrent-Account']).to eq('wdc')
        expect(request.headers['Authorization']).to eq('Bearer my-pat-token')
        expect(WebMock).not_to have_requested(:post, 'https://oauth.xurrent-test.com/token')
      end
    end

    describe 'OAuth2 endpoint resolution' do
      it 'determines oauth2 endpoint from Prod stage' do
        setup_oauth_server({
          access_token: 'xyz=',
          token_type: 'bearer',
        }, url: 'https://oauth.xurrent.com/token')
        outbound_connection.config[:environment] = { stage: 'Prod' }

        outbound_connection.authenticate_request(request)
        expect(request.headers['Authorization']).to eq('Bearer xyz=')
      end

      it 'determines oauth2 endpoint from region and stage' do
        setup_oauth_server({
          access_token: 'ayz=',
          token_type: 'bearer',
        }, url: 'https://oauth.us.xurrent.com/token')
        outbound_connection.config[:environment] = { stage: 'Prod', region: 'us' }

        outbound_connection.authenticate_request(request)
        expect(request.headers['Authorization']).to eq('Bearer ayz=')
      end

      it 'ignores region for Demo stage' do
        setup_oauth_server({
          access_token: 'demo=',
          token_type: 'bearer',
        }, url: 'https://oauth.xurrent-demo.com/token')
        outbound_connection.config[:environment] = { stage: 'Demo', region: 'us' }

        outbound_connection.authenticate_request(request)
        expect(request.headers['Authorization']).to eq('Bearer demo=')
      end
    end

    describe 'error handling' do
      it 'raises when server returns 400' do
        setup_oauth_server({ message: 'bad request' }, status: 400)
        expect { outbound_connection.authenticate_request(request) }
          .to raise_error(IPaaS::Error, 'Unable to authenticate to oauth.xurrent-test.com (HTTP 400)')
      end

      it 'raises CustomerCredentialsError when server returns invalid_grant' do
        setup_oauth_server({ error: 'invalid_grant', error_description: 'Invalid client credentials' }, status: 400)
        expect { outbound_connection.authenticate_request(request) }
          .to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError,
                          'Authentication to oauth.xurrent-test.com failed: ' \
                          'invalid_grant: Invalid client credentials')
      end

      it 'raises when token type is unsupported' do
        setup_oauth_server({ access_token: 'token', token_type: 'mac' })
        expect { outbound_connection.authenticate_request(request) }
          .to raise_error("Unable to authenticate, unsupported token_type: 'mac'")
      end

      it 'raises when no access token is returned' do
        setup_oauth_server({ token_type: 'bearer' })
        expect { outbound_connection.authenticate_request(request) }
          .to raise_error('Unable to authenticate, no access_token found')
      end
    end

    describe 'token caching' do
      it 'reuses cached token within expiry window' do
        setup_oauth_server({ access_token: 'cached', token_type: 'bearer', expires_in: 3600 })

        outbound_connection.authenticate_request(request)
        expect(request.headers['Authorization']).to eq('Bearer cached')

        request2 = Faraday::Request.create(:get) do |req|
          req.headers = {}
          req.params = {}
        end
        outbound_connection.authenticate_request(request2)
        expect(request2.headers['Authorization']).to eq('Bearer cached')
      end

      it 'refreshes token after expiry' do
        create_mock_oauth_server
          .to_return(status: 200, body: {
            access_token: '1', token_type: 'bearer',
            expires_in: IPaaS::Job::Outbound::HTTP::OPEN_TIMEOUT,
          }.to_json, headers: { foo: :bar })
          .to_return(status: 200, body: {
            access_token: '2', token_type: 'bearer', expires_in: 3600,
          }.to_json, headers: {})

        outbound_connection.authenticate_request(request)
        expect(request.headers['Authorization']).to eq('Bearer 1')

        request2 = Faraday::Request.create(:get) do |req|
          req.headers = {}
          req.params = {}
        end
        outbound_connection.authenticate_request(request2)
        expect(request2.headers['Authorization']).to eq('Bearer 2')
      end

      it 'fetches new token each time when no expiry is set' do
        create_mock_oauth_server
          .to_return(status: 200, body: { access_token: '1', token_type: 'bearer' }.to_json, headers: { foo: :bar })
          .to_return(status: 200, body: { access_token: '2', token_type: 'bearer' }.to_json, headers: {})

        outbound_connection.authenticate_request(request)
        expect(request.headers['Authorization']).to eq('Bearer 1')

        request2 = Faraday::Request.create(:get) do |req|
          req.headers = {}
          req.params = {}
        end
        outbound_connection.authenticate_request(request2)
        expect(request2.headers['Authorization']).to eq('Bearer 2')
      end
    end
  end
end
