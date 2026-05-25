require 'spec_helper'

describe IPaaS::Encryption::SecretString do
  describe 'encrypt' do
    it 'encrypts the given plain text' do
      secret_string = described_class.encrypt(encryptor, '123')
      expect(secret_string).to be_a(IPaaS::Encryption::SecretString)
      expect(encryptor.decrypt(secret_string)).to eq('123')
    end

    it 'same plain text gives different encrypted text' do
      secret_string1 = described_class.encrypt(encryptor, '123')
      secret_string2 = described_class.encrypt(encryptor, '123')
      expect(secret_string2.to_s).not_to eq(secret_string1.to_s)
    end

    it 'does not re-encrypt SecretString objects' do
      secret_string = described_class.encrypt(encryptor, '123')
      secret_string2 = described_class.encrypt(encryptor, secret_string)
      expect(secret_string.object_id).to eq(secret_string2.object_id)
    end

    it 'has a sanitized printable representation' do
      secret_string = described_class.encrypt(encryptor, '123')
      expect(secret_string.inspect).to eq('"[SecretString]"')
    end
  end

  describe 'usage as hash key' do
    it 'does not work if no encryptor is known' do
      encrypt = ->(value) { described_class.new(encryptor.encrypt(value)) }
      plaintext, secrets_hash = check_hash_usage(encrypt)

      plaintext.size.times do |i|
        other_plaintext = plaintext[i].dup
        other_secret = encrypt.call(other_plaintext)
        expect(secrets_hash.key?(other_secret)).not_to eq(true), "No key found for #{i}"
        expect(secrets_hash[other_secret]).not_to eq("#{i}: #{plaintext[i]}"), "Incorrect value found for #{i}"
      end
    end

    it 'can be used as a hash key' do
      encrypt = ->(value) { described_class.encrypt(encryptor, value) }
      plaintext, secrets_hash = check_hash_usage(encrypt)

      plaintext.size.times do |i|
        other_plaintext = plaintext[i].dup
        other_secret = encrypt.call(other_plaintext)
        expect(secrets_hash.key?(other_secret)).to eq(true), "No key found for #{i}"
        expect(secrets_hash[other_secret]).to eq("#{i}: #{plaintext[i]}"), "Incorrect value found for #{i}"
      end
    end

    def check_hash_usage(encrypt)
      plaintext = []
      secrets_hash = {}
      100.times do |i|
        plaintext[i] = SecureRandom.hex
        secret = encrypt.call(plaintext[i])
        secrets_hash[secret] = "#{i}: #{plaintext[i]}"
      end

      [plaintext, secrets_hash]
    end
  end

  it 'accepts nil values' do
    secret_string = described_class.encrypt(encryptor, nil)
    expect(secret_string).to be_a(IPaaS::Encryption::SecretString)
    expect(secret_string).to be_blank
    expect(secret_string.inspect).to be_nil
  end
end
