shared_context 'connector', :connector do
  def connector
    raise "Missing connector_id. Should be defined like: let(:connector_id) { 'ef6a...8427d' }" unless connector_id

    result = IPaaS::Connector::Connector.by_uuid(connector_id)
    return result if result

    load_all_fixtures
    IPaaS::Connector::Connector.by_uuid(connector_id).tap do |connector|
      raise "Missing connector with id #{connector_id}" unless connector
    end
  end
end
