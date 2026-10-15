module IPaaS
  module Connector
    module Common
      # Makes a loaded connector, and the type schemas and authentication modules every connector is built
      # from, permanently unwritable. Only plain data and the classes a connector graph is built from are
      # frozen: freezing any other object would break whatever it memoizes, so one is left as it is and
      # `unsealed` names it.
      module Sealing
        DATA_CLASSES = [String, Array, Hash, Set, Regexp, Proc, Time].freeze

        # Included by the classes a connector graph is built from, and only those: a connection-derived object
        # that a graph ever held would be left unsealed and reported, not frozen under the solution using it.
        module Member
          extend ActiveSupport::Concern

          included do
            # State the object itself writes on every use, such as validation errors.
            class_attribute :writable_ivars, instance_accessor: false,
                                             default: [:@errors, :@context_for_validation].freeze
          end

          class_methods do
            def stays_writable(*ivars)
              self.writable_ivars = (writable_ivars + ivars).freeze
            end
          end

          # Stores, before freezing, what reading this object would otherwise store the first time.
          def warm_for_seal
            store_defaults if respond_to?(:store_defaults)
          end
        end

        class << self
          def seal!(root)
            return root if root.frozen?

            reached(root, warm: true).each { |object| object.freeze if sealable?(object) }
            root
          end

          def unsealed(root)
            reached(root).reject(&:frozen?)
          end

          # Built and sealed once, while the gem loads and before any thread can see one half-made. What was
          # sealed is kept, so a check never judges a module a spec defined later.
          def seal_globals!
            @global_schemas = type_schemas.each { |schema| seal!(schema) }.freeze
            @global_modules = extension_modules.each do |extension|
              extension.helpers_definition if extension.respond_to?(:helpers_definition)
              module_state(extension).each { |state| seal!(state) }
              extension.freeze
            end.freeze
          end

          def unsealed_globals
            raise IPaaS::Error, 'The global building blocks were never sealed.' unless @global_schemas

            @global_schemas.flat_map { |schema| unsealed(schema) } +
              @global_modules.reject(&:frozen?) +
              @global_modules.flat_map { |extension| module_state(extension).flat_map { |state| unsealed(state) } }
          end

          # Without the inspect Ruby puts in it: for a connector that runs to kilobytes and can carry configured
          # values, and the class is enough to say what was refused.
          def refusal(error)
            receiver = error.receiver
            reason = Member === receiver ? '; it is shared by every solution on the connector' : '' # rubocop:disable Style/CaseEquality
            FrozenError.new("can't modify frozen #{receiver.class}#{reason}", receiver: receiver).tap do |refusal|
              refusal.set_backtrace(error.backtrace)
            end
          rescue ArgumentError # raised with no receiver: a refusal worded where it was raised
            error
          end

          private

          # Identity-keyed: a field answers `hash` and `==` itself.
          def reached(root, warm: false)
            seen = {}.compare_by_identity
            pending = [root]
            until pending.empty?
              object = pending.pop
              next if seen.key?(object) || reference?(object, root)

              seen[object] = true
              object.warm_for_seal if warm && Member === object # rubocop:disable Style/CaseEquality
              pending.concat(contents(object))
            end
            seen.keys
          end

          # A reference points at what another owner answers for: a type, a module, another connector, or the
          # proxy procs see, which answers no method a walk could ask of it.
          # rubocop:disable Style/CaseEquality
          def reference?(object, root)
            Module === object || HelpersProxy === object ||
              (IPaaS::Connector::Connector === object && !root.equal?(object))
          end

          def contents(object)
            case object
            when Member then (object.instance_variables - object.class.writable_ivars).map do |ivar|
              object.instance_variable_get(ivar)
            end
            when Hash then object.keys + object.values
            when Array, Set then object.to_a
            else []
            end
          end

          def sealable?(object)
            Member === object || DATA_CLASSES.any? { |data_class| data_class === object }
          end
          # rubocop:enable Style/CaseEquality

          def type_schemas
            IPaaS::Connector::Types.all.values.select { |type| type.respond_to?(:schema) }.map(&:schema)
          end

          # Found by what they include: a registry would miss the proxy server module, which is included into
          # every outbound connection and never registered. Module-bound, since a class may answer `include?`.
          def extension_modules
            extensions = [IPaaS::Connector::Schema::Extension, IPaaS::Connector::Authentication::Inbound::Extension,
                          IPaaS::Connector::Authentication::Outbound::Extension,]
            includes = ::Module.instance_method(:include?)
            ObjectSpace.each_object(Module).select do |candidate|
              extensions.any? { |extension| includes.bind_call(candidate, extension) }
            end
          end

          def module_state(extension)
            extension.instance_variables.map { |ivar| extension.instance_variable_get(ivar) }
          end
        end
      end
    end
  end
end
