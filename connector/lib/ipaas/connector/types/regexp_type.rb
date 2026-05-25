module IPaaS
  module Connector
    module Types
      module RegexpType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            Regexp
          end

          def resolve(resolved_value, context: nil)
            return resolved_value if resolved_value.is_a?(Regexp)

            Regexp.new(resolved_value.to_s)
          end

          def example(_field)
            /\A[a-z]+\z/
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::RegexpType)
