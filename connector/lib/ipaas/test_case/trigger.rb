module IPaaS
  module TestCase
    # Part of a runbook test case that represents the mocked output of the trigger
    class Trigger
      include IPaaS::Connector::Common::Model
      include IPaaS::Job::Context

      attribute :mocked_output, type: [IPaaS::Connector::Mapping::FieldMapping]
      attribute :mocked_job_context_identifier, type: String

      validates :mocked_output, presence: { message: "can't be blank." }
      validates_length_of :mocked_job_context_identifier, maximum: 255

      class << self
        def parse(trigger)
          hash = IPaaS::Connector::Common::Serializer.parse(trigger)
          raise IPaaS::Error, 'Trigger must be a hash.' unless hash.is_a?(Hash)
          hash = hash.deep_symbolize_keys

          Trigger.new.tap do |obj|
            copy_trigger_values(obj, hash)
          end
        end

        private

        def copy_trigger_values(obj, hash)
          obj.mocked_output = Array(hash[:mocked_output]).map do |m|
            IPaaS::Connector::Mapping::FieldMapping.parse(m)
          end
          obj.mocked_job_context_identifier = hash[:mocked_job_context_identifier]&.to_s.presence
        end
      end

      def to_h_ref
        IPaaS::Connector::Common::Serializer.to_h(self, :mocked_output, :mocked_job_context_identifier)
      end

      def update_action_reference(reference_was, new_reference)
        updated = false
        mocked_output.each do |output|
          updated |= output.update_action_reference(reference_was, new_reference)
        end
        updated
      end
    end
  end
end
