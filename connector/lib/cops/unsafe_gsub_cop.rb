module RuboCop
  module Cop
    module Custom
      # This cop enforces using the block form of `gsub` when the replacement is a variable,
      # to preserve double backslashes.
      #
      # @example
      #   # bad
      #   str.gsub(pattern, replacement)
      #
      #   # good
      #   str.gsub(pattern) { replacement }
      #   str.gsub(pattern, 'literal_string')
      #
      class UnsafeGsub < Base
        include RangeHelp
        extend AutoCorrector

        MSG = 'Use block form of `gsub` when replacement is a variable to preserve double backslashes.'.freeze

        # @!method gsub_call?(node)
        def_node_matcher :gsub_call?, <<~PATTERN
          (send _ :gsub $_ $_)
        PATTERN

        def on_send(node)
          return unless gsub_call?(node)

          _pattern, replacement = *gsub_call?(node)
          return unless replacement.variable? || replacement.send_type?

          add_offense(node) do |corrector|
            autocorrect(corrector, node)
          end
        end

        private

        def autocorrect(corrector, node)
          _receiver, _method_name, pattern, replacement = *node

          # Remove the replacement argument and add it as a block
          corrector.remove(range_between(pattern.source_range.end_pos, replacement.source_range.end_pos))
          corrector.insert_after(node, " { #{replacement.source} }")
        end
      end
    end
  end
end
