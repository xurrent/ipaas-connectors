require 'spec_helper'

describe 'Lansweeper Get OAuth Refresh Token Action', :action do
  let(:connector_id) { '019b22da-f781-7c72-b3c6-5e796a404308' }
  let(:action_template_id) { '019b22da-f782-7c72-b3c6-5e796a404308' }

  describe 'input_schema' do
    it 'should have required input fields' do
      expect(action.input_schema.field(:client_id)).to be_truthy
      expect(action.input_schema.field(:client_id).required).to be_truthy
      expect(action.input_schema.field(:client_id).type).to eq(:string)

      expect(action.input_schema.field(:client_secret)).to be_truthy
      expect(action.input_schema.field(:client_secret).required).to be_truthy
      expect(action.input_schema.field(:client_secret).type).to eq(:secret_string)

      expect(action.input_schema.field(:callback_url)).to be_truthy
      expect(action.input_schema.field(:callback_url).required).to be_truthy
      expect(action.input_schema.field(:callback_url).type).to eq(:string)

      expect(action.input_schema.field(:authorization_code)).to be_truthy
      expect(action.input_schema.field(:authorization_code).required).to be_truthy
      expect(action.input_schema.field(:authorization_code).type).to eq(:string)
    end
  end

  describe 'output_schema' do
    it 'should define the output fields' do
      output_schema = action.output_schema.first

      output_schema.field(:response).tap do |field|
        expect(field.label).to eq('Response')
        expect(field.type).to eq(:nested)
        expect(field.required).to be_truthy

        expect(field.field(:status).type).to eq(:integer)
        expect(field.field(:body).type).to eq(:string)
        expect(field.field(:headers).type).to eq(:nested)
        expect(field.field(:headers).array).to be_truthy
      end

      output_schema.field(:refresh_token).tap do |field|
        expect(field.label).to eq('Refresh Token')
        expect(field.type).to eq(:secret_string)
        expect(field.required).to be_falsey
      end
    end
  end

  describe 'run' do
    let(:outbound_connection_config) do
      {
        credentials: {
          client_id: 'conn-client-id',
          client_secret: make_secret_string('conn-client-secret'),
          refresh_token: make_secret_string('conn-refresh-token'),
        },
      }
    end

    let(:action_input) do
      {
        client_id: 'test-client-id',
        client_secret: make_secret_string('test-client-secret'),
        callback_url: 'https://example.com/callback',
        authorization_code: 'test-auth-code-123',
      }
    end

    before(:each) do
      allow_any_instance_of(IPaaS::Connector::Connection).to receive(:authenticate_request) do |_connection, request|
      end
    end

    def generate_expected_url
      'https://api.lansweeper.com/api/integrations/oauth/token'
    end

    def trigger_action
      run_action(action_input)
    end

    describe 'successful token exchange' do
      it 'exchanges authorization code for tokens' do
        oauth_response = {
          access_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
          token_type: 'Bearer',
          expires_in: 3600,
          refresh_token: 'def50200e1234567890abcdef',
          scope: 'read write',
        }

        stub = stub_request(:post, generate_expected_url)
               .with(
                 body: hash_including(
                   client_id: 'test-client-id',
                   client_secret: 'test-client-secret',
                   grant_type: 'authorization_code',
                   code: 'test-auth-code-123',
                   redirect_uri: 'https://example.com/callback',
                 ),
                 headers: { 'Content-Type' => 'application/json' },
               )
               .to_return(status: 200, body: oauth_response.to_json)

        output = trigger_action

        expect(output[:response][:status]).to eq(200)
        expect(action.decrypt_secret_string(output[:refresh_token])).to eq('def50200e1234567890abcdef')

        parsed_body = JSON.parse(output[:response][:body])
        expect(parsed_body['access_token']).to eq('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...')
        expect(parsed_body['token_type']).to eq('Bearer')
        expect(parsed_body['expires_in']).to eq(3600)
        expect(parsed_body['refresh_token']).to eq('def50200e1234567890abcdef')

        expect(stub).to have_been_requested.once
      end

      it 'returns response object with status, body, and headers' do
        oauth_response = {
          access_token: 'test-access-token',
          refresh_token: 'test-refresh-token',
        }

        stub = stub_request(:post, generate_expected_url)
               .to_return(
                 status: 200,
                 body: oauth_response.to_json,
                 headers: { 'Content-Type' => 'application/json', 'X-Rate-Limit' => '100' },
               )

        output = trigger_action

        expect(output[:response]).to be_present
        expect(output[:response]).to be_a(Hash)
        expect(output[:response][:status]).to eq(200)
        expect(output[:response][:body]).to eq(oauth_response.to_json)
        expect(output[:response][:headers]).to be_an(Array)
        expect(output[:response][:headers]).to include(hash_including('name' => 'content-type',
                                                                      'value' => 'application/json'))
        expect(output[:response][:headers]).to include(hash_including('name' => 'x-rate-limit', 'value' => '100'))
        expect(action.decrypt_secret_string(output[:refresh_token])).to eq('test-refresh-token')

        expect(stub).to have_been_requested.once
      end
    end

    describe 'error handling' do
      it 'handles invalid_grant error' do
        error_response = {
          error: 'invalid_grant',
          error_description: 'The provided authorization code is invalid or expired',
        }

        stub = stub_request(:post, generate_expected_url)
               .with(headers: { 'Content-Type' => 'application/json' })
               .to_return(status: 400, body: error_response.to_json, headers: { 'Content-Type' => 'application/json' })

        output = trigger_action

        expect(output[:response][:status]).to eq(400)
        expect(action.decrypt_secret_string(output[:refresh_token])).to eq('')
        expect(stub).to have_been_requested.once
      end

      it 'handles unauthorized error' do
        error_response = {
          error: 'unauthorized_client',
          error_description: 'Client authentication failed',
        }

        stub = stub_request(:post, generate_expected_url)
               .with(headers: { 'Content-Type' => 'application/json' })
               .to_return(status: 401, body: error_response.to_json, headers: { 'Content-Type' => 'application/json' })

        output = trigger_action

        expect(output[:response][:status]).to eq(401)
        expect(action.decrypt_secret_string(output[:refresh_token])).to eq('')
        expect(stub).to have_been_requested.once
      end

      it 'fails job on non-JSON response' do
        stub = stub_request(:post, generate_expected_url)
               .with(headers: { 'Content-Type' => 'application/json' })
               .to_return(status: 500, body: 'Internal Server Error')

        expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Lansweeper GraphQL API response was not JSON/)

        expect(stub).to have_been_requested.once
      end

      it 'handles invalid client error' do
        error_response = {
          error: 'invalid_client',
          error_description: 'Client ID or secret is invalid',
        }

        stub = stub_request(:post, generate_expected_url)
               .with(headers: { 'Content-Type' => 'application/json' })
               .to_return(status: 400, body: error_response.to_json, headers: { 'Content-Type' => 'application/json' })

        output = trigger_action

        expect(output[:response][:status]).to eq(400)
        expect(action.decrypt_secret_string(output[:refresh_token])).to eq('')
        expect(stub).to have_been_requested.once
      end
    end

    describe 'rate limiting and backoff' do
      it 'raises RescheduleJob on 429 rate limit error' do
        stub = stub_request(:post, generate_expected_url)
               .with(headers: { 'Content-Type' => 'application/json' })
               .to_return(status: 429, body: 'Rate limit exceeded', headers: { 'Retry-After' => '5',
                                                                               'Content-Type' => 'text/plain', })

        expect { trigger_action }.to raise_error(IPaaS::Job::RescheduleJob, /Lansweeper API rate limit hit/)
        expect(stub).to have_been_requested.once
      end

      it 'raises RescheduleJob on 503 service unavailable error' do
        stub = stub_request(:post, generate_expected_url)
               .with(headers: { 'Content-Type' => 'application/json' })
               .to_return(status: 503, body: 'Service Temporarily Unavailable',
                          headers: { 'Content-Type' => 'text/plain' })

        expect { trigger_action }.to raise_error(IPaaS::Job::RescheduleJob, /Lansweeper API not available/)
        expect(stub).to have_been_requested.once
      end
    end

    describe 'input validation' do
      it 'requires client_id' do
        invalid_input = action_input.except(:client_id)

        expect do
          run_action(invalid_input)
        end.to raise_error(IPaaS::Error, /Field 'client_id' is required/)
      end

      it 'requires client_secret' do
        invalid_input = action_input.except(:client_secret)

        expect do
          run_action(invalid_input)
        end.to raise_error(IPaaS::Error, /Field 'client_secret' is required/)
      end

      it 'requires callback_url' do
        invalid_input = action_input.except(:callback_url)

        expect do
          run_action(invalid_input)
        end.to raise_error(IPaaS::Error, /Field 'callback_url' is required/)
      end

      it 'requires authorization_code' do
        invalid_input = action_input.except(:authorization_code)

        expect do
          run_action(invalid_input)
        end.to raise_error(IPaaS::Error, /Field 'authorization_code' is required/)
      end
    end

    describe 'secret handling' do
      it 'decrypts client secret before making request' do
        oauth_response = {
          access_token: 'test-token',
          refresh_token: 'test-refresh',
        }

        stub = stub_request(:post, generate_expected_url)
               .with(body: hash_including(client_secret: 'test-client-secret'))
               .to_return(status: 200, body: oauth_response.to_json)

        trigger_action

        expect(stub).to have_been_requested.once
      end
    end

    describe 'authentication handling' do
      it 'does not add Authorization header to token exchange request' do
        oauth_response = {
          access_token: 'test-token',
          refresh_token: 'test-refresh',
        }

        stub = stub_request(:post, generate_expected_url)
               .with(
                 body: hash_including(
                   client_id: 'test-client-id',
                   client_secret: 'test-client-secret',
                 ),
               ) do |request|
                 expect(request.headers['Authorization']).to be_nil
                 true
               end
               .to_return(status: 200, body: oauth_response.to_json)

        output = trigger_action

        expect(output[:response][:status]).to eq(200)
        expect(stub).to have_been_requested.once
      end

      it 'works without connection refresh token configured' do
        oauth_response = {
          access_token: 'new-access-token',
          refresh_token: 'new-refresh-token',
        }

        stub = stub_request(:post, generate_expected_url)
               .with(
                 body: hash_including(
                   client_id: 'test-client-id',
                   client_secret: 'test-client-secret',
                   grant_type: 'authorization_code',
                   code: 'test-auth-code-123',
                   redirect_uri: 'https://example.com/callback',
                 ),
                 headers: { 'Content-Type' => 'application/json' },
               )
               .to_return(status: 200, body: oauth_response.to_json)

        output = trigger_action

        expect(output[:response][:status]).to eq(200)
        expect(action.decrypt_secret_string(output[:refresh_token])).to eq('new-refresh-token')
        expect(stub).to have_been_requested.once
      end

      it 'uses input credentials instead of connection credentials' do
        oauth_response = {
          access_token: 'test-token',
          refresh_token: 'test-refresh',
        }

        stub = stub_request(:post, generate_expected_url)
               .with(body: hash_including(
                 client_id: 'test-client-id',
                 client_secret: 'test-client-secret',
               ))
               .to_return(status: 200, body: oauth_response.to_json)

        output = trigger_action

        expect(output[:response][:status]).to eq(200)
        expect(stub).to have_been_requested.once
      end
    end
  end
end
