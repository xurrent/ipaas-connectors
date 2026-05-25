require 'spec_helper'

describe 'Xurrent IMR Outbound Connection', :outbound_connection do
  let(:connector_id) { '019d6d9a-3230-7355-9268-3ec5c9ce502c' }

  let(:outbound_connection_config) do
    {
      credentials: {
        api_key: make_secret_string('test-api-key'),
      },
    }
  end

  describe 'config_schema' do
    let(:config_schema) { outbound_connection.config_schema }

    context 'base_url field' do
      let(:field) { config_schema.field(:base_url) }

      it { expect(field.type).to eq(:string) }
      it { expect(field.required).to be_falsy }
      it { expect(field.hint).to include('https://www.zenduty.com') }
      it { expect(field.visibility).to eq('optional') }
    end

    context 'credentials field' do
      let(:field) { config_schema.field(:credentials) }

      it { expect(field.type).to eq(:nested) }
      it { expect(field.required).to be(true) }

      context 'api_key field' do
        let(:nested_field) { field.field(:api_key) }

        it { expect(nested_field.type).to eq(:secret_string) }
        it { expect(nested_field.required).to be(true) }
        it { expect(nested_field.hint).to eq('Xurrent IMR API token') }
      end
    end
  end

  describe 'validation' do
    it 'is valid with all credentials provided' do
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'api_key is required' do
      outbound_connection_config[:credentials].delete(:api_key)
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
    end
  end

  describe 'authenticate' do
    let(:request) do
      Faraday::Request.create(:get) do |req|
        req.headers = {}
      end
    end

    before { outbound_connection.authenticate_request(request) }

    it { expect(request.headers['Authorization']).to eq('Token test-api-key') }
    it { expect(request.headers['Content-Type']).to eq('application/json') }

    context 'with different credentials' do
      let(:outbound_connection_config) do
        {
          credentials: {
            api_key: make_secret_string('other-api-key'),
          },
        }
      end

      it { expect(request.headers['Authorization']).to eq('Token other-api-key') }
    end
  end
end
