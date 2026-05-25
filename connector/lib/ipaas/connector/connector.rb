module IPaaS
  module Connector
    def self.by_uuid(uuid)
      IPaaS::Connector::Connector.by_uuid(uuid)
    end

    # Top level class containing the iPaaS connector definition.
    # It accepts the following configuration:
    #  * name
    #  * avatar
    #  * description
    #  * inbound_connection (IPaaS::Connector::InboundConnectionTemplate)
    #  * outbound_connection (IPaaS::Connector::OutboundConnectionTemplate)
    #  * trigger (IPaaS::Connector::TriggerTemplate, multiple allowed)
    #  * action (IPaaS::Connector::ActionTemplate, multiple allowed)
    class Connector
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :connection, :connector, :trigger, :action, :helper, :type_enumeration,
                :inbound_connection, :outbound_connection

      include IPaaS::Connector::Common::Model
      include IPaaS::Connector::Common::UuidMixin
      include IPaaS::Connector::Dsl::HelpersMixin

      attribute :version # source file hash
      attribute :name, required: true, length: { in: 4..120 }
      attribute :avatar, format: { with: IPaaS::Connector::Types::AVATAR_REGEXP }
      attribute :description

      attr_writer :inbound_connection, :outbound_connection
      validate :inbound_connection_valid?
      validate :outbound_connection_valid?

      attr_accessor :triggers do
        []
      end
      validate :triggers_valid?

      attr_accessor :actions do
        []
      end
      validate :actions_valid?

      def inbound_connection(&block)
        return @inbound_connection unless block
        raise IPaaS::Error, 'Duplicate inbound connection.' if instance_variable_defined?(:@inbound_connection)

        IPaaS::Connector::InboundConnectionTemplate.new.tap do |inbound|
          @inbound_connection = inbound
          inbound.connector = self
          inbound.instance_eval(&block)
        end
      end

      def outbound_connection(&block)
        return @outbound_connection unless block
        raise IPaaS::Error, 'Duplicate outbound connection.' if instance_variable_defined?(:@outbound_connection)

        IPaaS::Connector::OutboundConnectionTemplate.new.tap do |outbound|
          @outbound_connection = outbound
          outbound.connector = self
          outbound.instance_eval(&block)
        end
      end

      def trigger(uuid = nil, &block)
        unless block
          return triggers.first if uuid.blank?
          return triggers.detect { |template| template.uuid == uuid }
        end

        IPaaS::Connector::TriggerTemplate.new(uuid).tap do |t|
          t.connector = self
          triggers << t
          t.helpers.parent_helpers = self.helpers
          t.instance_eval(&block)
        end
      end

      def action(uuid = nil, &block)
        return actions.detect { |template| template.uuid == uuid } unless block

        IPaaS::Connector::ActionTemplate.new(uuid).tap do |a|
          a.connector = self
          actions << a
          a.helpers.parent_helpers = self.helpers
          a.instance_eval(&block)
        end
      end

      def helper(name, &block)
        helpers.define_helper(name, &block)
      end

      def update_available?
        default_connector = self.class.default_connector(self.uuid)
        reference_version = default_connector&.version || self.version
        self.version != reference_version
      end

      def type_enumeration
        IPaaS::Connector::Types.all.keys.map(&:to_s)
      end

      def to_h_ref
        IPaaS::Connector::Common::Serializer.to_h(self, :uuid)
      end

      class << self
        def default_connector(uuid)
          IPaaS::Connector::Connector.uuid_scope(IPaaS::Connector::Common::UuidMixin::DEFAULT_SCOPE) do
            by_uuid(uuid)
          end
        end
      end

      private

      def inbound_connection_valid?
        return unless inbound_connection
        return if inbound_connection.valid?

        self.errors.add(:inbound_connection,
                        "Inbound connection has errors: #{inbound_connection.full_error_messages}")
      end

      def outbound_connection_valid?
        return unless outbound_connection
        return if outbound_connection.valid?

        self.errors.add(:outbound_connection,
                        "Outbound connection has errors: #{outbound_connection.full_error_messages}")
      end

      def triggers_valid?
        triggers.reject(&:valid?).each do |trigger|
          self.errors.add(:triggers,
                          "Trigger #{trigger.uuid} has errors: #{trigger.full_error_messages}")
        end
      end

      def actions_valid?
        actions.reject(&:valid?).each do |action|
          self.errors.add(:actions,
                          "Action #{action.uuid} has errors: #{action.full_error_messages}")
        end
      end
    end
  end
end
