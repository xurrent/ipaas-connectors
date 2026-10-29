module IPaaS
  module Connector
    module Common
      module ProcRules
        class NoLocationKeywordRule < ProcRule
          def initialize(...)
            super
            @reported_keywords = []
          end

          def on_str(node)
            keyword = LocationKeyword.of(node)
            return if keyword.nil? || @reported_keywords.include?(keyword)

            @reported_keywords << keyword
            on_invalid.call("Keyword '#{keyword}' not allowed.")
          end
          alias on_int on_str
        end
      end
    end
  end
end
