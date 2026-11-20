shared_context 'microsoft exchange online', :microsoft_exchange_online do
  let(:connector_id) { '01a1f2c3-0276-7a6d-88ab-3d9d74512014' }
  let(:tenant_id) { '9c46a35a-b7cd-42ef-9ce5-9ea1481d40f1' }
  let(:organization) { 'contoso.onmicrosoft.com' }
  let(:token_url) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token" }
  let(:runner_base_url) { 'https://exchange-runner.example.test' }
  let(:runner_url) { "#{runner_base_url}/v1/cmdlets" }
  let(:graph_base_url) { 'https://graph.microsoft.com/v1.0' }

  let(:outbound_connection_config) do
    {
      credentials: {
        tenant_id: tenant_id,
        client_id: 'client-abc',
        client_secret: make_secret_string('secret-def'),
      },
      organization: organization,
      cloud: 'Global',
      runner: { url: runner_base_url, api_key: make_secret_string('runner-key') },
    }
  end

  # The runner answers each cmdlet on its own, so every stub matches the cmdlet named in the body. A stub
  # registered later wins in WebMock, which lets an example override one cmdlet of a shared setup.
  def stub_cmdlet(cmdlet, output: [], status: 200, error: nil, headers: {})
    body = status == 200 ? { output: output } : { error: error }
    stub_request(:post, runner_url)
      .with { |request| JSON.parse(request.body)['cmdlet'] == cmdlet }
      .to_return(status: status, body: body.to_json, headers: headers.merge('Content-Type' => 'application/json'))
  end

  def stub_cmdlet_error(cmdlet, error_id:, status: 400, category: 'invalid', message: 'Exchange said no.')
    stub_cmdlet(cmdlet, status: status, error: { category: category, error_id: error_id, message: message })
  end

  def runner_request(cmdlet, parameters = nil)
    a_request(:post, runner_url).with do |request|
      body = JSON.parse(request.body)
      body['cmdlet'] == cmdlet && (parameters.nil? || body['parameters'] == parameters.deep_stringify_keys)
    end
  end

  def expect_reschedule_after(seconds, message = nil, &step)
    Timecop.freeze do
      expect(&step).to raise_error(IPaaS::Job::RescheduleJob, message) do |error|
        expect(error.reschedule_after).to eq(seconds.seconds.from_now)
      end
    end
  end

  before(:each) do
    load_fixture('microsoft_exchange_online_connector')
    stub_request(:post, token_url)
      .with(body: hash_including('scope' => 'https://outlook.office365.com/.default'))
      .to_return(status: 200, body: { access_token: 'exchange-token', expires_in: 3599 }.to_json)
    stub_request(:post, token_url)
      .with(body: hash_including('scope' => 'https://graph.microsoft.com/.default'))
      .to_return(status: 200, body: { access_token: 'graph-token', expires_in: 3599 }.to_json)
  end
end
