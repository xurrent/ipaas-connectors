module IPaaS
  module Connector
    module Mapping
      class NestingCheck
        MAX_DEPTH = JSON::State.new.max_nesting
        LEAVE = Object.new.freeze

        class << self
          def problem(value, max_depth: MAX_DEPTH)
            return unless collection?(value)

            new(value, max_depth).problem
          end

          def collection?(value)
            value.is_a?(Array) || value.is_a?(Hash)
          end
        end

        def initialize(value, max_depth)
          @max_depth = max_depth
          @pending = [value]
          @entered = Set.new.compare_by_identity
          @heights = {}.compare_by_identity
          @path_heights = [0]
        end

        def problem
          until @pending.empty?
            node = @pending.pop
            next leave(@pending.pop) if node.equal?(LEAVE)

            found = visit(node)
            return found if found
          end
          nil
        end

        private

        def visit(node)
          return revisit(@heights[node]) if @heights.key?(node)
          return :contains_itself unless @entered.add?(node)
          return :too_deep if depth >= @max_depth

          enter(node)
          nil
        end

        def revisit(height)
          return :too_deep if depth + height > @max_depth

          note_height(height)
          nil
        end

        def enter(node)
          @path_heights << 0
          @pending << node << LEAVE
          return node.each { |member| push(member) } unless node.is_a?(Hash)

          node.each do |key, member|
            push(key)
            push(member)
          end
        end

        def leave(node)
          height = @path_heights.pop + 1
          @heights[node] = height
          note_height(height)
        end

        def note_height(height)
          @path_heights[-1] = height if height > @path_heights[-1]
        end

        def depth
          @path_heights.size - 1
        end

        def push(member)
          @pending << member if self.class.collection?(member)
        end
      end
    end
  end
end
