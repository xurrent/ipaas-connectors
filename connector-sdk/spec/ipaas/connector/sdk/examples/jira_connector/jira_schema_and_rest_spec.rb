require 'spec_helper'
require_relative 'jira_context'

describe 'Jira schema and REST actions', :action, :jira do
  let(:site_root) { 'https://api.atlassian.com/ex/jira/cloud-1' }

  describe 'Get Issue Schema' do
    let(:action_template_id) { '01a13f2d-b655-70bd-91ce-b19b81b37e5c' }
    let(:create_meta) { "#{api}/issue/createmeta/KAN/issuetypes/10001" }
    let(:team_field) do
      { fieldId: 'customfield_10234', name: 'Team', required: true, schema: { type: 'array', items: 'option' },
        allowedValues: [{ id: '1', value: 'Red', self: 'x' }, { id: '2', name: 'Blue' }], }
    end

    def stub_create_meta(start_at, fields, total)
      stub_request(:get, create_meta)
        .with(query: { 'startAt' => start_at, 'maxResults' => '200' })
        .to_return(status: 200, body: { fields: fields, startAt: start_at.to_i, maxResults: 1, total: total }.to_json)
    end

    it 'reads every page of the create screen of the project and issue type' do
      field_ids = %w[customfield_0 customfield_1 customfield_2]
      field_ids.each_with_index do |field_id, page|
        stub_create_meta(page.to_s, [{ fieldId: field_id }], field_ids.size)
      end
      output = run_action({ project_key: 'KAN', issue_type: '10001' })
      expect(output[:fields].map { |field| field[:field_id] }).to eq(field_ids)
    end

    it 'reads the create screen of a project key typed in lower case' do
      stub = stub_create_meta('0', [{ fieldId: 'summary' }], 1)
      run_action({ project_key: 'kan', issue_type: '10001' })
      expect(stub).to have_been_requested.once
    end

    it 'fails rather than returning part of a create screen that is longer than one run reads' do
      full_page = Array.new(JiraConnector::SCHEMA_PAGE_SIZE) { { fieldId: 'summary' } }
      stub_request(:get, create_meta)
        .with(query: hash_including({ 'maxResults' => '200' }))
        .to_return(status: 200, body: { fields: full_page, maxResults: full_page.size, total: 1_000_000 }.to_json)
      read = JiraConnector::SCHEMA_PAGE_SIZE * JiraConnector::MAX_SCHEMA_PAGES
      expect { run_action({ project_key: 'KAN', issue_type: '10001' }) }.to raise_error(
        IPaaS::Job::FailJob,
        "Issue type 10001 of project KAN has more than #{read} fields on its create screen, more than Get Issue " \
        'Schema can return.'
      )
    end

    it 'reads the fields from results when Jira sends no fields list' do
      stub_request(:get, create_meta)
        .with(query: hash_including({}))
        .to_return(status: 200, body: { results: [team_field], startAt: 0, maxResults: 200, total: 1 }.to_json)
      output = run_action({ project_key: 'KAN', issue_type: '10001' })
      expect(output[:fields].map { |field| field[:field_id] }).to eq(['customfield_10234'])
    end

    it 'maps each field to its ID, name, type, required flag and allowed values' do
      stub_create_meta('0', [team_field], 1)
      field = run_action({ project_key: 'KAN', issue_type: '10001' })[:fields].first
      expect(field).to include(field_id: 'customfield_10234', field_name: 'Team', field_type: 'array',
                               item_type: 'option', required: true)
      expect(field[:allowed_values].map(&:to_h))
        .to eq([{ 'id' => '1', 'name' => 'Red' }, { 'id' => '2', 'name' => 'Blue' }])
    end

    it 'looks up the issue type ID among the types the account can create when given its name' do
      stub_creatable_types('KAN', [{ id: '10001', name: 'Task' }])
      stub = stub_create_meta('0', [], 0)
      run_action({ project_key: 'KAN', issue_type: 'task' })
      expect(stub).to have_been_requested.once
    end

    it 'refuses an issue type ID from Jira that would change the request path' do
      stub_creatable_types('KAN', [{ id: '../10001', name: 'Task' }])
      expect { run_action({ project_key: 'KAN', issue_type: 'Task' }) }
        .to raise_error(IPaaS::Job::FailJob, "Jira issue type ID is not path safe: '../10001'")
      expect(a_request(:get, %r{issuetypes/\.\.})).not_to have_been_made
    end

    it 'lists the issue types the account can create when the name matches none' do
      stub_creatable_types('KAN', [{ id: '10001', name: 'Task' }, { id: '10002', name: 'Bug' }])
      expect { run_action({ project_key: 'KAN', issue_type: 'Story' }) }.to raise_error(
        IPaaS::Job::FailJob,
        "Project KAN has no issue type named 'Story' that this account can create. Available: Task, Bug."
      )
    end

    it 'says so when the account can create no issue type in the project' do
      stub_creatable_types('KAN', [])
      expect { run_action({ project_key: 'KAN', issue_type: 'Story' }) }.to raise_error(
        IPaaS::Job::FailJob,
        "Project KAN has no issue type named 'Story' that this account can create. Available: none."
      )
    end

    it 'reads the edit screen of an issue, taking each field ID from its key' do
      edit_meta = { fields: {
        'summary' => { name: 'Summary', required: true, schema: { type: 'string' } },
        'customfield_10077' => { name: 'Colour', required: false, schema: { type: 'array', items: 'string' },
                                 allowedValues: %w[red blue], },
      } }
      stub_request(:get, "#{api}/issue/KAN-1/editmeta").to_return(status: 200, body: edit_meta.to_json)
      fields = run_action({ issue_id_or_key: 'kan-1' })[:fields]
      expect(fields.map { |field| field[:field_id] }).to eq(%w[summary customfield_10077])
      expect(fields.last[:allowed_values].map { |value| value[:name] }).to eq(%w[red blue])
    end

    it 'refuses an issue type and an issue together before calling Jira' do
      expect { run_action({ project_key: 'KAN', issue_type: '10001', issue_id_or_key: 'KAN-1' }) }
        .to raise_error(IPaaS::Job::FailJob, 'Get Issue Schema needs an issue type, or an issue ID or key, not both.')
      expect(a_request(:get, /meta/)).not_to have_been_made
    end

    it 'refuses to run with neither an issue type nor an issue' do
      expect { run_action({ project_key: 'KAN' }) }
        .to raise_error(IPaaS::Job::FailJob, 'Get Issue Schema needs an issue type, or an issue ID or key, not both.')
    end
  end

  describe 'Execute Jira REST API Action' do
    let(:action_template_id) { '01a13f2d-b655-7093-8b62-995924004c8f' }
    let(:projects) { { values: [{ key: 'KAN' }], isLast: true, startAt: 0, maxResults: 50, total: 1 } }

    def stub_json(method, url, body, status: 200)
      stub_request(method, url)
        .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json;charset=UTF-8' })
    end

    def expect_path_refused(path)
      expect { run_action({ method: 'GET', path: path }) }.to raise_error(IPaaS::Job::FailJob, /may not hold/)
      expect(a_request(:any, /api\.atlassian\.com/)).not_to have_been_made
    end

    it 'returns the project list for GET /rest/api/3/project/search' do
      stub_json(:get, "#{api}/project/search", projects)
      output = run_action({ method: 'GET', path: '/rest/api/3/project/search' })
      expect(output).to include(status: 200, is_last: true, start_at: 0, max_results: 50, total: 1, content_bytes: nil)
      expect(output[:body]['values']).to eq([{ 'key' => 'KAN' }])
    end

    it 'returns a JSON list as the body' do
      stub_json(:get, "#{api}/field", [{ id: 'summary' }])
      expect(run_action({ method: 'GET', path: '/rest/api/3/field' })[:body]).to eq([{ 'id' => 'summary' }])
    end

    it 'reaches the agile API of the same site' do
      stub = stub_json(:get, "#{site_root}/rest/agile/1.0/board", { values: [] })
      run_action({ method: 'GET', path: '/rest/agile/1.0/board' })
      expect(stub).to have_been_requested.once
    end

    it 'sends a parameter given as a list once for each value' do
      stub_request(:get, %r{/rest/api/3/project/search})
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      encoded = nil
      allow(IPaaS::Job::Outbound::FlatSelectiveParamsEncoder)
        .to receive(:encode).and_wrap_original { |original, params| encoded = original.call(params) }
      run_action({ method: 'GET', path: '/rest/api/3/project/search', query: { id: %w[10000 10001] } })
      expect(encoded).to eq('id=10000&id=10001')
    end

    it 'never sends a credential given in Headers, and sends the other headers' do
      stub = stub_request(:get, "#{api}/myself")
             .with do |request|
               request.headers['Authorization'] == basic_auth &&
                 request.headers['X-Trace'] == '7'
             end
             .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      run_action({ method: 'GET', path: '/rest/api/3/myself',
                   headers: { 'Authorization' => 'Bearer stolen', 'X-Trace' => 7 }, })
      expect(stub).to have_been_requested.once
    end

    it 'never sends a Host, Cookie or Proxy-Authorization header given in Headers' do
      stub = stub_request(:get, "#{api}/myself")
             .with do |request|
               request.headers['Host'] != 'evil.example' && request.headers['Cookie'].nil? &&
                 request.headers['Proxy-Authorization'].nil?
             end
             .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      run_action({ method: 'GET', path: '/rest/api/3/myself',
                   headers: { 'Host' => 'evil.example', 'Cookie' => 'session=1', 'Proxy-Authorization' => 'x' }, })
      expect(stub).to have_been_requested.once
    end

    it 'refuses a query parameter that holds an object before calling Jira' do
      expect { run_action({ method: 'GET', path: '/rest/api/3/myself', query: { expand: { a: 1 } } }) }.to raise_error(
        IPaaS::Job::FailJob,
        'Query parameter expand holds an object or a nested list. Give a text, a number or a list of them.'
      )
    end

    it 'refuses a query parameter that holds a list of objects before calling Jira' do
      expect { run_action({ method: 'GET', path: '/rest/api/3/myself', query: { id: [{ a: 1 }] } }) }
        .to raise_error(IPaaS::Job::FailJob, /\AQuery parameter id holds an object or a nested list\./)
      expect(a_request(:get, /myself/)).not_to have_been_made
    end

    it 'sends no body when Request body is an empty text, also with a GET' do
      stub = stub_json(:get, "#{api}/myself", {})
      run_action({ method: 'GET', path: '/rest/api/3/myself', body: '' })
      expect(stub).to have_been_requested.once
    end

    it 'gives Jira 60 seconds to answer, inside the 90 seconds iPaaS allows one action' do
      stub_json(:get, "#{api}/myself", {})
      allow(action({ method: 'GET', path: '/rest/api/3/myself' })).to receive(:http_connection).and_call_original
      run_action
      expect(action).to have_received(:http_connection)
        .with("#{api}/myself", array_params: :flat, timeout: JiraConnector::ACTION_TIMEOUT)
    end

    it 'sends a list as the body of a PUT' do
      stub = stub_request(:put, "#{api}/filter/1/columns")
             .with(body: '["summary"]', headers: { 'Content-Type' => 'application/json' })
             .to_return(status: 204, body: '')
      run_action({ method: 'PUT', path: '/rest/api/3/filter/1/columns', body: ['summary'] })
      expect(stub).to have_been_requested.once
    end

    it 'reports a 413 as a Jira API error, not as an attachment limit' do
      stub_json(:post, "#{api}/issue/bulk", { errorMessages: ['Request too large'] }, status: 413)
      expect { run_action({ method: 'POST', path: '/rest/api/3/issue/bulk', body: { issueUpdates: [] } }) }
        .to raise_error(IPaaS::Job::FailJob, 'Jira API error (HTTP 413): Request too large')
    end

    it 'sends the body as JSON with a POST' do
      stub = stub_request(:post, "#{api}/issue")
             .with(body: { fields: { summary: 'Hi' } }.to_json, headers: { 'Content-Type' => 'application/json' })
             .to_return(status: 201, body: { key: 'KAN-2' }.to_json, headers: { 'Content-Type' => 'application/json' })
      output = run_action({ method: 'POST', path: '/rest/api/3/issue', body: { fields: { summary: 'Hi' } } })
      expect(stub).to have_been_requested.once
      expect(output).to include(status: 201)
    end

    it 'refuses a body with a GET before calling Jira' do
      expect { run_action({ method: 'GET', path: '/rest/api/3/issue', body: { a: 1 } }) }
        .to raise_error(IPaaS::Job::FailJob, 'A request body is sent with POST and PUT only, not with GET.')
    end

    it 'refuses a path that does not start with /rest/' do
      expect { run_action({ method: 'GET', path: 'https://evil.example/rest/api/3/myself' }) }.to raise_error(
        IPaaS::Job::FailJob,
        "The API path 'https://evil.example/rest/api/3/myself' must start with /rest/, for example " \
        '/rest/api/3/project/search.'
      )
    end

    it "refuses a path that climbs out with '..'" do
      expect { run_action({ method: 'GET', path: '/rest/api/3/../../admin' }) }
        .to raise_error(IPaaS::Job::FailJob, %r{may not hold '\.\.', '//'})
    end

    it 'refuses a path with an encoded dot or slash' do
      expect_path_refused('/rest/api/3/%2E%2e/admin')
    end

    it 'refuses a path that carries its own query string' do
      expect { run_action({ method: 'GET', path: '/rest/api/3/myself?expand=groups' }) }
        .to raise_error(IPaaS::Job::FailJob, /Put query parameters in Query parameters/)
    end

    it 'refuses a path with a doubled slash' do
      expect_path_refused('/rest//api/3/myself')
    end

    it 'refuses a path with a backslash' do
      expect_path_refused('/rest/api/3\\myself')
    end

    it "refuses a path with '#'" do
      expect_path_refused('/rest/api/3/myself#top')
    end

    it "refuses a path with '@'" do
      expect_path_refused('/rest/api/3/@evil.example')
    end

    it 'refuses a path with a space' do
      expect_path_refused('/rest/api/3/my self')
    end

    it 'refuses a path with a character outside ASCII' do
      expect_path_refused('/rest/api/3/project/café')
    end

    it 'refuses a path with an encoded slash' do
      expect_path_refused('/rest/api/3/a%2Fb')
    end

    it 'refuses a path with an encoded backslash' do
      expect_path_refused('/rest/api/3/a%5cb')
    end

    it 'refuses a path with a dot encoded twice' do
      expect_path_refused('/rest/%252e%252e/api/3/myself')
    end

    it "refuses a path with a '%' that starts no code" do
      expect_path_refused('/rest/api/3/issue/100%')
    end

    it 'tries a GET again later when Jira answers 503' do
      stub_request(:get, "#{api}/myself").to_return(status: 503, body: '')
      expect_reschedule_after(60) { run_action({ method: 'GET', path: '/rest/api/3/myself' }) }
    end

    it 'tries a GET again later when Jira does not answer' do
      stub_request(:get, "#{api}/myself").to_timeout
      expect_reschedule_after(60, /Jira did not answer .*The read is tried again later\./) do
        run_action({ method: 'GET', path: '/rest/api/3/myself' })
      end
    end

    it 'fails a POST at once when Jira does not answer, and says the change may have been made' do
      stub_request(:post, "#{api}/issue").to_timeout
      expect { run_action({ method: 'POST', path: '/rest/api/3/issue', body: { a: 1 } }) }.to raise_error(
        IPaaS::Job::FailJob, /\AJira did not answer \(.*\)\. The change may have been made, so check Jira before/
      )
      expect(a_request(:post, "#{api}/issue")).to have_been_made.once
    end

    it 'fails a POST at once when a header holds a line break, without saying the change may have been made' do
      input = { method: 'POST', path: '/rest/api/3/issue', body: { a: 1 }, headers: { 'X-Note' => "a\nb" } }
      expect { run_action(input) }.to raise_error(ArgumentError, %r{CR/LF})
      expect(a_request(:post, /atlassian/)).not_to have_been_made
    end

    it 'fails a GET at once when a header holds a line break, which no retry can mend' do
      expect { run_action({ method: 'GET', path: '/rest/api/3/myself', headers: { 'X-Note' => "a\nb" } }) }
        .to raise_error(ArgumentError, %r{CR/LF})
    end

    it 'fails a POST when Jira answers 503, so that the change is not made twice' do
      stub_request(:post, "#{api}/issue").to_return(status: 503, body: '')
      expect { run_action({ method: 'POST', path: '/rest/api/3/issue', body: { a: 1 } }) }
        .to raise_error(IPaaS::Job::FailJob, /HTTP 503/)
    end

    it 'sends a PUT once and fails when Jira answers 503, so that the change is not made twice' do
      put = stub_request(:put, "#{api}/issue/KAN-1").to_return(status: 503, body: '')
      expect { run_action({ method: 'PUT', path: '/rest/api/3/issue/KAN-1', body: { fields: {} } }) }
        .to raise_error(IPaaS::Job::FailJob, /HTTP 503/)
      expect(put).to have_been_requested.once
    end

    it 'sends a DELETE once and fails when Jira answers 503, so that the delete is not sent twice' do
      delete = stub_request(:delete, "#{api}/issue/KAN-1").to_return(status: 503, body: '')
      expect { run_action({ method: 'DELETE', path: '/rest/api/3/issue/KAN-1' }) }
        .to raise_error(IPaaS::Job::FailJob, /HTTP 503/)
      expect(delete).to have_been_requested.once
    end

    it 'names the path that was not found' do
      stub_json(:get, "#{api}/nothing", { errorMessages: ['Not here'] }, status: 404)
      expect { run_action({ method: 'GET', path: '/rest/api/3/nothing' }) }.to raise_error(
        IPaaS::Job::FailJob,
        'Jira path /rest/api/3/nothing was not found, or this account cannot see it (HTTP 404): Not here'
      )
    end

    it 'returns a response that is not JSON as base64 content' do
      stub_request(:get, "#{api}/attachment/content/1")
        .with(query: { 'redirect' => 'false' })
        .to_return(status: 200, body: 'a,b,c', headers: { 'Content-Type' => 'text/csv' })
      output = run_action({ method: 'GET', path: '/rest/api/3/attachment/content/1', query: { redirect: 'false' } })
      expect(output).to include(content_type: 'text/csv', content_bytes: Base64.strict_encode64('a,b,c'), body: nil)
    end

    it 'refuses a response over the size limit of one runbook step' do
      size = JiraConnector::MAX_DOWNLOAD_BYTES + 1
      stub_request(:get, "#{api}/big").to_return(status: 200, body: 'x' * size)
      expect { run_action({ method: 'GET', path: '/rest/api/3/big' }) }.to raise_error(
        IPaaS::Job::FailJob,
        "The Jira response is #{size} bytes, over the #{JiraConnector::MAX_DOWNLOAD_BYTES}-byte limit of one " \
        'runbook step.'
      )
    end
  end
end
