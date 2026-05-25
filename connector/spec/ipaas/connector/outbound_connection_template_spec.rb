require 'spec_helper'

describe IPaaS::Connector::OutboundConnectionTemplate do
  let(:outbound_connection) do
    IPaaS::Connector::OutboundConnectionTemplate.new
  end

  describe 'authenticators' do
    it 'should be possible to set the api_key authenticator' do
      outbound_connection.api_key_authenticator
      expect(outbound_connection.authenticators).to include(:api_key)
    end

    it 'should be possible to set the oauth 2 authenticator' do
      outbound_connection.oauth2_authenticator
      expect(outbound_connection.authenticators).to include(:oauth2)
    end

    it 'should be possible to set multiple authenticators' do
      outbound_connection.api_key_authenticator
      outbound_connection.basic_auth_authenticator
      expect(outbound_connection.authenticators).to include(:api_key)
      expect(outbound_connection.authenticators).to include(:basic_auth)
    end
  end

  describe 'schemas' do
    it 'should define the config_schema' do
      outbound_connection.config_schema do
        field :foo, 'Foo', :string
      end
      expect(outbound_connection.config_schema).to be_an_instance_of(IPaaS::Connector::Schema)
      expect(outbound_connection.config_schema.fields.first.id).to eq(:foo)
    end

    it 'should add the default proxy server fields available to all outbound connections' do
      proxy_server_field = outbound_connection.config_schema.field(:proxy_server)
      expect(proxy_server_field.label).to eq('Proxy server')
      expect(proxy_server_field.hint).not_to be_nil
      expect(proxy_server_field.visibility).to eq('optional')

      expect(proxy_server_field.fields.size).to eq(3)
      expect(proxy_server_field.fields.map(&:id)).to eq([:host, :username, :password])
    end
  end

  describe 'functions' do
    [:authenticate].each do |function_name|
      it "should define the #{function_name} function" do
        expect(outbound_connection.send(function_name)).to be_nil
        outbound_connection.send(function_name) do
          'Hello World!'
        end
        expect(outbound_connection.send(function_name).call).to eq('Hello World!')
      end
    end
  end

  describe 'validations' do
    it 'should validate the authenticators' do
      outbound_connection.authenticators = [:foo, :api_key]
      expect(outbound_connection).not_to be_valid
      expect(outbound_connection.errors[:authenticators].first).to eq('unknown: foo.')
    end
  end
end
