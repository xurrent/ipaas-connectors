module IPaaS
  module Connector
    module Types
      module IntegerType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            Integer
          end

          def resolve(resolved_value, context: nil)
            resolved_value = FloatType.resolve(resolved_value)
            return resolved_value.to_i if resolved_value.is_a?(Numeric)

            resolved_value
          end

          def example(_field)
            42
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::IntegerType)
