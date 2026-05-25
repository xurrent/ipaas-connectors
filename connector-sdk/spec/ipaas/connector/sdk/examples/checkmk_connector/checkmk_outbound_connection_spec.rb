require 'spec_helper'

describe 'Checkmk Connection', :outbound_connection do
  let(:connector_id) { '019d1f4e-7837-7a72-a0b5-df0ba9a5d44f' }

  let(:outbound_connection_config) do
    {
      domain: 'myserver.example.com',
      site_name: 'mysite',
      username: 'cmkadmin',
      password: make_secret_string('secret123'),
    }
  end

  describe 'config_schema' do
    context 'domain field' do
      let(:field) { outbound_connection.config_schema.field(:domain) }

      it { expect(field.label).to eq('Domain') }
      it { expect(field.type).to eq(:string) }
      it { expect(field.required).to be_truthy }
    end

    context 'site_name field' do
      let(:field) { outbound_connection.config_schema.field(:site_name) }

      it { expect(field.label).to eq('Site name') }
      it { expect(field.type).to eq(:string) }
      it { expect(field.required).to be_truthy }
    end

    context 'username field' do
      let(:field) { outbound_connection.config_schema.field(:username) }

      it { expect(field.label).to eq('Username') }
      it { expect(field.type).to eq(:string) }
      it { expect(field.required).to be_truthy }
    end

    context 'password field' do
      let(:field) { outbound_connection.config_schema.field(:password) }

      it { expect(field.label).to eq('Password') }
      it { expect(field.type).to eq(:secret_string) }
      it { expect(field.required).to be_truthy }
    end
  end

  describe 'validation' do
    it 'is valid with all fields' do
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'domain is required' do
      outbound_connection_config.delete(:domain)
      expect(outbound_connection).not_to be_valid
    end

    it 'site_name is required' do
      outbound_connection_config.delete(:site_name)
      expect(outbound_connection).not_to be_valid
    end

    it 'username is required' do
      outbound_connection_config.delete(:username)
      expect(outbound_connection).not_to be_valid
    end

    it 'password is required' do
      outbound_connection_config.delete(:password)
      expect(outbound_connection).not_to be_valid
    end
  end
end
