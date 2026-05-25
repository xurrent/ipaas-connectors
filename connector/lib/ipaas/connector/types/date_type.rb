module IPaaS
  module Connector
    module Types
      module DateType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            Date
          end

          def resolve(resolved_value, context: nil)
            return resolved_value.to_date if resolved_value.is_a?(DateTime)
            return resolved_value unless resolved_value.is_a?(String)

            Date.parse(resolved_value)
          rescue StandardError
            resolved_value
          end

          def example(_field)
            Date.current
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::DateType)
