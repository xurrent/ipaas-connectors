require 'spec_helper'

describe 'Xurrent Outbound Connection', :outbound_connection do
  let(:connector_id) { '01962529-c8eb-7a89-a682-73d6f09541d6' }

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
    it 'only region is invalid' do
      outbound_connection_config[:environment] = { region: 'us' }
      expect(outbound_connection).not_to be_valid
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

    it 'is valid without environment configured' do
      outbound_connection_config.delete(:environment)
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'is valid without account_id configured' do
      outbound_connection_config[:credentials].delete(:account_id)
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'is valid with only a personal access token (no client_id or client_secret)' do
      outbound_connection_config[:credentials] = {
        personal_access_token: make_secret_string('my-pat'),
      }
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'is invalid without client_id, client_secret, or personal_access_token' do
      # Passing contrast provided by 'demo should be valid' (OAuth2 credentials)
      # and 'is valid with only a personal access token' (PAT only).
      outbound_connection_config[:credentials] = { account_id: 'wdc' }
      expect(outbound_connection).not_to be_valid
    end

    it 'demo should be valid' do
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'qa should be valid' do
      outbound_connection.config[:environment][:stage] = 'QA'
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
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
      {
        client_id: outbound_connection.config[:credentials][:client_id],
        client_secret: encryptor.decrypt(outbound_connection.config[:credentials][:client_secret]),
        grant_type: 'client_credentials',
      }
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
        %w[QA Prod].each do |stage|
          it "can determine oauth2 endpoint based on stage #{stage}" do
            setup_oauth_server({
              access_token: 'xyz=',
              token_type: 'bearer',
            }, url: "https://oauth.xurrent.#{stage == 'QA' ? 'qa' : 'com'}/token")
            outbound_connection.config[:environment] = { stage: stage }

            outbound_connection.authenticate_request(request)

            authorization = request.headers['Authorization']
            expect(authorization).to eq('Bearer xyz=')
          end
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

    describe 'personal access token' do
      before(:each) do
        outbound_connection.config[:credentials][:personal_access_token] = make_secret_string('my-pat-token')
      end

      it 'sets bearer token from PAT' do
        outbound_connection.authenticate_request(request)
        expect(request.headers['Authorization']).to eq('Bearer my-pat-token')
      end

      it 'sets account header from configured account_id' do
        outbound_connection.authenticate_request(request)
        expect(request.headers['X-Xurrent-Account']).to eq(outbound_connection.config[:credentials][:account_id])
      end

      it 'does not call the OAuth server' do
        outbound_connection.authenticate_request(request)
        expect(a_request(:post, outbound_connection.config[:environment][:oauth2_endpoint])).not_to have_been_made
      end
    end
  end

  describe 'config_tester' do
    it_behaves_like 'xurrent token introspection config tester'
    it_behaves_like 'xurrent config tester with a personal access token'
  end

  describe 'system environment variable fallbacks' do
    let(:outbound_connection_config) do
      {
        credentials: {
          client_id: 'abc',
          client_secret: make_secret_string('def'),
        },
        # No environment block — exercises system_oauth_endpoint and system_account_id.
      }
    end

    let(:request) do
      Faraday::Request.create(:get) do |req|
        req.headers = {}
        req.params = {}
      end
    end

    it 'authenticates against system_oauth_endpoint and system_account_id when neither is configured' do
      outbound_connection.solution = double(environment: {
        xurrent_ipaas_account_id: 'sys-acct',
        xurrent_ipaas_oauth_endpoint: 'https://oauth.system.example/token',
      })
      stub = stub_request(:post, 'https://oauth.system.example/token')
             .to_return(status: 200, body: { access_token: 'sys-tok', token_type: 'bearer' }.to_json)

      outbound_connection.authenticate_request(request)

      expect(request.headers['X-Xurrent-Account']).to eq('sys-acct')
      expect(request.headers['Authorization']).to eq('Bearer sys-tok')
      expect(stub).to have_been_requested.once
    end

    it 'prefers explicit credentials.account_id and explicit oauth2_endpoint over the system values' do
      outbound_connection_config[:credentials][:account_id] = 'explicit-acct'
      outbound_connection_config[:environment] = {
        oauth2_endpoint: 'https://oauth.explicit.example/token',
        graphql_endpoint: 'https://graphql.explicit.example/',
      }
      outbound_connection.solution = double(environment: {
        xurrent_ipaas_account_id: 'sys-acct',
        xurrent_ipaas_oauth_endpoint: 'https://oauth.system.example/token',
      })
      explicit_stub = stub_request(:post, 'https://oauth.explicit.example/token')
                      .to_return(status: 200, body: { access_token: 'explicit-tok', token_type: 'bearer' }.to_json)
      system_stub = stub_request(:post, 'https://oauth.system.example/token')

      outbound_connection.authenticate_request(request)

      expect(request.headers['X-Xurrent-Account']).to eq('explicit-acct')
      expect(request.headers['Authorization']).to eq('Bearer explicit-tok')
      expect(explicit_stub).to have_been_requested.once
      expect(system_stub).not_to have_been_requested
    end
  end
end
