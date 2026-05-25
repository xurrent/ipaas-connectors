require 'spec_helper'

describe 'Xurrent Outbound Connection', :outbound_connection do
  let(:connector_id) { '01946424-c2ed-7fef-8202-fafd3751278c' }

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
    it 'is valid' do
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'only region is valid (stage falls back to current iPaaS stage at runtime)' do
      outbound_connection_config[:environment] = { region: 'us' }
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'only stage is valid (region falls back to current iPaaS region at runtime)' do
      outbound_connection_config[:environment] = { stage: 'Prod' }
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'only graphql endpoint is invalid' do
      outbound_connection_config[:environment] = { graphql_endpoint: 'https://graphql.xurrent.com/' }
      expect(outbound_connection).not_to be_valid
    end

    it 'only oauth2 endpoint is invalid' do
      outbound_connection_config[:environment] = { oauth2_endpoint: 'https://oauth.xurrent.com/token' }
      expect(outbound_connection).not_to be_valid
    end

    it 'explicit graphql and oauth2 endpoints are valid' do
      outbound_connection.config[:environment] = {
        oauth2_endpoint: 'https://oauth.xurrent.com/token',
        graphql_endpoint: 'https://graphql.xurrent.com/',
      }
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'demo should be valid' do
      outbound_connection.config[:environment][:stage] = 'Demo'
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'qa should be valid' do
      outbound_connection.config[:environment][:stage] = 'QA'
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'qa should be resolved' do
      outbound_connection.config[:environment][:stage] = 'QA'
      outbound_connection
    end

    it 'prod should be valid' do
      outbound_connection_config[:environment][:stage] = 'Prod'
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    %w[uk au ch us].each do |region|
      describe "region #{region}" do
        before(:each) do
          outbound_connection.config[:environment][:region] = region
        end

        it 'qa should be valid' do
          outbound_connection.config[:environment][:stage] = 'QA'
          expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
        end

        it 'prod should be valid' do
          outbound_connection.config[:environment][:stage] = 'Prod'
          expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
        end
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
        req.params = { foo: 'bar', baz: 'bie' }
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
      decrypted = outbound_connection.decrypt_secret_string(outbound_connection.config[:credentials][:client_secret])
      URI.encode_www_form({
        client_id: outbound_connection.config[:credentials][:client_id],
        client_secret: decrypted,
        grant_type: 'client_credentials',
      })
    end

    def setup_oauth_server(server_response, status: 200, url: nil)
      create_mock_oauth_server(url)
        .to_return(status: status, body: server_response.to_json, headers: { foo: :bar })
        .to_return(status: 401, body: 'No 2nd call expected', headers: {})
    end

    def update_connection_schema!(*credentials_fields)
      new_config = outbound_connection.config_schema
                                      .resolve(outbound_connection, field_mapping_for(*credentials_fields))
      outbound_connection.instance_variable_set(:@config, new_config)
    end

    def field_mapping_for(*credentials_fields)
      [
        { field_id: 'environment', nested: [
          { field_id: 'oauth2_endpoint',
            fixed: outbound_connection.config[:environment][:oauth2_endpoint], },
          { field_id: 'graphql_endpoint',
            fixed: outbound_connection.config[:environment][:graphql_endpoint], },
        ], },
        { field_id: 'credentials', nested: credentials_fields },
      ]
    end

    describe 'account header' do
      before(:each) do
        setup_oauth_server({
          access_token: 'abc',
          token_type: 'bearer',
        })
      end

      it 'adds account header' do
        outbound_connection.authenticate_request(request)
        authorization = request.headers['X-Xurrent-Account']
        expect(authorization).to eq(outbound_connection.config[:credentials][:account_id])
      end
    end

    describe 'client credentials' do
      describe 'no explicit OAuth2 endpoint' do
        it 'can determine oauth2 endpoint based on stage' do
          setup_oauth_server({
            access_token: 'xyz=',
            token_type: 'bearer',
          }, url: 'https://oauth.xurrent.com/token')
          outbound_connection.config[:environment] = { stage: 'Prod' }

          outbound_connection.authenticate_request(request)

          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer xyz=')
        end

        it 'can determine oauth2 endpoint based on region and stage' do
          setup_oauth_server({
            access_token: 'ayz=',
            token_type: 'bearer',
          }, url: 'https://oauth.us.xurrent.com/token')
          outbound_connection.config[:environment] = { stage: 'Prod', region: 'us' }

          outbound_connection.authenticate_request(request)

          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer ayz=')
        end

        it 'ignores demo region when determining OAuth2 endpoint' do
          setup_oauth_server({
            access_token: 'ayz=',
            token_type: 'bearer',
          }, url: 'https://oauth.xurrent-demo.com/token')
          outbound_connection.config[:environment] = { stage: 'Demo', region: 'us' }

          outbound_connection.authenticate_request(request)

          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer ayz=')
        end
      end

      it 'should raise an error when server returns 400 error' do
        setup_oauth_server({ message: 'bad request' }, status: 400)
        expect { outbound_connection.authenticate_request(request) }
          .to raise_error(IPaaS::Error, 'Unable to authenticate to oauth.xurrent-test.com (HTTP 400)')
      end

      it 'should raise CustomerCredentialsError when server returns invalid_grant' do
        setup_oauth_server({ error: 'invalid_grant', error_description: 'Invalid client credentials' }, status: 400)
        expect { outbound_connection.authenticate_request(request) }
          .to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError,
                          'Authentication to oauth.xurrent-test.com failed: ' \
                          'invalid_grant: Invalid client credentials')
      end

      it 'should raise an error when token type is mac' do
        setup_oauth_server({
          access_token: 'am9objpzZWNyZXQ=',
          token_type: 'mac',
        })
        expect do
          outbound_connection.authenticate_request(request)
        end.to raise_error("Unable to authenticate, unsupported token_type: 'mac'")
      end

      it 'should raise an error when no access token is provided' do
        setup_oauth_server({ token_type: 'bearer' })
        expect do
          outbound_connection.authenticate_request(request)
        end.to raise_error('Unable to authenticate, no access_token found')
      end

      it 'should add the bearer authentication to the header when token type is bearer' do
        setup_oauth_server({
          access_token: 'am9objpzZWNyZXQ=',
          token_type: 'bearer',
        })

        outbound_connection.authenticate_request(request)
        authorization = request.headers['Authorization']
        expect(authorization).to eq('Bearer am9objpzZWNyZXQ=')
      end

      context 'caches access token' do
        it 'does not call oauth server when access token already obtained' do
          setup_oauth_server({
            access_token: 'am9objpzZWNyZXQ=',
            token_type: 'bearer',
            expires_in: 3600,
          })

          outbound_connection.authenticate_request(request)
          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer am9objpzZWNyZXQ=')

          request2 = Faraday::Request.create(:post) do |req|
            req.headers = {}
            req.params = { foo: 'baz' }
          end
          outbound_connection.authenticate_request(request2)
          authorization2 = request2.headers['Authorization']
          expect(authorization2).to eq('Bearer am9objpzZWNyZXQ=')
        end

        it 'calls oauth server when access token has expired' do
          server_response1 = {
            access_token: '1',
            token_type: 'bearer',
            expires_in: IPaaS::Job::Outbound::HTTP::OPEN_TIMEOUT,
          }
          server_response2 = {
            access_token: '2',
            token_type: 'bearer',
            expires_in: 3600,
          }
          create_mock_oauth_server
            .to_return(status: 200, body: server_response1.to_json, headers: { foo: :bar })
            .to_return(status: 200, body: server_response2.to_json, headers: {})

          outbound_connection.authenticate_request(request)
          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer 1')

          request2 = Faraday::Request.create(:post) do |req|
            req.headers = {}
            req.params = { foo: 'baz' }
          end
          outbound_connection.authenticate_request(request2)
          authorization2 = request2.headers['Authorization']
          expect(authorization2).to eq('Bearer 2')
        end

        it 'calls oauth server each time when access token has no expiry' do
          server_response1 = {
            access_token: '1',
            token_type: 'bearer',
          }
          server_response2 = {
            access_token: '2',
            token_type: 'bearer',
          }
          create_mock_oauth_server
            .to_return(status: 200, body: server_response1.to_json, headers: { foo: :bar })
            .to_return(status: 200, body: server_response2.to_json, headers: {})

          outbound_connection.authenticate_request(request)
          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer 1')

          request2 = Faraday::Request.create(:post) do |req|
            req.headers = {}
            req.params = { foo: 'baz' }
          end
          outbound_connection.authenticate_request(request2)
          authorization2 = request2.headers['Authorization']
          expect(authorization2).to eq('Bearer 2')
        end
      end

      it 'calls oauth server after failed call' do
        server_response1 = {
          access_token: '1',
          token_type: 'mac',
        }
        server_response2 = {
          access_token: '2',
          token_type: 'bearer',
        }
        create_mock_oauth_server
          .to_return(status: 200, body: server_response1.to_json, headers: { foo: :bar })
          .to_return(status: 200, body: server_response2.to_json, headers: {})

        expect { outbound_connection.authenticate_request(request) }.to raise_error(IPaaS::Error)

        request2 = Faraday::Request.create(:post) do |req|
          req.headers = {}
          req.params = { foo: 'baz' }
        end
        outbound_connection.authenticate_request(request2)
        authorization2 = request2.headers['Authorization']
        expect(authorization2).to eq('Bearer 2')
      end

      it 'should clear the cache on schema update' do
        server_response1 = {
          access_token: '1',
          token_type: 'bearer',
          expires_in: 3600,
        }
        create_mock_oauth_server
          .to_return(status: 200, body: server_response1.to_json, headers: { foo: :bar })

        outbound_connection.authenticate_request(request)
        authorization = request.headers['Authorization']
        expect(authorization).to eq('Bearer 1')

        update_connection_schema!(
          { field_id: 'account_id', fixed: outbound_connection.config[:credentials][:account_id] },
          { field_id: 'client_id', fixed: 'b' },
          { field_id: 'client_secret', fixed: make_secret_string('a') },
        )
        server_response2 = {
          access_token: '2',
          token_type: 'bearer',
          expires_in: 3600,
        }
        create_mock_oauth_server
          .to_return(status: 200, body: server_response2.to_json, headers: {})

        request2 = Faraday::Request.create(:post) do |req|
          req.headers = {}
          req.params = { foo: 'baz' }
        end
        outbound_connection.authenticate_request(request2)
        authorization2 = request2.headers['Authorization']
        expect(authorization2).to eq('Bearer 2')
      end
    end
  end

  describe 'config_schema defaults' do
    it 'marks credentials.account_id as optional with leave-blank fallback' do
      field = outbound_connection.config_schema
                                 .field(:credentials).fields.detect { |f| f.id == :account_id }
      expect(field.required).to be_falsey
      expect(field.visibility).to eq('optional')
    end

    it 'marks the environment field as optional' do
      field = outbound_connection.config_schema.field(:environment)
      expect(field.required).to be_falsey
      expect(field.visibility).to eq('optional')
    end

    it 'is valid without account_id (system fallback handles it at runtime)' do
      outbound_connection_config[:credentials].delete(:account_id)
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'is valid without environment (system fallback handles endpoints at runtime)' do
      outbound_connection_config.delete(:environment)
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end
  end

  describe 'authenticate with system account fallback' do
    let(:outbound_connection_config) do
      {
        credentials: {
          client_id: 'abc',
          client_secret: make_secret_string('def'),
        },
        environment: {
          oauth2_endpoint: 'https://oauth.xurrent-test.com/token',
          graphql_endpoint: 'https://graphql.xurrent-test.com/',
        },
      }
    end

    let(:request) do
      Faraday::Request.create(:get) do |req|
        req.headers = {}
        req.params = {}
      end
    end

    def stub_oauth_token
      stub_request(:post, 'https://oauth.xurrent-test.com/token')
        .to_return(status: 200, body: { access_token: 'tok', token_type: 'bearer' }.to_json)
    end

    it 'sets X-Xurrent-Account from system_account_id when credentials.account_id is blank' do
      outbound_connection.solution = double(environment: { xurrent_ipaas_account_id: 'sys-acct' })
      stub_oauth_token

      outbound_connection.authenticate_request(request)
      expect(request.headers['X-Xurrent-Account']).to eq('sys-acct')
    end

    it 'prefers an explicit credentials.account_id over the system value' do
      outbound_connection_config[:credentials][:account_id] = 'explicit-acct'
      outbound_connection.solution = double(environment: { xurrent_ipaas_account_id: 'sys-acct' })
      stub_oauth_token

      outbound_connection.authenticate_request(request)
      expect(request.headers['X-Xurrent-Account']).to eq('explicit-acct')
    end
  end

  describe 'setup_info' do
    let(:outbound_connection_config) do
      {
        credentials: {
          account_id: 'acme',
          client_id: 'abc',
          client_secret: make_secret_string('def'),
        },
        environment: { stage: 'Prod' },
      }
    end

    def setup_info_link_href(info)
      info[:'Quick setup'][:'Create OAuth Application in Xurrent'][:href]
    end

    def setup_info_link_query(info)
      URI.decode_www_form(URI.parse(setup_info_link_href(info)).query).to_h
    end

    it 'returns a Quick setup section with a deep-link to the OAuth Application form' do
      info = outbound_connection.setup_info
      expect(setup_info_link_href(info)).to start_with('https://acme.xurrent.com/oauth_applications/new?')
    end

    it 'pre-fills the URL with grant_type=client_credentials and the provider scope list' do
      query = setup_info_link_query(outbound_connection.setup_info)
      expect(query['grant_type']).to eq('client_credentials')
      expect(query['scopes']).to eq(XurrentAppConnector::PROVIDER_OAUTH_SCOPES.join(','))
    end

    it 'uses the solution name as the OAuth Application name when present' do
      outbound_connection.solution = double(name: 'Acme iPaaS', environment: {})
      query = setup_info_link_query(outbound_connection.setup_info)
      expect(query['name']).to eq('Acme iPaaS')
    end

    it 'falls back to "iPaaS Integration" as the application name when solution is unavailable' do
      query = setup_info_link_query(outbound_connection.setup_info)
      expect(query['name']).to eq('iPaaS Integration')
    end

    it 'derives the URL host from system_account_id when credentials.account_id is blank' do
      outbound_connection_config[:credentials].delete(:account_id)
      outbound_connection.solution = double(name: nil, environment: { xurrent_ipaas_account_id: 'sys-acct' })
      expect(setup_info_link_href(outbound_connection.setup_info))
        .to start_with('https://sys-acct.xurrent.com/oauth_applications/new?')
    end

    it 'derives the URL host from system_account_id when credentials are missing entirely' do
      outbound_connection_config.delete(:credentials)
      outbound_connection.solution = double(name: nil, environment: { xurrent_ipaas_account_id: 'sys-acct' })
      expect(setup_info_link_href(outbound_connection.setup_info))
        .to start_with('https://sys-acct.xurrent.com/oauth_applications/new?')
    end

    it 'returns nil when neither credentials.account_id nor a system account is available' do
      outbound_connection_config[:credentials].delete(:account_id)
      expect(outbound_connection.setup_info).to be_nil
    end

    it 'returns nil when credentials are missing entirely and no system account is available' do
      outbound_connection_config.delete(:credentials)
      expect(outbound_connection.setup_info).to be_nil
    end

    describe 'system stage/region fallback' do
      it 'uses xurrent.qa when iPaaS is on QA and user environment is blank' do
        outbound_connection_config.delete(:environment)
        outbound_connection.solution = double(name: nil, environment: { xurrent_ipaas_stage: 'QA' })
        expect(setup_info_link_href(outbound_connection.setup_info))
          .to start_with('https://acme.xurrent.qa/oauth_applications/new?')
      end

      it 'uses xurrent-demo.com when iPaaS is on Demo and user environment is blank' do
        outbound_connection_config.delete(:environment)
        outbound_connection.solution = double(name: nil, environment: { xurrent_ipaas_stage: 'Demo' })
        expect(setup_info_link_href(outbound_connection.setup_info))
          .to start_with('https://acme.xurrent-demo.com/oauth_applications/new?')
      end

      it 'prefixes the system region when iPaaS is on Prod with a region and user environment is blank' do
        outbound_connection_config.delete(:environment)
        outbound_connection.solution = double(name: nil,
                                              environment: { xurrent_ipaas_stage: 'Prod', xurrent_ipaas_region: 'us' })
        expect(setup_info_link_href(outbound_connection.setup_info))
          .to start_with('https://acme.us.xurrent.com/oauth_applications/new?')
      end

      it 'ignores system region when iPaaS resolves to Demo' do
        outbound_connection_config.delete(:environment)
        outbound_connection.solution = double(name: nil,
                                              environment: { xurrent_ipaas_stage: 'Demo', xurrent_ipaas_region: 'us' })
        expect(setup_info_link_href(outbound_connection.setup_info))
          .to start_with('https://acme.xurrent-demo.com/oauth_applications/new?')
      end

      it 'lets an explicit user stage override the system stage' do
        outbound_connection_config[:environment] = { stage: 'Demo' }
        outbound_connection.solution = double(name: nil, environment: { xurrent_ipaas_stage: 'QA' })
        expect(setup_info_link_href(outbound_connection.setup_info))
          .to start_with('https://acme.xurrent-demo.com/oauth_applications/new?')
      end
    end

    describe 'URL encoding' do
      it 'percent-encodes URL-special characters in the solution name' do
        outbound_connection.solution = double(name: 'Acme & Co = test', environment: {})
        href = setup_info_link_href(outbound_connection.setup_info)
        expect(href).to include('%26').and include('%3D')
        expect(setup_info_link_query(outbound_connection.setup_info)['name']).to eq('Acme & Co = test')
      end
    end
  end

  describe 'PROVIDER_OAUTH_SCOPES_PROSE' do
    it 'expands "ui-extension:CRU" as "Ui Extension (Create, Read, Update)"' do
      expect(XurrentAppConnector::PROVIDER_OAUTH_SCOPES_PROSE)
        .to include('   - Ui Extension (Create, Read, Update)')
    end

    it 'expands "app-offering-automation-rule:CRUD" with all four action labels in order' do
      expect(XurrentAppConnector::PROVIDER_OAUTH_SCOPES_PROSE)
        .to include('   - App Offering Automation Rule (Create, Read, Update, Delete)')
    end
  end
end
