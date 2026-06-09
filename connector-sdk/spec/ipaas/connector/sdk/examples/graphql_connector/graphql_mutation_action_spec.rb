require 'spec_helper'
require_relative 'shared/graphql_error_handling_specs'

describe 'GraphQL Mutation Action', :action do
  include GraphqlIntrospectionHelper
  include GraphqlConnectorErrorHandlingSpecs

  let(:connector_id) { 'd5bbb2a2-4a95-4b49-b490-56711e4455f8' }
  let(:action_template_id) { 'f7d7f36f-4746-460a-ba28-30f817be3698' }

  let(:outbound_connection_config) { graphql_connector_outbound_connection_config }
  let(:graphql_endpoint) { graphql_connector_endpoint }
  let(:graphql_response_headers) { graphql_connector_response_headers }
  let(:action_input) { { mutation: 'createPost', input: { title: 'Test' } } }
  let(:graphql_success_data) do
    {
      'createPost' => {
        'post' => { 'id' => 'p1', 'title' => 'Test', 'body' => nil },
        'errors' => [],
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
      expect(schema.field(:mutation).enumeration).to be_present # non-vacuous: schema was available
      expect_after_update_not_to_retain_schema(schema)
    end
  end

  describe 'input_schema' do
    it 'defines the mutation field as required string' do
      field = action.input_schema.field(:mutation)
      expect(field.label).to eq('Mutation')
      expect(field.type).to eq(:string)
      expect(field.required).to be_truthy
    end

    it 'defines include_fields field' do
      action.input_schema.field(:include_fields).tap do |field|
        expect(field.label).to eq('Include nested fields')
        expect(field.type).to eq(:nested)
      end
    end

    it 'defines input field as required' do
      action.input_schema.field(:input).tap do |field|
        expect(field.label).to eq('Input')
        expect(field.required).to be_truthy
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
      it 'populates mutation enumeration from schema' do
        field = action.input_schema.field(:mutation)
        enum_ids = field.enumeration.map { |e| e[:id] }
        expect(enum_ids).to include('createPost', 'updateUser')
      end
    end
  end

  describe 'output_schema' do
    it 'has mutation_result output schema' do
      expect(action.output_schema.map(&:reference)).to contain_exactly('mutation_result')
    end

    describe 'mutation_result schema' do
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

  describe 'run' do
    describe 'successful mutation' do
      it 'executes createPost mutation' do
        stub = stub_graphql_connector_query(
          /createPost/,
          {
            'createPost' => {
              'post' => { 'id' => 'p1', 'title' => 'Hello', 'body' => 'World' },
              'errors' => [],
            },
          },
        )

        output = run_action({ mutation: 'createPost', input: { title: 'Hello', body: 'World' } })
        expect(output[:post]).to eq({ 'id' => 'p1', 'title' => 'Hello', 'body' => 'World' })
        expect(stub).to have_been_requested.once
      end

      it 'executes updateUser mutation' do
        stub = stub_graphql_connector_query(
          /updateUser/,
          {
            'updateUser' => {
              'user' => { 'id' => 'u1', 'name' => 'Updated Name', 'email' => 'new@example.com', 'active' => true },
              'errors' => [],
            },
          },
        )

        output = run_action({ mutation: 'updateUser', input: { id: 'u1', name: 'Updated Name' } })
        expect(output[:user]).to eq({
          'id' => 'u1', 'name' => 'Updated Name', 'email' => 'new@example.com', 'active' => true,
        })
        expect(stub).to have_been_requested.once
      end
    end

    describe 'mutation errors' do
      it 'fails when mutation returns errors' do
        stub_graphql_connector_query(
          /createPost/,
          {
            'createPost' => {
              'post' => nil,
              'errors' => [{ 'message' => 'Title is required', 'path' => %w[input title] }],
            },
          },
        )

        expect { run_action({ mutation: 'createPost', input: { title: 'Test' } }) }
          .to raise_error(IPaaS::Job::FailJob, 'Mutation error: Title is required')
      end

      it 'fails when no data returned' do
        stub_graphql_connector_query(
          /createPost/,
          { 'createPost' => nil },
        )

        expect { run_action({ mutation: 'createPost', input: { title: 'Test' } }) }
          .to raise_error(IPaaS::Job::FailJob, "No data returned for mutation 'createPost'")
      end
    end

    describe 'request ID extraction' do
      it 'extracts x-request-id header' do
        stub_graphql_connector_query(
          /createPost/,
          {
            'createPost' => {
              'post' => { 'id' => 'p1', 'title' => 'Hello', 'body' => 'World' },
              'errors' => [],
            },
          },
          headers: { 'x-request-id' => 'req-mut-789' },
        )

        output = run_action({ mutation: 'createPost', input: { title: 'Hello', body: 'World' } })
        expect(output[:request_id]).to eq('req-mut-789')
      end
    end
  end
end
