require 'spec_helper'

describe IPaaS::Connector::InboundConnectionTemplate do
  let(:inbound_connection) do
    IPaaS::Connector::InboundConnectionTemplate.new
  end

  describe 'validators' do
    it 'should be possible to set the api_key validator' do
      inbound_connection.api_key_validator
      expect(inbound_connection.validators).to include(:api_key)
    end

    it 'should be possible to set the basic_auth validator' do
      inbound_connection.basic_auth_validator
      expect(inbound_connection.validators).to include(:basic_auth)
    end

    it 'should be possible to set multiple validators' do
      inbound_connection.api_key_validator
      inbound_connection.basic_auth_validator
      expect(inbound_connection.validators).to include(:api_key)
      expect(inbound_connection.validators).to include(:basic_auth)
    end
  end

  describe 'schemas' do
    it 'should define the config_schema' do
      inbound_connection.config_schema do
        field :foo, 'Foo', :string
      end
      expect(inbound_connection.config_schema).to be_an_instance_of(IPaaS::Connector::Schema)
      expect(inbound_connection.config_schema.fields.first.id).to eq(:foo)
    end
  end

  describe 'functions' do
    before(:each) do
      skip_function_capture_validation
    end

    [:validate].each do |function_name|
      it "should define the #{function_name} function" do
        expect(inbound_connection.send(function_name)).to be_nil
        inbound_connection.send(function_name) do
          'Hello World!'
        end
        expect(inbound_connection.send(function_name).call).to eq('Hello World!')
      end
    end
  end

  describe 'validations' do
    it 'should validate the validators' do
      inbound_connection.validators = [:foo, :api_key]
      expect(inbound_connection).not_to be_valid
      expect(inbound_connection.errors[:validators].first).to eq('unknown: foo.')
    end

    it 'should ensure the validate function is present when no out-of-the-box validators are specified' do
      inbound_connection.validators = []
      expect(inbound_connection).not_to be_valid
      error_msg = "Validate function is required, define 'validate do ... end'."
      expect(inbound_connection.errors[:validate].first).to eq(error_msg)
    end
  end
end
