module IPaaS
  module Connector
    module Common
      module ProcRules
        BASIC_RULES = [
          NoConstDefRule,
          ValidConstantsRule,
          NoSharedVariableAccessRule,
          NoMethodDefRule,
          NoExecRule,
          NoRescueExceptionRule,
          ValidMethodsRule,
        ].freeze

        FIELD_RULES = [
          NoSafePresentRule,
        ].freeze

        class NodeValidator
          attr_reader :rules, :procedure

          def initialize(procedure: nil, **)
            @procedure = procedure
            @rules = create_rules(**)
          end

          def validate(node)
            rules.each { |rule| rule.process(node) }
          end

          def create_rules(context:, on_invalid:, field:)
            BASIC_RULES.map { |c| build(c, context, on_invalid) } +
              FIELD_RULES.map { |c| c.new(context, on_invalid: on_invalid, field: field) }
          end

          private

          # The constants a block may read depend on the file it was written in, so that rule alone
          # is handed the block; no other rule gets to read it by accident.
          def build(rule_class, context, on_invalid)
            if rule_class == ValidConstantsRule
              rule_class.new(context, on_invalid: on_invalid, procedure: procedure)
            else
              rule_class.new(context, on_invalid: on_invalid)
            end
          end
        end
      end
    end
  end
end
