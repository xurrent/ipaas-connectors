module IPaaS
  module Connector
    module Mapping
      class ResolvedMapping < HashWithIndifferentAccess
        include IPaaS::Connector::Common::Model

        DYNAMIC_MAPPING_TYPES = [:proc, :variable, :runbook_variable, :nested].freeze

        attr_accessor :context, :base_error
        attribute :fields, type: [IPaaS::Connector::Schema::Field]
        attribute :mapping, type: [IPaaS::Connector::Mapping::FieldMapping]

        validate :mapping_valid?
        validate :add_base_error

        # delegate hash (manipulation) methods to the plain hash version
        delegate :slice, :slice!, :except, :except!, to: :to_hash

        def initialize(context, schema_fields, mapping)
          super()
          @context = context
          @fields = schema_fields
          @mapping = IPaaS::Connector::Mapping::FieldMapping.parse(mapping)
        end

        def resolve
          self.mapping.each do |field_mapping|
            schema_field(field_mapping.field_id) do |field|
              add_resolved(field, resolve_field(field, field_mapping))
            end
          end
          resolve_default_fields
          self
        end

        def to_hash
          super.with_indifferent_access
        end

        def with_indifferent_access
          to_hash
        end

        def to_json(*_args)
          JSON.generate(to_hash)
        end

        private

        def add_resolved(field, resolved_value)
          return add_resolved_array(field, resolved_value) if field.array

          mapping_error(field, "Field '%<field>' is mapped twice.") if self.key?(field.id)
          resolved_value = field.type_def.resolve(resolved_value, context: context)
          validate_field(field, resolved_value)
          self[field.id] = resolved_value
        end

        def add_resolved_array(field, resolved_value)
          resolved_value = [resolved_value] unless resolved_value.is_a?(Array)
          resolved_values = resolved_value.each_with_index.map do |element_value, index|
            field.type_def.resolve(element_value, context: context).tap do |resolved_element_value|
              validate_field(field, resolved_element_value, field_designator: "#{field.id}[#{index}]")
            end
          end
          self[field.id] = (self[field.id] || []) + resolved_values
        end

        def resolve_default_fields
          fields.select(&:default).reject(&:disabled).each do |default_field|
            self[default_field.id] = default_field.default unless self.key?(default_field.id)
          end
        end

        def mapping_valid?
          @validating_mapping = true
          clear # clear the hash
          mapping.each { |field_mapping| field_mapping.errors.clear } # clear field mapping errors
          clear_nested_field_mapping_errors
          resolve # re-resolve to collect errors on individual resolved field values
          validate_fields # validations on groups of fields
          @validating_mapping = false
        end

        def add_base_error
          return unless @base_error

          errors.add(:base, @base_error.message)
          local_trace = @base_error.backtrace.filter_map { |trace| trace[%r{(/connectors?/.*)$}, 1] }
          errors.add(:base, local_trace.join("\n"))
        end

        def mapping_error(field, message, field_designator = nil, custom_errors = [])
          return unless @validating_mapping
          field_designator = field.try(:id)&.try(:to_s) if field_designator.nil?

          # cannot use format() as message can be an invalid pattern
          msg = interpolate_error_message(message, field_designator, custom_errors)
          errors.add(:base, msg, field_designator: field_designator)

          return unless field

          field_mappings_for(field).each do |field_mapping|
            field_mapping.errors.add(:base, msg, field_designator: field_designator)
          end
        end

        def interpolate_error_message(message, field_designator, custom_errors)
          # cannot use format() as message can be an invalid pattern
          msg = message.gsub('%<field>') { field_designator }
          msg.gsub('%<custom_errors>') do
            if custom_errors.present?
              " #{custom_errors.join('; ').strip}"
            else
              ''
            end
          end
        end

        def schema_field(field_id)
          fields.detect { |field| field.id == field_id }.tap do |field|
            yield field if field && !field.disabled
          end
        end

        def resolve_field(field, field_mapping)
          return field_mapping.fixed unless field_mapping.fixed.nil?
          DYNAMIC_MAPPING_TYPES.each do |type|
            value = field_mapping.send(type)
            return send(:"resolve_#{type}", field, value) if value.present?
          end

          nil # explicit nil, no default please
        end

        def resolve_proc(field, proc, params = nil, attribute: nil)
          log_attribute = "#{attribute} " if attribute.present?
          on_invalid = ->(msg) { mapping_error(field, "Field '%<field>' #{log_attribute}code invalid: #{msg}") }
          proc_helper = IPaaS::Connector::Common::ProcHelper.new(context, proc, on_invalid: on_invalid)
          begin
            proc_helper.execute_if_valid(*params)
          rescue StandardError => e
            mapping_error(field, "Field '%<field>' #{log_attribute}code raised #{e.class}: #{e.message}")
          end
        end

        def resolve_variable(field, variable)
          resolve_proc(field, %(environment[:"#{variable}"]))
        end

        def resolve_runbook_variable(field, variable)
          resolve_proc(field, %(runbook&.read_variable("#{variable}")))
        end

        def resolve_nested(field, mapping)
          ResolvedMapping.new(self.context, field.fields, mapping).resolve
        end

        # called when all fields have been resolved
        def validate_fields
          fields.each do |field|
            # if field is not nested and could not be resolved no need to do additional checks
            next if field_validation_errors?(field) && !field.type_def.nested?

            value = self[field.id]
            # Structural mismatch: variable mapped to a nested field. Check even in designer mode
            # because this is a mapping configuration error, not a missing value.
            validate_variable_nesting_mismatch(field, value)
            next if mapped_nil_in_designer_mode?(field, value)

            validate_required(field, value)
            validate_min_length(field, value)
            validate_max_length(field, value)
          end
        end

        def mapped_nil_in_designer_mode?(field, value)
          return false if value.present?

          field_mapping = mapping.detect { |m| m.field_id == field.id }
          return false unless field_mapping
          return false if (DYNAMIC_MAPPING_TYPES - [:variable]).all? { |type| field_mapping.send(type).nil? }

          context.try(:runbook).nil? || context.runbook.designer_mode?
        end

        def validate_required(field, value)
          return unless field.required && value.blank? && value != false && !field.disabled

          mapping_error(field, "Field '%<field>' is required.")
        end

        def validate_min_length(field, value)
          return unless field.min_length && value.respond_to?(:size)
          return unless value.size < field.min_length

          mapping_error(field, "Length of field '%<field>' should be at least #{field.min_length}.")
        end

        def validate_max_length(field, value)
          return unless field.max_length && value.respond_to?(:size)
          return unless value.size > field.max_length

          mapping_error(field, "Length of field '%<field>' should be at most #{field.max_length}.")
        end

        # called when a single field has been resolved
        def validate_field(field, value, field_designator: field.id.to_s)
          return unless @validating_mapping && value.present?
          return if field_validation_errors?(field, field_designator)
          return unless valid_type_def_type?(field, value, field_designator)

          prune_superfluous_nested_fields!(field, value)
          validate_field_value(field, value, field_designator)
        end

        def validate_field_value(field, value, field_designator)
          validate_nested_field(field, value, field_designator)
          validate_pattern(field, value, field_designator)
          validate_min(field, value, field_designator)
          validate_max(field, value, field_designator)
          validate_min_date(field, value, field_designator)
          validate_max_date(field, value, field_designator)
          validate_validator(field, value, field_designator)
          validate_enumeration(field, value, field_designator)
          validate_type_def(field, value, field_designator)
        end

        def prune_superfluous_nested_fields!(field, value)
          return prune_array_fields!(field, value) if field.array && value.is_a?(Array)
          return unless nested_hash?(field, value)

          remove_extra_fields!(value, valid_field_ids_for(field)) if field.remove_unmapped_fields
          prune_nested_fields_recursively(field, value)
        end

        def nested_hash?(field, value)
          field.type_def.nested? && value.is_a?(Hash)
        end

        def valid_field_ids_for(field)
          field.fields.compact.flat_map { |f| [f.id.to_sym, f.id.to_s] }
        end

        def remove_extra_fields!(value, valid_ids)
          extra_fields = value.keys - valid_ids
          extra_fields.each { |key| value.delete(key) }
        end

        def prune_array_fields!(field, value)
          return unless field.remove_unmapped_fields

          value.each do |element_value|
            prune_superfluous_nested_fields!(field, element_value)
          end
        end

        def prune_nested_fields_recursively(field, value)
          value.each do |key, nested_value|
            nested_field = find_nested_field(field, key)
            next unless nested_field

            prune_superfluous_nested_fields!(nested_field, nested_value)
          end
        end

        def find_nested_field(field, key)
          field.fields.compact.find { |f| f.id == key || f.id.to_s == key.to_s }
        end

        def validate_nested_field(field, value, field_designator)
          return unless field.type_def.nested?
          return if mapped_nil_in_designer_mode?(field, value)

          resolved_value = if value.respond_to?(:valid?)
                             value
                           elsif value.is_a?(Hash)
                             resolve_nested(field, IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(value))
                           end
          return if resolved_value.nil? || resolved_value.valid?

          add_nested_field_errors(field, resolved_value, field_designator)
        end

        def add_nested_field_errors(field, resolved_value, field_designator)
          resolved_value.errors.full_messages.each do |message|
            mapping_error(field, "Nested field '%<field>' invalid: #{message}", field_designator)

            populate_individual_nested_field_errors(field, message)
          end
        end

        def populate_individual_nested_field_errors(field, message)
          parent_field_mapping = mapping.detect { |m| m.field_id == field.id }
          return unless parent_field_mapping&.nested

          # Extract the field ID from the error message
          # Example: "Field 'frequency' should be one of..." -> "frequency"
          field_id_match = message.match(/Field '([^']+)'/)
          return unless field_id_match

          field_id = field_id_match[1]

          # Search for the nested field mapping recursively
          nested_field_mapping = find_nested_field_mapping_recursively(parent_field_mapping, field_id.to_sym)
          return unless nested_field_mapping

          nested_field_mapping.errors.add(:base, message)
        end

        def find_nested_field_mapping_recursively(field_mapping, target_field_id)
          return nil unless field_mapping.nested

          # First, check direct children
          direct_match = field_mapping.nested.detect { |n| n.field_id == target_field_id }
          return direct_match if direct_match

          # Then, search recursively in nested children
          field_mapping.nested.each do |nested|
            result = find_nested_field_mapping_recursively(nested, target_field_id)
            return result if result
          end

          nil
        end

        def validate_pattern(field, value, field_designator)
          return unless field.pattern
          return if value.to_s.match?(field.pattern)

          mapping_error(field,
                        "Field '%<field>' should confirm to pattern #{field.pattern.inspect}.",
                        field_designator)
        end

        def validate_min(field, value, field_designator)
          return unless field.min

          number_value = value_to_number(value)
          return unless number_value && number_value < value_to_number(field.min)

          mapping_error(field, "Field '%<field>' should be at least #{field.min}.", field_designator)
        end

        def validate_max(field, value, field_designator)
          return unless field.max

          number_value = value_to_number(value)
          return unless number_value && number_value > value_to_number(field.max)

          mapping_error(field, "Field '%<field>' should be at most #{field.max}.", field_designator)
        end

        def validate_min_date(field, value, field_designator)
          return unless field.min_date

          date_value = value_to_date(value)
          min = value_to_date(field.min_date)
          return unless date_value && min && date_value < min

          mapping_error(field, "Field '%<field>' should be on or after #{field.min_date}.", field_designator)
        end

        def validate_max_date(field, value, field_designator)
          return unless field.max_date

          date_value = value_to_date(value)
          max = value_to_date(field.max_date)
          return unless date_value && max && date_value > max

          mapping_error(field, "Field '%<field>' should be on or before #{field.max_date}.", field_designator)
        end

        def validate_validator(field, value, field_designator)
          return unless field.validator.present?
          return if resolve_proc(field, field.validator, [value], attribute: 'validator')

          mapping_error(field, "Field '%<field>' is not valid.", field_designator)
        end

        def validate_enumeration(field, value, field_designator)
          return unless field.enumeration.present?
          return if field.enumeration.detect { |enum| enum[:id] == value }

          allowed_values = field.enumeration.pluck(:id).join(', ')
          mapping_error(field, "Field '%<field>' should be one of #{allowed_values}.", field_designator)
        end

        def validate_type_def(field, value, field_designator)
          return if value.blank? && value != false
          errors = []
          return if field.type_def.valid?(value, errors)

          mapping_error(field, "Field '%<field>' is invalid.%<custom_errors>", field_designator, errors)
        end

        def valid_type_def_type?(field, value, field_designator)
          validate_type_def_type(field, value, field_designator)

          result = any_errors?(self) do |options|
            options[:field_designator].nil? || options[:field_designator] == field_designator
          end

          !result
        end

        def validate_type_def_type(field, value, field_designator)
          return true if (value.blank? && value != false) || value.is_a?(field.type_def.ruby_class)

          msg = if variable_on_nested_field?(field)
                  variable_nesting_mismatch_message
                else
                  type_mismatch_message(field, value)
                end
          mapping_error(field, msg, field_designator)
        end

        def validate_variable_nesting_mismatch(field, value)
          return unless value.blank? && variable_on_nested_field?(field)

          mapping_error(field, variable_nesting_mismatch_message)
        end

        def variable_on_nested_field?(field)
          return false unless field.type_def.nested?
          return false if field.type_def.variable_resolvable?

          field_mapping = mapping.detect { |m| m.field_id == field.id }
          field_mapping && (field_mapping.variable.present? || field_mapping.runbook_variable.present?)
        end

        def variable_nesting_mismatch_message
          "Field '%<field>' expects nested values but a variable was provided. " \
            'Use the Nested option to map variables to individual sub-fields.'
        end

        def type_mismatch_message(field, value)
          "Type of field '%<field>' invalid, expected #{field.type_def.ruby_class} found #{value.class}."
        end

        def value_to_number(value)
          return value.to_f if value.respond_to?(:to_f)
          return value.to_i if value.respond_to?(:to_i)
          return value.to_time.to_i if value.respond_to?(:to_time) # Dates
          nil
        end

        def value_to_date(value)
          return if value.blank?
          return value.to_date if value.is_a?(Date) || value.is_a?(Time)

          Date.iso8601(value.to_s)
        rescue StandardError
          nil
        end

        def field_validation_errors?(field, field_designator = nil)
          field_mappings_for(field).any? do |field_mapping|
            any_errors?(field_mapping) do |options|
              field_designator.nil? || field_designator == options[:field_designator]
            end
          end
        end

        def any_errors?(mapping)
          mapping.errors.where(:base).any? { |error| yield(error.options) }
        end

        def field_mappings_for(field)
          mapping.select { |field_mapping| field_mapping.field_id == field.id }
        end

        def clear_nested_field_mapping_errors
          mapping.each do |field_mapping|
            clear_nested_errors_recursively(field_mapping)
          end
        end

        def clear_nested_errors_recursively(field_mapping)
          field_mapping.nested&.each do |nested|
            nested.errors.clear
            clear_nested_errors_recursively(nested)
          end
        end
      end
    end
  end
end
