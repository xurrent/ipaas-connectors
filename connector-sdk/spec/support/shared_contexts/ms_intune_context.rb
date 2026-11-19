shared_context 'microsoft intune', :ms_intune do
  let(:tenant_id) { '9c46a35a-b7cd-42ef-9ce5-9ea1481d40f1' }
  let(:graph) { 'https://graph.microsoft.com/v1.0' }
  let(:beta) { 'https://graph.microsoft.com/beta' }
  let(:token_url) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token" }
  let(:device_id) { '3b336f00-6f00-3b33-006f-333b006f333b' }
  let(:entra_device_id) { '1ab40ab2-32a8-4b00-b6b5-ba724e407de9' }
  let(:user_id) { '87d349ed-44d7-43e1-9a83-5f2406dee5bd' }
  let(:access_denied_message) { 'Application is not authorized to perform this operation.' }
  let(:access_denied) { graph_error('Forbidden', access_denied_message) }

  let(:outbound_connection_config) do
    {
      credentials: {
        tenant_id: tenant_id,
        client_id: 'client-abc',
        client_secret: make_secret_string('secret-def'),
      },
    }
  end

  let(:endpoint_outside_v1) { 'https://graph.example.com/api' }
  let(:beta_refusal) do
    'This action calls the Microsoft Graph beta API, so the Graph API endpoint of the connection must end in ' \
      "/v1.0 or /beta. '#{endpoint_outside_v1}' does not."
  end

  def graph_error(code, message)
    { error: { code: code, message: message } }.to_json
  end

  def access_denied_failure(permission)
    "Microsoft Graph returned HTTP 403 Forbidden: #{access_denied_message} " \
      "Permission this action needs: #{permission}. Admin consent is required."
  end

  before(:each) do
    load_fixture('ms_entra_intune_connector')
    stub_request(:post, token_url)
      .to_return(status: 200, body: { access_token: 'intune-token', expires_in: 3599 }.to_json)
  end
end
