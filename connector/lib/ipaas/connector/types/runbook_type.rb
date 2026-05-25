module IPaaS
  module Connector
    module Types
      module RunbookType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            IPaaS::Connector::Runbook
          end

          def resolve(value, context: nil)
            return value if value.is_a?(IPaaS::Connector::Runbook)

            uuid = value.is_a?(Hash) ? value[:uuid] : value
            IPaaS::Connector::Runbook.by_uuid(uuid)
          end

          def example(field)
            '4a86113d-3106-4e17-8885-8ee10858030d'
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::RunbookType)
