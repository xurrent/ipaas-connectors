module IPaaS
  module Connector
    # schema definition for connector.outbound_connection
    class OutboundConnectionTemplate
      include IPaaS::Connector::Common::Model

      attr_accessor :connector

      attribute :authenticators, type: [Symbol], default: []
      validate :authenticators_valid?

      schema :config_schema do
        includes IPaaS::Connector::Authentication::Outbound::ProxyServer

        connector&.outbound_connection&.authenticators&.each do |authenticator|
          includes IPaaS::Connector::Authentication::Outbound.module(authenticator)
        end
      end

      IPaaS::Connector::Authentication::Outbound.keys.each do |authenticator_key|
        define_method(:"#{authenticator_key}_authenticator") do
          authenticators << authenticator_key unless authenticators.include?(authenticator_key)
        end
      end

      function :setup_info
      function :provision
      function :deprovision
      function :authenticate

      private

      def authenticators_valid?
        valid_keys = IPaaS::Connector::Authentication::Outbound.keys
        unknown_authenticators = authenticators.reject { |authenticator| valid_keys.include?(authenticator) }
        return if unknown_authenticators.empty?

        errors.add(:authenticators, "unknown: #{unknown_authenticators.join(', ')}.")
      end
    end
  end
end
