shared_context 'jira', :jira do
  let(:api) { 'https://api.atlassian.com/ex/jira/cloud-1/rest/api/3' }
  let(:webhook_api) { 'https://api.atlassian.com/ex/jira/cloud-1/rest/webhooks/1.0/webhook' }
  let(:tenant_info_url) { 'https://acme.atlassian.net/_edge/tenant_info' }
  let(:basic_auth) { "Basic #{Base64.strict_encode64('bot@example.com:token-abc')}" }
  let(:default_project) { nil }
  let(:outbound_connection_config) do
    { site: 'acme.atlassian.net', email: 'bot@example.com', api_token: make_secret_string('token-abc'),
      default_project: default_project, }.compact
  end
  let(:webhook_secret) { 'jira-webhook-secret' }

  def hub_signature(body, secret = webhook_secret)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
  end

  def signed_post(payload, headers = {})
    post_trigger(payload, headers: { 'X-Hub-Signature' => hub_signature(payload.to_json) }.merge(headers))
  end

  def signed_request(payload)
    body = payload.to_json
    double('request', body: StringIO.new(body), headers: { 'X-Hub-Signature' => hub_signature(body) })
  end

  def expect_reschedule_after(seconds, message = nil, &step)
    Timecop.freeze do
      expect(&step).to raise_error(IPaaS::Job::RescheduleJob, message) do |error|
        expect(error.reschedule_after).to eq(seconds.seconds.from_now)
      end
    end
  end

  def stub_webhook_list(webhooks = [], url: webhook_api)
    stub_request(:get, url).to_return(status: 200, body: webhooks.to_json)
  end

  def stub_creatable_types(project, issue_types)
    stub_request(:get, "#{api}/issue/createmeta/#{project}/issuetypes")
      .with(query: { 'startAt' => '0', 'maxResults' => JiraConnector::MAX_PAGE_SIZE.to_s })
      .to_return(status: 200, body: { issueTypes: issue_types, startAt: 0, total: issue_types.size }.to_json)
  end

  def stub_trigger_projects(issue_type_ids = %w[10001 10003])
    project_url = %r{\Ahttps://api\.atlassian\.com/ex/jira/[^/]+/rest/api/3/project/[^/?]+\z}
    issue_types = issue_type_ids.map { |id| { id: id } }
    stub_request(:get, project_url).to_return do |request|
      { status: 200, body: { key: request.uri.path.split('/').last, issueTypes: issue_types }.to_json }
    end
  end

  def stub_missing_project(key)
    stub_request(:get, "#{api}/project/#{key}")
      .to_return(status: 404, body: { errorMessages: ["No project could be found with key '#{key}'."] }.to_json)
  end

  def seed_stored_webhook(id: '55', secret: webhook_secret, host: 'acme.atlassian.net', jql: 'project = "KAN"')
    trigger.store.write('webhook', {
      'id' => id,
      'host' => host,
      'filter' => jql.delete('"'),
      'secret' => secret && make_secret_string(secret).to_s,
      'signature' => { host: host, endpoint: trigger.endpoint, events: trigger.config[:fire_on], jql: jql }.to_json,
    })
  end

  before do
    load_fixture('jira_connector')
    stub_request(:get, tenant_info_url).to_return(status: 200, body: { cloudId: 'cloud-1' }.to_json)
  end
end
