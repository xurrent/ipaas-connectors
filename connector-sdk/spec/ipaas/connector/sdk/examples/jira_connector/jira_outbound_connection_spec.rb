require 'spec_helper'
require_relative 'jira_context'

describe 'Jira outbound connection', :jira, :outbound_connection do
  let(:connector_id) { '01a13f2d-b655-7332-952d-145b7c29f5c3' }
  let(:request) { Faraday::Request.create(:get) { |req| req.headers = {} } }
  let!(:project_list) do
    stub_request(:get, "#{api}/project/search").with(query: { 'maxResults' => '1' })
                                               .to_return(status: 200, body: { values: [{ key: 'KAN' }] }.to_json)
  end

  describe 'config_schema' do
    it 'requires the site, the email and the token' do
      required = [:site, :email, :api_token].map { |id| outbound_connection.config_schema.field(id).required }
      expect(required).to all(be(true))
    end

    it 'keeps every credential in a secret field' do
      expect(outbound_connection.config_schema.field(:api_token).type).to eq(:secret_string)
    end

    it 'offers an optional default project picked from a list' do
      field = outbound_connection.config_schema.field(:default_project)
      expect(field.visibility).to eq('optional')
      expect(field.options).to be_present
    end
  end

  describe 'authenticate' do
    it 'sends basic auth built from the email and the token' do
      outbound_connection.authenticate_request(request)
      expect(request.headers['Authorization']).to eq(basic_auth)
      expect(request.headers['Accept']).to eq('application/json')
    end

    context 'with whitespace pasted around the token' do
      let(:outbound_connection_config) do
        { site: 'acme.atlassian.net', email: ' bot@example.com ', api_token: make_secret_string("  token-abc \n") }
      end

      it 'strips it rather than sending a credential that cannot work' do
        outbound_connection.authenticate_request(request)
        expect(request.headers['Authorization']).to eq(basic_auth)
      end
    end

    context 'when the connection has no credentials yet' do
      let(:outbound_connection_config) { { site: 'acme.atlassian.net', email: '', api_token: nil } }

      it 'fails the job rather than calling Jira without credentials' do
        expect { outbound_connection.authenticate_request(request) }
          .to raise_error(IPaaS::Job::FailJob, /no email or API token/)
        expect(request.headers).not_to have_key('Authorization')
      end
    end
  end

  describe 'config_tester' do
    it 'offers a connection test' do
      expect(outbound_connection.config_tester?).to be true
    end

    it 'names the account, its id and the site on success' do
      stub_request(:get, "#{api}/myself")
        .to_return(status: 200, body: { displayName: 'Build Bot', accountId: 'a1' }.to_json)
      result = outbound_connection.config_tester
      expect(result[:status]).to eq(:success)
      expect(result[:message]).to eq('Connected to Jira site acme.atlassian.net as Build Bot (account ID a1).')
    end

    it 'falls back to the account id when Jira hides the display name' do
      stub_request(:get, "#{api}/myself").to_return(status: 200, body: { accountId: 'a1' }.to_json)
      expect(outbound_connection.config_tester[:message]).to include('a1')
    end

    it 'sends the credentials to the Atlassian gateway and never to the site host' do
      myself = stub_request(:get, "#{api}/myself")
               .with(headers: { 'Authorization' => basic_auth })
               .to_return(status: 200, body: { accountId: 'a1' }.to_json)
      outbound_connection.config_tester
      expect(myself).to have_been_requested.once
      expect(a_request(:get, tenant_info_url).with { |req| !req.headers.key?('Authorization') })
        .to have_been_made.once
    end

    it 'says an API token lasts 1 to 365 days when Jira answers 401' do
      stub_request(:get, "#{api}/myself")
        .to_return(status: 401, body: { code: 401, message: 'Unauthorized' }.to_json)
      result = outbound_connection.config_tester
      expect(result[:status]).to eq(:failed)
      expect(result[:message]).to include('Unauthorized', '1 to 365 days')
    end

    it 'says the scoped token lacks a scope, not that it is wrong, when Jira answers 401 scope does not match' do
      stub_request(:get, "#{api}/myself")
        .to_return(status: 401, body: { code: 401, message: 'Unauthorized; scope does not match' }.to_json)
      expect(outbound_connection.config_tester[:message]).to eq(
        'Jira refused the request (HTTP 401): Unauthorized; scope does not match. The scoped API token on the ' \
        'connection lacks a scope this call needs. Add the scope to the token, or use a classic API token.'
      )
    end

    it 'reports a 403 as failed with Jira own words' do
      stub_request(:get, "#{api}/myself")
        .to_return(status: 403, body: { errorMessages: ['Login denied'] }.to_json)
      result = outbound_connection.config_tester
      expect(result[:status]).to eq(:failed)
      expect(result[:message]).to eq('Jira refused the request (HTTP 403): Login denied.')
    end

    it 'reports any other status as an error carrying Jira own words' do
      stub_request(:get, "#{api}/myself")
        .to_return(status: 500, body: { errorMessages: ['Internal error'] }.to_json)
      result = outbound_connection.config_tester
      expect(result[:status]).to eq(:error)
      expect(result[:message]).to include('Internal error')
    end

    it 'reports what Jira sent when it answers the account read with a page that is not JSON' do
      stub_request(:get, "#{api}/myself").to_return(status: 200, body: '<html>Maintenance</html>')
      result = outbound_connection.config_tester
      expect(result[:status]).to eq(:error)
      expect(result[:message])
        .to eq('Jira returned HTTP 200 with a body that is not a JSON object or list: <html>Maintenance</html>')
    end

    it 'says so when no Jira Cloud site answers at the host' do
      stub_request(:get, tenant_info_url).to_return(status: 404, body: { cloudId: 'cloud-1' }.to_json)
      result = outbound_connection.config_tester
      expect(result[:status]).to eq(:error)
      expect(result[:message]).to include('No Jira Cloud site answers at acme.atlassian.net')
    end

    it 'reads one project when no default project is set, so a token without Jira access fails the test' do
      stub_request(:get, "#{api}/myself").to_return(status: 200, body: { accountId: 'a1' }.to_json)
      expect(outbound_connection.config_tester[:status]).to eq(:success)
      expect(project_list).to have_been_requested.once
    end

    it 'fails with Jira own words when the account may not read projects and no default project is set' do
      stub_request(:get, "#{api}/myself").to_return(status: 200, body: { accountId: 'a1' }.to_json)
      stub_request(:get, "#{api}/project/search").with(query: { 'maxResults' => '1' })
                                                 .to_return(status: 403, body: { errorMessages: ['No scope'] }.to_json)
      result = outbound_connection.config_tester
      expect(result).to eq({ status: :failed, message: 'Jira refused the request (HTTP 403): No scope.' })
    end

    it 'fails when the account can see no project and no default project is set' do
      stub_request(:get, "#{api}/myself").to_return(status: 200, body: { accountId: 'a1' }.to_json)
      stub_request(:get, "#{api}/project/search").with(query: { 'maxResults' => '1' })
                                                 .to_return(status: 200, body: { values: [] }.to_json)
      expect(outbound_connection.config_tester).to eq(
        { status: :failed, message: 'The account can see no Jira project. Add it to the projects it works in.' }
      )
    end

    it 'replaces the stored cloud id with the one the site reports now, so a moved site works again' do
      outbound_connection.store.write('cloud_id:acme.atlassian.net', 'cloud-old')
      stub_request(:get, "#{api}/myself").to_return(status: 200, body: { accountId: 'a1' }.to_json)
      outbound_connection.config_tester
      expect(outbound_connection.store.read('cloud_id:acme.atlassian.net')).to eq('cloud-1')
    end

    context 'with a default project' do
      let(:default_project) { 'KAN' }

      before do
        stub_request(:get, "#{api}/myself").to_return(status: 200, body: { accountId: 'a1' }.to_json)
      end

      it 'checks that the account can open the project' do
        project = stub_request(:get, "#{api}/project/KAN").to_return(status: 200, body: { key: 'KAN' }.to_json)
        expect(outbound_connection.config_tester[:status]).to eq(:success)
        expect(project).to have_been_requested.once
      end

      it 'fails and names the project when the account cannot open it' do
        stub_request(:get, "#{api}/project/KAN")
          .to_return(status: 404, body: { errorMessages: ['No project could be found with key KAN.'] }.to_json)
        result = outbound_connection.config_tester
        expect(result[:status]).to eq(:failed)
        expect(result[:message]).to include('The default project KAN was not found, or this account cannot see it')
      end
    end

    context 'with a default project typed in lower case' do
      let(:default_project) { 'kan' }

      it 'checks the project under its upper-case key, the only form Jira finds' do
        stub_request(:get, "#{api}/myself").to_return(status: 200, body: { accountId: 'a1' }.to_json)
        project = stub_request(:get, "#{api}/project/KAN").to_return(status: 200, body: { key: 'KAN' }.to_json)
        expect(outbound_connection.config_tester[:status]).to eq(:success)
        expect(project).to have_been_requested.once
      end
    end
  end

  describe 'base URL' do
    context 'when the site carries a scheme, capitals, a path and a trailing slash' do
      let(:outbound_connection_config) do
        { site: 'https://ACME.atlassian.net/jira/', email: 'b@e.com', api_token: make_secret_string('t') }
      end

      it 'normalises it rather than building a double scheme' do
        stub = stub_request(:get, "#{api}/myself").to_return(status: 200, body: '{}')
        outbound_connection.config_tester
        expect(stub).to have_been_requested.once
      end
    end

    context 'with no site' do
      let(:outbound_connection_config) { { site: '', email: 'b@e.com', api_token: make_secret_string('t') } }

      it 'refuses the configuration before calling Jira' do
        result = outbound_connection.config_tester
        expect(result).to eq({ status: :error, message: 'Connection configuration is invalid.' })
        expect(a_request(:any, /atlassian/)).not_to have_been_made
      end
    end

    context 'with a site that has no domain' do
      let(:outbound_connection_config) { { site: 'acme', email: 'b@e.com', api_token: make_secret_string('t') } }

      it 'says that no Jira site answers there instead of showing the network error alone' do
        stub_request(:get, 'https://acme/_edge/tenant_info').to_raise(SocketError.new('getaddrinfo failed'))
        result = outbound_connection.config_tester
        expect(result[:status]).to eq(:error)
        expect(result[:message]).to start_with('No Jira Cloud site answers at acme (')
      end
    end

    context 'with a site that is not a host name' do
      let(:outbound_connection_config) do
        { site: 'acme atlassian.net', email: 'b@e.com', api_token: make_secret_string('t') }
      end

      it 'names the field rather than failing obscurely' do
        result = outbound_connection.config_tester
        expect(result[:status]).to eq(:error)
        expect(result[:message]).to include("The Jira site 'acme atlassian.net' on the connection is not a host name")
        expect(a_request(:any, /atlassian/)).not_to have_been_made
      end
    end
  end
end
