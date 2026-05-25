module IPaaS
  module TestCase
    class ActionIteration
      include IPaaS::Connector::Common::Model

      attribute :input_expectations, type: [IPaaS::TestCase::Expectation]
      attribute :mocked_outputs, type: [IPaaS::TestCase::MockedOutput]
      attribute :mocked_iteration_state, type: [IPaaS::Connector::Mapping::FieldMapping]
      attribute :expected_outputs, type: [IPaaS::TestCase::ExpectedOutput]
      attribute :iteration_state_expectations, type: [IPaaS::TestCase::Expectation]
      attribute :job_context_identifier_expectations, type: [IPaaS::TestCase::Expectation]

      validate :input_expectations_valid?
      validate :expected_outputs_valid?
      validate :iteration_state_expectations_valid?
      validate :job_context_identifier_expectations_valid?

      class << self
        def parse(hash)
          new.tap do |iteration|
            attribute_names.each do |attribute_name|
              parsed_value = send("parse_#{attribute_name}", hash[attribute_name])
              iteration.send("#{attribute_name}=", parsed_value)
            end
          end
        end

        def parse_input_expectations(inputs)
          Array(inputs).map { |input| IPaaS::TestCase::Expectation.parse(input) }
        end

        def parse_mocked_outputs(outputs)
          Array(outputs).map { |output| IPaaS::TestCase::MockedOutput.parse(output) }
        end

        def parse_mocked_iteration_state(iteration_state)
          Array(iteration_state).map do |m|
            IPaaS::Connector::Mapping::FieldMapping.parse(m)
          end
        end

        def parse_job_context_identifier_expectations(expectations)
          parse_input_expectations(expectations)
        end

        def parse_expected_outputs(expectations)
          Array(expectations).map { |expectation| IPaaS::TestCase::ExpectedOutput.parse(expectation) }
        end

        def parse_iteration_state_expectations(expectations)
          Array(expectations).map { |input| IPaaS::TestCase::Expectation.parse(input) }
        end
      end

      def to_h_ref
        IPaaS::Connector::Common::Serializer.to_h(self, *self.class.attribute_names)
      end

      def check_input_expectations(action, actual)
        return nil unless input_expectations.present?
        check_expectations(action, actual, input_expectations, schema: action.input_schema)
      end

      def check_expected_outputs(action, actual)
        return nil unless expected_outputs.present?

        if action.nested?
          check_nested_expectations(action, actual, expected_outputs)
        else
          schema = action.output_schema.first
          check_expectations(action, actual.first[:output], expected_outputs.first&.expectations || [], schema: schema)
        end
      end

      def check_job_context_identifier_expectations(action, actual)
        return nil if !job_context_identifier_expected? && actual.blank?

        if job_context_identifier_expected?
          check_expectations(action, actual, job_context_identifier_expectations)
        else
          ExpectationResult.new.tap do |result|
            result.errors << "No job context identifier change expected, got: #{actual}"
          end
        end
      end

      def check_iteration_state_expectations(action, actual)
        unless iteration_state_expected?
          return nil if actual.blank?

          return ExpectationResult.new.tap do |result|
            result.errors << "No iteration state expected, got: #{actual}"
          end
        end

        check_expectations(action, actual, iteration_state_expectations, schema: action.iteration_state_schema)
      end

      def iteration_state_expected?
        iteration_state_expectations.present?
      end

      def job_context_identifier_expected?
        job_context_identifier_expectations.present?
      end

      def update_action_reference(reference_was, new_reference)
        updated = false
        self.class.attribute_names.each do |attribute_name|
          Array(send(attribute_name)).each do |value|
            updated |= value.update_action_reference(reference_was, new_reference)
          end
        end
        updated
      end

      def update_runbook_variable(id_was, new_id)
        updated = false
        self.class.attribute_names.each do |attribute_name|
          Array(send(attribute_name)).each do |value|
            updated |= value.update_runbook_variable(id_was, new_id)
          end
        end
        updated
      end

      private

      def check_nested_expectations(action, actual_outputs, expected_outputs)
        actuals_by_reference = (actual_outputs || []).group_by { |a| a[:schema_reference] }
        expected_by_reference = expected_outputs.group_by(&:schema_reference)
        check_nested_expectations_by_reference(action, actuals_by_reference, expected_by_reference)
      end

      def check_nested_expectations_by_reference(action, actuals_by_reference, expected_by_reference)
        expected_by_reference.each_with_object(ExpectationResult.new) do |(reference, expected_outputs), result|
          actuals = actuals_by_reference[reference] || []
          next unless expected_size_ok?(actuals, expected_outputs, reference, result)

          schema = action.find_output_schema(reference)
          expected_outputs.zip(actuals).each do |expected_output, actual|
            output = actual[:output]
            expectations = expected_output.expectations
            result.errors += check_expectations(action, output, expectations, schema: schema).errors
          end
        end
      end

      def expected_size_ok?(actuals, outputs, reference, result)
        return true if actuals.length == outputs.length

        result.errors << <<~ERROR
          Expectation failed for number of outputs for schema '#{reference}'.
          Actual value: #{actuals.length}
          Expected value: #{outputs.length}
        ERROR

        false
      end

      def check_expectations(action, actual, expectations, schema: nil)
        (expectations || []).each_with_object(ExpectationResult.new) do |expectation, result|
          result.errors += expectation.match(action, actual, schema: schema)
        end
      end

      def input_expectations_valid?
        input_expectations&.each_with_index do |obj, index|
          unless obj.valid?
            errors.add(:input_expectations, "Input expectation #{index + 1} has errors: #{obj.full_error_messages}")
          end
        end
      end

      def expected_outputs_valid?
        if mocked_outputs.present? && expected_outputs.present?
          errors.add(:expected_outputs, 'Cannot set expectations on mocked output.')
        end

        expected_outputs&.each_with_index do |obj, index|
          unless obj.valid?
            errors.add(:expected_outputs, "has errors (output #{index + 1}): #{obj.full_error_messages}")
          end
        end
      end

      def iteration_state_expectations_valid?
        return true if iteration_state_expectations.blank?

        add_iteration_state_expectations_errors
        errors[:iteration_state_expectations].none?
      end

      def add_iteration_state_expectations_errors
        if mocked_iteration_state.present?
          errors.add(:iteration_state_expectations, 'Cannot set expectations on mocked iteration state.')
        end

        iteration_state_expectations.each_with_index do |obj, index|
          unless obj.valid?
            errors.add(:iteration_state_expectations,
                       "Iteration state expectation #{index + 1} has errors: #{obj.full_error_messages}")
          end
        end
      end

      def job_context_identifier_expectations_valid?
        job_context_identifier_expectations&.each_with_index do |obj, index|
          unless obj.valid?
            errors.add(:job_context_identifier_expectations,
                       "Job context identifier expectation #{index + 1} has errors: #{obj.full_error_messages}")
          end
        end
      end
    end
  end
end
