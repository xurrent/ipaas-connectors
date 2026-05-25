module IPaaS
  module Connector
    module Types
      module RunbookVariableType
        include IPaaS::Connector::Types::Base

        class << self
          def ruby_class
            IPaaS::Connector::Schema::Field
          end

          def resolve(value, context: nil)
            value = value.id if value.is_a?(ruby_class)
            value = value[:id] || value['id'] if value.is_a?(Hash)
            value = value.to_s
            return nil if value.blank? || !context.respond_to?(:runbook)

            context.runbook.runbook_variables.detect { |variable| variable.id.to_s == value }
          end

          def example(_field)
            'id-of-runbook-variable'
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::RunbookVariableType)
