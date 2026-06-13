module IPaaS
  module Connector
    module Types
      module DateTimeType
        include IPaaS::Connector::Types::Base

        SCHEMA_REFERENCE = 'date-time-type'.freeze

        class << self
          def ruby_class
            DateTime
          end

          def resolve(resolved_value, context: nil)
            return resolve_from_hash(resolved_value) if resolved_value.is_a?(Hash)
            if resolved_value.is_a?(Time) || resolved_value.is_a?(Date) || resolved_value.is_a?(ActiveSupport::TimeWithZone)
              return resolved_value.to_datetime
            end
            return resolved_value unless resolved_value.is_a?(String)

            DateTime.parse(resolved_value)
          rescue ArgumentError, TypeError
            resolved_value
          end

          def nested?
            true
          end

          def variable_resolvable?
            true
          end

          def example(field)
            IPaaS.use_time_zone(TimeZoneType.example(field)) do
              DateTime.current.in_time_zone.change(hour: 12, min: 0)
            end
          end

          def schema
            @schema ||= IPaaS::Connector::Schema.new(SCHEMA_REFERENCE) do
              field :date, 'Date', :date,
                    required: true

              field :time, 'Time', :time,
                    required: true

              field :time_zone, 'Time Zone', :time_zone,
                    required: true
            end
          end

          private

          def resolve_from_hash(resolved_value)
            date_time = resolved_value[:date].in_time_zone(resolved_value[:time_zone])
            time = resolved_value[:time]
            date_time.change({ hour: time.hour, min: time.min, sec: time.sec }).to_datetime
          rescue StandardError
            resolved_value
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::DateTimeType)
