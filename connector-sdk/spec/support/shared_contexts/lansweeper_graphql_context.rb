shared_context 'lansweeper graphql', :lansweeper_graphql do
  let(:outbound_connection_config) do
    {
      credentials: {
        client_id: 'test-client-id',
        client_secret: make_secret_string('test-client-secret'),
        refresh_token: make_secret_string('test-refresh-token'),
      },
    }
  end

  before(:each) do
    allow_any_instance_of(IPaaS::Connector::Connection).to receive(:authenticate_request) do |_connection, request|
      request.headers['Authorization'] = 'Bearer test-access-token'
      request.headers['Content-Type'] = 'application/json'
      request.headers['x-ls-integration-id'] = LansweeperConnector::LS_INTEGRATION_ID
      request.headers['x-ls-integration-version'] = LansweeperConnector::LS_INTEGRATION_VERSION
    end
  end

  def generate_expected_url
    'https://api.lansweeper.com/api/v2/graphql'
  end
end
