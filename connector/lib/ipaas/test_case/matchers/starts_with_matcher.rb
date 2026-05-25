module IPaaS
  module TestCase
    module Matchers
      class StartsWithMatcher
        class << self
          def matches?(actual, expected)
            return false unless actual.is_a?(String) && expected.is_a?(String)
            actual.starts_with?(expected)
          end
        end
      end
    end
  end
end
