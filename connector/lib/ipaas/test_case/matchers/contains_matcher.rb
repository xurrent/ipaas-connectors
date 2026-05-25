module IPaaS
  module TestCase
    module Matchers
      class ContainsMatcher
        class << self
          def matches?(actual, expected)
            return false unless actual.is_a?(String) && expected.is_a?(String)
            actual.include?(expected)
          end
        end
      end
    end
  end
end
