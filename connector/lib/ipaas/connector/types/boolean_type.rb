module IPaaS
  module Connector
    module Types
      module BooleanType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            Boolean
          end

          def resolve(resolved_value, context: nil)
            resolved_value = resolved_value.downcase if resolved_value.is_a?(String)
            ActiveModel::Type::Boolean.new.cast(resolved_value)
          end

          # rubocop:disable Naming/PredicateMethod
          def example(_field)
            true
          end
          # rubocop:enable Naming/PredicateMethod
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::BooleanType)
