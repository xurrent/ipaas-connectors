require 'spec_helper'

describe 'Raynet Connection', :outbound_connection do
  let(:connector_id) { '019e2b9d-de23-7092-94c3-1125dfc31d59' }

  let(:outbound_connection_config) do
    {
      instance: 'xurrent-demo-01',
      api_key: make_secret_string('5cf76a53-c347-4ec7-bc7f-4f720eb49680'),
    }
  end

  describe 'config_schema' do
    context 'instance field' do
      let(:field) { outbound_connection.config_schema.field(:instance) }

      it { expect(field.label).to eq('Instance') }
      it { expect(field.type).to eq(:string) }
      it { expect(field.required).to be_truthy }
    end

    context 'api_key field' do
      let(:field) { outbound_connection.config_schema.field(:api_key) }

      it { expect(field.label).to eq('API key') }
      it { expect(field.type).to eq(:secret_string) }
      it { expect(field.required).to be_truthy }
    end
  end

  describe 'validation' do
    it 'is valid with all fields' do
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'instance is required' do
      outbound_connection_config.delete(:instance)
      expect(outbound_connection).not_to be_valid
    end

    it 'api_key is required' do
      outbound_connection_config.delete(:api_key)
      expect(outbound_connection).not_to be_valid
    end
  end
end
