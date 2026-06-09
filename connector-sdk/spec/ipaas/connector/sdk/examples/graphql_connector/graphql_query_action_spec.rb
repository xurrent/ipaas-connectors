require 'spec_helper'
require_relative 'shared/graphql_error_handling_specs'

describe 'GraphQL Query Action', :action do
  include GraphqlIntrospectionHelper
  include GraphqlConnectorErrorHandlingSpecs

  let(:connector_id) { 'd5bbb2a2-4a95-4b49-b490-56711e4455f8' }
  let(:action_template_id) { 'eb80d943-e0a3-44c7-97aa-640e243f9320' }

  let(:outbound_connection_config) { graphql_connector_outbound_connection_config }
  let(:graphql_endpoint) { graphql_connector_endpoint }
  let(:graphql_response_headers) { graphql_connector_response_headers }
  let(:action_input) { { object: 'users' } }
  let(:graphql_success_data) do
    {
      'users' => {
        'totalCount' => 1,
        'pageInfo' => { 'hasNextPage' => false, 'endCursor' => 'end' },
        'nodes' => [{ 'id' => 'u1' }],
      },
    }
  end

  before(:each) do
    stub_graphql_connector_introspection
  end

  # Regression for request #78064178 (see SchemaClosureHelper).
  describe 'memory: after_update closure does not retain the parsed schema' do
    before(:each) { action.cache_write('gql_schema', graphql_connector_introspection_schema, 3600) }

    it 'releases schema_data so the cached after_update proc does not pin the parsed schema' do
      schema = action.input_schema
      expect(schema.field(:object).enumeration).to be_present # non-vacuous: schema was available
      expect_after_update_not_to_retain_schema(schema)
    end
  end

  describe 'input_schema' do
    it 'defines the object field as required string' do
      field = action.input_schema.field(:object)
      expect(field.label).to eq('Query object')
      expect(field.type).to eq(:string)
      expect(field.required).to be_truthy
    end

    it 'defines include_fields field' do
      action.input_schema.field(:include_fields).tap do |field|
        expect(field.label).to eq('Include nested fields')
        expect(field.type).to eq(:nested)
      end
    end

    it 'defines page_size field' do
      action.input_schema.field(:page_size).tap do |field|
        expect(field.label).to eq('Page size')
        expect(field.type).to eq(:integer)
        expect(field.min).to eq(1)
        expect(field.max).to eq(100)
        expect(field.default).to eq(100)
        expect(field.visibility).to eq('optional')
      end
    end

    it 'defines max_results field' do
      action.input_schema.field(:max_results).tap do |field|
        expect(field.label).to eq('Max results')
        expect(field.type).to eq(:integer)
        expect(field.min).to eq(1)
        expect(field.visibility).to eq('optional')
      end
    end

    it 'defines refresh_schema field' do
      action.input_schema.field(:refresh_schema).tap do |field|
        expect(field.label).to eq('Refresh schema')
        expect(field.type).to eq(:boolean)
        expect(field.visibility).to eq('optional')
        expect(field.default).to eq(false)
      end
    end

    describe 'with cached schema' do
      it 'populates object enumeration from schema' do
        field = action.input_schema.field(:object)
        enum_ids = field.enumeration.map { |e| e[:id] }
        expect(enum_ids).to include('users', 'viewer')
      end
    end
  end

  describe 'output_schema' do
    it 'has query_result output schema' do
      expect(action.output_schema.map(&:reference)).to contain_exactly('query_result')
    end

    describe 'query_result schema' do
      let(:output_schema) { action.output_schema.first }

      it 'defines request_id field' do
        output_schema.field(:request_id).tap do |field|
          expect(field.label).to eq('Request ID')
          expect(field.type).to eq(:string)
          expect(field.visibility).to eq('optional')
        end
      end
    end
  end

  describe 'iteration_state_schema' do
    it 'defines end_cursor field' do
      action.iteration_state_schema.field(:end_cursor).tap do |field|
        expect(field.label).to eq('End cursor')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end
    end

    it 'defines fetched_count field' do
      action.iteration_state_schema.field(:fetched_count).tap do |field|
        expect(field.label).to eq('Fetched count')
        expect(field.type).to eq(:integer)
      end
    end
  end

  describe 'run' do
    describe 'connection query (paginated)' do
      it 'queries users and returns paginated results' do
        stub = stub_graphql_connector_query(
          /users/,
          {
            'users' => {
              'totalCount' => 2,
              'pageInfo' => { 'hasNextPage' => false, 'endCursor' => 'cursor1' },
              'nodes' => [
                { 'id' => 'u1', 'name' => 'Alice', 'email' => 'alice@example.com', 'active' => true },
                { 'id' => 'u2', 'name' => 'Bob', 'email' => 'bob@example.com', 'active' => false },
              ],
            },
          },
        )

        output = run_action({ object: 'users' })
        expect(output[:total_count]).to eq(2)
        expect(output[:has_next_page]).to eq(false)
        expect(output[:nodes].length).to eq(2)
        expect(output[:nodes].first[:name]).to eq('Alice')
        expect(stub).to have_been_requested.once
      end

      describe 'iteration state handling' do
        it 'clears iteration_state_value when hasNextPage is false' do
          stub_graphql_connector_query(
            /users/,
            {
              'users' => {
                'totalCount' => 1,
                'pageInfo' => { 'hasNextPage' => false, 'endCursor' => 'end' },
                'nodes' => [{ 'id' => 'u1', 'name' => 'Alice' }],
              },
            },
          )

          expect(action({ object: 'users' })).to receive(:iteration_state_value=).with(nil)
          run_action({ object: 'users' })
        end

        it 'stores iteration_state_value when hasNextPage is true' do
          stub_graphql_connector_query(
            /users/,
            {
              'users' => {
                'totalCount' => 100,
                'pageInfo' => { 'hasNextPage' => true, 'endCursor' => 'cursor42' },
                'nodes' => [{ 'id' => 'u1' }],
              },
            },
          )

          expect(action({ object: 'users' })).to receive(:iteration_state_value=).with({ end_cursor: 'cursor42' })
          run_action({ object: 'users' })
        end

        it 'uses iteration_state_value for pagination cursor' do
          stub = stub_graphql_connector_query(
            /halfWay/,
            {
              'users' => {
                'totalCount' => 10,
                'pageInfo' => { 'hasNextPage' => false, 'endCursor' => 'end' },
                'nodes' => [{ 'id' => 'u5' }],
              },
            },
          )

          action({ object: 'users' }).send(:iteration_state_value=, { end_cursor: 'halfWay' })
          output = run_action({ object: 'users' })
          expect(output[:nodes].first[:id]).to eq('u5')
          expect(stub).to have_been_requested.once
        end
      end
    end

    describe 'simple query (single object)' do
      it 'queries viewer and returns result' do
        stub = stub_graphql_connector_query(
          /viewer/,
          {
            'viewer' => { 'id' => 'me1', 'name' => 'Current User', 'email' => 'me@example.com', 'active' => true },
          },
        )

        output = run_action({ object: 'viewer' })
        expect(output[:name]).to eq('Current User')
        expect(output[:email]).to eq('me@example.com')
        expect(stub).to have_been_requested.once
      end
    end

    describe 'list query (non-connection array)' do
      it 'queries posts and returns results in nodes array' do
        stub = stub_graphql_connector_query(
          /posts/,
          {
            'posts' => [
              { 'id' => 'p1', 'title' => 'First Post', 'body' => 'Hello' },
              { 'id' => 'p2', 'title' => 'Second Post', 'body' => 'World' },
            ],
          },
        )

        output = run_action({ object: 'posts' })
        expect(output[:nodes].length).to eq(2)
        expect(output[:nodes].first[:title]).to eq('First Post')
        expect(output[:nodes].last[:title]).to eq('Second Post')
        expect(stub).to have_been_requested.once
      end

      it 'passes user-provided arguments as variables' do
        stub = stub_graphql_connector_query(
          /posts.*status/,
          {
            'posts' => [
              { 'id' => 'p1', 'title' => 'Active Post', 'body' => 'Content' },
            ],
          },
        )

        output = run_action({ object: 'posts', status: 'active' })
        expect(output[:nodes].length).to eq(1)
        expect(stub).to have_been_requested.once
      end
    end

    describe 'request ID extraction' do
      it 'extracts x-request-id header' do
        stub_graphql_connector_query(
          /users/,
          {
            'users' => {
              'totalCount' => 1,
              'pageInfo' => { 'hasNextPage' => false, 'endCursor' => 'end' },
              'nodes' => [{ 'id' => 'u1' }],
            },
          },
          headers: { 'x-request-id' => 'req-abc-123' },
        )

        output = run_action({ object: 'users' })
        expect(output[:request_id]).to eq('req-abc-123')
      end
    end
  end
end
