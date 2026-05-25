shared_context 'inbound connection', :inbound_connection do
  include_context 'connector'

  def inbound_connection(config = nil)
    return @inbound_connection if defined?(@inbound_connection)

    config ||= inbound_connection_config if respond_to?(:inbound_connection_config)
    @inbound_connection ||= IPaaS::Connector::Connection.parse(
      {
        uuid: SecureRandom.uuid,
        direction: 'inbound',
        name: 'Inbound connection test',
        connector: {
          uuid: connector.uuid,
        },
        config_mapping: field_mapping(config || [], schema: connector.inbound_connection&.config_schema),
      },
    )
  end
end