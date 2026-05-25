module IPaaS
  module TestCase
    # Part of a runbook test case that represents the mocks and expectations of an action
    class Action
      include IPaaS::Connector::Common::Model
      include IPaaS::Job::Context

      attribute :reference # Matches the reference of the action under test

      # Since actions can be executed more than once (e.g. in a loop),
      # we have mocks and expectations for each iteration.
      attribute :iterations, type: [IPaaS::TestCase::ActionIteration]

      validate :iterations_valid?

      def initialize
        self.iterations = []
      end

      class << self
        def parse(action)
          hash = IPaaS::Connector::Common::Serializer.parse(action)
          raise IPaaS::Error, 'Action must be a hash.' unless hash.is_a?(Hash)
          hash = hash.deep_symbolize_keys

          Action.new.tap do |obj|
            obj.reference = hash[:reference]
            obj.iterations = parse_iterations(hash[:iterations])
          end
        end

        def parse_iterations(iterations)
          Array(iterations).map { |iteration| IPaaS::TestCase::ActionIteration.parse(iteration) }
        end
      end

      def to_h_ref
        IPaaS::Connector::Common::Serializer.to_h(self, :reference, :iterations)
      end

      def mocked_outputs(index)
        iteration(index)&.mocked_outputs || []
      end

      def mocked_iteration_state(index)
        iteration(index)&.mocked_iteration_state || []
      end

      def check_input_expectations(action, actual, index)
        iteration(index)&.check_input_expectations(action, actual)
      end

      def check_output_expectations(action, actual, index)
        iteration(index)&.check_expected_outputs(action, actual)
      end

      def check_job_context_identifier_expectations(action, actual, index)
        iteration(index)&.check_job_context_identifier_expectations(action, actual)
      end

      def job_context_identifier_expected?(index)
        !!iteration(index)&.job_context_identifier_expected?
      end

      def check_iteration_state_expectations(action, actual, index)
        iteration(index)&.check_iteration_state_expectations(action, actual)
      end

      def iteration_state_expected?(index)
        !!iteration(index)&.iteration_state_expected?
      end

      def update_action_reference(reference_was, new_reference)
        updated = false
        if reference == reference_was
          self.reference = new_reference
          updated = true
        end
        iterations.each do |iteration|
          updated |= iteration.update_action_reference(reference_was, new_reference)
        end
        updated
      end

      def update_runbook_variable(id_was, new_id)
        updated = false
        iterations.each do |iteration|
          updated |= iteration.update_runbook_variable(id_was, new_id)
        end
        updated
      end

      private

      def iteration(index)
        iterations[index]
      end

      def iterations_valid?
        iterations&.each_with_index do |iteration, index|
          unless iteration.valid?
            errors.add(:iterations, "has errors (iteration #{index + 1}): #{iteration.full_error_messages}")
          end
        end
      end
    end
  end
end
