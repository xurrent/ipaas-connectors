require 'spec_helper'

describe IPaaS::Connector::Authentication::Outbound::ProxyServer do
  describe 'schema' do
    let(:proxy_server_field) do
      IPaaS::Connector::OutboundConnectionTemplate.new.config_schema.field(:proxy_server)
    end

    it 'should define the top-level proxy server field' do
      expect(proxy_server_field.label).to eq('Proxy server')
      expect(proxy_server_field.hint).not_to be_nil
      expect(proxy_server_field.visibility).to eq('optional')
      expect(proxy_server_field.fields.size).to eq(3)
    end

    it 'should define the host field' do
      host_field = proxy_server_field.field(:host)
      expect(host_field.label).to eq('Host')
      expect(host_field.type).to eq(:uri)
      expect(host_field.required).to be_truthy
      expect(host_field.pattern).to eq(/[^?]*/)
    end

    it 'should define the username field' do
      username_field = proxy_server_field.field(:username)
      expect(username_field.label).to eq('Username')
      expect(username_field.type).to eq(:string)
      expect(username_field.required).to be_falsey
    end

    it 'should define the password field' do
      password_field = proxy_server_field.field(:password)
      expect(password_field.label).to eq('Password')
      expect(password_field.type).to eq(:secret_string)
      expect(password_field.required).to be_falsey
    end
  end
end
