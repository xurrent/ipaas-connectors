module IPaaS
  module Encryption
    class Encryptor
      attr_accessor :key_provider

      def initialize(key_provider = IPaaS::Encryption::TestKeyProvider.new)
        self.key_provider = key_provider
      end

      def encrypt(plaintext)
        return plaintext if plaintext.blank?

        drk = prepare_data_row_key
        encrypted_data = Cipher.new(drk.secret).encrypt(plaintext)
        drk.secret = nil
        DataRowRecord.new(key: drk, data: encrypted_data).serialize
      end

      def decrypt(encrypted_data)
        return encrypted_data if encrypted_data.to_s.blank?

        drr = DataRowRecord.deserialize(encrypted_data)
        drk = drr.key
        encrypted_data = drr.data

        mk = key_provider.decryption_key(drk.parent_key_identifier)
        secret = Cipher.new(mk.secret).decrypt(drk.encrypted_key)
        Cipher.new(secret).decrypt(encrypted_data).force_encoding(Encoding::UTF_8)
      end

      def prepare_data_row_key
        mk = key_provider.encryption_key
        drk = CryptoKey.generate
        drk.encrypted_key = Cipher.new(mk.secret).encrypt(drk.secret)
        drk.parent_key_identifier = mk.identifier
        drk
      end
    end
  end
end
