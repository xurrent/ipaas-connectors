module IPaaS
  module Connector
    module Common
      module ProcRules
        # Exceptions must be able to propagate out of authored procs: runtimes that execute
        # them enforce wall-clock deadlines by interrupting the proc with a non-StandardError
        # exception. We only allow literal classes in rescue block so we can validate whether they
        # are allowed via ValidConstantsRule.
        class NoRescueExceptionRule < ProcRule
          def initialize(...)
            super
            @reported = []
          end

          def on_resbody(node)
            exception_classes, _assignment, _body = *node
            return if exception_classes.nil? # bare `rescue` catches StandardError only

            exception_classes.children.each { |entry| validate_rescued_class(entry) }
          end

          def on_ensure(_node)
            report("'ensure' is not allowed.")
          end

          private

          def validate_rescued_class(entry)
            return if entry.type == :const

            report("'rescue' requires literal error classes, e.g. 'rescue StandardError'.")
          end

          def report(message)
            return if @reported.include?(message)

            @reported << message
            on_invalid.call(message)
          end
        end
      end
    end
  end
end
