module IPaaS
  module Connector
    # schema definition for connector.inbound_connection
    class InboundConnectionTemplate
      include IPaaS::Connector::Common::Model

      attr_accessor :connector

      attribute :validators, type: [Symbol], default: []
      validate :validators_valid?

      schema :config_schema do
        connector&.inbound_connection&.validators&.each do |validator|
          includes IPaaS::Connector::Authentication::Inbound.module(validator)
        end
      end

      IPaaS::Connector::Authentication::Inbound.keys.each do |validator_key|
        define_method(:"#{validator_key}_validator") do
          validators << validator_key unless validators.include?(validator_key)
        end
      end

      function :validate
      validate :validate_valid?

      private

      def validators_valid?
        valid_keys = IPaaS::Connector::Authentication::Inbound.keys
        unknown_validators = validators.reject { |validator| valid_keys.include?(validator) }
        return if unknown_validators.empty?

        errors.add(:validators, "unknown: #{unknown_validators.join(', ')}.")
      end

      def validate_valid?
        return if validate.present?
        return if validators.any?

        errors.add(:validate, "Validate function is required, define 'validate do ... end'.")
      end
    end
  end
end
