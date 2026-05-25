module IPaaS
  module Connector
    class RunbookVariable
      NO_VALUE = Object.new.freeze
      include IPaaS::Connector::Common::Model

      attribute :id, required: true, type: String, length: { in: 1..256 }
      attribute :field, type: IPaaS::Connector::Schema::Field
      attribute :value, type: Object

      def initialize(id, field, value = NO_VALUE)
        self.id = id.to_s
        self.field = field
        self.value = value
      end

      validate :field_value_valid?

      private

      def field_value_valid?
        return if field.nil? || value == NO_VALUE

        resolved = resolve_field_value
        return if resolved.valid?

        errors.add(:value, resolved.full_error_messages)
      end

      def resolve_field_value
        schema = IPaaS::Connector::Schema.new(:noop)
        schema.fields = [field]
        schema.resolve(self, [{ field_id: field.id.to_sym, fixed: value }])
      end
    end
  end
end
