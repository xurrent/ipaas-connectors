def load_minimal_fixture
  Object.send(:remove_const, :MinimalConnector) if Object.const_defined?(:MinimalConnector)
  load(File.join(File.dirname(__FILE__), '../fixtures/minimal_connector.rb'))
  @connector = IPaaS::Connector.by_uuid('uuid-connector')
  @trigger = @connector.trigger('uuid-trigger')
  @action = @connector.action('uuid-action')
end
