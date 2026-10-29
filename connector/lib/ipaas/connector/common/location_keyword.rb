module IPaaS
  module Connector
    module Common
      module LocationKeyword
        KEYWORDS = %w[__FILE__ __LINE__].to_set.freeze

        class << self
          def of(node)
            return unless node.str_type? || node.int_type?
            return unless node.loc.instance_of?(::Parser::Source::Map)

            name = node.source
            name if KEYWORDS.include?(name)
          end

          def keyword?(node)
            !of(node).nil?
          end
        end
      end
    end
  end
end
