module IPaaS
  module TestCase
    module Matchers
      class EndsWithMatcher
        class << self
          def matches?(actual, expected)
            return false unless actual.is_a?(String) && expected.is_a?(String)
            actual.ends_with?(expected)
          end
        end
      end
    end
  end
end
