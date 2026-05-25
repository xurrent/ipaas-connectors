require 'openssl'

module IPaaS
  module Encryption
    class Cipher
      CIPHER_TYPE = 'aes-256-gcm'.freeze
      EMPTY_AUTH_DATA = ''.freeze

      class << self
        def key_length
          OpenSSL::Cipher.new(CIPHER_TYPE).key_len
        end

        def iv_length
          OpenSSL::Cipher.new(CIPHER_TYPE).iv_len
        end

        def generate_random_key(length: key_length)
          SecureRandom.random_bytes(length)
        end
      end

      def initialize(secret)
        @secret = secret
      end

      def encrypt(plaintext)
        cipher, iv = create_encryption_cipher

        encrypted_data = plaintext.empty? ? plaintext.dup : cipher.update(plaintext)
        encrypted_data << cipher.final

        json = {
          k: ::Base64.strict_encode64(encrypted_data),
          iv: ::Base64.strict_encode64(iv),
          a: ::Base64.strict_encode64(cipher.auth_tag),
        }
        JSON.dump(json)
      end

      def decrypt(encrypted_data)
        json = JSON.parse(encrypted_data)

        cipher = create_decryption_cipher(json)

        encrypted_data = ::Base64.strict_decode64(json['k'])
        plaintext = encrypted_data.empty? ? encrypted_data : cipher.update(encrypted_data)
        plaintext << cipher.final

        plaintext
      rescue OpenSSL::Cipher::CipherError, TypeError, ArgumentError, JSON::ParserError => e
        raise Errors::Decryption, "Decryption failed: #{e.class.name} #{e.message}"
      end

      def inspect # :nodoc:
        "#<#{self.class.name}:#{format('%#016x', object_id << 1)}>"
      end

      private

      def create_encryption_cipher
        cipher = OpenSSL::Cipher.new(CIPHER_TYPE)
        cipher.encrypt
        cipher.key = @secret

        iv = cipher.random_iv
        cipher.iv = iv
        [cipher, iv]
      end

      def create_decryption_cipher(json)
        iv = ::Base64.strict_decode64(json['iv'])
        auth_tag = ::Base64.strict_decode64(json['a'])

        # Currently the OpenSSL bindings do not raise an error if auth_tag is
        # truncated, which would allow an attacker to easily forge it. See
        # https://github.com/ruby/openssl/issues/63
        raise Errors::EncryptedContentIntegrity if auth_tag.nil? || auth_tag.bytesize != 16

        cipher = OpenSSL::Cipher.new(CIPHER_TYPE)

        cipher.decrypt
        cipher.key = @secret
        cipher.iv = iv

        cipher.auth_tag = auth_tag
        cipher.auth_data = EMPTY_AUTH_DATA
        cipher
      end
    end
  end
end
