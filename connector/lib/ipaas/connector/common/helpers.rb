module IPaaS
  module Connector
    module Common
      class Helpers
        class << self
          # `helpers` must never answer nil: a proc would then be calling methods on `nil` rather
          # than on the proxy. Contexts with no helpers of their own get this instead.
          def empty_for_proc
            @empty_for_proc ||= new.for_proc
          end
        end

        attr_accessor :proc_helpers_by_name
        attr_reader :parent_helpers, :errors

        def initialize(context = nil, parent_helpers: nil, connector: nil)
          @context = context
          @connector = connector
          @errors = []
          self.parent_helpers = parent_helpers
          self.proc_helpers_by_name = {}.with_indifferent_access
        end

        def freeze
          for_proc
          proc_helpers_by_name.freeze
          super
        end

        def connector
          @connector || parent_helpers&.connector
        end

        # The default inspect would print the whole connector graph through @connector.
        def inspect
          "Helpers #{proc_helpers_by_name.keys}"
        end

        # `registered_helper` walks the chain, which a proxy cannot answer, so the chain must hold
        # only real Helpers. `===` rather than `is_a?`, which a proxy answers by refusing.
        # rubocop:disable-next Style/CaseEquality
        def parent_helpers=(value)
          valid = NilClass === value || Helpers === value
          raise ArgumentError, 'parent_helpers must be nil or a Helpers.' unless valid

          @parent_helpers = value
        end

        def copy_for(new_context)
          new_parent_helpers = parent_helpers&.copy_for(new_context)
          Helpers.new(new_context, parent_helpers: new_parent_helpers, connector: @connector).tap do |new_helpers|
            proc_helpers_by_name.each do |name, proc_helper|
              new_helpers.define_helper(name, &proc_helper.procedure)
            end
          end
        end

        def copy_to(new_context)
          new_helpers = copy_for(new_context).for_proc
          new_context.define_singleton_method(:helpers) { new_helpers }
        end

        def for_proc
          @for_proc ||= HelpersProxy.new(self)
        end

        def registered_helper(name)
          proc_helpers_by_name[name] || parent_helpers&.registered_helper(name)
        end

        def valid?
          errors.clear
          proc_helpers_by_name.map do |name, proc_helper|
            proc_helper.valid?.tap do |valid|
              errors << [name, proc_helper.errors] unless valid
            end
          end.detect(&:!).nil?
        end

        def define_helper(name, &block)
          if proc_helpers_by_name.frozen?
            raise FrozenError, "Helper '#{name}' cannot be defined; this connector's helpers are sealed."
          end
          # A proxy answers these itself, so a helper of the same name would never be dispatched.
          if HelpersProxy::RESERVED_NAMES.include?(name.to_sym)
            raise ArgumentError, "Helper '#{name}' is reserved; choose another name."
          end

          proc_helpers_by_name[name] = IPaaS::Connector::Common::ProcHelper.new(@context, block, connector: connector)
        end

        # Resolves through the registry rather than sending to the parent, so resolution never
        # depends on the parent answering an arbitrary name.
        def method_missing(method_name, *params, **, &block)
          proc_helper = registered_helper(method_name)
          raise NoMethodError, "Missing helper method '#{method_name}'." unless proc_helper

          proc_helper.execute(*params, **, &block)
        end

        # Asking `parent_helpers.respond_to?` answers for `NilClass` at the root of the chain,
        # claiming `to_a`, `to_h` and friends.
        def respond_to_missing?(method_name, include_private = false)
          !registered_helper(method_name).nil? || super
        end

        private

        # A copy needs its own proxy; the memoized one still points at the original.
        def initialize_copy(other)
          super
          @for_proc = nil
        end
      end
    end
  end
end
