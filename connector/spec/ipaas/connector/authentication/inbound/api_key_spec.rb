require 'spec_helper'

describe IPaaS::Connector::Authentication::Inbound::ApiKey do
  let(:connector) do
    IPaaS::Connector::Connector.new('uuid') do
      inbound_connection do
        api_key_validator
      end
    end
  end

  it 'should register the key' do
    expect(IPaaS::Connector::Authentication::Inbound.keys).to include(:api_key)
  end

  describe 'schema' do
    let(:api_key_field) do
      connector.inbound_connection.config_schema.field(:api_key)
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
      expect(value_field.type).to eq(:string)
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

  describe 'validate' do
    let(:connection) do
      IPaaS::Connector::Connection.parse(
        {
          uuid: 'connection-uuid',
          direction: 'inbound',
          name: 'test inbound connection',
          connector: {
            uuid: connector.uuid,
          },
          config_mapping: [
            { field_id: 'api_key', nested: [
              { field_id: 'key', fixed: 'secret-key' },
              { field_id: 'value', fixed: 'secret_value' },
              { field_id: 'placement', fixed: 'Header' },
            ], },
          ],
        },
      )
    end

    let(:request) do
      headers = { 'HTTP_SECRET_KEY' => 'secret_value' }
      Rack::Request.new(Rack::MockRequest.env_for('https://ipaas.xurrent.com/example?foo=bar&baz=bie', headers))
    end

    it 'should accept a valid API key' do
      connection.validate_request(request)
    end

    it 'should fail the job when the header is missing' do
      connection.config[:api_key][:key] = 'other_field'
      expect(connection).to receive(:fail_job!).with('Invalid or missing API key.')
      connection.validate_request(request)
    end

    it 'should accept an api key in the query parameters' do
      connection.config[:api_key][:placement] = 'Query'
      connection.config[:api_key][:key] = 'baz'
      connection.config[:api_key][:value] = 'bie'
      connection.validate_request(request)
    end

    it 'should fail the job when the query paramter is incorrect' do
      connection.config[:api_key][:placement] = 'Query'
      connection.config[:api_key][:key] = 'foo'
      connection.config[:api_key][:secret] = 'bie'
      expect(connection).to receive(:fail_job!).with('Invalid or missing API key.')
      connection.validate_request(request)
    end
  end
end
