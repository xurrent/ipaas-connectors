module IPaaS
  module Connector
    # Instance of an inbound or outbound connection.
    #
    # One is created by parsing a (JSON) hash where the `config_mapping` will be resolved
    # and used as the configuration for the connection.
    class Connection
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :setup_info

      include IPaaS::Connector::Common::Model
      include IPaaS::Connector::Common::UuidMixin
      include IPaaS::Job::Context

      attribute :version # GIT commit ID
      attribute :name, required: true, length: { in: 4..120 }
      attribute :direction, required: true, type: Symbol
      attribute :description
      attribute :connector, type: Connector
      attribute :config_mapping, type: [IPaaS::Connector::Mapping::FieldMapping]

      attr_accessor :solution
      delegate :account_id, to: :solution, allow_nil: true
      attr_accessor :runbook # dynamic for runbook variables

      schema :config_schema # deep copy of connection template config schema

      validates_presence_of :connector
      validate :direction_valid?
      validate :config_mapping_valid?

      class << self
        def parse(connection)
          hash = IPaaS::Connector::Common::Serializer.parse(connection, with_uuid: true)
          raise IPaaS::Error, 'Connection must be a hash.' unless hash.is_a?(Hash)
          hash = hash.deep_symbolize_keys

          Connection.new(hash[:uuid]).tap do |new_connection|
            copy_connection_values(new_connection, hash)
            new_connection.valid? # triggers resolve
          end
        end

        private

        def copy_connection_values(connection, hash)
          connection.name = hash[:name]
          connection.direction = hash[:direction]&.to_sym
          connection.description = hash[:description]
          connection.connector = IPaaS::Connector.by_uuid(hash.dig(:connector, :uuid))
          connection.config_mapping = Array(hash[:config_mapping]).map do |cm|
            IPaaS::Connector::Mapping::FieldMapping.parse(cm)
          end
          connection_template = connection.connector&.send(:"#{connection.direction}_connection")
          connection.copy_schema_blocks_from(connection_template, :config_schema) if connection_template
        end
      end

      def to_h
        IPaaS::Connector::Common::Serializer.to_h(self, :uuid, :name, :direction, :description, :connector,
                                                  :config_mapping)
      end

      def to_h_ref
        IPaaS::Connector::Common::Serializer.to_h(self, :uuid)
      end

      def update_runbook_variable(id_was, new_id)
        updated = false
        config_mapping.each do |mapping|
          updated |= mapping.update_runbook_variable(id_was, new_id)
        end
        updated
      end

      def config(resolve: false)
        return @config if defined?(@config) && !resolve

        config_schema.resolve(self, config_mapping) do |values|
          @config = values
        end
      end

      def inbound?
        direction == :inbound
      end

      def outbound?
        direction == :outbound
      end

      # 'direction' is already in use :(
      def inbound_outbound_internal
        return :inbound if inbound?
        configurable? ? :outbound : :internal
      end

      def validate_request(request)
        return unless inbound? && connection_definition

        connection_definition.validators.each do |validator|
          IPaaS::Connector::Authentication::Inbound.module(validator).validate_request(self, request)
        end
        connection_definition.call_function(:validate, self, request)
      end

      def authenticate_request(request)
        return unless outbound? && connection_definition

        connection_definition.authenticators.each do |authenticator|
          IPaaS::Connector::Authentication::Outbound.module(authenticator).authenticate_request(self, request)
        end
        connection_definition.call_function(:authenticate, self, request)
      end

      def setup_info
        return unless outbound? && connection_definition

        connection_definition.call_function(:setup_info, self)
      end

      def provision
        raise('Cannot provision connection when the config is invalid.') unless config.valid?
        connection_definition.call_function(:provision, self) if outbound?
      end

      def deprovision
        connection_definition.call_function(:deprovision, self) if outbound?
      end

      private

      def connection_definition
        connector&.send(:"#{direction}_connection")
      end

      def direction_valid?
        return if inbound? || outbound?

        errors.add(:direction, 'must be one of "inbound", "outbound".')
      end

      def config_mapping_valid?
        return unless connector && (inbound? || outbound?)
        return if IPaaS::Connector::Mapping.invalid_mapping?(self, :config_mapping)
        return if config.valid?

        errors.add(:config_mapping, "invalid: #{config.full_error_messages}")
      end
    end
  end
end
