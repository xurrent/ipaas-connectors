require 'spec_helper'
require_relative 'jira_context'

describe 'Jira paginated actions', :action, :jira do
  def run_page(input = action_input)
    run_action(input, schema_reference: 'page')
  end

  describe 'Search Issues by JQL' do
    let(:action_template_id) { '01a13f2d-b655-736a-8fe6-443987c6ea2e' }
    let(:action_input) { { jql: 'project = KAN' } }

    it 'asks for navigable fields by default, because this endpoint returns only ids otherwise' do
      stub = stub_request(:post, "#{api}/search/jql")
             .with(body: { jql: 'project = KAN', maxResults: 50, fields: ['*navigable'] })
             .to_return(status: 200, body: { issues: [], isLast: true }.to_json)
      run_page
      expect(stub).to have_been_requested.once
    end

    it 'gives the words of Jira for a mistyped field, without blaming a permission' do
      typo = { errorMessages: ["Field 'stauts' does not exist or you do not have permission to view it."] }
      stub_request(:post, "#{api}/search/jql").to_return(status: 400, body: typo.to_json)
      expect { run_page }.to raise_error(
        IPaaS::Job::FailJob,
        "Jira API error (HTTP 400): Field 'stauts' does not exist or you do not have permission to view it."
      )
    end

    it 'rejects a blank JQL at the input mapping, before any request is made' do
      expect { run_page({ jql: '   ' }) }
        .to raise_error(IPaaS::Error, /Field 'jql' is required/)
      expect(a_request(:any, %r{search/jql})).not_to have_been_made
    end

    it 'sends a stored cursor back to Jira on the next pass' do
      action(action_input).send(:iteration_state_value=, { page_token: 'tok-2' })
      stub = stub_request(:post, "#{api}/search/jql")
             .with(body: hash_including({ 'nextPageToken' => 'tok-2' }))
             .to_return(status: 200, body: { issues: [], isLast: true }.to_json)
      run_page
      expect(stub).to have_been_requested.once
    end

    it 'starts at a page token given as input' do
      stub = stub_request(:post, "#{api}/search/jql")
             .with(body: hash_including({ 'nextPageToken' => 'tok-9' }))
             .to_return(status: 200, body: { issues: [], isLast: true }.to_json)
      run_page(action_input.merge(page_token: 'tok-9'))
      expect(stub).to have_been_requested.once
    end

    it 'tries the search again later when Jira answers 503, because a search changes nothing' do
      stub_request(:post, "#{api}/search/jql").to_return(status: 503, body: '')
      expect_reschedule_after(60) { run_page }
    end

    it 'tries the search again later when the connection to Jira fails' do
      stub_request(:post, "#{api}/search/jql").to_timeout
      expect_reschedule_after(60, /Jira did not answer/) { run_page }
    end

    it 'ends on the page Jira marks as last even when it sends a token' do
      stub_request(:post, "#{api}/search/jql")
        .to_return(status: 200, body: { issues: [], isLast: true, nextPageToken: 'tok-x' }.to_json)
      output = run_page
      expect(output).to include(is_last: true, next_page_token: nil)
    end

    context 'when Jira returns a cursor' do
      before do
        page = { issues: [{ id: '1', key: 'KAN-1', fields: { summary: 'a' } }],
                 nextPageToken: 'tok-2', isLast: false, }
        stub_request(:post, "#{api}/search/jql").to_return(status: 200, body: page.to_json)
      end

      it 'stores the cursor and reports that this is not the last page' do
        expect(action(action_input))
          .to receive(:iteration_state_value=).with({ page_token: 'tok-2' }).and_call_original
        output = run_page
        expect(output).not_to have_key(:has_next_page)
        expect(output[:is_last]).to be(false)
        expect(output[:next_page_token]).to eq('tok-2')
        expect(output[:issues].first[:issue_key]).to eq('KAN-1')
      end
    end

    context 'on the last page' do
      before do
        stub_request(:post, "#{api}/search/jql").to_return(status: 200, body: { issues: [], isLast: true }.to_json)
      end

      it 'clears the iteration state so the loop ends' do
        expect(action(action_input)).to receive(:iteration_state_value=).with(nil).and_call_original
        output = run_page
        expect(output[:is_last]).to be(true)
        expect(output[:issues]).to eq([])
      end
    end

    it 'reports the content type of each attachment on a found issue' do
      attachment = { id: '10000', filename: 'report.csv', size: 12, mimeType: 'text/csv' }
      page = { issues: [{ id: '1', key: 'KAN-1', fields: { attachment: [attachment] } }], isLast: true }
      stub_request(:post, "#{api}/search/jql").to_return(status: 200, body: page.to_json)
      output = run_page
      expect(output[:issues].first[:attachments].first).to include(attachment_id: '10000', content_type: 'text/csv')
    end

    it 'returns the field names and schemas that Expand asked for on the page' do
      stub_request(:post, "#{api}/search/jql")
        .with(body: hash_including({ 'expand' => 'names' }))
        .to_return(status: 200, body: { issues: [], isLast: true, names: { summary: 'Summary' } }.to_json)
      output = run_page(action_input.merge(expand: ['names']))
      expect(output[:expanded]).to eq({ 'names' => { 'summary' => 'Summary' } })
    end

    it 'quotes Jira own JQL diagnostic, which names the line and character' do
      jql_error = "Error in the JQL Query: Expecting either 'OR' or 'AND' " \
                  "but got '='. (line 1, character 17)"
      stub_request(:post, "#{api}/search/jql")
        .to_return(status: 400, body: { errorMessages: [jql_error], errors: {} }.to_json)
      expect { run_page }.to raise_error(IPaaS::Job::FailJob, /line 1, character 17/)
    end
  end

  describe 'Search Issues' do
    let(:action_template_id) { '01a13f2d-b655-71bd-ae40-093304bf2ade' }
    let(:action_input) { { project_key: 'KAN' } }

    def stub_search(jql, page = { issues: [], isLast: true })
      stub_request(:post, "#{api}/search/jql")
        .with(body: { jql: jql, maxResults: 50, fields: JiraConnector::SEARCH_SUMMARY_FIELDS })
        .to_return(status: 200, body: page.to_json)
    end

    it 'builds the JQL from the filled filters, quoting text and comparing dates in milliseconds' do
      stub = stub_search('project = "KAN" AND issuetype = 10001 AND status = "In \\"Re\\\\view\\"" AND ' \
                         'assignee = "acc-1" AND labels = "ops" AND created >= 1767323045678 AND ' \
                         'updated < 1769904000000 ORDER BY updated DESC')
      run_page({ project_key: 'KAN', issue_type: '10001', status: 'In "Re\\view"', assignee_account_id: 'acc-1',
                 label: 'ops', created_after: '2026-01-02T03:04:05.678Z', updated_before: '2026-02-01T00:00:00Z', })
      expect(stub).to have_been_requested.once
    end

    context 'when Project is empty and the connection has a default project' do
      let(:default_project) { 'OPS' }

      it 'searches the default project' do
        stub = stub_search('project = "OPS" ORDER BY updated DESC')
        run_page({ page_size: 50 })
        expect(stub).to have_been_requested.once
      end
    end

    it 'refuses a project that is not a key before calling Jira' do
      expect { run_page({ project_key: 'KAN OR 1=1' }) }
        .to raise_error(IPaaS::Job::FailJob, "'KAN OR 1=1' is not a Jira project key or ID.")
      expect(a_request(:any, %r{search/jql})).not_to have_been_made
    end

    it 'returns the short issue shape, the query that ran and the next page token' do
      page = { issues: [{ id: '1', key: 'KAN-1',
                          fields: { summary: 'a', status: { name: 'Done' }, assignee: { accountId: 'acc-1' } }, }],
               nextPageToken: 'tok-2', isLast: false, }
      stub_search('project = "KAN" ORDER BY updated DESC', page)
      output = run_page
      expect(output[:issues].first).to include(issue_key: 'KAN-1', status: 'Done', browse_url: 'https://acme.atlassian.net/browse/KAN-1')
      expect(output[:issues].first[:assignee]).to include(account_id: 'acc-1')
      expect(output).to include(jql: 'project = "KAN" ORDER BY updated DESC', next_page_token: 'tok-2', is_last: false)
    end

    it 'continues the filtered search from the page token the previous page stored' do
      action(action_input).send(:iteration_state_value=, { page_token: 'tok-2' })
      jql = 'project = "KAN" ORDER BY updated DESC'
      stub = stub_request(:post, "#{api}/search/jql")
             .with(body: hash_including({ 'jql' => jql, 'nextPageToken' => 'tok-2' }))
             .to_return(status: 200, body: { issues: [], isLast: true }.to_json)
      run_page
      expect(stub).to have_been_requested.once
    end

    it 'stops the filtered search on the page Jira marks as last' do
      stub_search('project = "KAN" ORDER BY updated DESC')
      expect(action(action_input)).to receive(:iteration_state_value=).with(nil).and_call_original
      expect(run_page).to include(is_last: true, next_page_token: nil)
    end
  end

  describe 'Get Changelog of an Issue' do
    let(:action_template_id) { '01a13f2d-b655-7c06-b0d0-33b304241bc9' }
    let(:action_input) { { issue_id_or_key: 'KAN-1', page_size: 2 } }
    let(:history) do
      { id: '100', created: '2026-10-15T00:00:00.000+0000',
        author: { accountId: 'acc-1', displayName: 'Bot' },
        items: [{ field: 'status', fieldtype: 'jira', fieldId: 'status', from: '1', fromString: 'To Do',
                  to: '3', toString: 'In Progress', }], }
    end

    it 'maps each change with its author and the old and new values' do
      stub_request(:get, "#{api}/issue/KAN-1/changelog")
        .with(query: { 'startAt' => '0', 'maxResults' => '2' })
        .to_return(status: 200, body: { values: [history], isLast: true, total: 1 }.to_json)
      entry = run_page[:entries].first
      expect(entry).to include(id: '100', created: '2026-10-15T00:00:00.000+0000')
      expect(entry[:author]).to include(account_id: 'acc-1', display_name: 'Bot')
      expect(entry[:items].first).to include(field: 'status', field_id: 'status', from: '1', from_string: 'To Do',
                                             to: '3', to_string: 'In Progress')
    end

    it 'continues from the offset in the page token and ends where Jira says it is the last page' do
      action(action_input).send(:iteration_state_value=, { page_token: '2' })
      stub_request(:get, "#{api}/issue/KAN-1/changelog")
        .with(query: { 'startAt' => '2', 'maxResults' => '2' })
        .to_return(status: 200, body: { values: [history, history], isLast: true, total: 9 }.to_json)
      expect(run_page).to include(is_last: true, next_page_token: nil)
    end
  end

  describe 'Get Issue Comments' do
    let(:action_template_id) { '01a13f2d-b655-75db-a5f2-3059c5573d6c' }

    def adf_comment(id, text)
      { id: id,
        body: { type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: text }] }] },
        author: { accountId: 'a', displayName: 'A' }, }
    end
    let(:action_input) { { issue_id_or_key: 'KAN-1', page_size: 2 } }

    it 'pages by offset and flattens each comment body to text' do
      stub_request(:get, "#{api}/issue/KAN-1/comment")
        .with(query: { 'startAt' => '0', 'maxResults' => '2' })
        .to_return(status: 200, body: {
          comments: [adf_comment('1', 'one'), adf_comment('2', 'two')],
          total: 5,
        }.to_json)
      output = run_page
      expect(output[:comments].map { |comment| comment[:comment_body] }).to eq(%w[one two])
      expect(output[:is_last]).to be(false)
    end

    it 'returns the offset of the next page as the page token' do
      stub_request(:get, "#{api}/issue/KAN-1/comment")
        .with(query: hash_including({}))
        .to_return(status: 200,
                   body: { comments: [adf_comment('1', 'one'), adf_comment('2', 'two')], total: 5 }.to_json)
      expect(action(action_input)).to receive(:iteration_state_value=).with({ page_token: '2' }).and_call_original
      expect(run_page[:next_page_token]).to eq('2')
    end

    it 'ends the iteration on a short page, since Jira does not always send isLast' do
      stub_request(:get, "#{api}/issue/KAN-1/comment")
        .with(query: hash_including({}))
        .to_return(status: 200, body: { comments: [{ id: '1', body: 'x' }] }.to_json)
      expect(action(action_input)).to receive(:iteration_state_value=).with(nil).and_call_original
      expect(run_page[:is_last]).to be(true)
    end

    it 'passes the order through when asked' do
      stub = stub_request(:get, "#{api}/issue/KAN-1/comment")
             .with(query: hash_including({ 'orderBy' => '-created' }))
             .to_return(status: 200, body: { comments: [] }.to_json)
      run_page(action_input.merge(order_by: '-created'))
      expect(stub).to have_been_requested.once
    end

    it 'asks for the next offset once a page has been consumed' do
      action(action_input).send(:iteration_state_value=, { page_token: '2' })
      stub = stub_request(:get, "#{api}/issue/KAN-1/comment")
             .with(query: hash_including({ 'startAt' => '2' }))
             .to_return(status: 200, body: { comments: [], total: 2 }.to_json)
      run_page
      expect(stub).to have_been_requested.once
    end

    it 'starts at the offset of a page token given as input' do
      stub = stub_request(:get, "#{api}/issue/KAN-1/comment")
             .with(query: hash_including({ 'startAt' => '4' }))
             .to_return(status: 200, body: { comments: [], total: 4 }.to_json)
      run_page(action_input.merge(page_token: '4'))
      expect(stub).to have_been_requested.once
    end

    it 'keeps paging on a short page when Jira total says there is more' do
      stub_request(:get, "#{api}/issue/KAN-1/comment")
        .with(query: hash_including({}))
        .to_return(status: 200, body: { comments: [{ id: '1', body: 'x' }], total: 9 }.to_json)
      expect(run_page[:is_last]).to be(false)
    end
  end

  describe 'Search Assignable Users' do
    let(:action_template_id) { '01a13f2d-b655-7eeb-aa38-633093dde9cd' }
    let(:action_input) { { project_key: 'KAN', page_size: 2 } }

    def stub_assignable(query, users)
      stub_request(:get, "#{api}/user/assignable/search")
        .with(query: query)
        .to_return(status: 200, body: users.to_json)
    end

    it 'asks for the users of the project who start with the query and maps each one' do
      stub = stub_assignable({ 'project' => 'KAN', 'query' => 'jo', 'startAt' => '0', 'maxResults' => '2' },
                             [{ accountId: 'acc-1', displayName: 'Jo', emailAddress: nil, active: true }])
      output = run_page(action_input.merge(query: 'jo'))
      expect(stub).to have_been_requested.once
      expect(output[:users].size).to eq(1)
      expect(output[:users].first).to include(account_id: 'acc-1', display_name: 'Jo', email_address: nil)
    end

    it 'goes on after an empty page, because Jira leaves out the users it cannot assign' do
      stub_assignable(hash_including({ 'startAt' => '0' }), [])
      later = stub_assignable({ 'project' => 'KAN', 'startAt' => '2', 'maxResults' => '998' }, [{ accountId: 'acc-1' }])
      expect(action(action_input)).to receive(:iteration_state_value=).with({ page_token: '2' }).and_call_original
      expect(run_page).to include(users: [], is_last: false, next_page_token: '2')
      expect(later).to have_been_requested.once
    end

    it 'ends on an empty page when nobody up to the 1000th user can be assigned' do
      stub_assignable(hash_including({ 'startAt' => '0' }), [])
      later = stub_assignable({ 'project' => 'KAN', 'startAt' => '2', 'maxResults' => '998' }, [])
      expect(action(action_input)).to receive(:iteration_state_value=).with(nil).and_call_original
      expect(run_page).to include(users: [], is_last: true, next_page_token: nil)
      expect(later).to have_been_requested.once
    end

    it 'ends on the page that reaches the 1000th user' do
      stub_assignable(hash_including({ 'startAt' => '998' }), [{ accountId: 'acc-1' }])
      expect(run_page(action_input.merge(page_token: '998'))).to include(is_last: true, next_page_token: nil)
    end

    it 'asks about one issue when given an issue key' do
      stub = stub_assignable({ 'issueKey' => 'KAN-1', 'startAt' => '0', 'maxResults' => '2' }, [{ accountId: 'acc-1' }])
      run_page({ issue_id_or_key: 'kan-1', page_size: 2 })
      expect(stub).to have_been_requested.once
    end

    it 'asks about one issue by its ID when given a number' do
      stub = stub_assignable({ 'issueId' => '10001', 'startAt' => '0', 'maxResults' => '2' }, [{ accountId: 'acc-1' }])
      run_page({ issue_id_or_key: '10001', page_size: 2 })
      expect(stub).to have_been_requested.once
    end

    it 'refuses an issue and a project together before calling Jira' do
      expect { run_page(action_input.merge(issue_id_or_key: 'KAN-1')) }
        .to raise_error(IPaaS::Job::FailJob, 'Search Assignable Users takes an issue or a project, not both.')
      expect(a_request(:get, %r{user/assignable})).not_to have_been_made
    end

    context 'when neither an issue nor a project is given' do
      let(:default_project) { 'OPS' }

      it 'uses the default project of the connection' do
        stub = stub_assignable(hash_including({ 'project' => 'OPS' }), [{ accountId: 'acc-1' }])
        run_page({ page_size: 2 })
        expect(stub).to have_been_requested.once
      end
    end
  end
end
