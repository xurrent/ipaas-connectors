module IPaaS
  module Connector
    module Common
      module ProcRules
        class NoConstDefRule < ProcRule
          def initialize(...)
            super
            @const_assign_reported = []
          end

          def on_casgn(node)
            _, const_name = *node
            return if @const_assign_reported.include?(const_name)
            on_invalid.call("Defining a constant '#{const_name}' is not allowed.")
            @const_assign_reported << const_name
          end
        end
      end
    end
  end
end
