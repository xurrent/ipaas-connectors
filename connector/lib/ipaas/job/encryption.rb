module IPaaS
  module Job
    module Encryption
      extend ActiveSupport::Concern
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :make_secret_string, :new_secret_string, :decrypt_secret_string

      attr_writer :encryptor

      def make_secret_string(plain)
        IPaaS::Encryption::SecretString.encrypt(encryptor, plain)
      end

      def new_secret_string(serialized_secret)
        IPaaS::Encryption::SecretString.new(serialized_secret, encryptor)
      end

      def decrypt_secret_string(secret_string)
        unless secret_string.is_a?(IPaaS::Encryption::SecretString)
          secret_string = IPaaS::Encryption::SecretString.new(secret_string, encryptor)
        end
        if secret_string.encryptor
          secret_string.decrypt
        else
          encryptor.decrypt(secret_string.encrypted)
        end
      end

      private

      def hash_with_encrypted_secrets(value, schema)
        return value unless value.is_a?(Hash)

        value.each do |key, v|
          field = schema.field(key)
          value[key] = field_with_encrypted_secrets(v, field) if field
        end
      end

      def encryptor
        @encryptor ||= IPaaS::Encryption::Encryptor.new
      end

      def array_with_encrypted_secrets(values, field)
        return values unless values.is_a?(Array)

        values.map do |value|
          if field.type == :nested
            hash_with_encrypted_secrets(value, field)
          elsif field.type == :secret_string
            IPaaS::Encryption::SecretString.encrypt(encryptor, value)
          else
            value
          end
        end
      end

      def field_with_encrypted_secrets(value, field)
        if field.array
          array_with_encrypted_secrets(value, field)
        elsif field.type == :nested
          hash_with_encrypted_secrets(value, field)
        elsif field.type == :secret_string
          IPaaS::Encryption::SecretString.encrypt(encryptor, value)
        else
          value
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Encryption)
