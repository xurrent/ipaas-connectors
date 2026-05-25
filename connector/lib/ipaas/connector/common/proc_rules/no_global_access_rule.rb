module IPaaS
  module Connector
    module Common
      module ProcRules
        class NoGlobalAccessRule < ProcRule
          NOT_ALLOWED_NAMES = Set.new(Object.constants
                                    .excluding(:IO, :JWT, :URI, :JSON, :YAML)
                                    .select { |n| n.to_s.upcase == n.to_s } +
                                      [:RUBY_PATCH_LEVEL, :DATA, :ENVx])
                                 .freeze

          def initialize(...)
            super
            @const_reported = []
            @global_vars_reported = []
          end

          def on_lvasgn(node)
            _, value = *node
            visit(value)
          end

          def on_dstr(node)
            visit(node)
          end

          def on_gvar(node)
            target, = *node
            return if @global_vars_reported.include?(target)

            @global_vars_reported << target
            on_invalid.call("Access to '#{target}' not allowed.")
          end

          def on_send(node)
            target, _, *params = *node
            if target&.type == :const && report_access?(target)
              name = target.children[1]
              on_invalid.call("Calling methods on '#{name}' not allowed.")
              return
            end
            params.each { |p| visit(p) }
          end

          def visit(node)
            if node.try(:type) == :const && report_access?(node)
              name = node.children[1]
              on_invalid.call("Access to '#{name}' not allowed.")
              return
            end
            return unless node.is_a?(RuboCop::AST::Node)
            node.to_a.each { |n| visit(n) }
          end

          def report_access?(target)
            # we only check top level constants
            return false unless target.children[0].nil?

            name = target.children[1]
            return false if @const_reported.include?(name) || NOT_ALLOWED_NAMES.exclude?(name)

            @const_reported << name
            true
          end
        end
      end
    end
  end
end
