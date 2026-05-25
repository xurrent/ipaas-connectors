module IPaaS
  module Encryption
    class TestKms
      def encrypt(plaintext, kms_key_arn)
        cipher(kms_key_arn).encrypt(plaintext)
      end

      def decrypt(ciphertext, kms_key_arn)
        cipher(kms_key_arn).decrypt(ciphertext)
      end

      private

      def cipher(kms_key_arn)
        secret = kms_key_arn + ('k' * 32)
        IPaaS::Encryption::Cipher.new(secret[0...32])
      end
    end
  end
end
