require 'spec_helper'
require_relative 'shared/graphql_error_handling_specs'

describe 'Xurrent Query Action', :action do
  include XurrentIntrospectionHelper

  let(:action_template_id) { '019ce240-76c9-75d1-beac-8c07b2325e76' }
  let(:outbound_connection_config) { xurrent_outbound_connection_config }
  let(:graphql_endpoint) { xurrent_graphql_endpoint }

  before(:each) do
    stub_introspection
  end

  describe 'input_schema' do
    describe 'base fields (no object selected)' do
      it 'defines the object field as required string' do
        field = action.input_schema.field(:object)
        expect(field.label).to eq('Query object')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end

      it 'defines page_size with default 100 and optional visibility' do
        field = action.input_schema.field(:page_size)
        expect(field.type).to eq(:integer)
        expect(field.default).to eq(100)
        expect(field.visibility).to eq('optional')
      end

      it 'defines max_results as optional integer without default' do
        field = action.input_schema.field(:max_results)
        expect(field.type).to eq(:integer)
        expect(field.min).to eq(1)
        expect(field.default).to be_nil
        expect(field.visibility).to eq('optional')
      end

      it 'defines refresh_schema as optional boolean' do
        field = action.input_schema.field(:refresh_schema)
        expect(field.type).to eq(:boolean)
        expect(field.default).to eq(false)
        expect(field.visibility).to eq('optional')
      end

      it 'does not show view, filter, or order without object selected' do
        expect(action.input_schema.field(:view)).to be_nil
        expect(action.input_schema.field(:filter)).to be_nil
        expect(action.input_schema.field(:order)).to be_nil
      end
    end

    describe 'object field enumeration' do
      context 'with cached schema' do
        before(:each) do
          action.cache_write('gql_schema', introspection_schema, 3600)
        end

        it 'populates the object field with humanized labels' do
          field = action.input_schema.field(:object)
          enum_ids = field.enumeration.map { |e| e[:id] }
          expect(enum_ids).to include('people', 'me')
          labels = field.enumeration.map { |e| e[:label] }
          expect(labels).to include('People', 'Me')
        end

        it 'does not show a notice when schema is loaded' do
          field = action.input_schema.field(:object)
          expect(field.notice).to be_nil
        end
      end

      context 'without cached schema' do
        let(:uncached_action) do
          new_runbook = IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
          IPaaS::Connector::Action.parse(
            new_runbook,
            {
              reference: SecureRandom.uuid,
              outbound_connection: { uuid: outbound_connection.uuid },
              action_template: { uuid: action_template_id },
              input_mapping: field_mapping({}, schema: action_template.input_schema),
            },
          )
        end

        it 'shows object as free-text input with pattern validation' do
          field = uncached_action.input_schema.field(:object)
          expect(field.type).to eq(:string)
          expect(field.required).to be_truthy
        end

        it 'shows a notice prompting to configure the outbound connection' do
          # Use action_template.input_schema directly to test the schema before after_update
          # caches the GraphQL schema via introspection
          field = action_template.input_schema.field(:object)
          expect(field.notice).to include('outbound connection')
        end
      end
    end

    describe 'dynamic fields after object selection' do
      context 'connection type with view/filter/order args (people)' do
        let(:action_input) { { object: 'people', page_size: 25 } }

        it 'shows view as a visible select field with humanized enum labels' do
          view_field = action.input_schema.field(:view)
          expect(view_field).to be_present
          expect(view_field.type).to eq(:string)
          expect(view_field.visibility).not_to eq('optional')
          expect(view_field.notice).to be_nil

          enum_ids = view_field.enumeration.map { |e| e[:id] }
          expect(enum_ids).to eq(%w[all disabled internal directory supportDomain])

          labels = view_field.enumeration.map { |e| e[:label] }
          expect(labels).to include('All', 'Disabled', 'Internal', 'Directory', 'Support Domain')
          expect(labels).not_to include('supportDomain')
        end

        it 'shows filter as a visible nested field with alphabetically sorted, typed sub-fields' do
          filter_field = action.input_schema.field(:filter)
          expect(filter_field).to be_present
          expect(filter_field.type).to eq(:nested)
          expect(filter_field.visibility).not_to eq('optional')

          sub_field_ids = filter_field.fields.map(&:id)
          expect(sub_field_ids).to eq([:createdAt, :disabled, :name, :primaryEmail, :query])

          expect(filter_field.fields.detect { |f| f.id == :query }.type).to eq(:string)
          expect(filter_field.fields.detect { |f| f.id == :disabled }.type).to eq(:boolean)
          expect(filter_field.fields.detect { |f| f.id == :createdAt }.type).to eq(:date_time)

          name_field = filter_field.fields.detect { |f| f.id == :name }
          expect(name_field.type).to eq(:string)
          expect(name_field.array).to be_truthy
        end

        it 'keeps query filter visible, sets others to optional, and passes GraphQL descriptions as hints' do
          filter_field = action.input_schema.field(:filter)
          query_field = filter_field.fields.detect { |f| f.id == :query }
          expect(query_field.visibility).not_to eq('optional')
          expect(query_field.hint).to eq('Search by keyword')

          filter_field.fields.reject { |f| f.id == :query }.each do |sub_field|
            expect(sub_field.visibility).to eq('optional'),
                                            "expected filter sub-field :#{sub_field.id} to have visibility 'optional'"
          end

          disabled_field = filter_field.fields.detect { |f| f.id == :disabled }
          expect(disabled_field.hint).to eq('Filter by disabled')
        end

        it 'shows order as an array of nested objects with field/direction enums and hints' do
          order_field = action.input_schema.field(:order)
          expect(order_field).to be_present
          expect(order_field.type).to eq(:nested)
          expect(order_field.array).to be_truthy

          field_subfield = order_field.fields.detect { |f| f.id == :field }
          expect(field_subfield).to be_present
          expect(field_subfield.required).to be_truthy
          expect(field_subfield.hint).to eq('Field to order by')
          field_enum_ids = field_subfield.enumeration.map { |e| e[:id] }
          expect(field_enum_ids).to include('name', 'createdAt', 'updatedAt')
          labels = field_subfield.enumeration.map { |e| e[:label] }
          expect(labels).to include('Name', 'Created At', 'Updated At')

          direction_subfield = order_field.fields.detect { |f| f.id == :direction }
          expect(direction_subfield).to be_present
          expect(direction_subfield.hint).to eq('Order direction')
          expect(direction_subfield.enumeration.map { |e| e[:id] }).to eq(%w[asc desc])
          expect(direction_subfield.enumeration.map { |e| e[:label] }).to eq(%w[Asc Desc])
        end
      end

      context 'single object type without args (me)' do
        let(:action_input) { { object: 'me', page_size: 100 } }

        it 'does not show view, filter, or order fields but keeps page_size and refresh_schema' do
          expect(action.input_schema.field(:view)).to be_nil
          expect(action.input_schema.field(:filter)).to be_nil
          expect(action.input_schema.field(:order)).to be_nil
          expect(action.input_schema.field(:page_size)).to be_present
          expect(action.input_schema.field(:refresh_schema)).to be_present
        end
      end
    end
  end

  describe 'output_schema' do
    context 'connection type (people)' do
      let(:action_input) { { object: 'people', page_size: 25, include_fields: { organization: true } } }

      it 'generates connection wrapper with typed nested fields, hints, and metadata' do
        output_schema = action.output_schemas.first
        field_ids = output_schema.fields.map(&:id)

        expect(field_ids).to include(:total_count, :has_next_page, :nodes)
        expect(field_ids).to include(:ratelimit, :costlimit, :request_id)

        nodes_field = output_schema.fields.detect { |f| f.id == :nodes }
        expect(nodes_field.array).to be_truthy
        node_field_ids = nodes_field.fields.map(&:id)
        expect(node_field_ids).to include(:id, :name, :primaryEmail, :disabled, :organization)

        # Type mapping
        expect(nodes_field.fields.detect { |f| f.id == :id }.type).to eq(:string)
        expect(nodes_field.fields.detect { |f| f.id == :name }.type).to eq(:string)
        expect(nodes_field.fields.detect { |f| f.id == :disabled }.type).to eq(:boolean)

        # Hints from GraphQL descriptions
        expect(nodes_field.fields.detect { |f| f.id == :name }.hint).to eq('Full name of the person.')
        org_field = nodes_field.fields.detect { |f| f.id == :organization }
        expect(org_field.hint).to eq('Organization the person belongs to.')

        # Nested organization fields
        org_field = nodes_field.fields.detect { |f| f.id == :organization }
        expect(org_field).to be_present
        expect(org_field.fields.map(&:id)).to include(:id, :name)
      end
    end

    context 'single object type (me)' do
      let(:action_input) { { object: 'me', page_size: 100 } }

      it 'generates flat output fields with metadata but without nodes wrapper' do
        output_schema = action.output_schemas.first
        field_ids = output_schema.fields.map(&:id)

        expect(field_ids).to include(:id, :name, :primaryEmail, :disabled)
        expect(field_ids).not_to include(:total_count, :has_next_page, :nodes)
        expect(field_ids).to include(:ratelimit, :costlimit, :request_id)
      end
    end
  end

  describe 'introspection caching' do
    let(:action_input) { { object: 'people' } }

    let(:query_response) do
      { 'people' => { 'nodes' => [] } }
    end

    before(:each) do
      stub_graphql_query(/people/, query_response)
      @query_action = action(action_input)
      # action() triggers after_update which fetches and caches the schema
      WebMock.reset!

      stub_graphql_query(/people/, query_response)
    end

    it 'fetches schema via introspection when cache is empty' do
      @query_action.cache_clear('gql_schema')
      @query_action.cache_clear('_schema_present')

      introspection_stub = stub_introspection
      @query_action.run

      # run triggers a fresh introspection call because cache was cleared
      expect(introspection_stub).to have_been_requested

      expect(@action.cache_read('gql_schema')).to be_present
      expect(@action.cache_read('_schema_present')).to eq(true)
    end

    it 'skips introspection when schema is already cached' do
      @query_action.run

      # run reuses the cached schema without making an introspection call
      expect(WebMock).not_to have_requested(:post, graphql_endpoint)
        .with { |req| req.body.include?('__schema') }
    end

    context 'refresh_schema' do
      let(:action_input) { { refresh_schema: true, object: 'people' } }

      it 'does not skip introspection when schema is already cached' do
        introspection_stub = stub_introspection

        @query_action.run

        # run triggers a fresh introspection call
        expect(introspection_stub).to have_been_requested
      end
    end
  end

  describe 'run' do
    context 'connection query (basic)' do
      let(:action_input) { { object: 'people', page_size: 25 } }

      it 'executes a paginated connection query and returns structured output' do
        stub_graphql_query(/people/, {
          'people' => {
            'totalCount' => 2,
            'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil },
            'nodes' => [
              { 'id' => 'NG1lLnAxIQ', 'name' => 'John Doe', 'primaryEmail' => 'john@example.com',
                'disabled' => false, 'organization' => { 'id' => 'org1', 'name' => 'Acme' }, },
              { 'id' => 'NG1lLnAyIQ', 'name' => 'Jane Smith', 'primaryEmail' => 'jane@example.com',
                'disabled' => false, 'organization' => { 'id' => 'org1', 'name' => 'Acme' }, },
            ],
          },
        })

        output = run_action(action_input, schema_reference: 'query_result')

        expect(output[:total_count]).to eq(2)
        expect(output[:has_next_page]).to eq(false)
        expect(output[:nodes].length).to eq(2)
        expect(output[:nodes].first['name']).to eq('John Doe')
        expect(output[:nodes].second['name']).to eq('Jane Smith')

        # rate and cost limit fields are present in the output
        expect(output[:ratelimit][:limit]).to eq('3600')
        expect(output[:ratelimit][:remaining]).to eq('3599')
        expect(output[:costlimit][:cost]).to eq('12')
        expect(output[:costlimit][:remaining]).to eq('4988')
        expect(output[:request_id]).to eq('req-test-123')
      end

      it 'sends first parameter matching page_size' do
        query_stub = stub_request(:post, graphql_endpoint)
                     .with do |req|
                       body = JSON.parse(req.body)
                       !body['query'].include?('__schema') && body['query'].include?('first: 25')
                     end
          .to_return(
            status: 200,
            body: {
              data: {
                'people' => {
                  'totalCount' => 0,
                  'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil },
                  'nodes' => [],
                },
              },
            }.to_json,
            headers: graphql_response_headers,
          )

        run_action(action_input)
        expect(query_stub).to have_been_requested
      end
    end

    context 'pagination' do
      let(:action_input) { { object: 'people', page_size: 25 } }

      it 'returns has_next_page true when more pages available' do
        stub_graphql_query(/people/, {
          'people' => {
            'totalCount' => 50,
            'pageInfo' => { 'hasNextPage' => true, 'endCursor' => 'cursor-abc' },
            'nodes' => [{ 'id' => 'p1', 'name' => 'First', 'primaryEmail' => 'p1@test.com',
                          'disabled' => false, 'organization' => nil, }],
          },
        })

        output = run_action(action_input, schema_reference: 'query_result')

        expect(output[:has_next_page]).to eq(true)
        expect(output[:total_count]).to eq(50)
      end

      it 'returns has_next_page false when no more pages' do
        stub_graphql_query(/people/, {
          'people' => {
            'totalCount' => 1,
            'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil },
            'nodes' => [{ 'id' => 'p1', 'name' => 'Only', 'primaryEmail' => 'p1@test.com',
                          'disabled' => false, 'organization' => nil, }],
          },
        })

        output = run_action(action_input, schema_reference: 'query_result')
        expect(output[:has_next_page]).to eq(false)
      end

      it 'fails when query returns no data' do
        stub_graphql_query(/people/, { 'people' => nil })

        expect { run_action(action_input) }.to raise_error(IPaaS::Job::FailJob, /No data returned/)
      end
    end

    context 'with max_results' do
      it 'reduces page_size to remaining count when max_results is smaller' do
        query_stub = stub_request(:post, graphql_endpoint)
                     .with do |req|
                       body = JSON.parse(req.body)
                       !body['query'].include?('__schema') && body['query'].include?('first: 5')
                     end
          .to_return(
            status: 200,
            body: {
              data: {
                'people' => {
                  'totalCount' => 50,
                  'pageInfo' => { 'hasNextPage' => true, 'endCursor' => 'cursor-1' },
                  'nodes' => Array.new(5) { |i| { 'id' => "p#{i}", 'name' => "P#{i}" } },
                },
              },
            }.to_json,
            headers: graphql_response_headers,
          )

        run_action({ object: 'people', page_size: 25, max_results: 5 })
        expect(query_stub).to have_been_requested
      end

      it 'stops pagination when max_results is reached' do
        stub_graphql_query(/people/, {
          'people' => {
            'totalCount' => 50,
            'pageInfo' => { 'hasNextPage' => true, 'endCursor' => 'cursor-1' },
            'nodes' => Array.new(10) { |i| { 'id' => "p#{i}", 'name' => "P#{i}" } },
          },
        })

        action_instance = action({ object: 'people', page_size: 10, max_results: 10 })
        action_instance.run

        expect(action_instance.send(:iteration_state_value)).to be_nil
      end

      it 'continues pagination when fetched count is below max_results' do
        stub_graphql_query(/people/, {
          'people' => {
            'totalCount' => 50,
            'pageInfo' => { 'hasNextPage' => true, 'endCursor' => 'cursor-1' },
            'nodes' => Array.new(10) { |i| { 'id' => "p#{i}", 'name' => "P#{i}" } },
          },
        })

        action_instance = action({ object: 'people', page_size: 10, max_results: 25 })
        action_instance.run

        state = action_instance.send(:iteration_state_value)
        expect(state).to be_present
        expect(state['end_cursor']).to eq('cursor-1')
        expect(state['fetched_count']).to eq(10)
      end

      it 'adjusts page_size on subsequent pages based on fetched_count' do
        query_stub = stub_request(:post, graphql_endpoint)
                     .with do |req|
                       body = JSON.parse(req.body)
                       !body['query'].include?('__schema') && body['query'].include?('first: 5')
                     end
          .to_return(
            status: 200,
            body: {
              data: {
                'people' => {
                  'totalCount' => 50,
                  'pageInfo' => { 'hasNextPage' => true, 'endCursor' => 'cursor-2' },
                  'nodes' => Array.new(5) { |i| { 'id' => "p#{i}", 'name' => "P#{i}" } },
                },
              },
            }.to_json,
            headers: graphql_response_headers,
          )

        action_instance = action({ object: 'people', page_size: 25, max_results: 15 })
        action_instance.send(:iteration_state_value=, { end_cursor: 'cursor-1', fetched_count: 10 })
        action_instance.run

        expect(query_stub).to have_been_requested
        expect(action_instance.send(:iteration_state_value)).to be_nil
      end

      it 'paginates normally when max_results is not set' do
        stub_graphql_query(/people/, {
          'people' => {
            'totalCount' => 50,
            'pageInfo' => { 'hasNextPage' => true, 'endCursor' => 'cursor-1' },
            'nodes' => Array.new(25) { |i| { 'id' => "p#{i}", 'name' => "P#{i}" } },
          },
        })

        action_instance = action({ object: 'people', page_size: 25 })
        action_instance.run

        state = action_instance.send(:iteration_state_value)
        expect(state).to be_present
        expect(state).not_to have_key('fetched_count')
      end
    end

    context 'single object query (me)' do
      let(:action_input) { { object: 'me', page_size: 100 } }

      it 'executes a single object query without pagination wrapper' do
        stub_graphql_query(/me/, {
          'me' => {
            'id' => 'NG1lLnAxIQ',
            'name' => 'Current User',
            'primaryEmail' => 'me@example.com',
            'disabled' => false,
            'organization' => { 'id' => 'org1', 'name' => 'My Org' },
          },
        })

        output = run_action(action_input, schema_reference: 'query_result')

        expect(output[:id]).to eq('NG1lLnAxIQ')
        expect(output[:name]).to eq('Current User')
        expect(output[:request_id]).to eq('req-test-123')

        # does not include connection fields in output
        expect(output).not_to have_key(:total_count)
        expect(output).not_to have_key(:has_next_page)
        expect(output).not_to have_key(:nodes)
      end

      it 'fails when single object returns no data' do
        stub_graphql_query(/me/, { 'me' => nil })

        expect { run_action(action_input) }.to raise_error(IPaaS::Job::FailJob, /No data returned/)
      end
    end

    context 'with view parameter' do
      let(:action_input) do
        { object: 'people', page_size: 10, view: 'disabled' }
      end

      it 'passes view as a GraphQL variable' do
        query_stub = stub_request(:post, graphql_endpoint)
                     .with do |req|
                       body = JSON.parse(req.body)
                       !body['query'].include?('__schema') &&
                         body['query'].include?('$view: PersonView') &&
                         body['query'].include?('view: $view') &&
                         body['variables']['view'] == 'disabled'
                     end
          .to_return(
            status: 200,
            body: {
              data: {
                'people' => {
                  'totalCount' => 0,
                  'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil },
                  'nodes' => [],
                },
              },
            }.to_json,
            headers: graphql_response_headers,
          )

        run_action(action_input)
        expect(query_stub).to have_been_requested
      end
    end

    context 'with filter parameter' do
      let(:action_input) do
        { object: 'people', page_size: 10, filter: { name: ['John'] } }
      end

      it 'passes filter as a GraphQL variable' do
        query_stub = stub_request(:post, graphql_endpoint)
                     .with do |req|
                       body = JSON.parse(req.body)
                       !body['query'].include?('__schema') &&
                         body['query'].include?('$filter: PersonFilter') &&
                         body['query'].include?('filter: $filter') &&
                         body['variables']['filter'] == { 'name' => ['John'] }
                     end
          .to_return(
            status: 200,
            body: {
              data: { 'people' => { 'nodes' => [] } },
            }.to_json,
            headers: graphql_response_headers,
          )

        run_action(action_input)
        expect(query_stub).to have_been_requested
      end

      it 'omits filter variable when filter is empty' do
        query_stub = stub_request(:post, graphql_endpoint)
                     .with do |req|
                       body = JSON.parse(req.body)
                       !body['query'].include?('__schema') &&
                         !body['query'].include?('$filter') &&
                         (body['variables'].nil? || !body['variables'].key?('filter'))
                     end
          .to_return(
            status: 200,
            body: {
              data: { 'people' => { 'nodes' => [] } },
            }.to_json,
            headers: graphql_response_headers,
          )

        run_action({ object: 'people', page_size: 10 })
        expect(query_stub).to have_been_requested
      end
    end

    context 'with order parameter' do
      let(:action_input) do
        { object: 'people', page_size: 10, order: [{ 'field' => 'name', 'direction' => 'asc' }] }
      end

      it 'passes order as a GraphQL variable' do
        query_stub = stub_request(:post, graphql_endpoint)
                     .with do |req|
                       body = JSON.parse(req.body)
                       !body['query'].include?('__schema') &&
                         body['query'].include?('$order: [PersonOrder!]') &&
                         body['query'].include?('order: $order') &&
                         body['variables']['order'] == [{ 'field' => 'name', 'direction' => 'asc' }]
                     end
          .to_return(
            status: 200,
            body: {
              data: { 'people' => { 'nodes' => [] } },
            }.to_json,
            headers: graphql_response_headers,
          )

        run_action(action_input)
        expect(query_stub).to have_been_requested
      end
    end

    context 'with all parameters combined' do
      let(:action_input) do
        {
          object: 'people',
          page_size: 10,
          filter: { name: ['John'] },
          order: [{ 'field' => 'name', 'direction' => 'desc' }],
          view: 'all',
        }
      end

      it 'includes all variables in query and passes correct variable types' do
        query_stub = stub_request(:post, graphql_endpoint)
                     .with do |req|
                       body = JSON.parse(req.body)
                       query = body['query']
                       variables = body['variables']
                       !query.include?('__schema') &&
                         query.include?('$view: PersonView') &&
                         query.include?('$filter: PersonFilter') &&
                         query.include?('$order: [PersonOrder!]') &&
                         variables['view'] == 'all' &&
                         variables['filter'] == { 'name' => ['John'] } &&
                         variables['order'] == [{ 'field' => 'name', 'direction' => 'desc' }]
                     end
          .to_return(
            status: 200,
            body: {
              data: { 'people' => { 'nodes' => [] } },
            }.to_json,
            headers: graphql_response_headers,
          )

        run_action(action_input)
        expect(query_stub).to have_been_requested
      end
    end
  end

  describe 'error handling' do
    let(:action_input) { { object: 'people', page_size: 10 } }

    include GraphqlErrorHandlingSpecs
  end

  describe 'introspection' do
    it 'fails on run when introspection returns an error' do
      WebMock.reset!
      stub_request(:post, xurrent_graphql_endpoint)
        .to_return(status: 401, body: 'Unauthorized')

      new_runbook = IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
      a = IPaaS::Connector::Action.parse(
        new_runbook,
        {
          reference: SecureRandom.uuid,
          outbound_connection: { uuid: outbound_connection.uuid },
          action_template: { uuid: action_template_id },
          input_mapping: field_mapping({ object: 'people', page_size: 10 }, schema: action_template.input_schema),
        },
      )

      expect { a.run }.to raise_error(IPaaS::Job::FailJob, /401/)
    end
  end
end
