module IPaaS
  module Connector
    module Common
      module ProcRules
        class NoMethodDefRule < ProcRule
          def initialize(...)
            super
            @methods_reported = []
            @keywords_reported = []
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

          def on_alias(_node)
            report_keyword(:alias)
          end

          def on_undef(_node)
            report_keyword(:undef)
          end

          def report_method_definition(method)
            return if @methods_reported.include?(method)

            on_invalid.call("Method definition '#{method}' not allowed.")
            @methods_reported << method
          end

          private

          def report_keyword(keyword)
            return if @keywords_reported.include?(keyword)

            @keywords_reported << keyword
            on_invalid.call("'#{keyword}' not allowed.")
          end
        end
      end
    end
  end
end
