require 'spec_helper'

describe IPaaS::Connector::Types::SecretStringType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(IPaaS::Encryption::SecretString)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  describe 'resolve' do
    it 'should leave nils untouched' do
      expect(subject.resolve(nil)).to be_nil
    end

    it 'should leave secret strings untouched' do
      context = double(encryptor: IPaaS::Encryption::Encryptor.new)
      input_secret = make_secret_string('Hello Moon!')
      resolved = subject.resolve(input_secret, context: context)

      expect(resolved).to be(input_secret)
    end

    it 'should return secret strings' do
      context = double(encryptor: IPaaS::Encryption::Encryptor.new)
      resolved = subject.resolve(make_secret_string('Hello Moon!').to_s, context: context)
      expect(resolved).to be_a(IPaaS::Encryption::SecretString)
      expect(resolved.to_s).not_to eq('Hello Moon!')
      expect(resolved.decrypt).to eq('Hello Moon!')
      expect(context.encryptor.decrypt(resolved.to_s)).to eq('Hello Moon!')
    end

    it 'handles nil context' do
      input_secret = make_secret_string('Hello Moon!')
      resolved = subject.resolve(input_secret.to_s)

      expect(resolved).to be_a(IPaaS::Encryption::SecretString)
      expect(resolved.to_s).not_to eq('Hello Moon!')
      expect(IPaaS::Encryption::Encryptor.new.decrypt(resolved.to_s)).to eq('Hello Moon!')
    end
  end

  describe 'valid?' do
    it 'should validate secrets' do
      errors = []
      secret = make_secret_string('Hello Moon!')
      expect(subject.valid?(secret, errors)).to be_truthy
      expect(errors).to be_empty
    end

    it 'should validate blank values' do
      expect(subject.valid?(nil)).to be_truthy
      expect(subject.valid?('')).to be_truthy
      expect(subject.valid?(IPaaS::Encryption::SecretString.new(nil))).to be_truthy
      expect(subject.valid?(IPaaS::Encryption::SecretString.new(''))).to be_truthy
    end

    it 'should invalidate non-secrets' do
      expect(subject.valid?('Hello Moon!')).to be_falsey
      expect(subject.valid?(42)).to be_falsey
      not_a_drr = { not: 'a', data: 'row_record' }.to_json
      expect(subject.valid?(not_a_drr)).to be_falsey
      expect(subject.valid?(IPaaS::Encryption::SecretString.new(not_a_drr))).to be_falsey
    end

    it 'should explain the expected type when invalidating a non-secret' do
      errors = []
      subject.valid?('Hello Moon!', errors)
      expect(errors).to eq(['Expected an encrypted secret string value.'])
    end
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :secret_string)
    expect(subject.example(field)).to eq('Secret')
  end

  it 'should override inspect' do
    secret_string = make_secret_string('Hello Moon!')
    expect(secret_string.inspect).to eq('"[SecretString]"')
  end
end
