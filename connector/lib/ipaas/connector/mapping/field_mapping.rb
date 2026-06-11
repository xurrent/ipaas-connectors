module IPaaS
  module Connector
    module Mapping
      class << self
        def invalid_mapping?(record, attribute)
          mapping = record.send(attribute)
          if mapping.present?
            !validate_mapping(record, attribute, mapping)
          else
            false
          end
        end

        def update_action_reference(proc_container, reference_was, new_reference)
          replacer = IPaaS::Connector::Common::ProcHelper.create_action_ref_replacer(reference_was, new_reference)
          proc_container.visit_procs(false) do |_path, mapping, already_updated, proc|
            mapping.proc = replacer.call(proc)
            already_updated || (mapping.proc != proc)
          end
        end

        def update_runbook_variable(proc_container, id_was, new_id)
          replacer = IPaaS::Connector::Common::ProcHelper.create_runbook_variable_replacer(id_was, new_id)
          proc_container.visit_procs(false) do |_path, mapping, already_updated, proc|
            mapping.proc = replacer.call(proc)
            already_updated || (mapping.proc != proc)
          end
        end

        def runbook_variables_used?(proc_container)
          proc_container.visit_procs(false) do |_path, _mapping, found, proc|
            found || IPaaS::Connector::Common::ProcHelper.runbook_variables_used?(proc)
          end
        end

        private

        def validate_mapping(record, attribute, mappings)
          mappings.all? do |mapping|
            mapping.field_definition = get_field_definition(record, attribute, mapping.field_id)

            if mapping.valid?
              all_action_refs_valid?(record, attribute, mapping)
            else
              record.errors.add(attribute, "(#{mapping.field_id}) invalid: #{mapping.full_error_messages}")
              false
            end
          end
        end

        def all_action_refs_valid?(record, attribute, mapping)
          if fixed_ruby_input_field?(record, attribute, mapping)
            valid_fixed_ruby?(record, attribute, mapping)
          else
            action_refs_valid?(record, attribute, mapping)
          end
        end

        def fixed_ruby_input_field?(record, attribute, mapping)
          attribute == :input_mapping &&
            mapping.fixed.present? &&
            get_field_definition(record, attribute, mapping.field_id)&.type == :ruby
        end

        def valid_fixed_ruby?(record, attribute, mapping)
          # mapping.fixed is ruby code: check its content
          invalid_refs = invalid_action_refs(record, mapping.fixed)
          return true if invalid_refs.blank?

          add_invalid_refs_error(record, attribute, mapping.field_id.to_s, invalid_refs)
          false
        end

        def action_refs_valid?(record, attribute, proc_container)
          errors_found = proc_container.visit_procs(false) do |path, _, already_found_error, proc|
            invalid_refs = invalid_action_refs(record, proc)
            mapping_error = invalid_refs.present?
            add_invalid_refs_error(record, attribute, path.join('.'), invalid_refs) if mapping_error
            already_found_error || mapping_error
          end
          !errors_found
        end

        def invalid_action_refs(action, proc)
          refs = IPaaS::Connector::Common::ProcHelper.action_references(proc)
          return [] if refs.empty?

          valid_refs = action.other_actions.map(&:reference)
          refs - valid_refs
        end

        def add_invalid_refs_error(record, attribute, path, invalid_refs)
          return unless invalid_refs.present?

          ref_message_part = invalid_refs.map { |r| "'#{r}'" }.join(', ')
          record.errors.add(attribute, "(#{path}) invalid action references: #{ref_message_part}")
        end

        def get_field_definition(record, attribute, field_id)
          case attribute
          when :input_mapping
            record.input_schema.field(field_id)
          when :output_mapping
            record.output_schema.field(field_id)
          else
            record.schema.field(field_id) if record.respond_to?(:schema)
          end
        end
      end

      class FieldMapping
        include IPaaS::Connector::Common::Model
        include IPaaS::Connector::Common::ProcContainer

        attribute :field_id, required: true, type: Symbol
        attribute :fixed, type: Object
        attribute :nested, type: [FieldMapping]
        attribute :variable, type: String
        attribute :runbook_variable, type: String
        attribute :field_definition, type: Object

        validate :proc_valid?
        validate :nested_valid?

        class << self
          def parse(field_mapping)
            array_or_hash = IPaaS::Connector::Common::Serializer.parse(field_mapping)
            return array_or_hash.map { |fm| parse(fm) } if array_or_hash.is_a?(Array)
            return field_mapping if field_mapping.is_a?(FieldMapping)

            raise IPaaS::Error, 'Field mapping must be a hash.' unless array_or_hash.is_a?(Hash)
            hash = array_or_hash.deep_symbolize_keys

            FieldMapping.new.tap do |new_field_mapping|
              copy_field_mapping_values(new_field_mapping, hash)
            end
          rescue Psych::SyntaxError
            raise IPaaS::Error, "Field mapping must be a YAML hash. Found: #{field_mapping.inspect}."
          end

          def fixed_mapping(values)
            return [] if values.blank?
            raise IPaaS::Error, 'Values must be a hash.' unless values.is_a?(Hash)

            values.map do |field_id, value|
              { field_id: field_id.to_sym, fixed: value }
            end
          end

          private

          def copy_field_mapping_values(field_mapping, hash)
            field_mapping.field_id = hash[:field_id]&.to_sym
            field_mapping.nested = parse(hash[:nested]) if hash[:nested].present?
            [:fixed, :proc, :variable, :runbook_variable].each do |key|
              field_mapping.send(:"#{key}=", hash[key])
            end
          end
        end

        def to_h_ref
          IPaaS::Connector::Common::Serializer.to_h(self,
                                                    :field_id,
                                                    :fixed,
                                                    :proc,
                                                    :variable,
                                                    :runbook_variable,
                                                    :nested)
        end

        def update_action_reference(reference_was, new_reference)
          Mapping.update_action_reference(self, reference_was, new_reference)
        end

        def update_runbook_variable(id_was, new_id)
          updated = try_update_runbook_variable_attribute?(id_was, new_id)
          updated |= try_update_fixed_attribute?(id_was, new_id)
          updated |= Mapping.update_runbook_variable(self, id_was, new_id)
          updated |= update_nested_mappings(id_was, new_id)
          updated
        end

        # Mirrors the shapes update_runbook_variable touches; runbook_variables_used? covers
        # procs in nested mappings, the recursion covers their other attributes.
        def uses_runbook_variables?
          runbook_variable.present? ||
            fixed_runbook_variable? ||
            Mapping.runbook_variables_used?(self) ||
            nested_uses_runbook_variables?
        end

        private

        def fixed_runbook_variable?
          fixed.present? && field_definition&.type == :runbook_variable
        end

        def nested_uses_runbook_variables?
          nested.present? && nested.any?(&:uses_runbook_variables?)
        end

        def try_update_runbook_variable_attribute?(id_was, new_id)
          return false unless runbook_variable == id_was

          self.runbook_variable = new_id
          true
        end

        def try_update_fixed_attribute?(id_was, new_id)
          return false unless fixed.to_s == id_was
          return false unless field_definition&.type == :runbook_variable

          self.fixed = new_id
          true
        end

        def update_nested_mappings(id_was, new_id)
          return false if nested.blank?

          nested.reduce(false) do |updated, mapping|
            updated || mapping.update_runbook_variable(id_was, new_id)
          end
        end

        def proc_valid?
          return if proc.blank?

          helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc, field: field_definition)
          return if helper.valid?

          self.errors.add(:proc, "invalid: #{helper.errors.join(' ')}")
        end

        def nested_valid?
          return true if nested.blank?

          nested.reject(&:valid?).each do |nested_mapping|
            errors.add(:nested, "(#{nested_mapping.field_id}) invalid: #{nested_mapping.full_error_messages}")
          end
          errors[:nested].none?
        end
      end
    end
  end
end
