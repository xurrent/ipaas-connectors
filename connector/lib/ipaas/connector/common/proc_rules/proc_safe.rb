module IPaaS
  module Connector
    module Common
      module ProcRules
        module ProcSafe
          def self.registry
            @registry ||= Set.new
          end

          def proc_safe(*method_names)
            method_names.each { |name| ProcSafe.registry << name }
          end
        end
      end
    end
  end
end
