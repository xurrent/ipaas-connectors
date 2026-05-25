module IPaaS
  module TestCase
    # A test case tests all or part of a runbook.
    class TestCase
      include IPaaS::Connector::Common::Model
      include IPaaS::Connector::Common::UuidMixin
      include IPaaS::Job::Store
      include IPaaS::Job::Environment

      attribute :name
      attribute :description
      attribute :runbook_uuid
      attribute :trigger, type: IPaaS::TestCase::Trigger
      attribute :actions, type: [IPaaS::TestCase::Action]

      attr_accessor :runbook
      delegate :solution, to: :runbook, allow_nil: true

      validates :name, :trigger, presence: { message: "can't be blank." }
      validate :trigger_valid?
      validate :actions_valid?

      class << self
        def parse(test_case)
          hash = IPaaS::Connector::Common::Serializer.parse(test_case, with_uuid: true)
          raise IPaaS::Error, 'TestCase must be a hash.' unless hash.is_a?(Hash)
          hash = hash.deep_symbolize_keys

          TestCase.new(hash[:uuid]).tap do |obj|
            copy_test_case_values(obj, hash)
            obj.valid?
          end
        end

        private

        def copy_test_case_values(obj, hash)
          obj.name = hash[:name]
          obj.description = hash[:description]
          obj.runbook_uuid = hash[:runbook_uuid]
          obj.trigger = IPaaS::TestCase::Trigger.parse(hash[:trigger]) if hash.key?(:trigger)
          obj.actions = Array(hash[:actions]).map do |action|
            IPaaS::TestCase::Action.parse(action)
          end
        end
      end

      def to_h
        IPaaS::Connector::Common::Serializer.to_h(self, :uuid, :name, :description, :runbook_uuid, :trigger, :actions)
      end

      def update_action_reference(reference_was, new_reference)
        updated = trigger&.update_action_reference(reference_was, new_reference)
        actions.each do |action|
          updated |= action.update_action_reference(reference_was, new_reference)
        end
        updated
      end

      def update_runbook_variable(id_was, new_id)
        updated = false
        actions.each do |action|
          updated |= action.update_runbook_variable(id_was, new_id)
        end
        updated
      end

      def load_runbook
        self.runbook ||= IPaaS::Connector::Runbook.find(runbook_uuid)
      end

      private

      def trigger_valid?
        return true unless trigger
        return true if trigger.valid?

        errors.add(:trigger, "invalid: #{trigger.full_error_messages}")
        false
      end

      def actions_valid?
        return true if actions.blank?

        actions.reject(&:valid?).each do |action|
          errors.add(:actions, "(#{action.reference}) invalid: #{action.full_error_messages}")
        end
        errors[:actions].none?
      end
    end
  end
end
