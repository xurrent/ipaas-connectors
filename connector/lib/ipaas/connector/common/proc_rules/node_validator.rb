module IPaaS
  module Connector
    module Common
      module ProcRules
        BASIC_RULES = [
          NoConstDefRule,
          NoGlobalAccessRule,
          NoMethodDefRule,
          NoExecRule,
          ValidMethodsRule,
        ].freeze

        FIELD_RULES = [
          NoSafePresentRule,
        ].freeze

        class NodeValidator
          attr_reader :rules

          def initialize(**)
            @rules = create_rules(**)
          end

          def validate(node)
            rules.each { |rule| rule.process(node) }
          end

          def create_rules(context:, on_invalid:, field:)
            BASIC_RULES.map { |c| c.new(context, on_invalid: on_invalid) } +
              FIELD_RULES.map { |c| c.new(context, on_invalid: on_invalid, field: field) }
          end
        end
      end
    end
  end
end
