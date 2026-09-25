module IPaaS
  module Connector
    module Dsl
      # The HelpersMixin module provides a DSL for defining helper methods that can be used by functions
      # in that class.
      module HelpersMixin
        extend ActiveSupport::Concern
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :helpers

        included do
          attr_accessor :helpers_definition do
            IPaaS::Connector::Common::Helpers.new(connector: (self if is_a?(IPaaS::Connector::Connector)))
          end
          validate :helpers_valid?

          # Defined on the including class, not this module: `HelpersRef` installs its own
          # `helpers` the same way, and would otherwise resolve a template to its connector.
          def helpers
            helpers_definition.for_proc
          end
        end

        def helper(name, &block)
          helpers_definition.define_helper(name, &block)
        end

        def helpers_valid?
          return if helpers_definition.valid?

          self.errors.add(:helpers, "Helpers have errors: #{helpers_definition.errors}")
        end
      end
    end
  end
end
