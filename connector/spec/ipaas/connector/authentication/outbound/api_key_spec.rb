require 'spec_helper'

describe IPaaS::Connector::Authentication::Outbound::ApiKey do
  let(:connector) do
    IPaaS::Connector::Connector.new('uuid') do
      outbound_connection do
        api_key_authenticator
      end
    end
  end

  it 'should register the key' do
    expect(IPaaS::Connector::Authentication::Outbound.keys).to include(:api_key)
  end

  describe 'schema' do
    let(:api_key_field) do
      connector.outbound_connection.config_schema.field(:api_key)
    end

    it 'should define the top-level api key field' do
      expect(api_key_field.label).to eq('API key')
      expect(api_key_field.hint).not_to be_nil
      expect(api_key_field.visibility).to eq('optional')
      expect(api_key_field.fields.size).to eq(3)
    end

    it 'should define the key field' do
      key_field = api_key_field.field(:key)
      expect(key_field.label).to eq('Key')
      expect(key_field.type).to eq(:string)
      expect(key_field.required).to be_truthy
    end

    it 'should define the value field' do
      value_field = api_key_field.field(:value)
      expect(value_field.label).to eq('Value')
      expect(value_field.type).to eq(:secret_string)
      expect(value_field.required).to be_truthy
    end

    it 'should define the placement field' do
      placement_field = api_key_field.field(:placement)
      expect(placement_field.label).to eq('Placement')
      expect(placement_field.type).to eq(:string)
      expect(placement_field.required).to be_falsey
      expect(placement_field.enumeration.pluck(:id)).to eq(['Header', 'Query params']) # 'Cookie'
      expect(placement_field.default).to eq('Header')
    end
  end

  describe 'authenticate' do
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
            { field_id: 'api_key', nested: [
              { field_id: 'key', fixed: 'secret_key' },
              { field_id: 'value', fixed: make_secret_string('secret_value').to_s },
              { field_id: 'placement', fixed: 'Header' },
            ], },
          ],
        },
      )
    end

    let(:request) do
      Faraday::Request.create(:get) do |req|
        req.headers = {}
        req.params = { foo: 'bar', baz: 'bie' }
      end
    end

    it 'should add the api key to the header' do
      connection.authenticate_request(request)
      expect(request.headers['secret_key']).to eq('secret_value')
      expect(request.params[:foo]).to eq('bar')
    end

    it 'should add the api key to the query' do
      connection.config[:api_key][:placement] = 'Query'
      connection.authenticate_request(request)
      expect(request.params['secret_key']).to eq('secret_value')
      expect(request.params[:foo]).to eq('bar')
    end
  end
end
