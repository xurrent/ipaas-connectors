module IPaaS
  module Connector
    module Common
      module ProcRules
        class NoMethodDefRule < ProcRule
          def initialize(...)
            super
            @methods_reported = []
          end

          def on_defs(node)
            object, method_name, = *node
            name = method_name
            name = "#{object.children[1]}.#{method_name}" if object.type == :send

            report_method_definition(name)
          end

          def on_def(node)
            name, = *node
            report_method_definition(name)
          end

          def report_method_definition(method)
            return if @methods_reported.include?(method)

            on_invalid.call("Method definition '#{method}' not allowed.")
            @methods_reported << method
          end
        end
      end
    end
  end
end
