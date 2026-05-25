require 'spec_helper'

describe 'Virima Outbound Connection', :outbound_connection do
  let(:connector_id) { '019b91f0-cfe4-7648-9d97-3854c4c0e0f0' }

  let(:outbound_connection_config) do
    {
      credentials: {
        api_key: make_secret_string('test-api-key'),
        tenant_id: 'test-tenant-id',
      },
      api_endpoint: 'https://login.virima.com',
    }
  end

  describe 'validation' do
    it 'api_key is required' do
      outbound_connection_config[:credentials].delete(:api_key)
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
    end

    it 'tenant_id is required' do
      outbound_connection_config[:credentials].delete(:tenant_id)
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
    end

    it 'api_endpoint is not required' do
      outbound_connection_config.delete(:api_endpoint)
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'api_endpoint has default value' do
      outbound_connection_config.delete(:api_endpoint)
      expect(outbound_connection.config_schema.field(:api_endpoint).default).to eq('https://login.virima.com')
    end

    it 'valid with all credentials provided' do
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end
  end

  describe 'authenticate' do
    let(:request) do
      Faraday::Request.create(:get) do |req|
        req.headers = {}
      end
    end

    it 'adds Api-Key header' do
      outbound_connection.authenticate_request(request)
      expect(request.headers['Api-Key']).to eq('test-api-key')
    end

    it 'adds Tenant-Id header' do
      outbound_connection.authenticate_request(request)
      expect(request.headers['Tenant-Id']).to eq('test-tenant-id')
    end

    it 'adds Content-Type header' do
      outbound_connection.authenticate_request(request)
      expect(request.headers['Content-Type']).to eq('application/json')
    end

    it 'decrypts the api_key secret string' do
      outbound_connection_config[:credentials][:api_key] = make_secret_string('encrypted-secret-key')
      outbound_connection.authenticate_request(request)
      expect(request.headers['Api-Key']).to eq('encrypted-secret-key')
    end
  end
end
