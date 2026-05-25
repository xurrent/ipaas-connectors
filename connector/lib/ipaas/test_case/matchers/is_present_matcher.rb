module IPaaS
  module TestCase
    module Matchers
      class IsPresentMatcher
        class << self
          def matches?(actual, _expected)
            actual.present?
          end
        end
      end
    end
  end
end
