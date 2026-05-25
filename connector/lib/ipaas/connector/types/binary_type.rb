module IPaaS
  module Connector
    module Types
      module BinaryType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            String
          end

          def example(field)
            if field.pattern
              'no-example-for-pattern'
            else
              'Hello World!'
            end
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::BinaryType)
