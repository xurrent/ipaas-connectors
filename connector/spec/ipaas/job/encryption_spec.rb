require 'spec_helper'

describe IPaaS::Job::Encryption do
  class TestContext
    include IPaaS::Job::Context
  end

  let(:context) { TestContext.new }

  let(:schema) do
    IPaaS::Connector::Schema.new('reference')
  end

  class MyTestKeyProvider < IPaaS::Encryption::TestKeyProvider
    def secret
      'y' * 32
    end
  end

  let(:encryptor) do
    IPaaS::Encryption::Encryptor.new(MyTestKeyProvider.new)
  end

  describe 'decrypt_secret_string' do
    it 'decrypts secret string objects' do
      obj = context.send(:make_secret_string, 'foo')
      expect(obj.encrypted).not_to eq('foo')
      expect(context.decrypt_secret_string(obj)).to eq('foo')
      expect(obj.decrypt).to eq('foo')
    end

    it 'decrypts encrypted strings' do
      obj = context.send(:make_secret_string, 'foo')
      expect(obj.encrypted).not_to eq('foo')
      expect(context.decrypt_secret_string(obj.encrypted)).to eq('foo')
    end

    it 'decrypts secret string objects that do not have an encryptor already' do
      obj = context.send(:make_secret_string, 'foo')
      obj.encryptor = nil
      expect(obj.encrypted).not_to eq('foo')
      expect { obj.decrypt }.to raise_error(RuntimeError)

      expect(context.decrypt_secret_string(obj)).to eq('foo')
    end
  end

  describe 'hash_with_encrypted_secrets' do
    it 'encrypts fields in the hash' do
      schema.field :foo, 'Foo', :nested do
        field :bar, 'Bar', :secret_string
        field :baz, 'Baz', :string
      end

      context.encryptor = encryptor
      result = context.send(:hash_with_encrypted_secrets, { foo: { bar: 'barry', baz: 'bazzy', quux: 'quuxxy' } },
                            schema)
      foo = result[:foo]
      expect(foo[:bar]).to be_a(IPaaS::Encryption::SecretString)
      expect(encryptor.decrypt(foo[:bar])).to eq('barry')

      # Decryption should fail with a different encryptor
      expect do
        IPaaS::Encryption::Encryptor.new.decrypt(foo[:bar])
      end.to raise_error(IPaaS::Encryption::Errors::Decryption)

      expect(foo[:baz]).to eq('bazzy')
      expect(foo[:quux]).to eq('quuxxy')
    end

    it 'encrypts fields in a hash with indifferent access' do
      schema.field :foo, 'Foo', :nested do
        field :bar, 'Bar', :secret_string
      end

      context.encryptor = encryptor
      result = context.send(:hash_with_encrypted_secrets, { foo: { bar: 'barry' } }.with_indifferent_access, schema)
      expect(encryptor.decrypt(result[:foo][:bar])).to eq('barry')
    end

    context 'on a Ruby action output holding a value the field check will reject' do
      let(:output) { {}.with_indifferent_access }

      def encrypt_on_worker_thread
        Thread.new do
          Thread.current.report_on_exception = false
          context.send(:hash_with_encrypted_secrets, output, schema)
        end.value
      end

      it 'does not overflow on a value that contains itself' do
        schema.field :data, 'Data', :any
        output[:data] = []
        output[:data] << output[:data]

        expect { encrypt_on_worker_thread }.not_to raise_error
      end

      it 'does not overflow on a value nested far too deeply' do
        schema.field :data, 'Data', :any
        output[:data] = []
        (IPaaS::Connector::Mapping::NestingCheck::MAX_DEPTH * 10).times.reduce(output[:data]) do |inner, _|
          [].tap { |deeper| inner << deeper }
        end

        expect { encrypt_on_worker_thread }.not_to raise_error
      end

      it 'does not overflow on an array field whose element contains itself, though it rebuilds the array' do
        schema.field :items, 'Items', :any, array: true
        output[:items] = [[]]
        output[:items].first << output[:items].first

        expect { encrypt_on_worker_thread }.not_to raise_error
      end

      it 'hands the value on as it is, for the field check to reject' do
        schema.field :data, 'Data', :any
        output[:data] = []
        output[:data] << output[:data]
        data = output[:data]

        expect(encrypt_on_worker_thread[:data]).to equal(data)
      end
    end

    it 'encrypts fields in arrays' do
      schema.field :foo, 'Foo', :nested, array: true do
        field :bar, 'Bar', :secret_string
        field :baz, 'Baz', :secret_string, array: true
        field :quux, 'Quux', :string, array: true
      end

      input = { foo: [
        { bar: 'bar1', baz: %w[baz1a baz1b], quux: ['quux1a'] },
        { bar: 'bar2', baz: [], quux: ['quux2a'] },
      ] }

      context.encryptor = encryptor
      result = context.send(:hash_with_encrypted_secrets, input, schema)

      foo = result[:foo]
      expect(foo.pluck(:bar).map { |f| encryptor.decrypt(f) }).to eq(%w[bar1 bar2])
      expect(foo.pluck(:baz).flatten.map { |f| encryptor.decrypt(f) }).to eq(%w[baz1a baz1b])
      expect(foo.pluck(:quux).flatten).to eq(%w[quux1a quux2a])
    end
  end
end
