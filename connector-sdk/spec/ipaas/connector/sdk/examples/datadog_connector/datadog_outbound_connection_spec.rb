require 'spec_helper'

describe 'Datadog Outbound Connection', :outbound_connection do
  let(:connector_id) { '019ccf8a-e9c0-70ea-980c-ee7ed4fa2e80' }

  let(:outbound_connection_config) do
    {
      credentials: {
        api_key: make_secret_string('test-api-key'),
        application_key: make_secret_string('test-application-key'),
      },
      region: 'us1',
    }
  end

  describe 'config_schema' do
    let(:config_schema) { outbound_connection.config_schema }

    context 'credentials field' do
      let(:field) { config_schema.field(:credentials) }

      it { expect(field.hint).to eq('API credentials for Datadog access') }

      context 'api_key field' do
        let(:nested_field) { field.field(:api_key) }

        it { expect(nested_field.hint).to eq('Datadog API Key (keep secure)') }
      end

      context 'application_key field' do
        let(:nested_field) { field.field(:application_key) }

        it { expect(nested_field.hint).to eq('Datadog Application Key (keep secure)') }
      end
    end

    context 'region field' do
      let(:field) { config_schema.field(:region) }

      it { expect(field.hint).to eq('Datadog site/region for API access') }

      it 'enumerates all supported regions' do
        expect(field.enumeration.map { |e| e[:id] })
          .to contain_exactly('us1', 'us3', 'us5', 'eu1', 'us1-fed', 'ap1', 'ap2')
      end
    end
  end

  describe 'validation' do
    it 'api_key is required' do
      outbound_connection_config[:credentials].delete(:api_key)
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
    end

    it 'application_key is required' do
      outbound_connection_config[:credentials].delete(:application_key)
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
    end

    it 'region is required' do
      outbound_connection_config.delete(:region)
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
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

    before { outbound_connection.authenticate_request(request) }

    it { expect(request.headers['DD-API-KEY']).to eq('test-api-key') }
    it { expect(request.headers['DD-APPLICATION-KEY']).to eq('test-application-key') }
    it { expect(request.headers['Content-Type']).to eq('application/json') }

    context 'with encrypted credentials' do
      let(:outbound_connection_config) do
        {
          credentials: {
            api_key: make_secret_string('encrypted-api-key'),
            application_key: make_secret_string('encrypted-app-key'),
          },
          region: 'us1',
        }
      end

      it { expect(request.headers['DD-API-KEY']).to eq('encrypted-api-key') }
      it { expect(request.headers['DD-APPLICATION-KEY']).to eq('encrypted-app-key') }
    end
  end
end
