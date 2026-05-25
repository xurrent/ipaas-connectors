require 'spec_helper'

describe 'Microsoft Entra and Intune Connection', :outbound_connection do
  let(:connector_id) { '01983ca8-546f-7610-93c9-c6cc164300fc' }

  let(:outbound_connection_config) do
    {
      credentials: {
        tenant_id: 'wdc',
        client_id: 'abc',
        client_secret: make_secret_string('def'),
      },
    }
  end

  describe 'validation' do
    it 'tenant_id is required' do
      outbound_connection_config[:credentials].delete(:tenant_id)
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
    end

    it 'client_id is required' do
      outbound_connection_config[:credentials].delete(:client_id)
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
    end

    it 'client_secret is required' do
      outbound_connection_config[:credentials].delete(:client_secret)
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
    end

    it 'endpoints are not required' do
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'explicit graph and oauth2 endpoints are valid' do
      outbound_connection.config[:environment] = {
        oauth2_endpoint: 'https://login.microsoftonline.com',
        graph_endpoint: 'https://graph.microsoft.com/v1.0',
      }
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end
  end

  describe 'authenticate' do
    before(:each) do
      outbound_connection.config[:environment] = {
        oauth2_endpoint: 'https://oauth.xurrent-test.com',
        graphql_endpoint: 'https://graph.xurrent-test.com/',
      }
    end

    let(:request) do
      Faraday::Request.create(:get) do |req|
        req.headers = {}
      end
    end

    def create_mock_oauth_server(url = nil)
      base_url = outbound_connection.config[:environment][:oauth2_endpoint]
      url ||= "#{base_url}/#{outbound_connection.config[:credentials][:tenant_id]}/oauth2/v2.0/token"
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
        scope: 'https://graph.microsoft.com/.default',
        grant_type: 'client_credentials',
      }
    end

    def setup_oauth_server(server_response, status: 200, url: nil)
      create_mock_oauth_server(url)
        .to_return(status: status, body: server_response.to_json, headers: { foo: :bar })
        .to_return(status: 401, body: 'No 2nd call expected', headers: {})
    end

    # rubocop:disable Metrics/MethodLength
    def update_connection_schema!(*credentials_fields)
      new_config = outbound_connection.config_schema
                                      .resolve(outbound_connection, [
                                        { field_id: 'environment', nested: [
                                          { field_id: 'oauth2_endpoint',
                                            fixed: outbound_connection.config[:environment][:oauth2_endpoint], },
                                          { field_id: 'graph_endpoint',
                                            fixed: outbound_connection.config[:environment][:graph_endpoint], },
                                        ], },
                                        { field_id: 'credentials', nested: credentials_fields },
                                      ])
      outbound_connection.instance_variable_set(:@config, new_config)
    end
    # rubocop:enable Metrics/MethodLength

    describe 'tenant ID' do
      it 'defaults oauth URL' do
        outbound_connection.config[:environment].delete(:oauth2_endpoint)
        setup_oauth_server({
          access_token: 'abc',
          token_type: 'bearer',
        }, url: 'https://login.microsoftonline.com/wdc/oauth2/v2.0/token')
        outbound_connection.authenticate_request(request)

        authorization = request.headers['Authorization']
        expect(authorization).to eq('Bearer abc')
      end

      it 'uses tenant ID in oauth URL' do
        outbound_connection.config[:credentials][:tenant_id] = 'abc123'
        setup_oauth_server({
          access_token: 'abc',
          token_type: 'bearer',
        }, url: 'https://oauth.xurrent-test.com/abc123/oauth2/v2.0/token')
        outbound_connection.authenticate_request(request)

        authorization = request.headers['Authorization']
        expect(authorization).to eq('Bearer abc')
      end
    end

    describe 'client credentials' do
      it 'should raise an error when server returns 400 error' do
        setup_oauth_server({ message: 'bad request' }, status: 400)
        msg = 'Unable to authenticate to oauth.xurrent-test.com (HTTP 400)'
        expect { outbound_connection.authenticate_request(request) }.to raise_error(msg)
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
          { field_id: 'tenant_id', fixed: outbound_connection.config[:credentials][:tenant_id] },
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
end
