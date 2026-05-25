module IPaaS
  module TestCase
    module Matchers
      class EqualsMatcher
        class << self
          def matches?(actual, expected)
            actual == expected
          end
        end
      end
    end
  end
end
