module IPaaS
  module TestCase
    class MockedOutput
      include IPaaS::Connector::Common::Model

      attribute :schema_reference, type: String
      attribute :output, type: [IPaaS::Connector::Mapping::FieldMapping]

      class << self
        def parse(hash)
          MockedOutput.new.tap do |obj|
            obj.output = Array(hash[:output]).map { |m| IPaaS::Connector::Mapping::FieldMapping.parse(m) }
            obj.schema_reference = hash[:schema_reference].to_s if hash.key?(:schema_reference)
          end
        end
      end

      def to_h_ref
        IPaaS::Connector::Common::Serializer.to_h(self, :schema_reference, :output)
      end

      def update_action_reference(reference_was, new_reference)
        updated = false
        output.each do |output|
          updated |= output.update_action_reference(reference_was, new_reference)
        end
        updated
      end

      def update_runbook_variable(id_was, new_id)
        updated = false
        output.each do |output|
          updated |= output.update_runbook_variable(id_was, new_id)
        end
        updated
      end
    end
  end
end
