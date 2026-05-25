module IPaaS
  module Connector
    module Types
      module SchemaFieldType
        include IPaaS::Connector::Types::Base

        SCHEMA_REFERENCE = 'schema-field-type'.freeze

        class << self
          def ruby_class
            IPaaS::Connector::Schema::Field
          end

          def resolve(value, context: nil)
            return value if value.is_a?(IPaaS::Connector::Schema::Field)
            return value unless value.is_a?(Hash)

            value[:type] = value[:type].to_sym if value[:type]
            value[:id] = value[:id].to_sym if value[:id]
            fields = value[:fields]
            IPaaS::Connector::Schema::Field.new.tap do |schema_field|
              valid_attributes = value.except(:fields).select do |attr_name, _attr_value|
                schema_field.class.attribute_names.include?(attr_name.to_sym)
              end
              schema_field.attributes = valid_attributes
              schema_field.fields = (fields || []).filter_map { |f| resolve(f) }
            end
          end

          def nested?
            true
          end

          def example(field)
            # prevent eternal nesting in example
            return if field.id == :fields

            resolve(fields_example(schema.fields))
          end

          def schema
            @schema ||= IPaaS::Connector::Schema.new(SCHEMA_REFERENCE) do
              field :id, 'Field ID', :string,
                    required: true,
                    sample: 'given_name',
                    max_length: 40

              field :label, 'Label', :string,
                    required: true,
                    sample: 'Given name',
                    max_length: 120

              field :type, 'Type', :string,
                    required: true,
                    sample: 'string',
                    enumeration: []

              field :disabled, 'Disabled', :boolean,
                    sample: false

              field :array, 'Array', :boolean,
                    sample: false

              field :default, 'Default', :string,
                    sample: ''

              field :hint, 'Hint', :string,
                    sample: 'Please provide your given name.',
                    visibility: 'optional'

              field :sample, 'Sample', :string,
                    sample: 'Mary',
                    visibility: 'optional'

              field :visibility, 'Visibility', :string,
                    default: 'visible',
                    enumeration: [
                      { id: 'visible', label: 'Visible - Always visible in the mapping' },
                      { id: 'optional', label: 'Optional - Allow the user to add this field to the mapping' },
                      { id: 'hidden', label: 'Hidden - Field cannot be added to the mapping' },
                    ]

              field :required, 'Required', :boolean

              field :pattern, 'Pattern', :regexp,
                    sample: /\A[\w ]+\Z/,
                    visibility: 'optional'

              field :min, 'Minimum', :integer,
                    visibility: 'optional',
                    sample: 2
              field :max, 'Maximum', :integer,
                    visibility: 'optional',
                    sample: 10

              field :min_length, 'Minimum length', :integer,
                    sample: 2,
                    visibility: 'optional'
              field :max_length, 'Maximum length', :integer,
                    sample: 120,
                    visibility: 'optional'

              field :enumeration, 'Enumeration', :nested,
                    array: true,
                    sample: [],
                    visibility: 'optional' do
                field :id, 'ID', :string,
                      required: true
                field :label, 'Label', :string,
                      required: true
              end

              field :fields, 'Fields', :schema_field,
                    array: true,
                    required: true,
                    min_length: 1,
                    sample: [],
                    disabled: true

              field :remove_unmapped_fields, 'Remove unmapped fields', :boolean,
                    default: true,
                    hint: 'Automatically removes fields that are not mapped in the schema.
 This prevents unexpected extra fields from marking the field mapping as invalid.',
                    visibility: 'optional'

              after_update do |fields, values|
                type_field = fields.detect { |f| f.id == :type }
                type_field.enumeration = connector.type_enumeration

                default_field = fields.detect { |f| f.id == :default }
                default_field.type = values[:type]

                sample_field = fields.detect { |f| f.id == :sample }
                sample_field.type = values[:type]

                fields_field = fields.detect { |f| f.id == :fields }
                fields_field.disabled = values[:type] != 'nested'

                remove_unmapped_fields_field = fields.detect { |f| f.id == :remove_unmapped_fields }
                remove_unmapped_fields_field.disabled = values[:type] != 'nested'

                fields
              end
            end
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::SchemaFieldType)
