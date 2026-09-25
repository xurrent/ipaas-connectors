module IPaaS
  module Connector
    class Schema
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :includes, :after_update, :first_after_update_pass?

      include IPaaS::Connector::Common::Model

      # Each pass reveals one more level of the fields an after_update derives from its values,
      # and one further pass has to observe that nothing changed. GraphQL selections, the deepest
      # case, are capped at IPaaS::Job::Graphql::Schema::MAX_FIELD_DEPTH (6), so 8 leaves headroom.
      MAX_AFTER_UPDATE_PASSES = 8

      class UnsettledAfterUpdate < IPaaS::Error
      end

      attr_reader :connector
      attr_accessor :reference, :shared
      attribute :name, length: { in: 2..120 }

      schema_fields

      function :after_update

      delegate :trigger, :action, :connection, :config, :input,
               :cache_read, :cache_write, :cache_clear,
               to: :context_or_connector, allow_nil: true

      def helpers
        context_or_connector&.helpers || IPaaS::Connector::Common::Helpers.empty_for_proc
      end

      def initialize(reference, &block)
        self.reference = reference
        self.instance_eval(&block) if block
      end

      def example
        fields.filter_map do |field|
          next unless field.is_a?(Field)

          [field.id, field.example]
        end.to_h
      end

      def resolve(context, field_mapping, &block)
        # A schema marked shared is a process-global singleton (RecurrenceType): its after_update
        # mutates fields in place and validation reads those flags live, so concurrent requests
        # would contaminate each other. Resolve on a private copy to keep the template read-only.
        # #80388755.
        return deep_dup.tap { |copy| copy.shared = false }.resolve(context, field_mapping, &block) if shared?

        using_context(context) { resolve_within_context(context, field_mapping, &block) }
      end

      def shared?
        @shared == true
      end

      # explicitly regenerate the schema itself, e.g. when the trigger configuration is updated
      def regenerate(context, &block)
        using_context(context) do
          @regenerator ||= block
          if context && @regenerator
            IPaaS::Connector::Mapping::ResolvedMapping.tracking_resolution(context) do
              context.instance_exec(self, &@regenerator)
            end
          end
          nil # explicit nil as to not inadvertently return move these fields to a different schema
        end
      end

      def inspect
        inspected_name = name.present? ? " '#{name}'" : ''
        "Schema#{inspected_name} (#{reference}) - #{fields.map(&:id)}"
      end

      def deep_dup
        super.tap { |duped| duped.attributes = attributes.deep_dup }
      end

      def includes(mixin)
        unless mixin.respond_to?(:apply_schema)
          raise IPaaS::Error, "Schema extension #{mixin.name} must include IPaaS::Connector::Schema::Extension."
        end

        mixin.apply_schema(self)
      end

      # A partly unresolved schema leaves nils and UnresolvedNodes among the fields, and neither
      # answers an id.
      def field_definition(field_id)
        Array(fields).compact.detect { |f| f.try(:id).to_s == field_id.to_s }
      end

      def declares_secret_string?
        Array(fields).any? { |field| field.is_a?(Field) && field.declares_secret_string? }
      end

      # True while after_update is executing its first pass, so a connector can keep a
      # side effect (a cache invalidation, a refetch) from repeating once per pass.
      def first_after_update_pass?
        @after_update_pass.nil? || @after_update_pass <= 1
      end

      private

      def resolve_within_context(context, field_mapping, &block)
        was_resolving = @resolving
        @resolving = true
        begin
          values = resolved_mapping(context, field_mapping)
          safe_resolve(context, field_mapping, values, was_resolving, &block)
        ensure
          @resolving = was_resolving
        end
      end

      def update_values_after_update(context, field_mapping, values)
        return values unless after_update

        using_context(context) do
          proc_helper = after_update_helper(context)
          new_fields = IPaaS::Connector::Mapping::ResolvedMapping.tracking_resolution(context) do
            proc_helper.execute(self.fields, values)
          end
          self.fields = new_fields if new_fields.is_a?(Array) && new_fields.all?(Field)

          # resolve again, fields may be updated
          resolved_mapping(context, field_mapping).resolve
        end
      end

      def after_update_helper(context)
        # TODO: How to properly handle this error? It is most likely an issue in the connector itself
        on_invalid = ->(msg) { raise("Schema '#{reference}' after_update failure: #{msg}") }
        IPaaS::Connector::Common::ProcHelper.new(context, after_update, on_invalid: on_invalid, connector: connector)
      end

      def resolved_mapping(context, field_mapping)
        IPaaS::Connector::Mapping::ResolvedMapping.new(context, self.fields, field_mapping)
      end

      def safe_resolve(context, field_mapping, values, was_resolving, &block)
        begin
          values.resolve
          block&.call(values)
          values = run_after_update_passes(context, field_mapping, values, &block) if after_update && !was_resolving
        rescue StandardError, SystemStackError => e
          values.base_error = e
        end
        values
      end

      def run_after_update_passes(context, field_mapping, values, &block)
        MAX_AFTER_UPDATE_PASSES.times do |pass|
          @after_update_pass = pass + 1
          previous = values.to_hash
          values = next_after_update_values(context, field_mapping, values, &block)
          return values if values.base_error || values.to_hash == previous
        end
        fail_unsettled_after_update(values)
      ensure
        @after_update_pass = nil
      end

      def next_after_update_values(context, field_mapping, values, &block)
        update_values_after_update(context, field_mapping, values).tap { |v| block&.call(v) }
      rescue StandardError, SystemStackError => e
        values.tap { |v| v.base_error = e }
      end

      def fail_unsettled_after_update(values)
        return values if values.invalid?

        raise UnsettledAfterUpdate, "Schema '#{reference}' after_update kept changing the values over " \
                                    "#{MAX_AFTER_UPDATE_PASSES} passes, so the fields it reveals never settled"
      rescue StandardError => e
        values.tap { |v| v.base_error = e }
      end

      def using_context(context)
        return yield if context == @context

        @context = context
        begin
          yield
        ensure
          @context = nil
        end
      end

      def context_or_connector
        @context || connector
      end
    end
  end
end
