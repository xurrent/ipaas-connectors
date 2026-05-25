require_relative 'current'

module IPaaS
  module Connector
    module Common
      # Include this module to force all instances of the class to be created with a UUID
      # (universal unique identifier).
      #
      # Note that it is possible to "scope" the UUID, e.g. to be able to load different
      # versions of the same connector for each solution.
      module UuidMixin
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :uuid

        DEFAULT_SCOPE = :default

        mattr_accessor(:uuid_classes) do
          []
        end

        # Purge all registered UUID records in all classes that include the UuidMixin.
        def self.purge(except: [])
          uuid_classes.each do |uuid_class|
            uuid_class.records_by_uuid = {} unless except.include?(uuid_class)
          end
        end

        extend ActiveSupport::Concern

        included do
          IPaaS::Connector::Common::UuidMixin.uuid_classes << self

          # Store UUIDs scoped by a given context
          cattr_accessor :records_by_uuid do
            {}
          end

          attribute :uuid

          def initialize(uuid, &block)
            initialize_uuid(uuid)
            instance_eval(&block) if block
          end

          class << self
            # Sets the UUID scope context for all operations within the provided block.
            # Creating and querying instances of UuidMixin-included-classes will be isolated to that particular scope.
            #
            # This makes it possible to load multiple versions of the same connector (same UUID) at once, but
            # in different scopes (e.g. scoped by solution).
            #
            # The scope is thread-local and is automatically restored after the block finishes,
            # even if an error is raised.
            #
            # When called without a block, this method simply returns the current UUID scope.
            #
            # @param scope [Symbol, Hash, nil] The UUID scope to apply.
            # @yield Runs the block with the given UUID scope in effect.
            # @return [Object] The current UUID scope if no block is given, or the result of the block.
            #
            # @example Get the current scope:
            #   current_scope = IPaaS::Connector::Connector.uuid_scope
            #
            # @example Temporarily set a scope:
            #   IPaaS::Connector::Connector.uuid_scope(:foo) do
            #     MyConnector.new("abc-123")
            #   end
            #
            # @example Provide a scope as a hash (clearing provided hash will remove all loaded records from the scope):
            #   IPaaS::Connector::Connector.uuid_scope({}) do
            #     MyConnector.new("abc-123")
            #   end
            def uuid_scope(scope = nil)
              current_scope = IPaaS::Connector::Common::Current.uuid_scope
              return current_scope unless block_given?

              IPaaS::Connector::Common::Current.uuid_scope = scope
              yield
            ensure
              IPaaS::Connector::Common::Current.uuid_scope = current_scope
            end

            def all
              scoped_records_by_uuid.values
            end

            def first
              all.first
            end

            def find_each(&block)
              all.each(&block)
            end

            # Retrieve an instance by UUID within the current scope
            def by_uuid(uuid)
              scoped_records_by_uuid[uuid]
            end

            def find(uuid)
              by_uuid(uuid)
            end

            def add_record_by_uuid(record)
              scoped_records_by_uuid[record.uuid] = record
            end

            def scoped_records_by_uuid
              return uuid_scope[self.model_name] ||= {} if uuid_scope.is_a?(Hash)

              records_by_uuid[uuid_scope] ||= {}
            end

            def uuid_scope_postfix_for_error_msg
              scope = uuid_scope
              return ', in default scope' if scope == DEFAULT_SCOPE

              scope_str = scope.to_s
              scope_str = scope.to_h { |k, v| [k.to_s, v.is_a?(Hash) ? v.keys : v.to_s] } if scope.is_a?(Hash)

              ", in scope: #{scope_str}"
            end
          end

          private

          # Initialize the UUID within the specified scope
          def initialize_uuid(uuid)
            if self.class.scoped_records_by_uuid.key?(uuid)
              message = "Duplicate #{self.class.model_name.human.titleize} UUID: #{uuid}"
              raise IPaaS::Error, "#{message}#{self.class.uuid_scope_postfix_for_error_msg}."
            end

            @uuid = uuid
            self.class.add_record_by_uuid(self)
          end
        end
      end
    end
  end
end
