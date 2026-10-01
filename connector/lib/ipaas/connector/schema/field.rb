module IPaaS
  module Connector
    class Schema
      class Field
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :type, :'type=', :array, :'array=', :disabled, :'disabled=',
                  :label, :'label=', :hint, :'hint=', :required, :'required=',
                  :visibility, :'visibility=', :enumeration, :'enumeration=', :default,
                  :fields, :'fields=', # no new reach: `fields(new_fields)` already writes
                  :min_date, :'min_date=', :max_date, :'max_date=', :options

        ANY_TYPE_PATTERN = /\Aany_[a-z_]+_type\z/
        REQUIRED_OPTION_DEPENDENCY_PARAMETER_KINDS = [:keyreq].freeze
        OPTION_DEPENDENCY_PARAMETER_KINDS = (REQUIRED_OPTION_DEPENDENCY_PARAMETER_KINDS + [:key]).freeze
        ENUMERABLE_TYPES = [:string, :integer, :time_zone].freeze
        NOTICE_TYPES = IPaaS.make_shareable(%w[info error])
        NOTICE_ACTIONS = IPaaS.make_shareable(%w[edit_connection])
        SERIALIZABLE_ATTRS = [
          :id, :label, :type, :disabled, :array, :default, :sample, :hint, :notice, :notice_type, :notice_action,
          :visibility, :required, :pattern, :min, :max, :min_length, :max_length, :min_date, :max_date, :enumeration,
          :fields, :remove_unmapped_fields,
        ].freeze

        include IPaaS::Connector::Common::Model
        include ActiveModel::Validations::Callbacks

        attr_reader :connector

        MAX_ID_LENGTH = 64

        attribute :id, length: { in: 1..MAX_ID_LENGTH }, type: Symbol, required: true
        attribute :label, length: { in: 1..120 }, required: true
        attribute :type, type: Symbol, required: true
        attribute :disabled, type: Boolean
        attribute :array, type: Boolean
        attribute :default, type: -> { self.array ? [type_def.ruby_class] : type_def.ruby_class }
        attribute :sample, type: -> { self.array ? [type_def.ruby_class] : type_def.ruby_class }
        attribute :hint
        attribute :notice
        attribute :notice_type, type: String
        attribute :notice_action, type: String
        attribute :visibility, type: String, default: 'visible'
        attribute :required, type: Boolean
        attribute :pattern, type: Regexp
        attribute :min, type: Integer
        attribute :max, type: Integer
        attribute :min_length, type: Integer
        attribute :max_length, type: Integer
        attribute :min_date, type: String
        attribute :max_date, type: String
        attribute :enumeration, type: [Hash]
        attribute :remove_unmapped_fields, type: Boolean, default: true
        # TODO: Add support for custom validation message, e.g. failure_message('My custom message')
        function :validator
        function :options

        schema_fields

        def option_dependencies
          option_parameter_names(OPTION_DEPENDENCY_PARAMETER_KINDS)
        end

        def required_option_dependencies
          option_parameter_names(REQUIRED_OPTION_DEPENDENCY_PARAMETER_KINDS)
        end

        def options_for(context, **)
          return unless options

          IPaaS::Connector::Common::ProcHelper.new(context, options, connector: connector).execute(**)
        end

        def inspect
          "Field (#{id}) - #{type}#{'[]' if array}"
        end

        def fields_with_nested_schema(new_fields = nil)
          return self.fields = new_fields if new_fields
          return fields_without_nested_schema unless type_def.respond_to?(:schema)

          type_def.schema.fields
        end
        alias fields_without_nested_schema fields
        alias fields fields_with_nested_schema

        validate :options_type_valid?
        validate :options_parameters_valid?
        validate :nested_options_valid?
        validate :enumeration_valid?
        validate :visibility_valid?
        validate :notice_type_valid?
        validate :notice_action_valid?
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
          @sample = keep_as_is?(value) ? value : type_def.resolve(value)
        end

        def default=(value)
          @default = keep_as_is?(value) ? value : type_def.resolve(value)
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
          return sample.deep_dup unless sample.nil?
          return default.deep_dup unless default.nil?

          result = type_def.example(self)
          array ? [result] : result
        end

        def deep_dup
          super.tap do |duped|
            duped.attributes = attributes.except(:fields).deep_dup
            duped.fields = fields_without_nested_schema.map(&:deep_dup)
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
          Array(fields).compact.detect { |f| f.try(:id).to_s == field_id.to_s }
        end

        def unloadable_values?
          own_attributes = self.class.attribute_names - [:fields]
          return true if own_attributes.any? { |name| IPaaS::Connector::Common::UnresolvedNode.within?(send(name)) }

          Array(fields_without_nested_schema).any? do |child|
            child.is_a?(IPaaS::Connector::Common::UnresolvedNode) ||
              (child.is_a?(Field) && child.unloadable_values?)
          end
        end

        def secret_string?
          type == :secret_string
        end

        def declares_secret_string?
          return true if secret_string?
          return false unless type == :nested

          Array(fields).any? { |field| field.is_a?(Field) && field.declares_secret_string? }
        end

        def to_h_ref
          attributes = SERIALIZABLE_ATTRS.dup
          attributes.delete(:visibility) if visibility == 'visible' # This is the default
          attributes.delete(:remove_unmapped_fields) if type != :nested || remove_unmapped_fields == true
          attributes.delete(:fields) unless fields_without_nested_schema.present?
          IPaaS::Connector::Common::Serializer.to_h(self, *attributes)
        end

        protected

        def descendant_option_field_ids
          Array(fields_without_nested_schema).grep(Field).flat_map do |child|
            (child.options ? [child.id] : []) + child.descendant_option_field_ids
          end
        end

        private

        def option_parameter_names(kinds)
          return [] unless options

          options.parameters.filter_map { |kind, name| name if kinds.include?(kind) }
        end

        def keep_as_is?(value)
          value.nil? || !type_def.respond_to?(:resolve) ||
            IPaaS::Connector::Common::UnresolvedNode.within?(value)
        end

        def parse_enumeration
          return unless convertible_enumeration?

          self.enumeration = enumeration.map { |val| { id: val, label: val.to_s } }
        end

        def convertible_enumeration?
          return false if self.enumeration.is_a?(IPaaS::Connector::Common::UnresolvedNode)
          return false unless self.enumeration&.first.present?
          return false if self.enumeration.first.is_a?(Hash)
          return false unless self.type.in?(ENUMERABLE_TYPES)

          !IPaaS::Connector::Common::UnresolvedNode.within?(self.enumeration)
        end

        def nested_options_valid?
          return unless self.array

          offenders = descendant_option_field_ids
          return if offenders.empty?

          errors.add(:fields, 'cannot provide dynamic options inside an array field, so ' \
                              "#{offenders.join(', ')} must drop the options block.")
        end

        def options_type_valid?
          return if options.blank? || self.type.in?(ENUMERABLE_TYPES)

          errors.add(:options, 'are restricted to string, integer, and time zone types.')
        end

        def options_parameters_valid?
          return unless options

          unsupported = options.parameters.filter_map do |kind, name|
            name unless OPTION_DEPENDENCY_PARAMETER_KINDS.include?(kind)
          end
          return if unsupported.empty?

          errors.add(:options, 'must declare every dependency as a keyword parameter, so ' \
                               "#{unsupported.join(', ')} cannot be used. Write |name:| instead of |name|.")
        end

        def enumeration_valid?
          return if self.enumeration.blank? || errors[:enumeration].any?

          unless self.type.in?(ENUMERABLE_TYPES)
            errors.add(:enumeration, 'Enumeration is restricted to string, integer, and time zone types.')
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

        def notice_type_valid?
          return if self.notice_type.blank?

          return if NOTICE_TYPES.include?(self.notice_type)
          errors.add(:notice_type, 'is invalid.')
        end

        def notice_action_valid?
          return if self.notice_action.blank?

          return if NOTICE_ACTIONS.include?(self.notice_action)
          errors.add(:notice_action, 'is invalid.')
        end

        def valid_enum_value?(value)
          return false unless value.is_a?(Hash)

          value[:id].present? && value[:label].present?
        end

        def type_valid?
          return unless type.present?
          return if IPaaS::Connector::Common::UnresolvedNode.within?(type)
          return if ANY_TYPE_PATTERN.match?(type.to_s) # any_item_type
          return if IPaaS::Connector::Types.for(type.to_sym)

          errors.add(:type, "should be one of #{known_type_list}.")
        end

        def known_type_list
          IPaaS::Connector::Types.all.keys.sort.map(&:inspect).join(', ').gsub(':any', ':any_..._type')
        end

        def fields_valid?
          report_schema_shadowed_fields
          return unless fields_without_nested_schema.any?
          return if type_def.nested?

          errors.add(:fields, 'Subfields are only available when the type is nested.')
        end

        def report_schema_shadowed_fields
          return unless type_def.respond_to?(:schema)

          stored = fields_without_nested_schema
          return unless IPaaS::Connector::Common::UnresolvedNode.within?(stored)

          report_unresolved_values(:fields, stored)
        end
      end
    end
  end
end
