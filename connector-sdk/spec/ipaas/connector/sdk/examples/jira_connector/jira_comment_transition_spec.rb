require 'spec_helper'
require_relative 'jira_context'

describe 'Jira comment and transition actions', :action, :jira do
  let(:adf) do
    { 'version' => 1, 'type' => 'doc',
      'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Hello' }] }], }
  end
  let(:comment_body) do
    { id: '10', self: "#{api}/issue/1/comment/10",
      body: { type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Hello' }] }] },
      author: { accountId: 'acc-1', displayName: 'Bot' },
      created: '2026-10-15T00:00:00.000+0000', updated: '2026-10-15T00:00:00.000+0000', }
  end

  describe 'Create Comment' do
    let(:action_template_id) { '01a13f2d-b655-7b6d-89bb-38d0d9057f81' }

    it 'wraps plain text in ADF and flattens the reply back to text' do
      stub = stub_request(:post, "#{api}/issue/KAN-1/comment")
             .with(body: { body: adf })
             .to_return(status: 201, body: comment_body.to_json)
      output = run_action({ issue_id_or_key: 'KAN-1', body: 'Hello' })
      expect(stub).to have_been_requested.once
      expect(output[:comment_id]).to eq('10')
      expect(output[:comment_body]).to eq('Hello')
      expect(output[:author][:account_id]).to eq('acc-1')
    end

    it 'returns the visibility and the author with the email as nested objects' do
      visibility = { type: 'role', value: 'Administrator', identifier: 'Administrator' }
      author = { accountId: 'acc-1', displayName: 'Bot', emailAddress: 'bot@example.com' }
      restricted = comment_body.merge(visibility: visibility, author: author)
      stub_request(:post, "#{api}/issue/KAN-1/comment").to_return(status: 201, body: restricted.to_json)
      output = run_action({ issue_id_or_key: 'KAN-1', body: 'Hello',
                            visibility_type: 'role', visibility_value: 'Administrator', })
      expect(output[:visibility]).to include(type: 'role', value: 'Administrator', identifier: 'Administrator')
      expect(output[:author]).to include(account_id: 'acc-1', display_name: 'Bot', email_address: 'bot@example.com')
    end

    it 'sends visibility only when both halves are given' do
      stub = stub_request(:post, "#{api}/issue/KAN-1/comment")
             .with(body: { body: adf, visibility: { type: 'role', value: 'Administrators' } })
             .to_return(status: 201, body: comment_body.to_json)
      run_action({ issue_id_or_key: 'KAN-1', body: 'Hello',
                   visibility_type: 'role', visibility_value: 'Administrators', })
      expect(stub).to have_been_requested.once
    end

    it 'refuses a half-filled visibility restriction rather than posting the comment unrestricted' do
      expect { run_action({ issue_id_or_key: 'KAN-1', body: 'Hello', visibility_type: 'role' }) }
        .to raise_error(IPaaS::Job::FailJob, /needs both a type and a value/)
      expect(a_request(:post, "#{api}/issue/KAN-1/comment")).not_to have_been_made
    end

    it 'refuses when neither a body nor an ADF body is supplied' do
      expect { run_action({ issue_id_or_key: 'KAN-1' }) }
        .to raise_error(IPaaS::Job::FailJob, /either Body or Body \(ADF\)/)
      expect(a_request(:post, /atlassian/)).not_to have_been_made
    end

    it 'sends a pre-built Body (ADF) as given instead of the plain-text Body' do
      custom_adf = { 'version' => 1, 'type' => 'doc', 'content' => [] }
      stub = stub_request(:post, "#{api}/issue/KAN-1/comment")
             .with(body: { body: custom_adf })
             .to_return(status: 201, body: comment_body.to_json)
      run_action({ issue_id_or_key: 'KAN-1', body: 'ignored', body_adf: custom_adf })
      expect(stub).to have_been_requested.once
    end
  end

  describe 'Update Comment' do
    let(:action_template_id) { '01a13f2d-b655-732a-bfcf-6437a2df8179' }
    let(:comment_url) { "#{api}/issue/KAN-1/comment/10" }

    def refuse_edit(status, message, author:)
      stub_request(:put, comment_url).to_return(status: status, body: { errorMessages: [message] }.to_json)
      stub_request(:get, comment_url).to_return(status: 200, body: comment_body.merge(author: author).to_json)
      stub_request(:get, "#{api}/myself").to_return(status: 200, body: { accountId: 'acc-1' }.to_json)
    end

    def expect_edit_refused(message)
      expect { run_action({ issue_id_or_key: 'KAN-1', comment_id: '10', body: 'Hello' }) }
        .to raise_error(IPaaS::Job::FailJob, message)
      expect(a_request(:put, comment_url)).to have_been_made.once
    end

    it 'names Edit All Comments when Jira refuses an edit of a comment another user wrote' do
      refuse_edit(403, 'Forbidden', author: { accountId: 'acc-2' })
      expect_edit_refused(
        'Jira refused the request (HTTP 403): Forbidden. The account needs the Edit All Comments permission.'
      )
    end

    it 'names Edit Own Comments when Jira answers 400 for lack of permission on a comment the account wrote' do
      refuse_edit(400, 'You do not have the permission to edit this comment.', author: { accountId: 'acc-1' })
      expect_edit_refused('Jira refused the request (HTTP 400): You do not have the permission to edit this ' \
                          'comment. The account needs the Edit Own Comments permission.')
    end

    it 'names both edit permissions when it finds the author but not the account of the connection' do
      refuse_edit(403, 'Forbidden', author: { accountId: 'acc-1' })
      stub_request(:get, "#{api}/myself").to_timeout
      expect_edit_refused(/The account needs the Edit All Comments or Edit Own Comments permission\.\z/)
      expect(a_request(:get, "#{api}/myself")).to have_been_made.once
    end

    it 'names both edit permissions after it fails to find who wrote the comment' do
      stub_request(:put, comment_url).to_return(status: 403, body: { errorMessages: ['Forbidden'] }.to_json)
      stub_request(:get, comment_url).to_return(status: 404, body: '')
      stub_request(:get, "#{api}/myself").to_timeout
      expect_edit_refused(/The account needs the Edit All Comments or Edit Own Comments permission\.\z/)
      expect(a_request(:get, comment_url)).to have_been_made.once
    end

    it 'gives the words of Jira alone, and looks nothing up, when a 400 says nothing about permission' do
      refuse_edit(400, 'Comment body is not valid.', author: { accountId: 'acc-2' })
      expect_edit_refused('Jira API error (HTTP 400): Comment body is not valid.')
      expect(a_request(:get, comment_url)).not_to have_been_made
    end

    it 'puts the new body at the comment path' do
      stub = stub_request(:put, "#{api}/issue/KAN-1/comment/10")
             .with(body: { body: adf })
             .to_return(status: 200, body: comment_body.to_json)
      output = run_action({ issue_id_or_key: 'KAN-1', comment_id: '10', body: 'Hello' })
      expect(stub).to have_been_requested.once
      expect(output[:comment_body]).to eq('Hello')
    end

    it 'refuses a comment id that would escape the path' do
      expect { run_action({ issue_id_or_key: 'KAN-1', comment_id: '10/../../x', body: 'H' }) }
        .to raise_error(IPaaS::Job::FailJob, /not path safe/)
      expect(a_request(:put, /atlassian/)).not_to have_been_made
    end
  end

  describe 'Update Issue Status' do
    let(:action_template_id) { '01a13f2d-b655-774a-9dc7-9000aa60a67c' }
    let(:transitions_body) do
      { transitions: [{ id: '31', name: 'Done', to: { id: '3', name: 'Done' } },
                      { id: '11', name: 'To Do', to: { id: '1', name: 'To Do' } },] }
    end

    it 'uses an explicit transition id without looking anything up' do
      stub = stub_request(:post, "#{api}/issue/KAN-1/transitions")
             .with(body: { transition: { id: '31' } })
             .to_return(status: 204, body: '')
      output = run_action({ issue_id_or_key: 'KAN-1', transition: '31' })
      expect(stub).to have_been_requested.once
      expect(output).to include(issue_key: 'KAN-1', transition_id: '31', transitioned: true)
      expect(a_request(:get, "#{api}/issue/KAN-1/transitions")).not_to have_been_made
    end

    it 'names the Transition Issues permission when Jira answers 400 for lack of it' do
      refusal = { errorMessages: ['You do not have permission to transition this issue.'] }
      stub_request(:post, "#{api}/issue/KAN-1/transitions").to_return(status: 400, body: refusal.to_json)
      expect { run_action({ issue_id_or_key: 'KAN-1', transition: '31' }) }.to raise_error(
        IPaaS::Job::FailJob, 'Jira refused the request (HTTP 400): You do not have permission to transition this ' \
                             'issue. The account needs the Transition Issues permission.'
      )
    end

    it 'gives the page Jira sent when a 400 is not JSON' do
      stub_request(:post, "#{api}/issue/KAN-1/transitions").to_return(status: 400, body: '<html>Bad Request</html>')
      expect { run_action({ issue_id_or_key: 'KAN-1', transition: '31' }) }
        .to raise_error(IPaaS::Job::FailJob, 'Jira API error (HTTP 400): <html>Bad Request</html>')
    end

    it 'names no permission when only a screen field of the transition mentions the word' do
      refusal = { errorMessages: [], errors: { 'customfield_10050' => 'Permission level is required.' } }
      stub_request(:post, "#{api}/issue/KAN-1/transitions").to_return(status: 400, body: refusal.to_json)
      expect { run_action({ issue_id_or_key: 'KAN-1', transition: '31' }) }.to raise_error(
        IPaaS::Job::FailJob, 'Jira API error (HTTP 400): customfield_10050: Permission level is required.'
      )
    end

    it 'reports an issue given by its numeric ID as the issue ID of the transition' do
      stub_request(:post, "#{api}/issue/10001/transitions").to_return(status: 204, body: '')
      output = run_action({ issue_id_or_key: '10001', transition: '31' })
      expect(output).to include(issue_id: '10001')
      expect(output[:issue_key]).to be_nil
    end

    it 'resolves a transition name case-insensitively' do
      stub_request(:get, "#{api}/issue/KAN-1/transitions")
        .with(query: hash_including({})).to_return(status: 200, body: transitions_body.to_json)
      stub = stub_request(:post, "#{api}/issue/KAN-1/transitions")
             .with(body: { transition: { id: '31' } }).to_return(status: 204, body: '')
      output = run_action({ issue_id_or_key: 'KAN-1', transition: 'done' })
      expect(stub).to have_been_requested.once
      expect(output[:transition_id]).to eq('31')
    end

    it 'lists what is available when the name matches nothing' do
      stub_request(:get, "#{api}/issue/KAN-1/transitions")
        .with(query: hash_including({})).to_return(status: 200, body: transitions_body.to_json)
      expect { run_action({ issue_id_or_key: 'KAN-1', transition: 'Ship it' }) }
        .to raise_error(IPaaS::Job::FailJob, /Available: Done, To Do/)
      expect(a_request(:post, "#{api}/issue/KAN-1/transitions")).not_to have_been_made
    end

    it 'says so when the issue has no transitions at all' do
      stub_request(:get, "#{api}/issue/KAN-1/transitions")
        .with(query: hash_including({})).to_return(status: 200, body: { transitions: [] }.to_json)
      expect { run_action({ issue_id_or_key: 'KAN-1', transition: 'Done' }) }
        .to raise_error(IPaaS::Job::FailJob, /Available: none/)
      expect(a_request(:post, "#{api}/issue/KAN-1/transitions")).not_to have_been_made
    end

    it 'refuses at the input mapping when no transition is given' do
      expect { run_action({ issue_id_or_key: 'KAN-1' }) }
        .to raise_error(IPaaS::Error, /Field 'transition' is required/)
      expect(a_request(:post, "#{api}/issue/KAN-1/transitions")).not_to have_been_made
    end

    it 'sends screen fields with the transition and adds the comment after it, because Jira drops a comment there' do
      transition = stub_request(:post, "#{api}/issue/KAN-1/transitions")
                   .with(body: { transition: { id: '31' }, fields: { resolution: { name: 'Done' } } })
                   .to_return(status: 204, body: '')
      comment = stub_request(:post, "#{api}/issue/KAN-1/comment")
                .with(body: { body: adf })
                .to_return(status: 201, body: comment_body.to_json)
      output = run_action({ issue_id_or_key: 'KAN-1', transition: '31', comment: 'Hello',
                            fields: { resolution: { name: 'Done' } }, })
      expect(transition).to have_been_requested.once
      expect(comment).to have_been_requested.once
      expect(output).to include(issue_key: 'KAN-1', transition_id: '31', transitioned: true)
    end

    it 'fails saying the issue already moved when Jira does not add the comment' do
      transition = stub_request(:post, "#{api}/issue/KAN-1/transitions").to_return(status: 204, body: '')
      stub_request(:post, "#{api}/issue/KAN-1/comment")
        .to_return(status: 403, body: { errorMessages: ['You cannot comment.'] }.to_json)
      expect { run_action({ issue_id_or_key: 'KAN-1', transition: '31', comment: 'Hello' }) }.to raise_error(
        IPaaS::Job::FailJob,
        'Issue KAN-1 moved through transition 31, but the comment was not added. Jira refused the request ' \
        '(HTTP 403): You cannot comment. The account needs the Add Comments permission.'
      )
      expect(transition).to have_been_requested.once
    end

    it 'says the issue already moved when the connection breaks while the comment is sent' do
      transition = stub_request(:post, "#{api}/issue/KAN-1/transitions").to_return(status: 204, body: '')
      stub_request(:post, "#{api}/issue/KAN-1/comment").to_timeout
      expect { run_action({ issue_id_or_key: 'KAN-1', transition: '31', comment: 'Hello' }) }.to raise_error(
        IPaaS::Job::FailJob,
        /\AIssue KAN-1 moved through transition 31, but Jira did not answer the comment request .*may or may not/
      )
      expect(transition).to have_been_requested.once
    end

    it 'fails at once rather than moving the issue again when Jira limits the rate of the comment' do
      transition = stub_request(:post, "#{api}/issue/KAN-1/transitions").to_return(status: 204, body: '')
      stub_request(:post, "#{api}/issue/KAN-1/comment")
        .to_return(status: 429, headers: { 'Retry-After' => '30' }, body: '')
      expect { run_action({ issue_id_or_key: 'KAN-1', transition: '31', comment: 'Hello' }) }
        .to raise_error(IPaaS::Job::FailJob, /\AIssue KAN-1 moved through transition 31, but the comment was not added/)
      expect(transition).to have_been_requested.once
    end

    it 'says the comment may or may not have been added when Jira answers 503 to it' do
      transition = stub_request(:post, "#{api}/issue/KAN-1/transitions").to_return(status: 204, body: '')
      stub_request(:post, "#{api}/issue/KAN-1/comment").to_return(status: 503, body: 'down')
      expect { run_action({ issue_id_or_key: 'KAN-1', transition: '31', comment: 'Hello' }) }.to raise_error(
        IPaaS::Job::FailJob,
        'Issue KAN-1 moved through transition 31, but the comment may or may not have been added. Jira API error ' \
        '(HTTP 503): down'
      )
      expect(transition).to have_been_requested.once
    end
  end
end
