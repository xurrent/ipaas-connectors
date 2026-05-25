require 'spec_helper'

describe IPaaS::Connector::EnvironmentVariable do
  let(:string_env_hash) do
    {
      uuid: 'string_env_uuid',
      name: 'My Var',
      description: 'Test description',
      type: :string,
    }
  end

  let(:string_env) do
    IPaaS::Connector::EnvironmentVariable.parse(string_env_hash)
  end

  context 'validation' do
    it 'should be valid' do
      expect(string_env).to be_valid
    end

    it 'should validate the given value is a hash' do
      expect do
        IPaaS::Connector::EnvironmentVariable.parse([1, 2])
      end.to raise_error('EnvironmentVariable must be a hash.')
    end

    it 'should validate name is required' do
      string_env.name = nil
      expect(string_env).not_to be_valid
      expect(string_env.errors[:name]).to eq(["can't be blank."])
    end

    it 'should validate type is required' do
      string_env.type = nil
      expect(string_env).not_to be_valid
      expect(string_env.errors[:type]).to eq(["can't be blank."])
    end

    it 'should validate the type' do
      string_env.type = :not_valid
      expect(string_env).not_to be_valid
      expect(string_env.errors[:type]).to include('must be one of: string, secret_string')

      string_env.type = 'secret_string'
      expect(string_env).to be_valid
    end
  end

  context 'uuid' do
    it 'should take the given UUID' do
      expect(string_env.uuid).to eq('string_env_uuid')
    end

    it 'should generate a UUID when none is provided' do
      expect(SecureRandom).to receive(:uuid_v7) { 'foo-uuid' }
      uuid_trigger = IPaaS::Connector::EnvironmentVariable.parse({ name: 'foo' })
      expect(uuid_trigger.uuid).to eq('foo-uuid')
    end
  end

  context 'to_h' do
    it 'should define to_h' do
      expect(string_env.to_h).to eq(string_env_hash)
    end
  end

  context 'to_h_ref' do
    it 'should define to_h_ref' do
      expect(string_env.to_h_ref).to eq(string_env_hash.slice(:uuid))
    end
  end

  context 'value' do
    it 'should read the value from the solution' do
      solution = double
      value = double(value: 'my value')
      allow(solution).to receive(:environment_variable_value_for).with('string_env_uuid') { value }
      allow(string_env).to receive(:solution) { solution }
      expect(string_env.value).to eq('my value')
    end
  end
end
