module IPaaS
  module Connector
    module Types
      module StringType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            String
          end

          def resolve(resolved_value, context: nil)
            return resolved_value.to_s if resolved_value.is_a?(Numeric)

            resolved_value
          end

          def example(field)
            if field.pattern
              if field.id == :url_postfix
                'webhook/endpoint'
              else
                'no-example-for-pattern'
              end
            else
              'Hello World!'
            end
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::StringType)
