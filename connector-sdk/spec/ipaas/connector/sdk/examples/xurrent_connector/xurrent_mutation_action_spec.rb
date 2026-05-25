require 'spec_helper'
require_relative 'shared/graphql_error_handling_specs'

describe 'Xurrent Mutation Action', :action do
  include XurrentIntrospectionHelper

  let(:action_template_id) { '019ce240-76c9-7847-9dfa-a48d104515b3' }
  let(:outbound_connection_config) { xurrent_outbound_connection_config }
  let(:graphql_endpoint) { xurrent_graphql_endpoint }

  before(:each) do
    stub_introspection
  end

  describe 'input_schema' do
    context 'without cached schema' do
      it 'defines the mutation field as a required free-text string' do
        field = action.input_schema.field(:mutation)
        expect(field.label).to eq('Mutation')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end

      it 'defines the input field as a required hash' do
        field = action.input_schema.field(:input)
        expect(field.type).to eq(:hash)
        expect(field.required).to be_truthy
      end

      it 'shows a notice prompting to configure the outbound connection' do
        field = action_template.input_schema.field(:mutation)
        expect(field.notice).to include('outbound connection')
      end
    end

    context 'with cached schema' do
      before(:each) do
        action.cache_write('gql_schema', introspection_schema, 3600)
      end

      it 'populates the mutation field with enum values and human-readable labels' do
        field = action.input_schema.field(:mutation)
        expect(field.type).to eq(:string)
        enum_ids = field.enumeration.map { |e| e[:id] }
        expect(enum_ids).to include('requestCreate', 'personUpdate')
        labels = field.enumeration.map { |e| e[:label] }
        expect(labels).to include('Request Create', 'Person Update')
      end

      it 'does not show a notice when schema is loaded' do
        field = action.input_schema.field(:mutation)
        expect(field.notice).to be_nil
      end

      it 'defines refresh_schema as optional boolean' do
        field = action.input_schema.field(:refresh_schema)
        expect(field.type).to eq(:boolean)
        expect(field.default).to eq(false)
        expect(field.visibility).to eq('optional')
      end
    end
  end

  describe 'dynamic input schema generation' do
    let(:action_input) { { mutation: 'requestCreate', input: { 'subject' => 'Test' } } }

    it 'generates typed input fields with correct required flags from the mutation input type' do
      input_field = action.input_schema.field(:input)
      expect(input_field.type).to eq(:nested)

      input_field_ids = input_field.fields.map(&:id)
      expect(input_field_ids).to include(:subject, :category)

      subject_field = input_field.fields.detect { |f| f.id == :subject }
      category_field = input_field.fields.detect { |f| f.id == :category }
      expect(subject_field.required).to be_truthy
      expect(category_field.required).to be_falsey
      expect(category_field.visibility).to eq('optional')

      custom_fields = input_field.fields.detect { |f| f.id == :customFields }
      expect(custom_fields).to be_present
      expect(custom_fields.array).to be_truthy
      expect(custom_fields.required).to be_falsey
      expect(custom_fields.visibility).to eq('optional')
    end

    it 'keeps key integration fields always visible' do
      input_field = action.input_schema.field(:input)
      source_field = input_field.fields.detect { |f| f.id == :source }
      source_id_field = input_field.fields.detect { |f| f.id == :sourceID }

      expect(source_field.required).to be_falsey
      expect(source_field.visibility).not_to eq('optional')
      expect(source_id_field.required).to be_falsey
      expect(source_id_field.visibility).not_to eq('optional')
    end

    it 'generates enum values for enum input fields' do
      input_field = action.input_schema.field(:input)
      category_field = input_field.fields.detect { |f| f.id == :category }

      expect(category_field.type).to eq(:string)
      enum_ids = category_field.enumeration.map { |e| e[:id] }
      expect(enum_ids).to include('incident', 'rfc', 'rfi', 'complaint')
    end
  end

  describe 'dynamic input schema for personUpdate' do
    let(:action_input) { { mutation: 'personUpdate', input: { 'id' => 'p1' } } }

    it 'excludes clientMutationId and marks the id field as required' do
      input_field = action.input_schema.field(:input)
      input_field_ids = input_field.fields.map(&:id)

      expect(input_field_ids).not_to include(:clientMutationId)
      expect(input_field_ids).to include(:id, :name, :primaryEmail, :disabled)

      id_field = input_field.fields.detect { |f| f.id == :id }
      expect(id_field.required).to be_truthy
      expect(id_field.type).to eq(:string)
    end
  end

  describe 'dynamic output schema generation' do
    let(:action_input) do
      { mutation: 'requestCreate', input: { 'subject' => 'Test' },
        include_fields: [{ field: 'request' }, { field: 'errors' }], }
    end

    it 'generates output fields including metadata from the mutation return type' do
      output_schema = action.output_schemas.first
      field_ids = output_schema.fields.map(&:id)

      expect(field_ids).to include(:request, :errors)
      expect(field_ids).to include(:ratelimit, :costlimit, :request_id)
    end

    it 'generates nested fields for the mutation result object' do
      output_schema = action.output_schemas.first
      request_field = output_schema.fields.detect { |f| f.id == :request }

      expect(request_field).to be_present
      request_subfields = request_field.fields.map(&:id)
      expect(request_subfields).to include(:id, :subject)
    end

    it 'includes errors field with message and path' do
      output_schema = action.output_schemas.first
      errors_field = output_schema.fields.detect { |f| f.id == :errors }

      expect(errors_field).to be_present
      error_subfields = errors_field.fields.map(&:id)
      expect(error_subfields).to include(:message, :path)
    end
  end

  describe 'nested input mapping (GUI scenario)' do
    def nested_action_def(nested_input_fields)
      {
        reference: SecureRandom.uuid,
        outbound_connection: { uuid: outbound_connection.uuid },
        action_template: { uuid: action_template_id },
        input_mapping: [
          { field_id: :mutation, fixed: 'requestCreate' },
          { field_id: :input, nested: nested_input_fields },
        ],
      }
    end

    def create_action_with_nested_mapping(nested_input_fields)
      runbook = IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
      IPaaS::Connector::Action.parse(runbook, nested_action_def(nested_input_fields))
    end

    it 'preserves mutation value and resolves input with nested mapping' do
      a = create_action_with_nested_mapping([
        { field_id: :subject, fixed: 'Test request' },
        { field_id: :category, fixed: 'incident' },
        { field_id: :source, fixed: 'my_integration' },
      ])

      expect(a.input[:mutation]).to eq('requestCreate')
      expect(a.input[:input]).to be_present
      expect(a.input[:input][:subject]).to eq('Test request')

      # Removing a sub-field still preserves the mutation value
      a2 = create_action_with_nested_mapping([
        { field_id: :subject, fixed: 'Test request' },
        { field_id: :source, fixed: 'my_integration' },
      ])
      expect(a2.input[:mutation]).to eq('requestCreate')
      expect(a2.input[:input][:subject]).to eq('Test request')
      expect(a2.input[:input][:category]).to be_nil
    end

    it 'preserves mutation value on re-resolve after modifying input mapping' do
      a = create_action_with_nested_mapping([
        { field_id: :subject, fixed: 'Test request' },
        { field_id: :category, fixed: 'incident' },
      ])
      expect(a.input[:mutation]).to eq('requestCreate')

      a.input_mapping = [
        { field_id: :mutation, fixed: 'requestCreate' },
        { field_id: :input, nested: [
          { field_id: :subject, fixed: 'Test request' },
        ], },
      ].map { |m| IPaaS::Connector::Mapping::FieldMapping.parse(m) }

      resolved = a.input(resolve: true)
      expect(resolved[:mutation]).to eq('requestCreate')
      expect(resolved[:input][:subject]).to eq('Test request')
    end

    it 'populates all dynamic schema fields regardless of which fields are mapped' do
      a = create_action_with_nested_mapping([
        { field_id: :subject, fixed: 'Test request' },
      ])

      input_field = a.input_schema.field(:input)
      expect(input_field.type).to eq(:nested)

      input_field_ids = input_field.fields.map(&:id)
      expect(input_field_ids).to include(:subject, :category, :source, :sourceID)
    end
  end

  describe 'introspection caching' do
    let(:action_input) do
      { mutation: 'requestCreate', input: { 'subject' => 'Test request', 'category' => 'incident' } }
    end

    let(:mutation_response) do
      {
        'requestCreate' => {
          'request' => { 'id' => 'req-123' },
        },
      }
    end

    before(:each) do
      stub_graphql_query(/requestCreate/, mutation_response)
      @mutation_action = action(action_input)
      # action() triggers after_update which fetches and caches the schema
      WebMock.reset!

      stub_graphql_query(/requestCreate/, mutation_response)
    end

    it 'fetches schema via introspection when cache is empty' do
      @mutation_action.cache_clear('gql_schema')
      @mutation_action.cache_clear('_schema_present')

      introspection_stub = stub_introspection
      @mutation_action.run

      # run triggers a fresh introspection call because cache was cleared
      expect(introspection_stub).to have_been_requested

      expect(@mutation_action.cache_read('gql_schema')).to be_present
      expect(@mutation_action.cache_read('_schema_present')).to eq(true)
    end

    it 'skips introspection when schema is already cached' do
      @mutation_action.run

      # run reuses the cached schema without making an introspection call
      expect(WebMock).not_to have_requested(:post, graphql_endpoint)
        .with { |req| req.body.include?('__schema') }
    end

    context 'refresh_schema' do
      let(:action_input) do
        {
          refresh_schema: true,
          mutation: 'requestCreate',
          input: { 'subject' => 'Test request', 'category' => 'incident' },
        }
      end

      it 'does not skip introspection when schema is already cached' do
        introspection_stub = stub_introspection

        @mutation_action.run

        # run triggers a fresh introspection call
        expect(introspection_stub).to have_been_requested
      end
    end
  end

  describe 'run' do
    let(:action_input) do
      { mutation: 'requestCreate', input: { 'subject' => 'Test request', 'category' => 'incident' } }
    end

    it 'executes a mutation and returns the result' do
      stub_graphql_query(/requestCreate/, {
        'requestCreate' => {
          'request' => {
            'id' => 'req-123',
            'name' => 'Test request',
            'primaryEmail' => nil,
            'disabled' => false,
            'organization' => nil,
          },
          'errors' => [],
        },
      })

      output = run_action(action_input)

      expect(output).to be_present
      expect(output[:request_id]).to eq('req-test-123')
    end

    it 'fails when mutation returns errors' do
      stub_graphql_query(/requestCreate/, {
        'requestCreate' => {
          'request' => nil,
          'errors' => [
            { 'message' => 'Subject is required', 'path' => %w[input subject] },
            { 'message' => 'Invalid category', 'path' => %w[input category] },
          ],
        },
      })

      expect { run_action(action_input) }.to raise_error(
        IPaaS::Job::FailJob,
        /Subject is required; Invalid category/,
      )
    end

    it 'fails when mutation returns no data' do
      stub_graphql_query(/requestCreate/, { 'requestCreate' => nil })

      expect { run_action(action_input) }.to raise_error(IPaaS::Job::FailJob, /No data returned/)
    end

    it 'resolves the correct input type name from introspection' do
      query_stub = stub_request(:post, graphql_endpoint)
                   .with do |req|
                     body = req.body
                     !body.include?('__schema') &&
                       body.include?('RequestCreateInput')
                   end
        .to_return(
          status: 200,
          body: {
            data: {
              'requestCreate' => { 'request' => { 'id' => 'r1' }, 'errors' => [] },
            },
          }.to_json,
          headers: graphql_response_headers,
        )

      run_action(action_input)
      expect(query_stub).to have_been_requested
    end
  end

  describe 'error handling' do
    let(:action_input) do
      { mutation: 'requestCreate', input: { 'subject' => 'Test' } }
    end

    include GraphqlErrorHandlingSpecs
  end
end
