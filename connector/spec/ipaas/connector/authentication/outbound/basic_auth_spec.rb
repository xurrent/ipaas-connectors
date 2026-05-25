require 'spec_helper'

describe IPaaS::Connector::Authentication::Outbound::BasicAuth do
  let(:connector) do
    IPaaS::Connector::Connector.new('uuid') do
      outbound_connection do
        basic_auth_authenticator
      end
    end
  end

  it 'should register the key' do
    expect(IPaaS::Connector::Authentication::Outbound.keys).to include(:basic_auth)
  end

  describe 'schema' do
    let(:basic_auth_field) do
      connector.outbound_connection.config_schema.field(:basic_auth)
    end

    it 'should define the top-level basic auth field' do
      expect(basic_auth_field.label).to eq('Basic authentication')
      expect(basic_auth_field.hint).not_to be_nil
      expect(basic_auth_field.visibility).to eq('optional')
      expect(basic_auth_field.fields.size).to eq(2)
    end

    it 'should define the username field' do
      username_field = basic_auth_field.field(:username)
      expect(username_field.label).to eq('Username')
      expect(username_field.type).to eq(:string)
      expect(username_field.required).to be_truthy
    end

    it 'should define the password field' do
      password_field = basic_auth_field.field(:password)
      expect(password_field.label).to eq('Password')
      expect(password_field.type).to eq(:secret_string)
      expect(password_field.required).to be_truthy
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
            { field_id: 'basic_auth', nested: [
              { field_id: 'username', fixed: 'john' },
              { field_id: 'password', fixed: make_secret_string('secret').to_s },
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

    it 'should add the basic authentication to the header' do
      connection.authenticate_request(request)
      authorization = request.headers['Authorization']
      expect(authorization).to eq('Basic am9objpzZWNyZXQ=')
      expect(Base64.decode64(authorization.split.last)).to eq('john:secret')
    end

    it 'should not add the basic authentication to the header when the config is missing' do
      connection.config[:basic_auth] = nil
      connection.authenticate_request(request)
      expect(request.headers['Authorization']).to be_nil
    end
  end
end
