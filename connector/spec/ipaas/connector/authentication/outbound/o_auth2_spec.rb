require 'spec_helper'

describe IPaaS::Connector::Authentication::Outbound::OAuth2 do
  let(:connector) do
    IPaaS::Connector::Connector.new('uuid') do
      outbound_connection do
        oauth2_authenticator
        config_schema do
          field :base_url,
                'Base URL',
                :string
        end
      end
    end
  end

  it 'should register the key' do
    expect(IPaaS::Connector::Authentication::Outbound.keys).to include(:oauth2)
  end

  describe 'schema' do
    let(:oauth2_field) do
      connector.outbound_connection.config_schema.field(:oauth2)
    end

    it 'should define the top-level OAuth 2 field' do
      expect(oauth2_field.label).to eq('OAuth 2')
      expect(oauth2_field.hint).not_to be_nil
      expect(oauth2_field.visibility).to eq('optional')
      expect(oauth2_field.fields.size).to eq(6)
    end

    it 'should define the grant type field' do
      grant_type_field = oauth2_field.field(:grant_type)
      expect(grant_type_field.label).to eq('Grant type')
      expect(grant_type_field.type).to eq(:string)
      expect(grant_type_field.required).to be_truthy
      grant_types = ['Client Credentials', 'Refresh Token']
      expect(grant_type_field.enumeration.pluck(:id)).to eq(grant_types)
    end

    it 'should define the authorization URL field' do
      username_field = oauth2_field.field(:authorization_url)
      expect(username_field.label).to eq('Authorization URL')
      expect(username_field.type).to eq(:uri)
      expect(username_field.required).to be_truthy
    end

    it 'should define the refresh token field' do
      access_token_url = oauth2_field.field(:refresh_token)
      expect(access_token_url.label).to eq('Refresh token')
      expect(access_token_url.type).to eq(:string)
      expect(access_token_url.required).to be_falsey
    end

    it 'should define the scope field' do
      scope_field = oauth2_field.field(:scope)
      expect(scope_field.label).to eq('Scope')
      expect(scope_field.type).to eq(:string)
      expect(scope_field.required).to be_falsey
      expect(scope_field.visibility).to eq('optional')
    end

    it 'should define the client ID field' do
      client_id_field = oauth2_field.field(:client_id)
      expect(client_id_field.label).to eq('Client ID')
      expect(client_id_field.type).to eq(:string)
      expect(client_id_field.required).to eq(true)
    end

    it 'should define the client secret field' do
      client_secret_field = oauth2_field.field(:client_secret)
      expect(client_secret_field.label).to eq('Client secret')
      expect(client_secret_field.type).to eq(:secret_string)
      expect(client_secret_field.required).to eq(true)
    end
  end

  describe 'authenticate' do
    let(:request) do
      Faraday::Request.create(:get) do |req|
        req.headers = {}
        req.params = { foo: 'bar', baz: 'bie' }
      end
    end

    let(:authorization_url) do
      'https://example.com/callback'
    end

    let(:connection) do
      IPaaS::Connector::Connection.parse(
        {
          uuid: 'connection-uuid',
          direction: 'outbound',
          name: 'test outbound connection',
          connector: {
            uuid: connector.uuid,
          },
          config_mapping: [
            { field_id: 'oauth2', nested: [
              { field_id: 'grant_type', fixed: 'Client Credentials' },
              { field_id: 'authorization_url', fixed: authorization_url },
            ], },
          ],
        },
      )
    end

    def create_mock_oauth_server
      stub_request(:post, authorization_url)
        .with(body: @expected_request_body,
              headers: {
                'Accept' => 'application/json',
                'Content-Type' => 'application/x-www-form-urlencoded',
                'User-Agent' => 'Xurrent iPaaS',
              })
    end

    def setup_oauth_server(server_response, status: 200)
      create_mock_oauth_server
        .to_return(status: status, body: server_response.to_json, headers: { foo: :bar })
        .to_return(status: 401, body: 'No 2nd call expected', headers: {})
    end

    def update_connection_schema!(*oauth_fields)
      new_config = connection.config_schema
                             .resolve(connection, [{ field_id: 'oauth2', nested: oauth_fields }])
      connection.instance_variable_set(:@config, new_config)
    end

    it 'should not do anything when no field value configured' do
      simple_config = IPaaS::Connector::Connection.parse(
        {
          uuid: 'connection-uuid',
          direction: 'outbound',
          name: 'test outbound connection',
          connector: {
            uuid: connector.uuid,
          },
          config_mapping: [
            { field_id: 'base_url', fixed: 'abc' },
          ],
        },
      )
      simple_config.authenticate_request(request)
      expect(request.headers['Authorization']).to be_nil
    end

    it 'should not do anything when the config is missing' do
      connection.config[:oauth2] = nil
      connection.authenticate_request(request)
      expect(request.headers['Authorization']).to be_nil
    end

    it 'should raise on unknown grant type' do
      connection.config[:oauth2][:grant_type] = 'Foo'
      expect { connection.authenticate_request(request) }.to raise_error(IPaaS::Error)
    end

    describe 'client credentials' do
      before(:each) do
        secret = make_secret_string('s3cret')
        connection.config[:oauth2][:grant_type] = 'Client Credentials'
        connection.config[:oauth2][:client_id] = 'client-ID'
        connection.config[:oauth2][:client_secret] = secret
        @expected_request_body = {
          client_id: connection.config[:oauth2][:client_id],
          client_secret: 's3cret',
          grant_type: 'client_credentials',
        }
      end

      it 'should raise an error when server returns 400 error' do
        setup_oauth_server({ message: 'bad request' }, status: 400)
        expect { connection.authenticate_request(request) }
          .to raise_error(IPaaS::Error, 'Unable to authenticate to example.com (HTTP 400)')
      end

      it 'includes the scope in the token request body when configured' do
        connection.config[:oauth2][:scope] = 'https://graph.microsoft.com/.default'
        @expected_request_body[:scope] = 'https://graph.microsoft.com/.default'
        setup_oauth_server({ access_token: 'am9objpzZWNyZXQ=', token_type: 'bearer' })

        connection.authenticate_request(request)
        expect(request.headers['Authorization']).to eq('Bearer am9objpzZWNyZXQ=')
      end

      it 'strips surrounding whitespace from the scope before sending' do
        connection.config[:oauth2][:scope] = "  https://graph.microsoft.com/.default\n"
        @expected_request_body[:scope] = 'https://graph.microsoft.com/.default'
        setup_oauth_server({ access_token: 'am9objpzZWNyZXQ=', token_type: 'bearer' })

        connection.authenticate_request(request)
        expect(request.headers['Authorization']).to eq('Bearer am9objpzZWNyZXQ=')
      end

      it 'should raise an error when token type is mac' do
        setup_oauth_server({
          access_token: 'am9objpzZWNyZXQ=',
          token_type: 'mac',
        })
        expect do
          connection.authenticate_request(request)
        end.to raise_error("Unable to authenticate, unsupported token_type: 'mac'")
      end

      it 'should raise an error when no access token is provided' do
        setup_oauth_server({ token_type: 'bearer' })
        expect do
          connection.authenticate_request(request)
        end.to raise_error('Unable to authenticate, no access_token found')
      end

      it 'should add the bearer authentication to the header when token type is bearer' do
        setup_oauth_server({
          access_token: 'am9objpzZWNyZXQ=',
          token_type: 'bearer',
        })

        connection.authenticate_request(request)
        authorization = request.headers['Authorization']
        expect(authorization).to eq('Bearer am9objpzZWNyZXQ=')
      end

      it 'should add the bearer authentication to the header when token type is missing' do
        setup_oauth_server({
          access_token: 'am9objpzZWNyZXQ=',
        })

        connection.authenticate_request(request)
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

          connection.authenticate_request(request)
          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer am9objpzZWNyZXQ=')

          request2 = Faraday::Request.create(:post) do |req|
            req.headers = {}
            req.params = { foo: 'baz' }
          end
          connection.authenticate_request(request2)
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

          connection.authenticate_request(request)
          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer 1')

          request2 = Faraday::Request.create(:post) do |req|
            req.headers = {}
            req.params = { foo: 'baz' }
          end
          connection.authenticate_request(request2)
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

          connection.authenticate_request(request)
          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer 1')

          request2 = Faraday::Request.create(:post) do |req|
            req.headers = {}
            req.params = { foo: 'baz' }
          end
          connection.authenticate_request(request2)
          authorization2 = request2.headers['Authorization']
          expect(authorization2).to eq('Bearer 2')
        end

        it 'only caches when resolved values remain the same' do
          server_response1 = {
            access_token: '1',
            token_type: 'bearer',
            expires_in: 3600,
          }
          create_mock_oauth_server
            .to_return(status: 200, body: server_response1.to_json, headers: { foo: :bar })

          connection.authenticate_request(request)
          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer 1')

          new_client_id = 'new_value'
          connection.config[:oauth2][:client_id] = new_client_id
          @expected_request_body = URI.encode_www_form({
            client_id: new_client_id,
            client_secret: 's3cret',
            grant_type: 'client_credentials',
          })
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
          connection.authenticate_request(request2)
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

        expect { connection.authenticate_request(request) }.to raise_error(IPaaS::Error)

        request2 = Faraday::Request.create(:post) do |req|
          req.headers = {}
          req.params = { foo: 'baz' }
        end
        connection.authenticate_request(request2)
        authorization2 = request2.headers['Authorization']
        expect(authorization2).to eq('Bearer 2')
      end

      it 'retrieves new token after schema update' do
        server_response1 = {
          access_token: '1',
          token_type: 'bearer',
          expires_in: 3600,
        }
        create_mock_oauth_server
          .to_return(status: 200, body: server_response1.to_json, headers: { foo: :bar })

        connection.authenticate_request(request)
        authorization = request.headers['Authorization']
        expect(authorization).to eq('Bearer 1')

        update_connection_schema!(
          { field_id: 'grant_type', fixed: connection.config[:oauth2][:grant_type] },
          { field_id: 'authorization_url', fixed: connection.config[:oauth2][:authorization_url] },
          { field_id: 'client_id', fixed: 'b' },
          { field_id: 'client_secret', fixed: make_secret_string('a').to_s },
        )
        server_response2 = {
          access_token: '2',
          token_type: 'bearer',
          expires_in: 3600,
        }
        @expected_request_body = @expected_request_body.merge(client_id: 'b', client_secret: 'a')
        create_mock_oauth_server
          .to_return(status: 200, body: server_response2.to_json, headers: {})

        request2 = Faraday::Request.create(:post) do |req|
          req.headers = {}
          req.params = { foo: 'baz' }
        end
        connection.authenticate_request(request2)
        authorization2 = request2.headers['Authorization']
        expect(authorization2).to eq('Bearer 2')
      end
    end

    describe 'refresh token' do
      before(:each) do
        secret = make_secret_string('s3cret!')
        connection.config[:oauth2][:grant_type] = 'Refresh Token'
        connection.config[:oauth2][:client_id] = 'client-ID2'
        connection.config[:oauth2][:client_secret] = secret
        connection.config[:oauth2][:refresh_token] = 'abc'
        @expected_request_body = {
          client_id: connection.config[:oauth2][:client_id],
          client_secret: 's3cret!',
          refresh_token: connection.config[:oauth2][:refresh_token],
          grant_type: 'refresh_token',
        }
      end

      it 'includes the scope in the token request body when configured' do
        connection.config[:oauth2][:scope] = 'offline_access https://graph.microsoft.com/.default'
        @expected_request_body[:scope] = 'offline_access https://graph.microsoft.com/.default'
        setup_oauth_server({ access_token: 'am9objpzZWNyZXQ=', token_type: 'bearer' })

        connection.authenticate_request(request)
        expect(request.headers['Authorization']).to eq('Bearer am9objpzZWNyZXQ=')
      end

      it 'requires refresh token to be configured' do
        update_connection_schema!(
          { field_id: 'grant_type', fixed: 'Refresh Token' },
          { field_id: 'authorization_url', fixed: connection.config[:oauth2][:authorization_url] },
          { field_id: 'client_id', fixed: connection.config[:oauth2][:client_id] },
          { field_id: 'client_secret', fixed: connection.config[:oauth2][:client_secret].to_s },
        )

        oauth2_field = connection.config_schema.field(:oauth2)
        refresh_token_field = oauth2_field.field(:refresh_token)
        expect(refresh_token_field.label).to eq('Refresh token')
        expect(refresh_token_field.type).to eq(:string)
        expect(refresh_token_field.required).to eq(true)

        # switching back to client credentials the field should no longer be required
        update_connection_schema!(
          { field_id: 'grant_type', fixed: 'Client Credentials' },
          { field_id: 'authorization_url', fixed: connection.config[:oauth2][:authorization_url] },
          { field_id: 'client_id', fixed: connection.config[:oauth2][:client_id] },
          { field_id: 'client_secret', fixed: connection.config[:oauth2][:client_secret] },
        )
        oauth2_field = connection.config_schema.field(:oauth2)
        refresh_token_field = oauth2_field.field(:refresh_token)
        expect(refresh_token_field.label).to eq('Refresh token')
        expect(refresh_token_field.type).to eq(:string)
        expect(refresh_token_field.required).to eq(false)
      end

      it 'should raise an error when server returns 400 error' do
        setup_oauth_server({ message: 'bad request' }, status: 400)
        expect { connection.authenticate_request(request) }
          .to raise_error(IPaaS::Error, 'Unable to authenticate to example.com (HTTP 400)')
      end

      it 'should raise an error when token type is mac' do
        setup_oauth_server({
          access_token: 'am9objpzZWNyZXQ=',
          token_type: 'mac',
        })
        expect do
          connection.authenticate_request(request)
        end.to raise_error("Unable to authenticate, unsupported token_type: 'mac'")
      end

      it 'should raise an error when no access token is provided' do
        setup_oauth_server({ token_type: 'bearer' })
        expect do
          connection.authenticate_request(request)
        end.to raise_error('Unable to authenticate, no access_token found')
      end

      it 'should add the bearer authentication to the header when token type is bearer' do
        setup_oauth_server({
          access_token: 'am9objpzZWNyZXQ=',
          token_type: 'bearer',
        })

        connection.authenticate_request(request)
        authorization = request.headers['Authorization']
        expect(authorization).to eq('Bearer am9objpzZWNyZXQ=')
      end

      it 'should add the bearer authentication to the header when token type is missing' do
        setup_oauth_server({
          access_token: 'am9objpzZWNyZXQ=',
        })

        connection.authenticate_request(request)
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

          connection.authenticate_request(request)
          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer am9objpzZWNyZXQ=')

          request2 = Faraday::Request.create(:post) do |req|
            req.headers = {}
            req.params = { foo: 'baz' }
          end
          connection.authenticate_request(request2)
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

          connection.authenticate_request(request)
          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer 1')

          request2 = Faraday::Request.create(:post) do |req|
            req.headers = {}
            req.params = { foo: 'baz' }
          end
          connection.authenticate_request(request2)
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

          connection.authenticate_request(request)
          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer 1')

          request2 = Faraday::Request.create(:post) do |req|
            req.headers = {}
            req.params = { foo: 'baz' }
          end
          connection.authenticate_request(request2)
          authorization2 = request2.headers['Authorization']
          expect(authorization2).to eq('Bearer 2')
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

          expect { connection.authenticate_request(request) }.to raise_error(IPaaS::Error)

          request2 = Faraday::Request.create(:post) do |req|
            req.headers = {}
            req.params = { foo: 'baz' }
          end
          connection.authenticate_request(request2)
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

          connection.authenticate_request(request)
          authorization = request.headers['Authorization']
          expect(authorization).to eq('Bearer 1')

          update_connection_schema!(
            { field_id: 'grant_type', fixed: connection.config[:oauth2][:grant_type] },
            { field_id: 'authorization_url', fixed: connection.config[:oauth2][:authorization_url] },
            { field_id: 'client_id', fixed: connection.config[:oauth2][:client_id] },
            { field_id: 'client_secret', fixed: connection.config[:oauth2][:client_secret] },
            { field_id: 'refresh_token', fixed: 'a' },
          )
          server_response2 = {
            access_token: '2',
            token_type: 'bearer',
            expires_in: 3600,
          }
          @expected_request_body = @expected_request_body.merge(refresh_token: 'a')
          create_mock_oauth_server
            .to_return(status: 200, body: server_response2.to_json, headers: {})

          request2 = Faraday::Request.create(:post) do |req|
            req.headers = {}
            req.params = { foo: 'baz' }
          end
          connection.authenticate_request(request2)
          authorization2 = request2.headers['Authorization']
          expect(authorization2).to eq('Bearer 2')
        end
      end
    end

    describe 'cache key generation' do
      def generate_key(url, body, **extra_params)
        connection.send(:create_cache_key, url, body, **extra_params)
      end

      it 'uses url' do
        keys = [
          generate_key('abc1', { foo: :bar }),
          generate_key('abc2', { foo: :bar }),
        ]
        expect(keys.uniq).to eq(keys)
      end

      it 'uses body' do
        keys = [
          generate_key('abc', { foo: :bar }),
          generate_key('abc', { foo: :baz }),
        ]
        expect(keys.uniq).to eq(keys)
      end

      it 'uses extra values' do
        keys = [
          generate_key('abc', { foo: :bar }),
          generate_key('abc', { foo: :bar }, account_id: 'wdc'),
          generate_key('abc', { foo: :bar }, account_id: 'wna-it'),
          generate_key('abc', { foo: :bar }, account_id: 'wna-it', boo: :ba),
        ]
        expect(keys.uniq).to eq(keys)
      end

      it 'should have stable key length' do
        keys = [
          generate_key('abc', { foo: :bar }),
          generate_key('abc2', { foo: :bar }, account_id: 'wdc'),
          generate_key('abc', { foo: :ba }, account_id: 'wna-it'),
          generate_key('abcadad', { foo: :bar, bar: :baz }, account_id: 'wna-it', boo: :ba),
        ]
        expect(keys.map(&:length).uniq).to contain_exactly(keys[0].length)
        # max allowed length of key column of solution_store_entries table
        max_store_key_length = 512
        expect(keys[0].length + IPaaS::Job::Cache::KEY_PREFIX.length).to be < max_store_key_length
      end
    end
  end
end
