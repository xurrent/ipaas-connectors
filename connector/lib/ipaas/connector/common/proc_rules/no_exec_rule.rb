module IPaaS
  module Connector
    module Common
      module ProcRules
        class NoExecRule < ProcRule
          def initialize(...)
            super
            @exec_reported = false
          end

          def on_xstr(_node)
            return if @exec_reported

            @exec_reported = true
            on_invalid.call('Running a program is not allowed.')
          end
        end
      end
    end
  end
end
