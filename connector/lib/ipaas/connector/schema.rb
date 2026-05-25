module IPaaS
  module Connector
    class Schema
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :includes, :after_update

      include IPaaS::Connector::Common::Model

      attr_accessor :connector, :reference
      attribute :name, length: { in: 2..120 }

      schema_fields

      function :after_update

      delegate :trigger, :action, :connection, :config, :input,
               :helpers, :cache_read, :cache_write, :cache_clear,
               to: :context_or_connector, allow_nil: true

      def initialize(reference, &block)
        self.reference = reference
        self.instance_eval(&block) if block
      end

      def example
        fields.to_h do |field|
          [field.id, field.example]
        end
      end

      def resolve(context, field_mapping, &block)
        using_context(context) do
          was_resolving = @resolving
          @resolving = true
          begin
            values = resolved_mapping(context, field_mapping)
            safe_resolve(context, field_mapping, values, was_resolving, &block)
          ensure
            @resolving = was_resolving
          end
        end
      end

      # explicitly regenerate the schema itself, e.g. when the trigger configuration is updated
      def regenerate(context, &block)
        using_context(context) do
          @regenerator ||= block
          context.instance_exec(self, &@regenerator) if context && @regenerator
          nil # explicit nil as to not inadvertently return move these fields to a different schema
        end
      end

      def inspect
        inspected_name = name.present? ? " '#{name}'" : ''
        "Schema#{inspected_name} (#{reference}) - #{fields.map(&:id)}"
      end

      def deep_dup
        super.tap do |duped|
          duped.attributes = attributes.deep_dup
          duped.connector = connector
        end
      end

      def includes(mixin)
        unless mixin.respond_to?(:apply_schema)
          raise IPaaS::Error, "Schema extension #{mixin.name} must include IPaaS::Connector::Schema::Extension."
        end

        mixin.apply_schema(self)
      end

      def field_definition(field_id)
        fields.detect { |f| f.id.to_s == field_id.to_s }
      end

      private

      def update_values_after_update(context, field_mapping, values)
        return values unless after_update

        using_context(context) do
          # TODO: How to properly handle this error? It is most likely an issue in the connector itself
          on_invalid = ->(msg) { raise("Schema '#{reference}' after_update failure: #{msg}") }
          proc_helper = IPaaS::Connector::Common::ProcHelper.new(context, after_update, on_invalid: on_invalid)
          new_fields = proc_helper.execute(self.fields, values)
          self.fields = new_fields if new_fields.is_a?(Array) && new_fields.all?(Field)

          # resolve again, fields may be updated
          resolved_mapping(context, field_mapping).resolve
        end
      end

      def resolved_mapping(context, field_mapping)
        IPaaS::Connector::Mapping::ResolvedMapping.new(context, self.fields, field_mapping)
      end

      def safe_resolve(context, field_mapping, values, was_resolving)
        begin
          values.resolve
          yield values if block_given?
          values = update_values_after_update(context, field_mapping, values) unless was_resolving
          yield values if block_given?
        rescue StandardError => e
          values.base_error = e
        end
        values
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
