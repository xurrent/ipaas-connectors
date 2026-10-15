module IPaaS
  module Connector
    module Common
      class UnresolvedNode
        CHECKED_NODES_KEY = :ipaas_unresolved_checked_nodes

        attr_reader :unresolved_class, :message, :node

        class << self
          def for_node(node)
            reject_aliases!(node)
            new(node.tag, node)
          end

          def forget_checked_nodes!
            Thread.current[CHECKED_NODES_KEY] = nil
          end

          def within?(value)
            return value.is_a?(self) unless walkable?(value)

            !nodes_within(value, first_only: true).empty?
          end

          def symbolize(value)
            return value if within?(value)

            value&.to_s&.presence&.to_sym
          end

          def all_within(value)
            nodes_within(value, first_only: false)
          end

          private

          def walkable?(value)
            value.is_a?(Array) || value.is_a?(Hash) || Serializer::ALLOWED_CLASS_SET.include?(value.class)
          end

          def nodes_within(value, first_only:)
            found = []
            seen = Set.new.compare_by_identity
            pending = [value]
            until pending.empty?
              node = pending.pop
              next push_members(node, seen, pending) unless node.is_a?(self)

              found << node
              break if first_only
            end
            found
          end

          def push_members(value, seen, pending)
            case value
            when Array then push_array(value, seen, pending)
            when Hash then push_hash(value, seen, pending)
            else push_ivars(value, seen, pending)
            end
          end

          def push_array(array, seen, pending)
            return unless seen.add?(array)

            array.reverse_each { |member| pending << member }
          end

          def push_hash(hash, seen, pending)
            return unless seen.add?(hash)

            hash.reverse_each do |key, nested|
              pending << nested << key
            end
          end

          def push_ivars(value, seen, pending)
            return unless Serializer::ALLOWED_CLASS_SET.include?(value.class)
            return if value.instance_variables.empty? || !seen.add?(value)

            value.instance_variables.reverse_each { |name| pending << value.instance_variable_get(name) }
          end

          def reject_aliases!(node)
            return unless checked_nodes.add?(node)

            case node
            when Psych::Nodes::Alias then raise Psych::AliasesNotEnabled
            when Psych::Nodes::Sequence, Psych::Nodes::Mapping
              node.children.each { |child| reject_aliases!(child) }
            when Psych::Nodes::Scalar then nil
            else raise IPaaS::Error, "Cannot capture #{node.class}"
            end
          end

          def checked_nodes
            Thread.current[CHECKED_NODES_KEY] ||= Set.new.compare_by_identity
          end
        end

        def initialize(tag, node)
          @coder_tag = tag
          @node = node
          @unresolved_class = tag.to_s.delete_prefix('!ruby/object:').delete_prefix('!')
          @message = "could not load value of type '#{@unresolved_class}'"
        end

        def encode_with(_coder)
          raise IPaaS::Error, "#{@message}; write it with Serializer.dump to keep the original node"
        end

        def as_json(_options = nil)
          nil
        end

        def to_s
          @message
        end

        def <=>(other)
          case other
          when UnresolvedNode then message <=> other.message
          when String, Symbol then message <=> other.to_s
          end
        end

        def inspect
          "#<IPaaS::Connector::Common::UnresolvedNode #{@unresolved_class}>"
        end
      end
    end
  end
end
