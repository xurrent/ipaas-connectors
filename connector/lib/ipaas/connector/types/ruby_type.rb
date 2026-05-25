module IPaaS
  module Connector
    module Types
      module RubyType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            String
          end

          def resolve(resolved_value, context: nil)
            resolved_value&.to_s
          end

          def valid?(value, errors = [])
            return true if value&.to_s.blank?

            on_invalid = ->(msg) {
              errors << msg
            }

            IPaaS::Connector::Common::ProcHelper.new(Object.new, value, on_invalid: on_invalid).valid?
          end

          def example(_field)
            '(1..10).to_a.join(", ")'
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::RubyType)
