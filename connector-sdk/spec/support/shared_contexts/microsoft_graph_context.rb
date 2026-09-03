shared_context 'microsoft_graph', :microsoft_graph do
  let(:connector_id) { '019ff9e8-8af5-75e8-941c-66be5c24a6a1' }

  let(:tenant_id) { 'test-tenant-id' }
  let(:client_id) { 'test-client-id' }
  let(:client_secret) { 'test-client-secret' }

  let(:outbound_connection_config) do
    {
      credentials: {
        tenant_id: tenant_id,
        client_id: client_id,
        client_secret: make_secret_string(client_secret),
      },
    }
  end

  let(:graph_token_url) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token" }

  def stub_graph_token(access_token: 'test-access-token', status: 200)
    stub_request(:post, graph_token_url)
      .to_return(status: status, body: { access_token: access_token, token_type: 'Bearer', expires_in: 3600 }.to_json)
  end
end
