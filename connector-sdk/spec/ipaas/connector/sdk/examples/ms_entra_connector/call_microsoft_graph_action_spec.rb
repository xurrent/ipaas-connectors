require 'spec_helper'

describe 'Microsoft Entra Call Microsoft Graph Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-760e-bdd2-e162ae2c5b97' }
  let(:manager_url) { "#{graph}/users/adele.vance@contoso.com/manager" }
  let(:manager) { { id: '0b2e1b59-2b8c-4b36-8d2b-5f6a5d4e1a2b', displayName: 'Megan Bowen' }.to_json }
  let(:path_refused) { %r{must be a Microsoft Graph path that starts with one '/'} }

  def expect_path_refused(path)
    expect { run_action({ method: 'GET', path: path }) }.to raise_error(IPaaS::Job::FailJob, path_refused)
    expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
  end

  describe 'sending the request' do
    it 'sends a GET to the Graph address of the path with the query parameters' do
      stub_request(:get, manager_url).with(query: { '$select' => 'id,displayName', '$top' => '5' })
                                     .to_return(status: 200, body: manager)
      query = [{ name: '$select', value: 'id,displayName' }, { name: '$top', value: '5' }]
      output = run_action({ method: 'GET', path: '/users/adele.vance@contoso.com/manager', query: query })
      expect(output[:status]).to eq(200)
      expect(output[:body]).to eq(manager)
    end

    it 'adds the query parameters after a query that the path already holds' do
      stub_request(:get, "#{graph}/users").with(query: { '$top' => '5', '$select' => 'id' })
                                          .to_return(status: 200, body: '{}')
      output = run_action({ method: 'GET', path: '/users?$top=5', query: [{ name: '$select', value: 'id' }] })
      expect(output[:status]).to eq(200)
    end

    it 'sends no content type on a request with no body' do
      stub_request(:get, "#{graph}/users").to_return(status: 200, body: '{}')
      run_action({ method: 'GET', path: '/users' })
      expect(a_request(:get, "#{graph}/users").with { |request| !request.headers.key?('Content-Type') })
        .to have_been_made.once
    end

    it 'sends the JSON body of a POST with a JSON content type' do
      body = { displayName: 'Finance' }.to_json
      stub_request(:post, "#{graph}/groups").to_return(status: 201, body: '{}')
      run_action({ method: 'POST', path: '/groups', body: body })
      expect(a_request(:post, "#{graph}/groups").with(body: body, headers: { 'Content-Type' => 'application/json' }))
        .to have_been_made.once
    end

    it 'sends the JSON body of a PATCH with a JSON content type' do
      body = { jobTitle: 'Analyst' }.to_json
      stub_request(:patch, "#{graph}/users/#{user_id}").to_return(status: 204, body: '')
      run_action({ method: 'PATCH', path: "/users/#{user_id}", body: body })
      expect(a_request(:patch, "#{graph}/users/#{user_id}")
               .with(body: body, headers: { 'Content-Type' => 'application/json' })).to have_been_made.once
    end

    it 'sends the JSON body of a PUT with a JSON content type' do
      body = { '@odata.id': "#{graph}/users/#{user_id}" }.to_json
      stub_request(:put, "#{graph}/users/#{user_id}/manager/$ref").to_return(status: 204, body: '')
      run_action({ method: 'PUT', path: "/users/#{user_id}/manager/$ref", body: body })
      expect(a_request(:put, "#{graph}/users/#{user_id}/manager/$ref")
               .with(body: body, headers: { 'Content-Type' => 'application/json' })).to have_been_made.once
    end

    it 'fails without a request when the body is not JSON' do
      expect { run_action({ method: 'POST', path: '/groups', body: 'not json' }) }
        .to raise_error(IPaaS::Job::FailJob, /Body must be JSON/)
      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'sends ConsistencyLevel eventual when advanced query is on' do
      stub_request(:get, "#{graph}/users").with(query: hash_including({})).to_return(status: 200, body: '{}')
      run_action({ method: 'GET', path: '/users', query: [{ name: '$count', value: 'true' }], advanced_query: true })
      expect(a_request(:get, "#{graph}/users").with(query: { '$count' => 'true' },
                                                    headers: { 'ConsistencyLevel' => 'eventual' }))
        .to have_been_made.once
    end

    it 'sends no ConsistencyLevel header when advanced query is off' do
      stub_request(:get, "#{graph}/users").to_return(status: 200, body: '{}')
      run_action({ method: 'GET', path: '/users' })
      expect(a_request(:get,
                       "#{graph}/users").with(headers: { 'ConsistencyLevel' => 'eventual' })).not_to have_been_made
      expect(a_request(:get, "#{graph}/users")).to have_been_made.once
    end

    it 'refuses a method it does not know before it sends anything' do
      expect { run_action({ method: 'TRACE', path: '/users' }) }
        .to raise_error(IPaaS::Error, /Field 'method' should be one of GET, POST, PATCH, PUT, DELETE/)
      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    end
  end

  describe 'refusing a path' do
    it 'refuses a path with no leading slash' do
      expect_path_refused('users')
    end

    it 'refuses a path that starts with two slashes' do
      expect_path_refused('//evil.example.com/x')
    end

    it 'refuses a path that holds a dot dot segment' do
      expect_path_refused('/users/../me')
    end

    it 'refuses a path that holds another address' do
      expect_path_refused('/x?y=https://evil')
    end

    it 'refuses a path that holds a space' do
      expect_path_refused('/users/adele vance')
    end

    it 'refuses a path that holds a hash' do
      expect_path_refused('/users#fragment')
    end

    it 'refuses a path that holds a backslash' do
      expect_path_refused('/users\\evil')
    end

    it 'refuses a path that hides two dots in percent encoding' do
      expect_path_refused('/users/%2E%2E/me')
    end

    it 'refuses a path that hides a slash in percent encoding' do
      expect_path_refused('/users%2fevil')
    end

    it 'refuses a path that hides a backslash in percent encoding' do
      expect_path_refused('/users%5Cevil')
    end
  end

  describe 'answers from Microsoft Graph' do
    it 'fails with the message Microsoft Graph gives on 404' do
      missing = "Resource 'manager' does not exist."
      stub_request(:get, manager_url).to_return(status: 404, body: graph_error('Request_ResourceNotFound', missing))
      expect { run_action({ method: 'GET', path: '/users/adele.vance@contoso.com/manager' }) }
        .to raise_error(IPaaS::Job::FailJob, "Microsoft Graph returned HTTP 404 Request_ResourceNotFound: #{missing}")
    end

    it 'fails with the message Microsoft Graph gives and the permission the endpoint needs on 403' do
      stub_request(:get, manager_url).to_return(status: 403, body: access_denied.to_json)
      expect { run_action({ method: 'GET', path: '/users/adele.vance@contoso.com/manager' }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 403 Authorization_RequestDenied: Insufficient privileges. ' \
                        "Permission this action needs: the one that this endpoint's Microsoft Graph page lists. " \
                        'Admin consent is required.')
    end

    it 'reschedules a GET answered 503' do
      stub_request(:get, manager_url).to_return(status: 503, body: 'Service Unavailable')
      expect { run_action({ method: 'GET', path: '/users/adele.vance@contoso.com/manager' }) }
        .to raise_error(IPaaS::Job::RescheduleJob)
    end

    it 'fails a POST answered 503 after one request, because Microsoft may have run it' do
      stub = stub_request(:post, "#{graph}/groups")
             .to_return(status: 503, body: graph_error('serviceNotAvailable', 'Service unavailable'))
      expect { run_action({ method: 'POST', path: '/groups', body: { displayName: 'Finance' }.to_json }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 503 serviceNotAvailable: Service unavailable')
      expect(stub).to have_been_requested.once
    end

    it 'reschedules the job on 429' do
      stub_request(:get, manager_url).to_return(status: 429, body: '{}', headers: { 'Retry-After' => '3' })
      expect { run_action({ method: 'GET', path: '/users/adele.vance@contoso.com/manager' }) }
        .to raise_error(IPaaS::Job::RescheduleJob)
    end
  end
end
