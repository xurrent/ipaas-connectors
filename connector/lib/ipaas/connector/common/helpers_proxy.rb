module IPaaS
  module Connector
    module Common
      # The face `helpers` presents to an authored proc. It inherits no vocabulary, so a proc
      # reaches registered helper names and nothing else; `Helpers` itself is an ordinary object
      # and would hand over the whole `Object`/`Kernel` surface.
      #
      # Dispatch resolves through the registry and calls the helper directly, so a registered name
      # can never reach a real method of the same name on `Helpers`.
      class HelpersProxy < BasicObject
        # Everything `BasicObject` provides, derived rather than listed: a list would silently miss
        # whatever a future Ruby adds, and anything still defined here never reaches
        # `method_missing`. Removed first, then only what the proxy needs is defined below.
        INHERITED_METHODS = (instance_methods(true) + private_instance_methods(true)).freeze

        # `undef_method` warns about `__send__` and `__id__` whatever the verbosity.
        # `helpers_proxy_spec` asserts nothing inherited survives, so this cannot hide a failure.
        silence_warnings { INHERITED_METHODS.each { |method_name| undef_method(method_name) } }

        # `inspect` and `to_s` exist because inspecting any object holding a proxy would otherwise
        # raise from `method_missing`.
        OWN_METHODS = [:inspect, :to_s, :respond_to?].freeze

        # Names no helper may take: the proxy's own, and the methods a proc may hand a class to —
        # a helper under one of those would receive the class the constant rules let through.
        RESERVED_NAMES = (OWN_METHODS + ProcRules::ValidConstantsRule::READ_METHODS).freeze

        def initialize(helpers)
          unless ::IPaaS::Connector::Common::Helpers === helpers # rubocop:disable Style/CaseEquality
            ::Kernel.raise ::ArgumentError, 'HelpersProxy target must be a Helpers.'
          end

          @helpers = helpers
        end

        # rubocop:disable-next Style/MissingRespondToMissing
        def method_missing(method_name, *params, **, &block)
          proc_helper = @helpers.registered_helper(method_name)
          ::Kernel.raise ::NoMethodError, "Missing helper method '#{method_name}'." unless proc_helper

          proc_helper.execute(*params, **, &block)
        end

        # rubocop:disable-next Style/OptionalBooleanParameter
        def respond_to?(method_name, _include_private = false)
          OWN_METHODS.include?(method_name) || !@helpers.registered_helper(method_name).nil?
        end

        def inspect
          "#<#{::IPaaS::Connector::Common::HelpersProxy.name}>"
        end
        alias to_s inspect
      end
    end
  end
end
