module IPaaS
  module Connector
    module Types
      module TimeType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            Time
          end

          def resolve(resolved_value, context: nil)
            return resolved_value.to_time if resolved_value.is_a?(DateTime)
            return resolved_value unless resolved_value.is_a?(String)

            Time.parse(resolved_value)
          rescue StandardError
            resolved_value
          end

          def example(field)
            IPaaS.use_time_zone(TimeZoneType.example(field)) do
              Time.current.in_time_zone.change(hour: 12, min: 0)
            end
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::TimeType)
