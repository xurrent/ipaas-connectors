require 'spec_helper'
require_relative 'jira_context'

describe 'Jira issue actions', :action, :jira do
  let(:adf) do
    { 'version' => 1, 'type' => 'doc',
      'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Hello' }] }], }
  end

  describe 'Create Issue' do
    let(:action_template_id) { '01a13f2d-b655-77ed-8ce9-829f4c4eea1d' }
    let(:action_input) { { project_key: 'KAN', issue_type: 'Task', summary: 'Build it' } }

    def expect_fields_sent(fields)
      stub = stub_request(:post, "#{api}/issue")
             .with(body: hash_including({ 'fields' => hash_including(fields) }))
             .to_return(status: 201, body: { id: '1', key: 'KAN-1' }.to_json)
      run_action(action_input)
      expect(stub).to have_been_requested.once
    end

    it 'posts project, issue type and summary, and returns a browse URL Jira does not send' do
      stub = stub_request(:post, "#{api}/issue")
             .with(body: { fields: { summary: 'Build it', project: { key: 'KAN' },
                                     issuetype: { name: 'Task' }, } })
             .to_return(status: 201, body: { id: '1', key: 'KAN-1', self: "#{api}/issue/1" }.to_json)
      output = run_action(action_input)
      expect(stub).to have_been_requested.once
      expect(output[:issue_key]).to eq('KAN-1')
      expect(output[:browse_url]).to eq('https://acme.atlassian.net/browse/KAN-1')
    end

    context 'when the project is numeric' do
      let(:action_input) { { project_key: '10000', issue_type: 'Task', summary: 'S' } }

      it 'sends a numeric project as a project ID' do
        expect_fields_sent('project' => { 'id' => '10000' })
      end
    end

    context 'when the issue type is numeric' do
      let(:action_input) { { project_key: 'KAN', issue_type: '10003', summary: 'S' } }

      it 'sends it as an id rather than a name' do
        expect_fields_sent('issuetype' => { 'id' => '10003' })
      end
    end

    context 'with a plain-text description' do
      let(:action_input) do
        { project_key: 'KAN', issue_type: 'Task', summary: 'S', description: 'Hello' }
      end

      it 'wraps it in Atlassian Document Format, which v3 requires' do
        expect_fields_sent('description' => adf)
      end
    end

    context 'with a formatted description' do
      let(:action_input) do
        { project_key: 'KAN', issue_type: 'Task', summary: 'S', description: "Hello *you*\nsecond line\n\n- one" }
      end
      let(:formatted) do
        { 'version' => 1, 'type' => 'doc', 'content' => [
          { 'type' => 'paragraph', 'content' => [
            { 'type' => 'text', 'text' => 'Hello ' },
            { 'type' => 'text', 'text' => 'you', 'marks' => [{ 'type' => 'strong' }] },
            { 'type' => 'hardBreak' },
            { 'type' => 'text', 'text' => 'second line' },
          ], },
          { 'type' => 'bulletList', 'content' => [
            { 'type' => 'listItem', 'content' => [
              { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'one' }] },
            ], },
          ], },
        ], }
      end

      it 'turns the Markdown-lite text into the matching ADF document' do
        expect_fields_sent('description' => formatted)
      end
    end

    context 'with both a plain-text and a pre-built ADF description' do
      let(:custom_adf) { { 'version' => 1, 'type' => 'doc', 'content' => [] } }
      let(:action_input) do
        { project_key: 'KAN', issue_type: 'Task', summary: 'S',
          description: 'ignored', description_adf: custom_adf, }
      end

      it 'prefers the pre-built document' do
        expect_fields_sent('description' => custom_adf)
      end
    end

    context 'with every optional field supplied' do
      let(:action_input) do
        { project_key: 'KAN', issue_type: 'Task', summary: 'S',
          assignee_account_id: 'acc-1', reporter_account_id: 'acc-2', priority: 'High',
          labels: %w[a b], components: ['Web'], due_date: '2026-12-01', parent_key: 'KAN-9',
          additional_fields: { 'customfield_10234' => 'cf' }, }
      end

      it 'maps each to the shape Jira expects, custom fields included' do
        stub = stub_request(:post, "#{api}/issue")
               .with do |request|
                 fields = JSON.parse(request.body)['fields']
                 fields['assignee'] == { 'id' => 'acc-1' } && fields['reporter'] == { 'id' => 'acc-2' } &&
                   fields['priority'] == { 'name' => 'High' } && fields['labels'] == %w[a b] &&
                   fields['components'] == [{ 'name' => 'Web' }] && fields['duedate'] == '2026-12-01' &&
                   fields['parent'] == { 'key' => 'KAN-9' } && fields['customfield_10234'] == 'cf'
               end
               .to_return(status: 201, body: { id: '1', key: 'KAN-1' }.to_json)
        run_action(action_input)
        expect(stub).to have_been_requested.once
      end
    end

    context 'with a priority picked from the list' do
      let(:action_input) { { project_key: 'KAN', issue_type: 'Task', summary: 'S', priority: '2' } }

      it 'sends the priority by its id' do
        expect_fields_sent('priority' => { 'id' => '2' })
      end
    end

    context 'when Project is empty and the connection has a default project' do
      let(:default_project) { 'OPS' }
      let(:action_input) { { issue_type: 'Task', summary: 'S' } }

      it 'creates the issue in the default project' do
        expect_fields_sent('project' => { 'key' => 'OPS' })
      end
    end

    context 'when a project is picked and the connection has a default project' do
      let(:default_project) { 'OPS' }

      it 'creates the issue in the picked project' do
        expect_fields_sent('project' => { 'key' => 'KAN' })
      end
    end

    context 'when the project key and the parent key are typed in lower case' do
      let(:action_input) { { project_key: 'kan', issue_type: 'Task', summary: 'S', parent_key: 'kan-9' } }

      it 'sends both in upper case, because Jira finds a project key only in upper case' do
        expect_fields_sent('project' => { 'key' => 'KAN' }, 'parent' => { 'key' => 'KAN-9' })
      end
    end

    it 'says the issue may have been created when Jira does not answer' do
      stub_request(:post, "#{api}/issue").to_timeout
      expect { run_action(action_input) }.to raise_error(
        IPaaS::Job::FailJob, /\AJira did not answer \(.*\)\. The change may have been made, so check Jira before you/
      )
      expect(a_request(:post, "#{api}/issue")).to have_been_made.once
    end

    context 'when the parent is given by its numeric issue ID' do
      let(:action_input) { { project_key: 'KAN', issue_type: 'Subtask', summary: 'S', parent_key: ' 10001 ' } }

      it 'sends it as a parent ID rather than a key' do
        expect_fields_sent('parent' => { 'id' => '10001' })
      end
    end

    it 'names each field Jira refuses when it answers 400' do
      refusal = { errorMessages: [], errors: { 'summary' => 'You must specify a summary of the issue.',
                                               'customfield_10050' => 'Permission level is required.', }, }
      stub_request(:post, "#{api}/issue").to_return(status: 400, body: refusal.to_json)
      expect { run_action(action_input) }.to raise_error(
        IPaaS::Job::FailJob, 'Jira API error (HTTP 400): summary: You must specify a summary of the issue.; ' \
                             'customfield_10050: Permission level is required.'
      )
    end

    context 'when neither Project nor a default project is set' do
      let(:action_input) { { issue_type: 'Task', summary: 'S' } }

      it 'asks for a project before calling Jira' do
        expect { run_action(action_input) }
          .to raise_error(IPaaS::Job::FailJob, 'Pick a Jira project, or set a Default project on the connection.')
        expect(a_request(:post, /atlassian/)).not_to have_been_made
      end
    end

    context 'when the project is not a key' do
      let(:action_input) { { project_key: 'KAN" OR project = "OPS', issue_type: 'Task', summary: 'S' } }

      it 'refuses it before calling Jira' do
        expect { run_action(action_input) }
          .to raise_error(IPaaS::Job::FailJob, /is not a Jira project key or ID/)
        expect(a_request(:post, /atlassian/)).not_to have_been_made
      end
    end

    context 'when Additional fields sets a field that an input sets too' do
      let(:action_input) do
        { project_key: 'KAN', issue_type: 'Task', summary: 'S', priority: 'High',
          additional_fields: { 'priority' => { 'id' => '2' } }, }
      end

      it 'refuses the clash instead of sending one of the two values' do
        expect { run_action(action_input) }.to raise_error(
          IPaaS::Job::FailJob,
          'Additional fields and an input both set priority. Give each field in one place only. Nothing was sent.'
        )
        expect(a_request(:post, /atlassian/)).not_to have_been_made
      end
    end

    context 'when an input is mapped but empty and Additional fields sets the same field' do
      let(:action_input) do
        { project_key: 'KAN', issue_type: 'Task', summary: 'S', priority: '',
          additional_fields: { 'priority' => { 'id' => '2' } }, }
      end

      it 'sends the value of Additional fields, because an empty input sends nothing when an issue is created' do
        expect_fields_sent('priority' => { 'id' => '2' })
      end
    end

    context 'when Additional fields names a project while the default project fills Project' do
      let(:default_project) { 'OPS' }
      let(:action_input) do
        { issue_type: 'Task', summary: 'S', additional_fields: { 'project' => { 'key' => 'KAN' } } }
      end

      it 'refuses it instead of creating the issue in the default project' do
        expect { run_action(action_input) }.to raise_error(
          IPaaS::Job::FailJob,
          'Additional fields cannot set project, which this action sets from its own inputs. Nothing was sent.'
        )
        expect(a_request(:post, /atlassian/)).not_to have_been_made
      end
    end

    context 'when Additional fields sets the issue type' do
      let(:action_input) do
        { project_key: 'KAN', issue_type: 'Task', summary: 'S',
          additional_fields: { 'issuetype' => { 'id' => '10009' } }, }
      end

      it 'refuses it instead of sending the Issue type input in its place' do
        expect { run_action(action_input) }.to raise_error(IPaaS::Job::FailJob, /cannot set issuetype,/)
        expect(a_request(:post, /atlassian/)).not_to have_been_made
      end
    end

    context 'when Additional fields sets the description and Description (ADF) is given' do
      let(:action_input) do
        { project_key: 'KAN', issue_type: 'Task', summary: 'S', description_adf: adf,
          additional_fields: { 'description' => adf }, }
      end

      it 'refuses the clash instead of sending the ADF description alone' do
        expect { run_action(action_input) }.to raise_error(IPaaS::Job::FailJob, /both set description\./)
        expect(a_request(:post, /atlassian/)).not_to have_been_made
      end
    end
  end

  describe 'Get Issue' do
    let(:action_template_id) { '01a13f2d-b655-7009-a59c-1550a7382d9d' }
    let(:action_input) { { issue_id_or_key: 'KAN-1' } }
    let(:issue_body) do
      { id: '1', key: 'KAN-1', self: "#{api}/issue/1",
        fields: { summary: 'Build it', status: { name: 'To Do', statusCategory: { name: 'New' } },
                  issuetype: { id: '10001', name: 'Task' }, project: { key: 'KAN' },
                  priority: { name: 'High' },
                  assignee: { accountId: 'acc-1', displayName: 'Bot', emailAddress: 'bot@example.com' },
                  reporter: { accountId: 'acc-2' }, labels: ['x'],
                  created: '2026-10-15T00:00:00.000+0000',
                  updated: '2026-10-15T01:00:00.000+0000',
                  'customfield_10234' => 'cf', }, }
    end

    def stub_issue(body, status: 200, headers: {})
      stub_request(:get, "#{api}/issue/KAN-1")
        .with(query: hash_including({}))
        .to_return(status: status, headers: headers, body: body.is_a?(String) ? body : body.to_json)
    end

    it 'flattens the common fields and still returns the whole field map' do
      stub_request(:get, "#{api}/issue/KAN-1").with(query: { 'fields' => '*all' })
                                              .to_return(status: 200, body: issue_body.to_json)
      output = run_action(action_input.merge(all_fields: true))
      expect(output[:summary]).to eq('Build it')
      expect(output[:status]).to eq('To Do')
      expect(output[:status_category]).to eq('New')
      expect(output[:assignee]).to include(account_id: 'acc-1', display_name: 'Bot', email_address: 'bot@example.com')
      expect(output[:project]).to eq('KAN')
      expect(output[:issue_type_id]).to eq('10001')
      expect(output[:labels]).to eq(['x'])
      expect(output[:fields]['customfield_10234']).to eq('cf')
    end

    it 'returns the resolution and when it was set' do
      resolved = issue_body.deep_merge(fields: { resolution: { id: '10000', name: 'Done' },
                                                 resolutiondate: '2026-10-16T09:00:00.000+0000', })
      stub_issue(resolved)
      expect(run_action(action_input)).to include(resolution: 'Done', resolution_date: '2026-10-16T09:00:00.000+0000')
    end

    it 'returns no resolution for an issue that is not resolved' do
      stub_issue(issue_body.deep_merge(fields: { resolution: nil }))
      expect(run_action(action_input)).to include(resolution: nil, resolution_date: nil)
    end

    it 'asks for the standard field set by default' do
      stub = stub_request(:get, "#{api}/issue/KAN-1")
             .with(query: { 'fields' => JiraConnector::DEFAULT_ISSUE_FIELDS.join(',') })
             .to_return(status: 200, body: issue_body.to_json)
      run_action(action_input)
      expect(stub).to have_been_requested.once
    end

    it 'asks for the standard field set when Fields holds only an empty entry' do
      stub = stub_request(:get, "#{api}/issue/KAN-1")
             .with(query: { 'fields' => JiraConnector::DEFAULT_ISSUE_FIELDS.join(',') })
             .to_return(status: 200, body: issue_body.to_json)
      run_action(action_input.merge(fields: ['']))
      expect(stub).to have_been_requested.once
    end

    it 'joins the fields and expand lists into query parameters' do
      stub = stub_request(:get, "#{api}/issue/KAN-1")
             .with(query: { 'fields' => 'summary,status', 'expand' => 'changelog' })
             .to_return(status: 200, body: issue_body.to_json)
      run_action(action_input.merge(fields: %w[summary status], expand: ['changelog']))
      expect(stub).to have_been_requested.once
    end

    it 'returns the description as text, the components, the attachments and the comment count' do
      fields = issue_body[:fields].merge(
        description: { type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Why' }] }] },
        components: [{ id: '5', name: 'Web', self: "#{api}/component/5" }],
        attachment: [{ id: 77, filename: 'a.csv', size: 5, mimeType: 'text/csv',
                       created: '2026-10-15T00:00:00.000+0000', author: { accountId: 'acc-1' }, }],
        comment: { comments: [{ id: '9', body: 'secret' }], maxResults: 1, total: 3, startAt: 0 }
      )
      stub_issue(issue_body.merge(fields: fields))
      output = run_action(action_input)
      expect(output[:description]).to eq('Why')
      expect(output[:components].first).to include(id: '5', name: 'Web')
      expect(output[:attachments].first)
        .to include(attachment_id: '77', filename: 'a.csv', content_type: 'text/csv')
      expect(output[:attachments].first[:author]).to include(account_id: 'acc-1')
      expect(output[:comment_count]).to eq(3)
      expect(output[:fields]).not_to have_key('comment')
    end

    it 'leaves empty Expand entries out of the query' do
      stub = stub_request(:get, "#{api}/issue/KAN-1")
             .with(query: { 'fields' => JiraConnector::DEFAULT_ISSUE_FIELDS.join(','), 'expand' => 'changelog' })
             .to_return(status: 200, body: issue_body.to_json)
      run_action(action_input.merge(expand: ['', 'changelog']))
      expect(stub).to have_been_requested.once
    end

    it 'gives Jira 60 seconds to answer the read, inside the 90 seconds iPaaS allows one action' do
      stub_issue(issue_body)
      allow(action(action_input)).to receive(:http_get).and_call_original
      run_action
      expect(action).to have_received(:http_get)
        .with("#{api}/issue/KAN-1", anything, nil, open_timeout: nil, timeout: JiraConnector::ACTION_TIMEOUT)
    end

    it 'fails at once rather than trying again for ever when the TLS connection to Jira cannot be made' do
      stub_request(:get, "#{api}/issue/KAN-1").with(query: hash_including({}))
                                              .to_raise(OpenSSL::SSL::SSLError.new('certificate verify failed'))
      expect { run_action(action_input) }
        .to raise_error(IPaaS::Job::FailJob, /\AThe request to Jira failed \(.*certificate verify failed/)
    end

    it 'returns the parts asked for with Expand' do
      stub_issue(issue_body.merge(renderedFields: { description: '<p>Why</p>' }))
      output = run_action(action_input.merge(expand: ['renderedFields']))
      expect(output[:expanded]).to eq({ 'renderedFields' => { 'description' => '<p>Why</p>' } })
    end

    it 'leaves the comments out of the expanded parts, as it does out of Fields' do
      comments = { comments: [{ id: '9', body: '<p>Only for the team</p>' }], total: 1 }
      stub_issue(issue_body.merge(renderedFields: { description: '<p>Why</p>', comment: comments },
                                  versionedRepresentations: { comment: { '1' => comments } }))
      output = run_action(action_input.merge(expand: %w[renderedFields versionedRepresentations]))
      expected = { 'renderedFields' => { 'description' => '<p>Why</p>' }, 'versionedRepresentations' => {} }
      expect(output[:expanded]).to eq(expected)
    end

    it 'reads the Fields given when All fields is mapped to false' do
      stub = stub_request(:get, "#{api}/issue/KAN-1").with(query: { 'fields' => 'summary,status' })
                                                     .to_return(status: 200, body: issue_body.to_json)
      run_action(action_input.merge(fields: %w[summary status], all_fields: false))
      expect(stub).to have_been_requested.once
    end

    it 'explains that Jira answers 404 both for missing and for invisible issues' do
      stub_issue({ errorMessages: ['Issue does not exist or you do not have permission to see it.'], errors: {} },
                 status: 404)
      expect { run_action(action_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        /Issue does not exist or you do not have permission to see it\./)
    end

    it 'names the issue that was not found' do
      stub_issue({ errorMessages: ['Gone'] }, status: 404)
      expect { run_action(action_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Issue KAN-1 was not found, or this account cannot see it (HTTP 404): Gone')
    end

    it 'names the permission the account needs on a 403' do
      stub_issue({ errorMessages: ['No permission'] }, status: 403)
      expect { run_action(action_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Jira refused the request (HTTP 403): No permission. ' \
                        'The account needs the Browse Projects permission.')
    end

    it 'names the credential as the problem on a 401 with no body at all' do
      stub_issue('', status: 401)
      expect { run_action(action_input) }
        .to raise_error(IPaaS::Job::FailJob, /rejected the credentials \(HTTP 401\)/)
    end

    it 'says an API token lasts 1 to 365 days on a 401' do
      stub_issue({ code: 401, message: 'Unauthorized' }, status: 401)
      expect { run_action(action_input) }
        .to raise_error(IPaaS::Job::FailJob, /Unauthorized\. .*past its expiry date\. API tokens last 1 to 365 days/)
    end

    it 'reports the status rather than a parse error when an error body is not JSON' do
      stub_issue('<html>Not here</html>', status: 404)
      expect { run_action(action_input) }
        .to raise_error(IPaaS::Job::FailJob, /cannot see it \(HTTP 404\): <html>Not here/)
    end

    it 'reads the messages shape of the admin API' do
      messages = [{ key: 'url', arguments: ['Invalid URL.'] }, { key: 'Webhook with ID 35 does not exist.' }]
      stub_issue({ messages: messages }, status: 400)
      expect { run_action(action_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Jira API error (HTTP 400): url: Invalid URL.; Webhook with ID 35 does not exist.')
    end

    it 'tries a read again later when Jira answers 502' do
      stub_issue('', status: 502)
      expect_reschedule_after(60) { run_action(action_input) }
    end

    it 'tries a read again later when the connection to Jira fails' do
      stub_request(:get, "#{api}/issue/KAN-1").with(query: hash_including({})).to_timeout
      expect_reschedule_after(60, /Jira did not answer/) { run_action(action_input) }
    end

    it 'backs off for as long as Jira asks when Jira rate limits the call' do
      stub_issue('', status: 429, headers: { 'Retry-After' => '30', 'RateLimit-Reason' => 'APP_QUOTA' })
      expect_reschedule_after(30) { run_action(action_input) }
    end

    context 'when the key would escape the path' do
      let(:action_input) { { issue_id_or_key: 'KAN-1/comment/9' } }

      it 'refuses before issuing a request rather than hitting another resource' do
        expect { run_action(action_input) }
          .to raise_error(IPaaS::Job::FailJob, /not path safe/)
        expect(a_request(:get, /atlassian/)).not_to have_been_made
      end
    end

    context 'when the key holds a backslash' do
      let(:action_input) { { issue_id_or_key: 'KAN-1\\x' } }

      it 'refuses it as not path safe before calling Jira' do
        expect { run_action(action_input) }.to raise_error(IPaaS::Job::FailJob, /not path safe/)
        expect(a_request(:any, /atlassian/)).not_to have_been_made
      end
    end

    context 'when the key is a dot segment' do
      let(:action_input) { { issue_id_or_key: '..' } }

      it 'refuses it rather than moving the request to another resource' do
        expect { run_action(action_input) }
          .to raise_error(IPaaS::Job::FailJob, /not path safe: '\.\.'/)
        expect(a_request(:any, /atlassian/)).not_to have_been_made
      end
    end
  end

  describe 'Update Issue' do
    let(:action_template_id) { '01a13f2d-b655-7acd-872d-e5582b5e3d4d' }
    let(:action_input) { { issue_id_or_key: 'KAN-1', summary: 'Changed' } }

    it 'sends only the fields it was given' do
      stub = stub_request(:put, "#{api}/issue/KAN-1")
             .with(body: { fields: { summary: 'Changed' } })
             .to_return(status: 204, body: '')
      output = run_action(action_input)
      expect(stub).to have_been_requested.once
      expect(output).to include(issue_key: 'KAN-1', updated: true)
    end

    it 'reports an issue given by its numeric ID as the issue ID of the update' do
      stub_request(:put, "#{api}/issue/10001").to_return(status: 204, body: '')
      output = run_action({ issue_id_or_key: '10001', summary: 'Changed' })
      expect(output).to include(issue_id: '10001', updated: true)
      expect(output[:issue_key]).to be_nil
    end

    it 'ignores an Additional fields input that is mapped but empty' do
      stub = stub_request(:put, "#{api}/issue/KAN-1")
             .with(body: { fields: { summary: 'Changed' } })
             .to_return(status: 204, body: '')
      output = run_action(action_input.merge(additional_fields: ''))
      expect(stub).to have_been_requested.once
      expect(output).to include(issue_key: 'KAN-1', updated: true)
    end

    it 'clears the fields that are mapped but empty, and never the summary' do
      stub = stub_request(:put, "#{api}/issue/KAN-1")
             .with(body: { fields: { assignee: nil, labels: [], components: [], duedate: nil } })
             .to_return(status: 204, body: '')
      run_action({ issue_id_or_key: 'KAN-1', summary: '', assignee_account_id: '', labels: [],
                   components: [], due_date: nil, })
      expect(stub).to have_been_requested.once
    end

    it 'clears Labels and Components when the mapped lists hold only empty entries' do
      stub = stub_request(:put, "#{api}/issue/KAN-1")
             .with(body: { fields: { labels: [], components: [] } })
             .to_return(status: 204, body: '')
      run_action({ issue_id_or_key: 'KAN-1', labels: [''], components: [''] })
      expect(stub).to have_been_requested.once
    end

    it 'says a conflicting change stopped the write, and does not send it again, when Jira answers 409' do
      put = stub_request(:put, "#{api}/issue/KAN-1")
            .to_return(status: 409, body: { errorMessages: ['The issue was changed by someone else.'] }.to_json)
      expect { run_action({ issue_id_or_key: 'KAN-1', summary: 'New' }) }.to raise_error(
        IPaaS::Job::FailJob,
        'Jira refused the change because of a conflicting change (HTTP 409): The issue was changed by someone else. ' \
        'It was not tried again, so nothing is applied twice. Read the item and run the step again.'
      )
      expect(put).to have_been_requested.once
    end

    it 'fails rather than writing twice when Jira answers 503 to the write, and says the change may have been made' do
      stub_request(:put, "#{api}/issue/KAN-1").to_return(status: 503, body: { errorMessages: ['Busy'] }.to_json)
      expect { run_action(action_input) }.to raise_error(
        IPaaS::Job::FailJob,
        'Jira answered the change with HTTP 503: Busy. The change may have been made, so check Jira before you run ' \
        'the step again.'
      )
    end

    it 'gives Jira 60 seconds to answer the write, inside the 90 seconds iPaaS allows one action' do
      stub_request(:put, "#{api}/issue/KAN-1").to_return(status: 204, body: '')
      allow(action(action_input)).to receive(:http_put).and_call_original
      run_action
      expect(action).to have_received(:http_put)
        .with("#{api}/issue/KAN-1", anything, anything, open_timeout: nil, timeout: JiraConnector::ACTION_TIMEOUT)
    end

    it 'ends the message with one period when the Jira message already ends with one' do
      stub_request(:put, "#{api}/issue/KAN-1")
        .to_return(status: 403,
                   body: { errorMessages: ['You do not have permission to edit issues in this project.'] }.to_json)
      expect { run_action(action_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Jira refused the request (HTTP 403): You do not have permission to edit issues in ' \
                        'this project. The account needs the Edit Issues permission.')
    end

    it 'tries a write again later when Jira limits the rate' do
      stub_request(:put, "#{api}/issue/KAN-1").to_return(status: 429, headers: { 'Retry-After' => '5' }, body: '')
      expect_reschedule_after(5) { run_action(action_input) }
    end

    context 'when no changeable field is supplied' do
      let(:action_input) { { issue_id_or_key: 'KAN-1' } }

      it 'refuses rather than sending an empty update Jira would accept as a no-op' do
        expect { run_action(action_input) }
          .to raise_error(IPaaS::Job::FailJob, /no fields to change/)
        expect(a_request(:put, /atlassian/)).not_to have_been_made
      end
    end
  end

  describe 'Assign User to Issue' do
    let(:action_template_id) { '01a13f2d-b655-7749-8870-fea1abc5bdc9' }

    it 'sets the assignee by account id' do
      stub = stub_request(:put, "#{api}/issue/KAN-1/assignee")
             .with(body: { accountId: 'acc-1' })
             .to_return(status: 204, body: '')
      output = run_action({ issue_id_or_key: 'KAN-1', account_id: 'acc-1' })
      expect(stub).to have_been_requested.once
      expect(output).to include(issue_key: 'KAN-1', account_id: 'acc-1', unassigned: false, to_project_default: false)
    end

    it 'unassigns by sending an explicit null, which is how Jira clears the field' do
      stub = stub_request(:put, "#{api}/issue/KAN-1/assignee")
             .with(body: { accountId: nil })
             .to_return(status: 204, body: '')
      output = run_action({ issue_id_or_key: 'KAN-1', account_id: 'acc-1', unassign: true })
      expect(stub).to have_been_requested.once
      expect(output[:unassigned]).to be(true)
    end

    it 'assigns the account when Unassign is mapped to false' do
      stub = stub_request(:put, "#{api}/issue/KAN-1/assignee")
             .with(body: { accountId: 'acc-1' })
             .to_return(status: 204, body: '')
      output = run_action({ issue_id_or_key: 'KAN-1', account_id: 'acc-1', unassign: false })
      expect(stub).to have_been_requested.once
      expect(output).to include(account_id: 'acc-1', unassigned: false)
    end

    it 'refuses an empty account id unless Unassign is on' do
      expect { run_action({ issue_id_or_key: 'KAN-1', account_id: ' ' }) }
        .to raise_error(IPaaS::Job::FailJob, /needs an assignee account ID\. Turn on Unassign/)
      expect(a_request(:put, /atlassian/)).not_to have_been_made
    end

    it 'reports a hand-off to the default assignee of the project' do
      stub_request(:put, "#{api}/issue/KAN-1/assignee").with(body: { accountId: '-1' })
                                                       .to_return(status: 204, body: '')
      output = run_action({ issue_id_or_key: 'KAN-1', account_id: '-1' })
      expect(output).to include(to_project_default: true, unassigned: false)
    end

    it 'names the account as well as the issue when Jira answers 404, because either can be the missing one' do
      stub_request(:put, "#{api}/issue/KAN-1/assignee")
        .to_return(status: 404, body: { errorMessages: ['Specified user does not exist'] }.to_json)
      expect { run_action({ issue_id_or_key: 'KAN-1', account_id: 'acc-9' }) }.to raise_error(
        IPaaS::Job::FailJob,
        'Issue KAN-1 or account acc-9 was not found, or this account cannot see it (HTTP 404): ' \
        'Specified user does not exist'
      )
    end

    it 'names only the issue when Jira answers 404 to a hand-off to the default assignee' do
      stub_request(:put, "#{api}/issue/KAN-1/assignee")
        .to_return(status: 404, body: { errorMessages: ['Issue does not exist'] }.to_json)
      expect { run_action({ issue_id_or_key: 'KAN-1', account_id: '-1' }) }.to raise_error(
        IPaaS::Job::FailJob, 'Issue KAN-1 was not found, or this account cannot see it (HTTP 404): Issue does not exist'
      )
    end

    it 'reports an issue given by its numeric ID as the issue ID of the assignment' do
      stub_request(:put, "#{api}/issue/10001/assignee").to_return(status: 204, body: '')
      output = run_action({ issue_id_or_key: '10001', account_id: 'acc-1' })
      expect(output).to include(issue_id: '10001', account_id: 'acc-1')
      expect(output[:issue_key]).to be_nil
    end
  end
end
