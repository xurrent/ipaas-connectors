module IPaaS
  module Connector
    module Common
      module ProcRules
        module ConstPaths
          # Nodes that reopen whatever they name. Reopening is not governed by these rules at all,
          # so no allowlist may exempt a constant reached inside one: an exempted path would
          # otherwise be usable to remove or redefine methods on the class for the whole process.
          DEFINITION_NODE_TYPES = [:casgn, :class, :module, :sclass].freeze

          # True when the path is being reopened, however the value reaches that point: testing
          # every ancestor rather than climbing a list of known wrappers means a node type nobody
          # enumerated fails closed instead of passing.
          def reopened?(node)
            node.each_ancestor.any? { |ancestor| DEFINITION_NODE_TYPES.include?(ancestor.type) }
          end

          # The last constant node of the path this node belongs to, so an inner namespace is
          # judged by the whole path rather than by the part of it that reached this node. A missing
          # parent leaves the node as its own outermost, which reports rather than exempts.
          def outermost_const(node)
            node = node.parent while node.parent&.const_type? && node.parent.children[0].equal?(node)
            node
          end

          # Constant path as symbols, root-first (`IPaaS::Job::Outbound::HTTP` → %i[IPaaS Job
          # Outbound HTTP]), or nil when the scope is not a pure constant path.
          def const_path(node)
            const_path_and_scope(node).first
          end

          # The path and whether it was written absolutely. A `::`-prefixed path bottoms out in a
          # `cbase` rather than nil and names the same constant, so both forms yield the same path.
          def const_path_and_scope(node)
            parts = []
            while node.is_a?(RuboCop::AST::Node) && node.type == :const
              parts.unshift(node.children[1])
              node = node.children[0]
            end
            return [nil, false] unless node.nil? || (node.is_a?(RuboCop::AST::Node) && node.type == :cbase)

            [parts, !node.nil?]
          end
        end
      end
    end
  end
end
