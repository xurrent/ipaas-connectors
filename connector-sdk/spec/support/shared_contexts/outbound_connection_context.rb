shared_context 'outbound connection', :outbound_connection do
  include_context 'connector'

  def outbound_connection(config = nil)
    return @outbound_connection if defined?(@outbound_connection)

    config ||= outbound_connection_config if respond_to?(:outbound_connection_config)
    @outbound_connection ||= IPaaS::Connector::Connection.parse(
      {
        uuid: SecureRandom.uuid,
        direction: 'outbound',
        name: 'outbound connection test',
        connector: {
          uuid: connector.uuid,
        },
        config_mapping: field_mapping(config || [], schema: connector.outbound_connection&.config_schema),
      },
    )
  end
end