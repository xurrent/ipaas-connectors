module IPaaS
  module TestCase
    class ExpectedOutput
      include IPaaS::Connector::Common::Model

      attribute :schema_reference, type: String
      attribute :expectations, type: [IPaaS::TestCase::Expectation]

      validate :expectations_valid?

      class << self
        def parse(hash)
          ExpectedOutput.new.tap do |obj|
            obj.schema_reference = hash[:schema_reference].to_s if hash.key?(:schema_reference)
            obj.expectations = Array.wrap(hash[:expectations]).map do |expectation|
              IPaaS::TestCase::Expectation.parse(expectation)
            end
          end
        end
      end

      def to_h_ref
        IPaaS::Connector::Common::Serializer.to_h(self, :schema_reference, :expectations)
      end

      def update_action_reference(reference_was, new_reference)
        updated = false
        expectations.each do |expectation|
          updated |= expectation.update_action_reference(reference_was, new_reference)
        end
        updated
      end

      def update_runbook_variable(id_was, new_id)
        updated = false
        expectations.each do |expectation|
          updated |= expectation.update_runbook_variable(id_was, new_id)
        end
        updated
      end

      private

      def expectations_valid?
        expectations&.each_with_index do |obj, index|
          unless obj.valid?
            errors.add(:expectations, "has errors (expectation #{index + 1}): #{obj.full_error_messages}")
          end
        end
      end
    end
  end
end
