module IPaaS
  module Connector
    module Dsl
      module SchemaMixin
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :schema, :field, :config_schema, :input_schema, :iteration_state_schema,
                  :output_schema, :output_schemas, :schema_reference, :regenerate_schema

        def self.original_accessor(name)
          :"_#{name}"
        end

        def self.schema_blocks_accessor(name)
          :"_#{name}_blocks_by_reference"
        end

        extend ActiveSupport::Concern

        included do
          # Defines a schema attribute for the class. If the schema is an array, it supports multiple schemas.
          # It also validates the schemas to ensure they are correctly defined.
          #
          # @param name [Symbol] the name of the schema attribute
          # @param array [Boolean] whether the schema is an array of schemas
          # @param default_fields [Proc] optional block to define default fields for the schema
          def self.schema(name, array: false, &default_fields)
            raise IPaaS::Error, "#{name} already defined" if self.respond_to?(name)

            attribute(name,
                      type: array ? [IPaaS::Connector::Schema] : IPaaS::Connector::Schema,
                      default: array ? [] : nil)
            attribute SchemaMixin.schema_blocks_accessor(name),
                      type: Hash,
                      default: {}

            # Make default_fields accessible at class level for lazy schema generation on instances
            define_singleton_method(:"_#{name}_default_fields") { default_fields }

            # remember the original attribute getter method and override with new behaviour
            alias_method(SchemaMixin.original_accessor(name), name)
            define_method(name) do |reference = nil, &block|
              if block
                reference ||= name.to_s.gsub('_schema', '')
                self.send(SchemaMixin.schema_blocks_accessor(name))[reference] = block
                generate_schema(name, reference, default_fields, array)
              else
                retrieve_schema(name, reference, default_fields, array)
              end
            end

            # for arrays also define the plural method for convenience
            # ```
            #   class Test do schema(:output_schema, array: true) end
            #   t = Test.new
            #   output_schema1 = t.output_schema 'reference1' do ... end
            #   output_schema2 = t.output_schema 'reference2' do ... end
            #   t.output_schemas == [output_schema1, output_schema2]
            # ```
            if array
              define_method(name.to_s.pluralize) do
                ensure_schemas_generated(name, default_fields)
              end
            end

            validate do |record|
              Array(record.send(:original_value, name)).each do |schema|
                unless schema.errors.none? && schema.valid?
                  self.errors.add(name, "Schema (#{schema.reference}) invalid: #{schema.full_error_messages}")
                end
              end
            end
          end

          # Add the fields attribute to the class.
          # It validates the fields to ensure they are correctly defined and handles various field attributes.
          def self.schema_fields
            raise IPaaS::Error, 'fields already defined' if self.respond_to?(:fields)

            attribute(:fields, type: [IPaaS::Connector::Schema::Field], default: [])

            # remember the original fields getter method and override with new behaviour
            alias_method(:_fields, :fields)
            define_method(:field) do |id, label = nil, type = nil, disabled: false,
              array: false, default: nil, hint: nil, notice: nil, notice_type: nil, notice_action: nil,
              sample: nil, visibility: 'visible',
              required: false, pattern: nil,
              min: nil, max: nil, min_length: nil, max_length: nil, min_date: nil, max_date: nil,
              validator: nil, enumeration: nil, fields: nil, remove_unmapped_fields: true, &block|

              if id.is_a?(IPaaS::Connector::Schema::Field)
                self._fields << IPaaS::Connector::Types::SchemaFieldType.resolve(id.to_h_ref).tap do |field|
                  field.instance_eval(&block) if block
                end
                return
              end

              id = id.to_sym
              unless type.present?
                next nil unless id.present?
                next self._fields.detect { |field| field.id == id }
              end

              if type.is_a?(Array)
                array = true
                type = type.first
              end

              # retrieve a hash with all method parameters
              field_params = { id: id, label: label, type: type }
              method(__method__).parameters.each_with_object(field_params) do |p, h|
                h[p[1].to_sym] = binding.local_variable_get(p[1].to_s) if p[0] == :key
              end

              self._fields << IPaaS::Connector::Schema::Field.new.tap do |field|
                field.attributes = field_params.except(:fields)
                field.fields = fields if fields&.any?
                field.instance_eval(&block) if block
              end
            end

            validate do |record|
              Array(record._fields).each do |f|
                next unless f.is_a?(IPaaS::Connector::Schema::Field)
                self.errors.add(:base, "Field (#{f.id}) invalid: #{f.full_error_messages}") unless f.valid?
              end
            end
          end

          def regenerate_schema(schema)
            schema.regenerate(self)
          end

          # Prepare this instance to lazily generate its own schema from a template.
          # Copies the template's schema block references and metadata so the schema
          # can be built on first access via generate_schemas_from_blocks.
          def copy_schema_blocks_from(source, schema_name, array: false)
            blocks_accessor = SchemaMixin.schema_blocks_accessor(schema_name)
            self.send(:"#{blocks_accessor}=", source.send(blocks_accessor).dup)

            default_fields_method = :"_#{schema_name}_default_fields"
            if source.class.respond_to?(default_fields_method)
              (@_schema_default_fields ||= {})[schema_name] = source.class.send(default_fields_method)
            end

            (@_schema_template_source ||= {})[schema_name] = source
            (@_pending_schema_generation ||= Set.new) << schema_name
            self.send(SchemaMixin.original_accessor(schema_name), array ? [] : nil)
          end

          private

          def retrieve_schema(name, reference, default_fields, array)
            if array
              retrieve_array_schema(name, reference, default_fields)
            else
              retrieve_single_schema(name, reference, default_fields)
            end
          end

          # Retrieve a single schema by name. Generates from template if pending,
          # or creates a new schema with default fields as a fallback.
          def retrieve_single_schema(name, reference, default_fields)
            result = original_value(name)
            if result.nil? && pending_schema_generation?(name)
              result = generate_schemas_from_blocks(name, default_fields, array: false)
            end
            result || IPaaS::Connector::Schema.new(reference || SecureRandom.uuid_v7).tap do |s|
              _regenerate_schema(name, s, s.reference, default_fields) if default_fields
            end
          end

          # Retrieve an array schema. Without a reference returns the full array;
          # with a reference finds the matching schema by reference.
          def retrieve_array_schema(name, reference, default_fields)
            schemas = ensure_schemas_generated(name, default_fields)
            return schemas unless reference.present?

            schemas.detect { |schema| schema.reference == reference }
          end

          # Generate pending array schemas if needed, then return the array.
          def ensure_schemas_generated(name, default_fields)
            if pending_schema_generation?(name) && original_value(name).empty?
              generate_schemas_from_blocks(name, default_fields, array: true)
            end
            original_value(name)
          end

          # Generates the initial schema and executes the given block with the field definitions.
          def generate_schema(name, reference, default_fields, array)
            if original_value(name)&.map(&:reference)&.include?(reference)
              raise IPaaS::Error, "Duplicate schema reference: #{reference}."
            end

            IPaaS::Connector::Schema.new(reference).tap do |s|
              _regenerate_schema(name, s, reference, default_fields)
            end.tap do |s|
              if array
                schemas = original_value(name)
                schemas << s
              else
                self.send(SchemaMixin.original_accessor(name), s)
              end
            end
          end

          def _regenerate_schema(name, schema, reference, default_fields)
            block = schema_block(name, reference)
            return unless block || default_fields

            schema.regenerate(self) do |s|
              s.fields.clear
              s.connector = resolve_connector_for_schema
              on_invalid = ->(msg) {
                s.errors.add(:base, msg)
              }
              IPaaS::Connector::Common::ProcHelper.new(s, block, on_invalid: on_invalid).execute_if_valid if block
              if default_fields
                IPaaS::Connector::Common::ProcHelper.new(s, default_fields, on_invalid: on_invalid).execute_if_valid
              end
            end
          end

          def resolve_connector_for_schema
            self.connector if respond_to?(:connector)
          end

          # Build schemas for this instance from the template's evaluated fields. Each new schema
          # gets a copy of the template's fields for immediate use, plus a regenerator that can
          # rebuild from the schema block with the instance's own context (cache, connections,
          # input values) when regenerate_schema is called from after_update hooks.
          def generate_schemas_from_blocks(name, default_fields, array:)
            @_pending_schema_generation&.delete(name)
            effective_default_fields = @_schema_default_fields&.dig(name) || default_fields
            template = @_schema_template_source&.dig(name)
            # Use the overridden getter so default_fields-only schemas (e.g., connection
            # templates without explicit blocks) are evaluated on access.
            template_schemas = Array(template&.send(name))
            blocks = self.send(SchemaMixin.schema_blocks_accessor(name))
            default_ref = name.to_s.gsub('_schema', '')

            if array
              generate_array_schemas(name, blocks, template_schemas, effective_default_fields, default_ref)
            else
              generate_single_schema(name, blocks, template_schemas, effective_default_fields, default_ref)
            end
          end

          def generate_single_schema(name, blocks, template_schemas, default_fields, default_ref)
            ref = template_schemas.first&.reference || blocks.keys.first || default_ref
            schema = build_schema_from_template(name, ref, template_schemas.first, default_fields)
            self.send(SchemaMixin.original_accessor(name), schema)
            schema
          end

          def generate_array_schemas(name, blocks, template_schemas, default_fields, default_ref)
            schemas = original_value(name)
            refs = blocks.any? ? blocks.keys : [default_ref]
            refs.each do |ref|
              template_schema = template_schemas.detect { |s| s.reference == ref }
              schemas << build_schema_from_template(name, ref, template_schema, default_fields)
            end
            schemas
          end

          # Create a new schema with the template's evaluated fields and a regenerator.
          # The template fields provide the initial state; the regenerator allows
          # after_update hooks to rebuild the schema with the instance's own context.
          def build_schema_from_template(name, ref, template_schema, default_fields)
            IPaaS::Connector::Schema.new(ref).tap do |schema|
              if template_schema
                schema.fields = template_schema.fields.map(&:deep_dup)
                schema.name = template_schema.name
                schema.connector = resolve_connector_for_schema
                au = template_schema.instance_variable_get(:@after_update)
                schema.instance_variable_set(:@after_update, au) if au
              end
              setup_regenerator(name, schema, ref, default_fields)
            end
          end

          # Store a regenerator on the schema without executing it. When regenerate_schema
          # is called (e.g., from an after_update hook), this proc rebuilds the schema
          # from the block using the instance's context.
          def setup_regenerator(name, schema, ref, default_fields)
            block = schema_block(name, ref)
            return unless block || default_fields

            instance = self
            schema.instance_variable_set(:@regenerator, proc { |s|
              s.fields.clear
              s.connector = instance.send(:resolve_connector_for_schema)
              on_invalid = ->(msg) { s.errors.add(:base, msg) }
              IPaaS::Connector::Common::ProcHelper.new(s, block, on_invalid: on_invalid).execute_if_valid if block
              if default_fields
                IPaaS::Connector::Common::ProcHelper.new(s, default_fields, on_invalid: on_invalid).execute_if_valid
              end
            })
          end

          def pending_schema_generation?(name)
            @_pending_schema_generation&.include?(name)
          end

          def original_value(name)
            self.send(SchemaMixin.original_accessor(name))
          end

          def schema_block(name, reference)
            self.send(SchemaMixin.schema_blocks_accessor(name))[reference]
          end
        end
      end
    end
  end
end
