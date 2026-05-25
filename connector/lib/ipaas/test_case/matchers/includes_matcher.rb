module IPaaS
  module TestCase
    module Matchers
      class IncludesMatcher
        class << self
          def matches?(actual, expected)
            check_inclusion(actual, expected)
          rescue StandardError
            false
          end

          private

          def check_inclusion(actual, expected)
            if actual.is_a?(Hash) && expected.is_a?(Hash)
              hash_includes?(actual, expected)
            elsif actual.is_a?(Array) && expected.is_a?(Array)
              expected.all? { |v| actual.include?(v) }
            elsif actual.respond_to?(:include?)
              actual.include?(expected)
            else
              false
            end
          end

          def hash_includes?(actual, expected)
            actual = actual.deep_symbolize_keys
            expected = expected.deep_symbolize_keys
            actual.slice(*expected.keys) == expected
          end
        end
      end
    end
  end
end
