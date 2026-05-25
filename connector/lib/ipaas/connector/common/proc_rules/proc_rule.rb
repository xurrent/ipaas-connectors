module IPaaS
  module Connector
    module Common
      module ProcRules
        class ProcRule < ::Parser::AST::Processor
          include RuboCop::AST::Traversal

          attr_accessor :context, :on_invalid

          def initialize(context, on_invalid: nil)
            super()
            @context = context
            @on_invalid = on_invalid
          end
        end
      end
    end
  end
end
