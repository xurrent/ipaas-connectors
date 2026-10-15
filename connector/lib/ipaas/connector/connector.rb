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
      # The maximum file size iPaaS allows for connectors, above this value they will not be loaded.
      MAX_SOURCE_FILE_BYTES = 150.kilobytes

      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :connection, :connector, :trigger, :action, :helper, :type_enumeration,
                :inbound_connection, :outbound_connection

      include IPaaS::Connector::Common::Model
      include IPaaS::Connector::Common::UuidMixin
      include IPaaS::Connector::Dsl::HelpersMixin
      include IPaaS::Connector::Common::Sealing::Member

      stays_writable :@proc_validations

      cattr_accessor :proc_validations_factory, instance_accessor: false do
        -> { Set.new }
      end

      attribute :version # source file hash
      attribute :name, required: true, length: { in: 3..120 }
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
      validate :field_options_consistent?

      def inbound_connection(&block)
        return @inbound_connection unless block

        refuse_once_sealed('An inbound connection')
        raise IPaaS::Error, 'Duplicate inbound connection.' if instance_variable_defined?(:@inbound_connection)

        IPaaS::Connector::InboundConnectionTemplate.new.tap do |inbound|
          @inbound_connection = inbound
          owned_by(inbound, self)
          inbound.helpers_definition.parent_helpers = self.helpers_definition
          inbound.instance_eval(&block)
        end
      end

      def outbound_connection(&block)
        return @outbound_connection unless block

        refuse_once_sealed('An outbound connection')
        raise IPaaS::Error, 'Duplicate outbound connection.' if instance_variable_defined?(:@outbound_connection)

        IPaaS::Connector::OutboundConnectionTemplate.new.tap do |outbound|
          @outbound_connection = outbound
          owned_by(outbound, self)
          outbound.helpers_definition.parent_helpers = self.helpers_definition
          outbound.instance_eval(&block)
        end
      end

      def trigger(uuid = nil, &block)
        return triggers.detect { |template| uuid.blank? || template.uuid == uuid } unless block

        refuse_once_sealed('A trigger', triggers)
        IPaaS::Connector::TriggerTemplate.new(uuid).tap do |t|
          owned_by(t, self)
          triggers << t
          t.helpers_definition.parent_helpers = self.helpers_definition
          t.instance_eval(&block)
        end
      end

      def action(uuid = nil, &block)
        return actions.detect { |template| template.uuid == uuid } unless block

        refuse_once_sealed('An action', actions)
        IPaaS::Connector::ActionTemplate.new(uuid).tap do |a|
          owned_by(a, self)
          actions << a
          a.helpers_definition.parent_helpers = self.helpers_definition
          a.instance_eval(&block)
        end
      end

      def helper(name, &block)
        helpers_definition.define_helper(name, &block)
      end

      # This connector and everything it is made of, sealed before any solution code can run.
      def seal!
        IPaaS::Connector::Common::Sealing.seal!(self)
      end

      def warm_for_seal
        super
        # A connector with no block at all never fills proc_validations.
        proc_validations
      end

      # No need to lock, a race condition only costs a few extra validations.
      def proc_validations
        @proc_validations ||= self.class.proc_validations_factory.call
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

      # A template registers itself by uuid as it is built, so a refusal by the frozen list would come too late:
      # the rogue template would still resolve by uuid. The list is what a copy of the connector still shares.
      def refuse_once_sealed(what, registry = self)
        raise FrozenError, "#{what} cannot be defined; this connector is sealed." if registry.frozen?
      end

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

      # The same field id means the same thing across the schemas that carry options, so two of them
      # giving it different options code is a copy-paste slip, not a feature.
      def field_options_consistent?
        options_sources_by_field_id.each do |field_id, sources|
          next if sources.uniq.one?

          self.errors.add(:base, "Field (#{field_id}) has different options code in different schemas")
        end
      end

      def options_sources_by_field_id
        fields_with_options.group_by(&:id).transform_values do |fields|
          fields.map { |field| IPaaS::Connector::Common::ProcHelper.proc_source(field.options).squish }
        end
      end

      # Options are supported on trigger config and action input schemas only. Connection config,
      # output and iteration state schemas, and nested fields, are out of scope until #82325699.
      def fields_with_options
        schemas = triggers.map(&:config_schema) + actions.map(&:input_schema)
        schemas.compact.flat_map(&:fields).select(&:options)
      end
    end
  end
end
