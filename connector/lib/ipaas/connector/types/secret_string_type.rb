module IPaaS
  module Connector
    module Types
      module SecretStringType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            IPaaS::Encryption::SecretString
          end

          def resolve(resolved_value, context: nil)
            return nil if resolved_value.nil?
            return resolved_value if resolved_value.is_a?(ruby_class)

            ruby_class.new(resolved_value.to_s, context.try(:encryptor))
          end

          def valid?(value, errors = [])
            return true if value.blank?
            value = resolve(value) unless value.is_a?(IPaaS::Encryption::SecretString)
            IPaaS::Encryption::DataRowRecord.deserialize(value.encrypted)
            true
          rescue StandardError
            errors << 'Expected an encrypted secret string value.'
            false
          end

          def example(_field)
            'Secret'
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::SecretStringType)
