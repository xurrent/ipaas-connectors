module IPaaS
  module Connector
    module Types
      module Base64Type
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            String
          end

          def resolve(resolved_value, context: nil)
            return resolved_value unless resolved_value.is_a?(::String)
            return resolved_value if base64?(resolved_value) || non_strict_base64?(resolved_value)

            encode(resolved_value) # default is strict encoding
          end

          def example(_field)
            encode('Hello World!')
          end

          private

          def encode(value)
            Base64.strict_encode64(value)
          end

          def decode(value)
            Base64.strict_decode64(value)
          end

          def base64?(value)
            encode(decode(value)) == value
          rescue ArgumentError
            false
          end

          def non_strict_base64?(value)
            Base64.encode64(Base64.decode64(value)) == value
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::Base64Type)
