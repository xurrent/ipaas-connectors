module IPaaS
  module Connector
    module Common
      module ProcRules
        module ClassCallContext
          TEXT_CONTEXTS = [:interpolated, :stringified].freeze
          STRINGIFYING_METHODS = [:name, :to_s, :inspect].freeze
          COMPARING_METHODS = [:==, :!=, :===].freeze
          ACCUMULATING_METHODS = [:reduce, :inject].freeze
          BINDING_NODES = [:lvasgn, :ivasgn, :gvasgn, :cvasgn, :casgn, :op_asgn, :or_asgn, :and_asgn, :array, :pair,
                           :hash, :splat, :kwsplat,].freeze
          BLOCK_NODES = [:block, :numblock, :itblock].freeze

          class << self
            def permitted?(node)
              context, method_name, holder, through_block = of(node)
              # The method taking a block receives the block's value before any text around the call does.
              return false if through_block

              # log() stores its message as text, so the proc never gets hold of the class itself.
              TEXT_CONTEXTS.include?(context) || sole_log_argument?(context, method_name, holder)
            end

            def of(node)
              return [:block_pass, nil, node.parent, false] if node.block_pass_type?

              child, parent, through_block = climb(node)
              return [:returned, nil, nil, through_block] if parent.nil?

              [*context_in(child, parent), through_block]
            end

            private

            def climb(node)
              child = node
              parent = node.parent
              through_block = false
              while parent && passes_value_on?(child, parent)
                through_block ||= BLOCK_NODES.include?(parent.type)
                child = parent
                parent = parent.parent
              end
              [child, parent, through_block]
            end

            # Only a receiverless call reaches Context#log; helpers.log is connector code.
            def sole_log_argument?(context, method_name, holder)
              context == :argument && method_name == :log && holder.receiver.nil? && holder.arguments.one?
            end

            def passes_value_on?(child, parent)
              return returns_block_body?(child, parent) if BLOCK_NODES.include?(parent.type)

              case parent.type
              when :begin, :kwbegin then parent.children.last.equal?(child)
              when :when then parent.body.equal?(child)
              when :case, :if then !parent.condition.equal?(child)
              when :or then true
              when :and then parent.rhs.equal?(child)
              else false
              end
            end

            def returns_block_body?(child, block)
              block.body.equal?(child) && ACCUMULATING_METHODS.exclude?(block.method_name)
            end

            def context_in(child, parent)
              case parent.type
              when :send, :csend then call_context(child, parent)
              when :dstr, :dsym then [:interpolated, nil, parent]
              when :const then [:scope, nil, parent]
              when :case, :when then [:compared, nil, parent]
              when *BINDING_NODES then [:bound, nil, parent]
              else [:other, parent.type, parent]
              end
            end

            def call_context(child, parent)
              method_name = parent.method_name
              return [:compared, method_name, parent] if COMPARING_METHODS.include?(method_name)
              return [:argument, method_name, parent] unless parent.receiver.equal?(child)
              return [:stringified, method_name, parent] if STRINGIFYING_METHODS.include?(method_name)

              [:receiver, method_name, parent]
            end
          end
        end
      end
    end
  end
end
