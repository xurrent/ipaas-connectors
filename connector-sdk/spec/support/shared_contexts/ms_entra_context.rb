shared_context 'microsoft entra', :ms_entra do
  let(:tenant_id) { '9c46a35a-b7cd-42ef-9ce5-9ea1481d40f1' }
  let(:graph) { 'https://graph.microsoft.com/v1.0' }
  let(:token_url) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token" }
  let(:user_id) { '87d349ed-44d7-43e1-9a83-5f2406dee5bd' }
  let(:group_id) { '02bd9fd6-8f93-4758-87c3-1fb73740a315' }
  let(:access_denied) { { error: { code: 'Authorization_RequestDenied', message: 'Insufficient privileges.' } } }

  let(:outbound_connection_config) do
    {
      credentials: {
        tenant_id: tenant_id,
        client_id: 'client-abc',
        client_secret: make_secret_string('secret-def'),
      },
    }
  end

  def graph_error(code, message)
    { error: { code: code, message: message } }.to_json
  end

  before(:each) do
    load_fixture('ms_entra_connector')
    stub_request(:post, token_url)
      .to_return(status: 200, body: { access_token: 'entra-token', expires_in: 3599 }.to_json)
  end
end
