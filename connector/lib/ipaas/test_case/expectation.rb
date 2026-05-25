module IPaaS
  module TestCase
    class Expectation
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :actual_value

      MATCHERS = [:equals, :contains, :includes, :starts_with, :ends_with, :is_present, :nested, :custom].freeze

      include IPaaS::Connector::Common::Model
      include IPaaS::Connector::Common::ProcContainer

      attribute :field_id, type: Symbol
      attribute :matcher, type: Symbol
      attribute :fixed, type: Object
      attribute :nested, type: [IPaaS::TestCase::Expectation]
      attribute :negated, type: Boolean
      attribute :failure_message, type: String

      attr_accessor :parent_path, :resolved_value, :matcher_class

      before_validation do
        next if matcher == :custom
        self.matcher_class = "IPaaS::TestCase::Matchers::#{matcher.to_s.camelize}Matcher".safe_constantize
      end

      validate :matcher_valid?
      validate :proc_valid?

      class << self
        def parse(hash, parent_path = nil)
          Expectation.new.tap do |obj|
            obj.parent_path = parent_path
            parse_simple_values(obj, hash)
            obj.nested = parse_nested(obj, hash[:nested])
          end
        end

        def parse_simple_values(obj, hash)
          [:fixed, :proc, :negated, :failure_message].each do |attr|
            obj.send("#{attr}=", hash[attr])
          end
          obj.field_id = hash[:field_id]&.to_sym
          obj.matcher = hash[:matcher]&.to_sym || :equals
        end

        def parse_nested(obj, value)
          path = [obj.parent_path, obj.field_id].compact.join('.')
          Array.wrap(value).map do |nested|
            IPaaS::TestCase::Expectation.parse(nested, path)
          end
        end
      end

      def to_h_ref
        IPaaS::Connector::Common::Serializer.to_h(
          self,
          :field_id, :matcher, :fixed, :proc, :nested, :failure_message
        ).tap do |h|
          h[:fixed] = fixed unless fixed.nil? # Make sure that e.g. [] is present in the output
        end
      end

      def match(context, actual_value, schema: nil)
        return [to_invalid_message(actual_value)] unless valid?

        if field_id
          actual_value = (actual_value || {})[field_id]
          field = schema&.field(field_id)
        end

        if matcher == :nested
          match_nested(context, actual_value, schema: schema)
        else
          match_non_nested(context, actual_value, field: field)
        end
      end

      def update_action_reference(reference_was, new_reference)
        IPaaS::Connector::Mapping.update_action_reference(self, reference_was, new_reference)
      end

      def update_runbook_variable(id_was, new_id)
        IPaaS::Connector::Mapping.update_runbook_variable(self, id_was, new_id)
      end

      private

      def to_failure_message(actual_value)
        details = failure_message_details(actual_value)

        "Expectation failed#{field_description_postfix} with #{'negated ' if negated}#{matcher} matcher.\n#{details}"
      end

      def to_invalid_message(actual_value)
        error_msgs = errors.messages.map { |a, messages| "#{a}: '#{messages.join("'; ")}'" }.join("\n")
        "Invalid expectation#{field_description_postfix}.\n#{error_msgs}\nActual value: '#{actual_value}'"
      end

      def field_description_postfix
        field_description = [parent_path, field_id].compact.join('.').presence
        return '' unless field_description

        " for field '#{field_description}'"
      end

      def failure_message_details(actual_value)
        details = []
        details << "Actual value: '#{actual_value}'"
        details << if failure_message.present?
                     "Failure message: #{failure_message}"
                   elsif matcher == :custom
                     "Matcher: '#{proc}'"
                   else
                     "Expected value: '#{resolved_value}'"
                   end
        details.join("\n")
      end

      def match_nested(context, actual_value, schema: nil)
        nested.flat_map do |expectation|
          expectation.match(context, actual_value, schema: schema)
        end
      end

      def match_non_nested(context, actual_value, field:)
        match_result = if matcher == :custom
                         match_custom?(context, actual_value)
                       else
                         match_standard?(context, actual_value, field: field)
                       end
        passed = negated ? !match_result : match_result
        passed ? [] : [to_failure_message(actual_value)]
      end

      def match_custom?(context, actual_value)
        with_actual_value(context, actual_value) do
          IPaaS::Connector::Common::ProcHelper.new(context, proc).execute_if_valid == true
        end
      end

      def match_standard?(context, actual_value, field:)
        self.resolved_value = resolve_expected_value(context, field: field)
        matcher_class.matches?(actual_value, resolved_value)
      end

      def resolve_expected_value(context, field:)
        if proc.present?
          IPaaS::Connector::Common::ProcHelper.new(context, proc).execute_if_valid
        elsif field
          resolve_fixed_with_field(context, field)
        else
          fixed
        end
      end

      def resolve_fixed_with_field(context, field)
        type_def = field.type_def
        if field.array && fixed.is_a?(Array)
          fixed.map do |item|
            type_def.resolve(item, context: context)
          end
        else
          type_def.resolve(fixed, context: context)
        end
      end

      def with_actual_value(context, actual)
        original_method = context.method(:actual_value) if context.respond_to?(:actual_value)
        context.define_singleton_method(:actual_value) { actual }

        yield
      ensure
        restore_method(context, :actual_value, original_method)
      end

      # FIXME: DRY, this method also exists in the Ruby job context
      def restore_method(context, method_name, original_method)
        if original_method
          context.define_singleton_method(method_name, original_method)
        else
          context.singleton_class.undef_method(method_name)
        end
      end

      def matcher_valid?
        return true if matcher == :nested
        return valid_custom_matcher_proc? if matcher == :custom
        return valid_not_nested_matcher? if matcher.in?(MATCHERS)

        errors.add(:matcher, "must be one of: #{MATCHERS.join(', ')}.")
        false
      end

      def valid_custom_matcher_proc?
        return true if proc.present?

        errors.add(:proc, 'Custom matcher requires proc.')
        false
      end

      def valid_not_nested_matcher?
        return true unless matcher_class.nil?

        errors.add(:matcher, "Unknown matcher: #{matcher}")
        false
      end

      def proc_valid?
        return if proc.blank?

        proc_error_msgs = Set.new
        on_invalid = ->(msg) {
          proc_error_msgs << msg
        }

        proc_helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc, on_invalid: on_invalid)
        return if proc_helper.valid?

        errors.add(:proc, proc_error_msgs.size == 1 ? proc_error_msgs.first : proc_error_msgs.to_a.to_s)
        false
      end
    end
  end
end
