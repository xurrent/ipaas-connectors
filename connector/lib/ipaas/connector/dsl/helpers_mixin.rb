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
          attr_accessor :helpers do
            IPaaS::Connector::Common::Helpers.new
          end
          validate :helpers_valid?
        end

        def helper(name, &block)
          helpers.define_helper(name, &block)
        end

        def helpers_valid?
          return if helpers.valid?

          self.errors.add(:helpers, "Helpers have errors: #{helpers.errors}")
        end
      end
    end
  end
end
