module IPaaS
  module Connector
    module Types
      module AnyType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            Object
          end

          def example(_field)
            'anything'
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::AnyType)
