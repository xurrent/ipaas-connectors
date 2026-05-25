module IPaaS
  module Connector
    module Common
      module ProcRules
        class NoSafePresentRule < ProcRule
          FORBIDDEN_METHODS = [:present?, :blank?].freeze

          def initialize(context, on_invalid: nil, field: nil)
            super(context, on_invalid: on_invalid)
            @field = field
            @reported_methods = []
          end

          def on_csend(node)
            _, method_name, = *node

            if FORBIDDEN_METHODS.include?(method_name) && should_validate?
              return if @reported_methods.include?(method_name)
              @reported_methods << method_name
              on_invalid.call(
                "Safe navigation with &.#{method_name} is not allowed for required boolean fields. " \
                'Use explicit nil checking instead.'
              )
            end

            super
          end

          private

          def should_validate?
            return false unless @field
            return false unless @field.try(:required)
            return false unless @field.try(:type) == :boolean

            true
          end
        end
      end
    end
  end
end
