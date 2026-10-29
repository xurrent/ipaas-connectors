module IPaaS
  module Connector
    class EnvironmentVariable
      TYPES = [:string, :secret_string, :hashed_credential].freeze

      include IPaaS::Connector::Common::Model
      include IPaaS::Connector::Common::UuidMixin

      attr_accessor :solution

      attribute :name, required: true, length: { in: 1..120 }
      attribute :description
      attribute :type, type: Symbol, required: true

      validate :type_valid?

      class << self
        def parse(yaml, resolve: true, tolerant: false, name: nil)
          hash = IPaaS::Connector::Common::Serializer.parse(yaml, with_uuid: true, tolerant: tolerant, name: name)
          raise IPaaS::Error, 'EnvironmentVariable must be a hash.' unless hash.is_a?(Hash)
          refuse_non_text_uuid!(hash)
          hash = loaded_binary_as_text(hash).deep_symbolize_keys

          EnvironmentVariable.new(hash[:uuid]).tap do |var|
            copy_connection_values(var, hash)
            var.valid? if resolve
          end
        end

        def copy_connection_values(var, hash)
          var.name = loaded_text(hash[:name])
          var.description = loaded_text(hash[:description])
          var.type = hash[:type]
        end
      end

      def to_h
        IPaaS::Connector::Common::Serializer.to_h(self, :uuid, :name, :description, :type)
      end

      def to_h_ref
        IPaaS::Connector::Common::Serializer.to_h(self, :uuid)
      end

      def value
        solution&.environment_variable_value_for(uuid)&.value
      end

      def type_with_to_sym=(value)
        self.type_without_to_sym = IPaaS::Connector::Common::UnresolvedNode.symbolize(value)
      end

      alias type_without_to_sym= type=
      alias type= type_with_to_sym=

      private

      def type_valid?
        return unless type.present?
        return if type.in?(TYPES)

        errors.add(:type, "must be one of: #{TYPES.join(', ')}")
      end
    end
  end
end
