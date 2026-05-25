module IPaaS
  module Connector
    module Types
      module NestedType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            Hash
          end

          def nested?
            true
          end

          def example(field)
            fields_example(field.fields)
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::NestedType)
