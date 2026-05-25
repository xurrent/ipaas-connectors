require 'spec_helper'

describe IPaaS::Connector::Authentication::Outbound::BearerToken do
  let(:connector) do
    IPaaS::Connector::Connector.new('uuid') do
      outbound_connection do
        bearer_authenticator
      end
    end
  end

  it 'should register the key' do
    expect(IPaaS::Connector::Authentication::Outbound.keys).to include(:bearer)
  end

  describe 'schema' do
    let(:bearer_field) do
      connector.outbound_connection.config_schema.field(:bearer)
    end

    it 'should define the top-level basic auth field' do
      expect(bearer_field.label).to eq('Bearer token authentication')
      expect(bearer_field.hint).not_to be_nil
      expect(bearer_field.visibility).to eq('optional')
      expect(bearer_field.fields.size).to eq(1)
    end

    it 'should define the bearer_token field' do
      username_field = bearer_field.field(:bearer_token)
      expect(username_field.label).to eq('Bearer token')
      expect(username_field.type).to eq(:secret_string)
      expect(username_field.required).to be_truthy
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
            { field_id: 'bearer', nested: [
              { field_id: 'bearer_token', fixed: make_secret_string('secret').to_s },
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

    it 'should add the bearer authentication to the header' do
      connection.authenticate_request(request)
      authorization = request.headers['Authorization']
      expect(authorization).to eq('Bearer secret')
    end

    it 'should not add the bearer authentication to the header when the config is missing' do
      connection.config[:bearer] = nil
      connection.authenticate_request(request)
      expect(request.headers['Authorization']).to be_nil
    end
  end
end
