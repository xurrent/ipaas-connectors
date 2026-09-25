require 'spec_helper'

# The actions build their ClickUp paths from mapped input and hand ClickUp's answer straight to the
# output schema. Both of those are places where a bad value used to travel further than it should.
describe 'ClickUp task actions', :action do
  let(:base_url) { 'https://api.clickup.com/api/v2' }
  # The Workspace lives on the connection; an action only names the Space, Folder and List.
  let(:outbound_connection_config) { { api_token: make_secret_string('pk_test_token'), workspace_id: '90' } }

  let(:location) { { space_id: '5', folder_id: '7', list_id: '9' } }

  describe 'Delete Task' do
    let(:action_template_id) { '019fed58-1d55-758f-a078-4caabf1d8c39' }
    let(:action_input) { location.merge(task_id: 'task-1') }

    it 'deletes the task it was given' do
      stub = stub_request(:delete, "#{base_url}/task/task-1").to_return(status: 200, body: '{}')

      run_action

      expect(stub).to have_been_requested.once
    end

    # 'abc/comment/999' reads as legal path segments once it is joined, so the old check let it
    # through and DELETE /task/abc/comment/999 removed a comment instead of the task.
    context 'when the task id carries slashes' do
      let(:action_input) { location.merge(task_id: 'abc/comment/999') }

      it 'fails before any request rather than delete another resource' do
        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, "ClickUp task_id is not path safe: 'abc/comment/999'")
        expect(a_request(:delete, /api\.clickup\.com/)).not_to have_been_made
      end
    end
  end

  describe 'Assign User To Task' do
    let(:action_template_id) { '019fed58-1d55-7baa-9e21-a405beea7954' }
    let(:action_input) { location.merge(task_id: 'task-1', add_assignees: '184') }

    def assign_stub(assignees: [{ id: 184, username: 'Sam' }])
      stub_request(:put, "#{base_url}/task/task-1")
        .to_return(status: 200, body: { id: 'task-1', assignees: assignees }.to_json)
    end

    it 'sends the ids to add and returns the assignees ClickUp reports' do
      stub = assign_stub.with(body: { assignees: { add: [184], rem: [] } }.to_json)

      output = run_action

      expect(stub).to have_been_requested.once
      expect(output[:id]).to eq('task-1')
      expect(output[:assignees]).to eq([{ id: 184, username: 'Sam' }.with_indifferent_access])
    end

    # ClickUp answers with a list of users. Declaring the field as a bare :hash forced the run to
    # wrap it in another hash, so the output no longer looked like what ClickUp sent.
    it 'declares the assignees output as a list of hashes' do
      field = action_template.output_schema.first.fields.detect { |f| f.id == :assignees }

      expect(field.type).to eq(:hash)
      expect(field.array).to be(true)
    end

    it 'returns an empty list when ClickUp reports no assignees' do
      assign_stub(assignees: nil)

      expect(run_action[:assignees]).to eq([])
    end

    context 'with both assignee fields left empty' do
      let(:action_input) { location.merge(task_id: 'task-1') }

      # Update Task already skips the assignees key when neither field is filled in. This action has
      # nothing else to send, so an empty change is a mistake, not a no-op worth a round trip.
      it 'fails instead of sending an empty change' do
        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, 'Select at least one assignee to add or to remove')
        expect(a_request(:put, /api\.clickup\.com/)).not_to have_been_made
      end
    end

    context 'with a non-numeric assignee id' do
      let(:action_input) { location.merge(task_id: 'task-1', add_assignees: 'sam@example.com') }

      # to_i turned anything non-numeric into user 0 and ClickUp was asked to assign that.
      it 'names the offending value instead of assigning user 0' do
        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, "Add assignees must be numeric ClickUp user ids, got 'sam@example.com'")
        expect(a_request(:put, /api\.clickup\.com/)).not_to have_been_made
      end
    end

    context 'with one good id and one bad id' do
      let(:action_input) { location.merge(task_id: 'task-1', add_assignees: '184, oops') }

      it 'rejects the whole list rather than send the half it could read' do
        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, "Add assignees must be numeric ClickUp user ids, got 'oops'")
        expect(a_request(:put, /api\.clickup\.com/)).not_to have_been_made
      end
    end

    context 'with a removal list' do
      let(:action_input) { location.merge(task_id: 'task-1', remove_assignees: '184,  200 ') }

      it 'reads a padded comma-separated list' do
        stub = assign_stub.with(body: { assignees: { add: [], rem: [184, 200] } }.to_json)

        run_action

        expect(stub).to have_been_requested.once
      end
    end
  end

  describe 'Create Task' do
    let(:action_template_id) { '019fed58-1d55-7372-9b84-a744947b9368' }
    let(:action_input) { location.merge(name: 'Write it up') }

    it 'creates the task in the list it was given' do
      stub = stub_request(:post, "#{base_url}/list/9/task")
             .to_return(status: 200, body: { id: 'task-1', name: 'Write it up' }.to_json)

      expect(run_action[:id]).to eq('task-1')
      expect(stub).to have_been_requested.once
    end

    # A JSON array used to travel on as an Array and blow up on the first slice with a NoMethodError.
    it 'fails with ClickUp\'s answer in the message when the body is a JSON array' do
      stub_request(:post, "#{base_url}/list/9/task")
        .to_return(status: 200, body: [{ id: 'task-1' }].to_json)

      expect { run_action }
        .to raise_error(IPaaS::Job::FailJob, /HTTP 200 with a JSON Array, expected an object/)
    end

    context 'with a non-numeric assignee id' do
      let(:action_input) { location.merge(name: 'Write it up', assignees: 'nobody') }

      it 'fails before the task is created' do
        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, "Assignees must be numeric ClickUp user ids, got 'nobody'")
        expect(a_request(:post, /api\.clickup\.com/)).not_to have_been_made
      end
    end

    context 'when the list id carries slashes' do
      let(:action_input) { location.merge(list_id: '9/task/1', name: 'Write it up') }

      it 'fails before any request' do
        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, "ClickUp list_id is not path safe: '9/task/1'")
        expect(a_request(:post, /api\.clickup\.com/)).not_to have_been_made
      end
    end

    # Every optional field was declared but none was ever sent, so the body assembly was unproven.
    context 'with every optional field filled in' do
      let(:action_input) do
        location.merge(name: 'Write it up', description: 'the description', markdown_content: '# heading',
                       status: 'in progress', priority: 2, due_date: 1_642_740_510_345, assignees: '184,200',
                       tags: 'urgent')
      end

      it 'sends each one in the shape ClickUp expects' do
        stub = stub_request(:post, "#{base_url}/list/9/task")
               .with(body: { name: 'Write it up', description: 'the description', markdown_content: '# heading',
                             assignees: [184, 200], status: 'in progress', priority: 2,
                             due_date: 1_642_740_510_345, tags: ['urgent'], }.to_json)
               .to_return(status: 200, body: { id: 'task-1', name: 'Write it up' }.to_json)

        run_action

        expect(stub).to have_been_requested.once
      end
    end

    context 'with a comma-separated tag string' do
      let(:action_input) { location.merge(name: 'Write it up', tags: 'urgent, blocked') }

      it 'splits it into one tag per name' do
        stub = stub_request(:post, "#{base_url}/list/9/task")
               .with(body: { name: 'Write it up', tags: %w[urgent blocked] }.to_json)
               .to_return(status: 200, body: { id: 'task-1' }.to_json)

        run_action

        expect(stub).to have_been_requested.once
      end
    end

    # Pins a known limitation rather than a wish. The Tags dropdown offers the tag NAME as the
    # option id and the field is a plain string, so a name carrying a comma is indistinguishable
    # from two names. The field hint says so; there is no shape that resolves it in the connector.
    context 'with a tag whose own name contains a comma' do
      let(:action_input) { location.merge(name: 'Write it up', tags: 'urgent, blocked') }

      it 'cannot tell one such tag from two, which is why the hint rules it out' do
        stub = stub_request(:post, "#{base_url}/list/9/task")
               .with(body: { name: 'Write it up', tags: %w[urgent blocked] }.to_json)
               .to_return(status: 200, body: { id: 'task-1' }.to_json)

        run_action

        expect(stub).to have_been_requested.once
        expect(action_template.input_schema.fields.detect { |f| f.id == :tags }.hint)
          .to include('cannot be set from this field')
      end
    end
  end

  describe 'Update Task' do
    let(:action_template_id) { '019fed58-1d55-7d7c-bac8-f7cf4bb76eef' }
    let(:action_input) { location.merge(task_id: 'task-1', name: 'Renamed') }

    it 'leaves the assignees key out when neither assignee field is filled in' do
      stub = stub_request(:put, "#{base_url}/task/task-1")
             .with(body: { name: 'Renamed' }.to_json)
             .to_return(status: 200, body: { id: 'task-1', name: 'Renamed' }.to_json)

      run_action

      expect(stub).to have_been_requested.once
    end

    # The shape guard runs before the status is judged, so this no longer reaches the branch that
    # used to ask whether the body was a Hash before reading its error envelope.
    it 'fails on a JSON array body even when ClickUp answers with an error status' do
      stub_request(:put, "#{base_url}/task/task-1")
        .to_return(status: 500, body: [{ err: 'boom' }].to_json)

      expect { run_action }
        .to raise_error(IPaaS::Job::FailJob, /HTTP 500 with a JSON Array, expected an object/)
    end

    it 'surfaces a ClickUp error envelope rather than the raw body' do
      stub_request(:put, "#{base_url}/task/task-1")
        .to_return(status: 401, body: { err: 'Team not authorized', ECODE: 'OAUTH_027' }.to_json)

      expect { run_action }
        .to raise_error(IPaaS::Job::FailJob, 'ClickUp API error (HTTP 401): Team not authorized (OAUTH_027)')
    end

    # The contrast to the example above: only the absent case was covered, so a change that swapped
    # add and rem, or that sent the key when both were blank, would have passed.
    context 'with an assignee to add and one to remove' do
      let(:action_input) do
        location.merge(task_id: 'task-1', name: 'Renamed', add_assignees: '184', remove_assignees: '200')
      end

      it 'sends the ids to add and to remove on their own sides' do
        stub = stub_request(:put, "#{base_url}/task/task-1")
               .with(body: { name: 'Renamed', assignees: { add: [184], rem: [200] } }.to_json)
               .to_return(status: 200, body: { id: 'task-1' }.to_json)

        run_action

        expect(stub).to have_been_requested.once
      end
    end

    # An empty body PUT reported success for a change that changed nothing. Assign User To Task
    # already refused this shape; Update Task now does too.
    context 'with nothing but the location and the task id' do
      let(:action_input) { location.merge(task_id: 'task-1') }

      it 'refuses rather than PUT an empty body' do
        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, 'Fill in at least one field to update on the task')
        expect(a_request(:put, /api\.clickup\.com/)).not_to have_been_made
      end
    end
  end

  describe 'Upload Task Attachment' do
    let(:action_template_id) { '019fed58-1d55-73d5-b66f-32bdaa7d2c07' }
    let(:action_input) { location.merge(task_id: 'task-1', content: 'hello', filename: 'note.txt') }

    it 'uploads to the task it was given' do
      stub = stub_request(:post, "#{base_url}/task/task-1/attachment")
             .to_return(status: 200, body: { id: 'a1', title: 'note.txt', url: 'https://x/y' }.to_json)

      output = run_action

      expect(stub).to have_been_requested.once
      expect(output[:id]).to eq('a1')
      expect(output[:title]).to eq('note.txt')
    end

    # This action built its URL without safe_id while every sibling used it, so a slash-bearing id
    # retargeted the upload: '../../team/90/webhook' posted the file to /api/team/90/webhook.
    context 'when the task id carries slashes' do
      let(:action_input) { location.merge(task_id: 'abc/comment/999', content: 'hello', filename: 'note.txt') }

      it 'fails before any request rather than post the file somewhere else' do
        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, "ClickUp task_id is not path safe: 'abc/comment/999'")
        expect(a_request(:post, /api\.clickup\.com/)).not_to have_been_made
      end
    end

    context 'when the task id climbs out of the task collection' do
      let(:action_input) do
        location.merge(task_id: '../../team/90/webhook', content: 'hello', filename: 'note.txt')
      end

      it 'fails before any request' do
        expect { run_action }
          .to raise_error(IPaaS::Job::FailJob, "ClickUp task_id is not path safe: '../../team/90/webhook'")
        expect(a_request(:post, /api\.clickup\.com/)).not_to have_been_made
      end
    end
  end

  describe 'Get Workspace Members' do
    let(:action_template_id) { '019fed58-1d55-76e0-bb83-a5c20e75de8f' }
    let(:action_input) { {} }

    # ClickUp nests the person under members[].user here, unlike /list/{id}/member which is flat.
    let(:sam) { { id: 184, username: 'Sam', email: 's@x.com' } }

    it 'reads the roster out of the connection\'s workspace' do
      stub_request(:get, "#{base_url}/team")
        .to_return(status: 200, body: { teams: [{ id: '90', members: [{ user: sam }] }] }.to_json)

      expect(run_action[:members]).to eq([sam.with_indifferent_access])
    end

    # A token that has lost access answers 200 with a list that does not carry the stored Workspace.
    # Reporting an empty roster there tells a syncing runbook to remove everyone.
    it 'fails rather than report an empty roster when the workspace is not in the response' do
      stub_request(:get, "#{base_url}/team")
        .to_return(status: 200, body: { teams: [{ id: '77', members: [] }] }.to_json)

      expect { run_action }.to raise_error(IPaaS::Job::FailJob, /did not return Workspace 90 for this token/)
    end
  end
end
