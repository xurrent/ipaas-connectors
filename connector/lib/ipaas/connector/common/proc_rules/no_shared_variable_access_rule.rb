module IPaaS
  module Connector
    module Common
      module ProcRules
        # Instance, class and global variables are state shared with the execution context or the
        # whole process; an expression reads and writes only its own locals. Constants are judged
        # by ValidConstantsRule.
        class NoSharedVariableAccessRule < ProcRule
          def initialize(...)
            super
            @reported = []
          end

          def on_ivar(node)
            report(node.children.first)
          end
          # A write is worse than the read, and every assignment node carries the name in the same child.
          alias on_ivasgn on_ivar
          alias on_cvar on_ivar
          alias on_cvasgn on_ivar
          alias on_gvar on_ivar
          alias on_gvasgn on_ivar

          private

          def report(name)
            return if @reported.include?(name)

            @reported << name
            on_invalid.call("Access to '#{name}' not allowed.")
          end
        end
      end
    end
  end
end
