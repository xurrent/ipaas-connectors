require 'spec_helper'

# The dynamic-dropdown option helpers are the layer this connector introduces and the layer the
# field-options endpoint drives. Caching is the platform's job, so a helper only fetches, maps and
# raises on failure so the endpoint can show a "couldn't load" state instead of an empty list.
describe 'ClickUp option helpers', :outbound_connection do
  let(:connector_id) { '019fed58-1d55-741b-b14d-c9366049dd7d' }
  let(:base_url) { 'https://api.clickup.com/api/v2' }
  let(:outbound_connection_config) { { api_token: make_secret_string('pk_test_token'), workspace_id: '90' } }

  # Bind the connector's outbound helpers to this connection, exactly as the runtime does before it
  # runs one, so http_get resolves against the connection's own credentials. `copy_to` is the
  # runtime's own call, split here into its two halves so the spec keeps the `Helpers` object: the
  # proxy it installs dispatches registered names only, so a helper cannot be reached by name.
  let(:bound_helpers) { connector.outbound_connection.helpers_definition.copy_for(outbound_connection) }

  before do
    helpers_proxy = bound_helpers.for_proc
    outbound_connection.define_singleton_method(:helpers) { helpers_proxy }
  end

  def fetch(name, **)
    bound_helpers.registered_helper(name).execute(**)
  end

  # One value per dependency name, so every block in the sweep can be resolved for real.
  let(:dependency_values) { { space_id: '5', folder_id: '7', list_id: '9' } }

  # Each collection answers with an id only it uses, so a block wired to the wrong helper is caught
  # by the id it comes back with, not just by a keyword that failed to bind.
  let(:option_endpoints) do
    {
      'team' => { teams: [{ id: 'w1', name: 'Acme' }] },
      'team/90/space' => { spaces: [{ id: 's1', name: 'Product' }] },
      'space/5/folder' => { folders: [{ id: 'f1', name: 'Sprints' }] },
      'folder/7/list' => { lists: [{ id: 'l1', name: 'Backlog' }] },
      'list/9/task' => { tasks: [{ id: 't1', name: 'Write it up' }], last_page: true },
      'list/9/member' => { members: [{ id: 184, username: 'sam' }] },
      'list/9' => { statuses: [{ status: 'st1' }] },
      'space/5/tag' => { tags: [{ name: 'tg1' }] },
    }
  end

  let(:expected_option_id) do
    {
      workspace_id: 'w1', space_id: 's1', folder_id: 'f1', list_id: 'l1', task_id: 't1',
      assignee: '184', assignees: '184', add_assignees: '184', remove_assignees: '184',
      assignee_filter: '184', status: 'st1', status_filter: 'st1', tags: 'tg1',
    }
  end

  def stub_option_endpoints
    option_endpoints.each do |path, body|
      request = stub_request(:get, "#{base_url}/#{path}")
      request = request.with(query: { page: '0' }) if path.end_with?('/task')
      request.to_return(status: 200, body: body.to_json)
    end
  end

  # A field carries its options as a block now, and the platform reaches it through call_function.
  # These drive the REAL schema, so they prove the block's keywords line up with what the platform
  # forwards, and that the converted declarations survive the connector's proc rules.
  describe 'the options blocks the converted fields carry' do
    let(:trigger_config) do
      IPaaS::Connector::TriggerTemplate.by_uuid('019fed58-1d55-76d4-bdfc-16fcf316c40c').config_schema
    end
    let(:connection_config) { connector.outbound_connection.config_schema }

    def field(id)
      trigger_config.fields.detect { |f| f.id == id }
    end

    def connection_field(id)
      connection_config.fields.detect { |f| f.id == id }
    end

    # [label, sibling field ids, field] for every field carrying an options block, across the
    # outbound connection config schema, the trigger config schema and all 21 action input schemas.
    def every_options_field
      schemas = [['connection', connection_config], ['trigger', trigger_config]]
      connector.actions.each { |action| schemas << [action.name, action.input_schema] }
      schemas.flat_map do |label, schema|
        ids = schema.fields.map(&:id)
        schema.fields.select(&:options).map { |f| [label, ids, f] }
      end
    end

    it 'derives each field\'s dependencies from its own block' do
      expect(connection_field(:workspace_id).option_dependencies).to eq([])
      expect(field(:space_id).option_dependencies).to eq([])
      expect(field(:folder_id).option_dependencies).to eq([:space_id])
      expect(field(:list_id).option_dependencies).to eq([:space_id, :folder_id])
    end

    it 'resolves a field whose block declares no dependencies' do
      stub_request(:get, "#{base_url}/team")
        .to_return(status: 200, body: { teams: [{ id: '90', name: 'Acme' }] }.to_json)

      expect(connection_field(:workspace_id).call_function(:options, outbound_connection))
        .to eq([{ id: '90', label: 'Acme' }])
    end

    # The Space list is the field that used to take a workspace keyword. It now reads the Workspace
    # from the connection, so it resolves with no dependency values at all.
    it 'resolves the space field from the connection\'s workspace' do
      stub_request(:get, "#{base_url}/team/90/space")
        .to_return(status: 200, body: { spaces: [{ id: 's1', name: 'Product' }] }.to_json)

      expect(field(:space_id).call_function(:options, outbound_connection))
        .to eq([{ id: 's1', label: 'Product' }])
    end

    it 'resolves a field using the keyword its block declares' do
      stub_request(:get, "#{base_url}/space/5/folder")
        .to_return(status: 200, body: { folders: [{ id: 'f1', name: 'Sprints' }] }.to_json)

      expect(field(:folder_id).call_function(:options, outbound_connection, space_id: '5'))
        .to eq([{ id: 'f1', label: 'Sprints' }])
    end

    # The four fields above are checked individually; these three sweep all 66 across the connection,
    # the trigger and every action, because loading the connector only proves the blocks PARSE. A
    # block that named the wrong keyword (|task_id:| where the helper wants list_id) would still load.
    it 'declares only dependencies that exist as sibling fields, in every schema' do
      mismatched = every_options_field.filter_map do |label, schema_field_ids, field|
        missing = field.option_dependencies - schema_field_ids
        "#{label}.#{field.id} depends on #{missing.inspect}" if missing.any?
      end

      expect(mismatched).to eq([])
    end

    # Reading option_dependencies only proves a block names a keyword that exists. Every block is
    # resolved here against a stub, so a block handed to the wrong helper fails on the ids it
    # returns: |list_id:| passed to fetch_task_options instead of fetch_assignee_options comes back
    # with the tasks collection, and that no longer matches what the field is meant to list.
    it 'resolves every options block through the helper that field is meant to use' do
      stub_option_endpoints

      wrong = every_options_field.filter_map do |label, _schema_field_ids, field|
        expected = expected_option_id[field.id]
        next "#{label}.#{field.id} carries options but this spec pins no collection for it" if expected.nil?

        kwargs = field.option_dependencies.to_h { |name| [name, dependency_values.fetch(name)] }
        ids = field.call_function(:options, outbound_connection, **kwargs).map { |option| option[:id] }
        "#{label}.#{field.id} listed #{ids.inspect}, expected #{[expected].inspect}" unless ids == [expected]
      end

      expect(wrong).to eq([])
    end

    # Tasks are the one ClickUp collection that pages. Stopping at the first page drops the saved
    # task off its own dropdown, and the designer then reports it as a value that no longer exists.
    it 'walks every page of tasks, not only the first' do
      stub_request(:get, "#{base_url}/list/9/task").with(query: { page: '0' })
                                                   .to_return(status: 200, body: { tasks: [{ id: 't1', name: 'One' }],
                                                                                   last_page: false, }.to_json)
      stub_request(:get, "#{base_url}/list/9/task").with(query: { page: '1' })
                                                   .to_return(status: 200, body: { tasks: [{ id: 't2', name: 'Two' }],
                                                                                   last_page: true, }.to_json)

      expect(fetch(:fetch_task_options, list_id: '9').map { |option| option[:id] }).to eq(%w[t1 t2])
    end

    # A list that never says it is done would otherwise walk for ever inside the endpoint's deadline.
    it 'stops at the page cap when ClickUp never reports the last page' do
      stub_request(:get, %r{#{base_url}/list/9/task})
        .to_return(status: 200, body: { tasks: [{ id: 't1', name: 'One' }], last_page: false }.to_json)

      expect(fetch(:fetch_task_options, list_id: '9').size)
        .to eq(ClickupConnector::MAX_OPTION_PAGES)
    end

    it 'pins the full sweep size and the closed set of dependency names' do
      expect(every_options_field.size).to eq(66)
      expect(every_options_field.map { |_, _, field| field.option_dependencies }.flatten.uniq.sort)
        .to eq([:folder_id, :list_id, :space_id])
    end

    # The assignee dropdown feeds fields whose run block puts the value through comma_ints, which
    # only accepts digits. Nothing crossed that boundary before, so the sweep could have pinned an
    # id the connector then refused. Real ClickUp member ids are numeric; this keeps the stub honest.
    it 'offers assignee ids the run blocks will actually accept' do
      stub_option_endpoints

      assignee_fields = every_options_field.select { |_, _, field| field.id.to_s.include?('assignee') }
      offered = assignee_fields.flat_map do |_, _, field|
        kwargs = field.option_dependencies.to_h { |name| [name, dependency_values.fetch(name)] }
        field.call_function(:options, outbound_connection, **kwargs).map { |option| option[:id] }
      end

      expect(assignee_fields).not_to be_empty
      expect(offered.uniq).to all(match(/\A\d+\z/))
    end

    # The Workspace is asked for once, on the connection, and nowhere else. The first expectation
    # proves the search finds a workspace field where one exists, so the empty result below means
    # the field is gone rather than that the predicate never matches anything.
    it 'carries a workspace field on the connection and in no other schema' do
      schemas = [['trigger', trigger_config]]
      connector.actions.each { |action| schemas << [action.name, action.input_schema] }

      expect(connection_config.fields.map(&:id)).to include(:workspace_id)

      carrying = schemas.select { |_, schema| schema.fields.any? { |f| f.id == :workspace_id } }

      expect(carrying.map(&:first)).to eq([])
    end

    it 'resolves the list field from only the non-blank half of its dependencies' do
      stub_request(:get, "#{base_url}/space/5/list")
        .to_return(status: 200, body: { lists: [{ id: 'l1', name: 'Backlog' }] }.to_json)

      expect(field(:list_id).call_function(:options, outbound_connection, space_id: '5'))
        .to eq([{ id: 'l1', label: 'Backlog' }])
    end
  end

  describe 'fetch_options_keyed (default id/name keys)' do
    it 'maps id/name onto id/label' do
      stub = stub_request(:get, "#{base_url}/team")
             .to_return(status: 200, body: { teams: [{ id: '90', name: 'Acme' }] }.to_json)

      expect(fetch(:fetch_workspace_options)).to eq([{ id: '90', label: 'Acme' }])
      expect(stub).to have_been_requested.once
    end

    it 'fetches again on every call, leaving caching to the platform' do
      stub = stub_request(:get, "#{base_url}/team")
             .to_return(status: 200, body: { teams: [{ id: '90', name: 'Acme' }] }.to_json)

      fetch(:fetch_workspace_options)
      fetch(:fetch_workspace_options)

      expect(stub).to have_been_requested.twice
    end

    it 'fails before any request when an id is not path safe, naming the whole value' do
      expect { fetch(:fetch_folder_options, space_id: '../../user') }
        .to raise_error(IPaaS::Job::FailJob, "ClickUp space_id is not path safe: '../../user'")
      expect(a_request(:get, /api\.clickup\.com/)).not_to have_been_made
    end

    # Checking the assembled path passed this: every piece of "space/1/list/9/folder" is a legal
    # segment on its own, so the id silently retargeted the request at another resource.
    it 'rejects an id whose slashes would read as legal path segments' do
      expect { fetch(:fetch_folder_options, space_id: '1/list/9') }
        .to raise_error(IPaaS::Job::FailJob, "ClickUp space_id is not path safe: '1/list/9'")
      expect(a_request(:get, /api\.clickup\.com/)).not_to have_been_made
    end

    it 'rejects the folder id on the folder branch of the list helper' do
      expect { fetch(:fetch_list_options, folder_id: '7/task/1') }
        .to raise_error(IPaaS::Job::FailJob, "ClickUp folder_id is not path safe: '7/task/1'")
      expect(a_request(:get, /api\.clickup\.com/)).not_to have_been_made
    end

    it 'returns an empty list, not an error, for a genuinely empty collection' do
      stub_request(:get, "#{base_url}/team").to_return(status: 200, body: { teams: [] }.to_json)

      expect(fetch(:fetch_workspace_options)).to eq([])
    end

    it 'raises on a non-2xx response' do
      stub_request(:get, "#{base_url}/team").to_return(status: 500, body: 'boom')

      expect { fetch(:fetch_workspace_options) }.to raise_error(/HTTP 500/)
    end

    # The options path shares the actions' response handler, so the reason names the status and
    # quotes the body rather than surfacing a bare parser error.
    it 'raises on a 2xx body that is not JSON, naming the status and the body' do
      stub_request(:get, "#{base_url}/team").to_return(status: 200, body: 'not json')

      expect { fetch(:fetch_workspace_options) }
        .to raise_error(IPaaS::Job::FailJob, 'ClickUp returned HTTP 200 with a non-JSON body: not json')
    end

    # A 200 whose body parses but has the wrong shape must raise, not read as an empty list.
    it 'raises when the collection key is missing' do
      stub_request(:get, "#{base_url}/team").to_return(status: 200, body: {}.to_json)

      expect { fetch(:fetch_workspace_options) }.to raise_error(/no 'teams' list/)
    end

    it 'raises when the collection is present but not a list' do
      stub_request(:get, "#{base_url}/team").to_return(status: 200, body: { teams: 'oops' }.to_json)

      expect { fetch(:fetch_workspace_options) }.to raise_error(/no 'teams' list/)
    end

    it 'raises when the body is a JSON array rather than an object' do
      stub_request(:get, "#{base_url}/team")
        .to_return(status: 200, body: [{ id: '90', name: 'Acme' }].to_json)

      expect { fetch(:fetch_workspace_options) }
        .to raise_error(IPaaS::Job::FailJob, /JSON Array, expected an object/)
    end

    it 'leaves the code out of the message when ClickUp sends err without ECODE' do
      stub_request(:get, "#{base_url}/team")
        .to_return(status: 200, body: { err: 'Team not authorized' }.to_json)

      # \z pins the end of the message: a missing code must not render as a trailing " ()".
      expect { fetch(:fetch_workspace_options) }.to raise_error(/Team not authorized\z/)
    end

    it 'surfaces ClickUp err text when a 200 carries an error envelope' do
      stub_request(:get, "#{base_url}/team")
        .to_return(status: 200, body: { err: 'Team not authorized', ECODE: 'OAUTH_027' }.to_json)

      expect { fetch(:fetch_workspace_options) }.to raise_error(/Team not authorized \(OAUTH_027\)/)
    end

    # The helper holds no state between calls, so a failure cannot affect the next call.
    it 'recovers on the next call once ClickUp answers properly' do
      stub_request(:get, "#{base_url}/team").to_return(status: 200, body: {}.to_json)
      expect { fetch(:fetch_workspace_options) }.to raise_error(/no 'teams' list/)

      WebMock.reset!
      stub_request(:get, "#{base_url}/team")
        .to_return(status: 200, body: { teams: [{ id: '90', name: 'Acme' }] }.to_json)

      expect(fetch(:fetch_workspace_options)).to eq([{ id: '90', label: 'Acme' }])
    end
  end

  # The Workspace lives on the connection now, so every workspace-scoped call reads it from there
  # rather than from a form field the user fills in again on each step.
  describe 'the workspace the connection carries' do
    it 'scopes the space list to it' do
      stub = stub_request(:get, "#{base_url}/team/90/space")
             .to_return(status: 200, body: { spaces: [{ id: 's1', name: 'Product' }] }.to_json)

      expect(fetch(:fetch_space_options)).to eq([{ id: 's1', label: 'Product' }])
      expect(stub).to have_been_requested.once
    end

    it 'reads it through connection_workspace_id' do
      expect(fetch(:connection_workspace_id)).to eq('90')
    end

    # The contrast case: a second connection carries a second Workspace, which is the whole point
    # of moving the field. A hardcoded id would pass the example above and fail this one.
    context 'on a connection carrying a different workspace' do
      let(:outbound_connection_config) { { api_token: make_secret_string('pk_test_token'), workspace_id: '77' } }

      it 'reads that one instead' do
        stub = stub_request(:get, "#{base_url}/team/77/space")
               .to_return(status: 200, body: { spaces: [{ id: 's9', name: 'Other' }] }.to_json)

        expect(fetch(:connection_workspace_id)).to eq('77')
        expect(fetch(:fetch_space_options)).to eq([{ id: 's9', label: 'Other' }])
        expect(stub).to have_been_requested.once
      end
    end

    context 'when the connection has no workspace selected' do
      let(:outbound_connection_config) { { api_token: make_secret_string('pk_test_token') } }

      it 'fails with a message pointing at the connection, before any request' do
        expect { fetch(:connection_workspace_id) }
          .to raise_error(IPaaS::Job::FailJob,
                          /This ClickUp connection has no Workspace selected\. Select one on the connection\./)
        expect(a_request(:get, /api\.clickup\.com/)).not_to have_been_made
      end

      it 'fails the space list the same way' do
        expect { fetch(:fetch_space_options) }
          .to raise_error(IPaaS::Job::FailJob, /This ClickUp connection has no Workspace selected/)
        expect(a_request(:get, /api\.clickup\.com/)).not_to have_been_made
      end
    end

    context 'when the workspace on the connection is not path safe' do
      let(:outbound_connection_config) do
        { api_token: make_secret_string('pk_test_token'), workspace_id: '../../user' }
      end

      it 'fails before any request, naming the whole value' do
        expect { fetch(:fetch_space_options) }
          .to raise_error(IPaaS::Job::FailJob, "ClickUp workspace_id is not path safe: '../../user'")
        expect(a_request(:get, /api\.clickup\.com/)).not_to have_been_made
      end

      it 'fails the same way when the helper is asked for the id on its own' do
        expect { fetch(:connection_workspace_id) }
          .to raise_error(IPaaS::Job::FailJob, "ClickUp workspace_id is not path safe: '../../user'")
      end
    end
  end

  describe 'fetch_list_options folderless path' do
    it 'lists a space directly when no folder is given' do
      stub = stub_request(:get, "#{base_url}/space/5/list")
             .to_return(status: 200, body: { lists: [{ id: 'l1', name: 'Backlog' }] }.to_json)

      expect(fetch(:fetch_list_options, space_id: '5')).to eq([{ id: 'l1', label: 'Backlog' }])
      expect(stub).to have_been_requested.once
    end

    it 'lists a folder when folder_id is present' do
      stub = stub_request(:get, "#{base_url}/folder/7/list")
             .to_return(status: 200, body: { lists: [{ id: 'l2', name: 'Sprint' }] }.to_json)

      expect(fetch(:fetch_list_options, space_id: '5', folder_id: '7')).to eq([{ id: 'l2', label: 'Sprint' }])
      expect(stub).to have_been_requested.once
    end

    it 'lists a folder even when space_id is absent, rather than raising ArgumentError' do
      stub = stub_request(:get, "#{base_url}/folder/7/list")
             .to_return(status: 200, body: { lists: [{ id: 'l2', name: 'Sprint' }] }.to_json)

      expect(fetch(:fetch_list_options, folder_id: '7')).to eq([{ id: 'l2', label: 'Sprint' }])
      expect(stub).to have_been_requested.once
    end

    it 'returns no options and makes no request when neither space nor folder is given' do
      expect(fetch(:fetch_list_options)).to eq([])
      expect(a_request(:get, /api\.clickup\.com/)).not_to have_been_made
    end
  end

  describe 'fetch_options_keyed (custom id/label keys)' do
    it 'maps custom keys onto id/label' do
      stub_request(:get, "#{base_url}/list/9")
        .to_return(status: 200, body: { statuses: [{ status: 'open' }, { status: 'done' }] }.to_json)

      expect(fetch(:fetch_status_options, list_id: '9')).to eq(
        [{ id: 'open', label: 'open' }, { id: 'done', label: 'done' }]
      )
    end

    it 'raises on a non-2xx response' do
      stub_request(:get, "#{base_url}/list/9").to_return(status: 404, body: 'nope')

      expect { fetch(:fetch_status_options, list_id: '9') }.to raise_error(/HTTP 404/)
    end

    it 'raises on a 2xx body that is not JSON, naming the status and the body' do
      stub_request(:get, "#{base_url}/list/9").to_return(status: 200, body: 'not json')

      expect { fetch(:fetch_status_options, list_id: '9') }
        .to raise_error(IPaaS::Job::FailJob, 'ClickUp returned HTTP 200 with a non-JSON body: not json')
    end

    it 'raises when the collection key is missing' do
      stub_request(:get, "#{base_url}/list/9").to_return(status: 200, body: {}.to_json)

      expect { fetch(:fetch_status_options, list_id: '9') }.to raise_error(/no 'statuses' list/)
    end
  end
end
