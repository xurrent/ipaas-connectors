module IPaaS
  module Connector
    module Types
      module HashType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            Hash
          end

          def resolve(resolved_value, context: nil)
            return resolved_value.with_indifferent_access if resolved_value.respond_to?(:with_indifferent_access)

            resolved_value
          end

          def example(_field)
            { foo: 'bar' }
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::HashType)
