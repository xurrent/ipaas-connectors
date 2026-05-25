module IPaaS
  module Connector
    module Types
      module UriType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            String
          end

          def valid?(value, _errors = [])
            URI.parse(value).scheme.present?
          rescue StandardError
            false
          end

          def example(_field)
            'https://xurrent.com'
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::UriType)
