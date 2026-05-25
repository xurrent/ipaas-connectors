module IPaaS
  module Connector
    module Types
      module FloatType
        include IPaaS::Connector::Types::Base

        FLOAT = /\A-?[0-9]+(\.[0-9]+)?\z/

        class << self
          def ruby_class
            Float
          end

          def resolve(resolved_value, context: nil)
            return resolved_value.to_f if resolved_value.is_a?(Numeric)
            return resolved_value.to_f if resolved_value.is_a?(String) && resolved_value.match?(FLOAT)

            resolved_value
          end

          def example(_field)
            3.14159265359
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::FloatType)
