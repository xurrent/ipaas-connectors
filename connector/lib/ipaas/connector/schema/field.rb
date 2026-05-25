module IPaaS
  module Connector
    class Schema
      class Field
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :type, :'type=', :array, :'array=', :disabled, :'disabled=',
                  :label, :'label=', :hint, :'hint=', :required, :'required=',
                  :visibility, :'visibility=', :enumeration, :'enumeration=', :fields

        ANY_TYPE_PATTERN = /\Aany_[a-z_]+_type\z/
        SERIALIZABLE_ATTRS = [
          :id, :label, :type, :disabled, :array, :default, :sample, :hint, :notice, :visibility, :required,
          :pattern, :min, :max, :min_length, :max_length, :enumeration, :fields, :remove_unmapped_fields,
        ].freeze

        include IPaaS::Connector::Common::Model
        include ActiveModel::Validations::Callbacks

        attribute :id, length: { in: 1..40 }, type: Symbol, required: true
        attribute :label, length: { in: 1..120 }, required: true
        attribute :type, type: Symbol, required: true
        attribute :disabled, type: Boolean
        attribute :array, type: Boolean
        attribute :default, type: -> { self.array ? [type_def.ruby_class] : type_def.ruby_class }
        attribute :sample, type: -> { self.array ? [type_def.ruby_class] : type_def.ruby_class }
        attribute :hint
        attribute :notice
        attribute :visibility, type: String, default: 'visible'
        attribute :required, type: Boolean
        attribute :pattern, type: Regexp
        attribute :min, type: Integer
        attribute :max, type: Integer
        attribute :min_length, type: Integer
        attribute :max_length, type: Integer
        attribute :enumeration, type: [Hash]
        attribute :remove_unmapped_fields, type: Boolean, default: true

        # TODO: Add support for custom validation message, e.g. failure_message('My custom message')
        function :validator

        schema_fields

        def fields_with_nested_schema(new_fields = nil)
          return self.fields = new_fields if new_fields
          return fields_without_nested_schema unless type_def.respond_to?(:schema)

          type_def.schema.fields
        end
        alias fields_without_nested_schema fields
        alias fields fields_with_nested_schema

        validate :enumeration_valid?
        validate :visibility_valid?
        validate :type_valid?
        validate :fields_valid?
        validate :pattern_valid?

        def enumeration_with_parse=(value)
          self.enumeration_without_parse = value
          parse_enumeration
        end
        alias enumeration_without_parse= enumeration=
        alias enumeration= enumeration_with_parse=

        def type=(value)
          @type_def = nil
          @type = value
        end

        def type_def
          @type_def ||= if ANY_TYPE_PATTERN.match?(type.to_s)
                          IPaaS::Connector::Types::AnyType
                        else
                          "IPaaS::Connector::Types::#{self.type.to_s.camelize}Type".safe_constantize ||
                            IPaaS::Connector::Types::AnyType
                        end
        end

        def sample=(value)
          @sample = value.nil? || !type_def.respond_to?(:resolve) ? value : type_def.resolve(value)
        end

        def default=(value)
          @default = value.nil? || !type_def.respond_to?(:resolve) ? value : type_def.resolve(value)
        end

        def pattern=(value)
          @pattern = assign_pattern(value)
        end

        def pattern_valid?
          return true if pattern.blank?

          case pattern
          when String
            compile_pattern(pattern)
          when Regexp
            true
          else
            errors.add(:pattern, "Pattern must be a string or Regexp, got #{pattern.class}")
            false
          end
        end

        def example
          return sample unless sample.nil?
          return default unless default.nil?

          result = type_def.example(self)
          array ? [result] : result
        end

        def deep_dup
          super.tap do |duped|
            duped.attributes = attributes
            duped.fields = fields.map(&:deep_dup) unless self.id == :fields # prevents stack level too deep
          end
        end

        def hash
          [
            id,
            type,
            array,
            self.id == :fields ? nil : fields.map(&:hash), # prevent stack level too deep
          ].hash
        end

        def ==(other)
          other.is_a?(self.class) &&
            other.id == id &&
            other.type == type &&
            other.array == array &&
            other.fields.eql?(fields)
        end
        alias eql? ==

        def field_definition(field_id)
          fields&.detect { |f| f.id.to_s == field_id.to_s }
        end

        def to_h_ref
          attributes = SERIALIZABLE_ATTRS.dup
          attributes.delete(:visibility) if visibility == 'visible' # This is the default
          attributes.delete(:remove_unmapped_fields) if type != :nested || remove_unmapped_fields == true
          attributes.delete(:fields) unless fields_without_nested_schema.present?
          IPaaS::Connector::Common::Serializer.to_h(self, *attributes)
        end

        private

        def parse_enumeration
          return unless self.enumeration&.first.present?
          return if self.enumeration.first.is_a?(Hash)
          return unless self.type.in?([:string, :integer])

          self.enumeration = enumeration.map { |val| { id: val, label: val.to_s } }
        end

        def enumeration_valid?
          return if self.enumeration.blank? || errors[:enumeration].any?

          unless self.type.in?([:string, :integer])
            errors.add(:enumeration, 'Enumeration is restricted to string and integer types.')
          end

          return if enumeration.all? { |value| valid_enum_value?(value) }
          errors.add(:enumeration, 'is invalid.')
        end

        def assign_pattern(value)
          return value unless value.is_a?(String) && value.present?

          Regexp.new(value)
        rescue RegexpError => e
          errors.add(:pattern, "Invalid regexp pattern: #{e.message}")
          value
        end

        def compile_pattern(value)
          @pattern = Regexp.new(value)
          true
        rescue RegexpError => e
          errors.add(:pattern, "Invalid regexp pattern: #{e.message}")
          false
        end

        def visibility_valid?
          return if self.visibility.blank?

          return if %w[visible optional hidden].include?(self.visibility)
          errors.add(:visibility, 'is invalid.')
        end

        def valid_enum_value?(value)
          return false unless value.is_a?(Hash)

          value[:id].present? && value[:label].present?
        end

        def type_valid?
          return unless type.present?
          return if ANY_TYPE_PATTERN.match?(type.to_s) # any_item_type
          return if IPaaS::Connector::Types.for(type.to_sym)

          all_types = IPaaS::Connector::Types.all.keys.sort.map(&:inspect).join(', ').gsub(':any', ':any_..._type')
          errors.add(:type, "should be one of #{all_types}.")
        end

        def fields_valid?
          return unless fields_without_nested_schema.any?
          return if type_def.nested?

          errors.add(:fields, 'Subfields are only available when the type is nested.')
        end
      end
    end
  end
end
