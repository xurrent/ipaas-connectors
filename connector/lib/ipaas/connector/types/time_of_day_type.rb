module IPaaS
  module Connector
    module Types
      module TimeOfDayType
        include IPaaS::Connector::Types::Base

        TIME_OF_DAY = /\A([012]?\d):([012345]?\d)(?::([012345]?\d))?(?:\.(\d+))?\z/

        class << self
          def ruby_class
            String
          end

          def resolve(resolved_value, context: nil)
            if resolved_value.respond_to?(:hour)
              result = [:hour, :min, :sec].map { |v| padded_number(resolved_value.send(v)) }.join(':')
              result << ".#{resolved_value.nsec}" if resolved_value.nsec > 0
              result
            else
              resolved_value.to_s
            end
          end

          def valid?(value, _errors = [])
            return false unless value.match?(TIME_OF_DAY)

            hours, minutes, seconds, _fraction = value.match(TIME_OF_DAY).captures
            hours.to_i < 25 && minutes.to_i < 60 && seconds.to_i < 60
          end

          def example(_field)
            '14:23:50'
          end

          def padded_number(value)
            value.to_s.rjust(2, '0')
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::TimeOfDayType)
