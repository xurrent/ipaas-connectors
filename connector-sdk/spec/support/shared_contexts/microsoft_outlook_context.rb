shared_context 'microsoft_outlook', :microsoft_outlook do
  let(:connector_id) { 'f6d6ff74-c001-40a8-90e7-97363438e58f' }

  let(:tenant_id) { 'test-tenant-id' }
  let(:client_id) { 'test-client-id' }
  let(:client_secret) { 'test-client-secret' }
  let(:default_mailbox) { 'shared@contoso.com' }

  let(:outbound_connection_config) do
    {
      credentials: {
        tenant_id: tenant_id,
        client_id: client_id,
        client_secret: make_secret_string(client_secret),
      },
      default_mailbox: default_mailbox,
    }
  end

  let(:graph_token_url) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token" }

  def stub_graph_token(access_token: 'test-access-token', status: 200)
    stub_request(:post, graph_token_url)
      .to_return(status: status, body: { access_token: access_token, token_type: 'Bearer', expires_in: 3600 }.to_json)
  end
end
