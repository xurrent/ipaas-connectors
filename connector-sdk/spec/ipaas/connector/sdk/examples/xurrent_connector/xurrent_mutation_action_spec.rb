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

  # Regression for request #78064178 (see SchemaClosureHelper).
  describe 'memory: after_update closure does not retain the parsed schema' do
    before(:each) { action.outbound_connection.cache_write('gql_schema', introspection_schema, 3600) }

    it 'releases schema_data so the cached after_update proc does not pin the parsed schema' do
      schema = action.input_schema
      expect(schema.field(:mutation).enumeration).to be_present # non-vacuous: schema was available
      expect_after_update_not_to_retain_schema(schema)
    end
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
        expect(field.notice).to eq('Outbound Connection is not configured correctly.')
        expect(field.notice_type).to eq('error')
        expect(field.notice_action).to eq('edit_connection')
      end
    end

    context 'with cached schema' do
      before(:each) do
        action.outbound_connection.cache_write('gql_schema', introspection_schema, 3600)
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

  # Regression for request #78631360. A scheduled runbook's Mutation action whose
  # input is mapped as nested sub-fields fails its pre-execution validation with
  # "Field 'input' is required" when the GraphQL schema was unavailable at the
  # moment the action was parsed (a cold worker re-parse racing an expired/failed
  # introspection): input degrades to a bare :hash and is frozen on the memoized
  # @input, and the pre-execution valid? gate never re-resolves it. The fix makes
  # the gate re-resolve dynamic schemas in execution mode, so it validates what
  # run actually uses. This proves the action then RUNS and SUCCEEDS end-to-end.
  describe 'execution-mode recovery when schema was unavailable at parse (req #78631360)' do
    def nested_mutation_def(nested_input_fields)
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

    def parse_nested_mutation(runbook, nested_input_fields)
      IPaaS::Connector::Action.parse(runbook, nested_mutation_def(nested_input_fields))
    end

    it 'validates and runs successfully after the cache is warmed, though parse saw no schema' do
      # 1. Parse while introspection is DOWN -> input degrades to a bare :hash,
      #    frozen on the memoized @input.
      WebMock.reset!
      stub_request(:post, graphql_endpoint)
        .with { |req| req.body.include?('__schema') }
        .to_return(status: 500, body: 'introspection unavailable')
      rb = IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
      a = parse_nested_mutation(rb, [
        { field_id: :subject, fixed: 'Test request' },
        { field_id: :category, fixed: 'incident' },
      ])
      expect(a.input_schema.field(:input).type).to eq(:hash) # degraded precondition

      # 2. The sibling Query warms gql_schema; introspection is healthy again and
      #    the mutation POST is stubbed, capturing what input reaches Xurrent.
      WebMock.reset!
      stub_introspection
      a.outbound_connection.cache_write('gql_schema', introspection_schema, 3600)
      received_input = nil
      stub_request(:post, graphql_endpoint)
        .with do |req|
          next false if req.body.include?('__schema')

          received_input = JSON.parse(req.body).dig('variables', 'input')
          req.body.include?('requestCreate')
        end
        .to_return(
          status: 200,
          body: { data: { 'requestCreate' => { 'request' => { 'id' => 'r1' }, 'errors' => [] } } }.to_json,
          headers: graphql_response_headers,
        )

      # 3. Drive the real execution path: the gate (valid?) then run.
      rb.in_execution_mode do
        expect(a).to be_valid # gate re-resolves -> :nested -> passes (was frozen :hash before the fix)
        results = a.run
        expect(results).to be_present
      end

      # 4. The nested sub-fields actually reached Xurrent (not an empty input).
      expect(received_input).to include('subject' => 'Test request', 'category' => 'incident')
    end

    it 'does NOT re-resolve in designer mode — uses memoized input without network calls' do
      # Parse while introspection is DOWN.
      WebMock.reset!
      stub_request(:post, graphql_endpoint)
        .with { |req| req.body.include?('__schema') }
        .to_return(status: 500, body: 'introspection unavailable')
      rb = IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
      a = parse_nested_mutation(rb, [
        { field_id: :subject, fixed: 'Test request' },
        { field_id: :category, fixed: 'incident' },
      ])
      expect(a.input_schema.field(:input).type).to eq(:hash) # degraded

      # Keep the cache empty. In designer mode the validation gate must use
      # the memoized @input (resolve: false) and NOT trigger introspection.
      WebMock.reset!
      introspection_stub = stub_request(:post, graphql_endpoint)
                           .with { |req| req.body.include?('__schema') }
                           .to_return(status: 200,
                                      body: { data: { __schema: introspection_schema } }.to_json,
                                      headers: graphql_response_headers)

      expect(rb).to be_designer_mode
      a.valid? # should NOT trigger an introspection call
      expect(introspection_stub).not_to have_been_requested
    end

    it 'still fails validation when introspection is down at both parse AND execution time' do
      # Parse while introspection is DOWN.
      WebMock.reset!
      stub_request(:post, graphql_endpoint)
        .with { |req| req.body.include?('__schema') }
        .to_return(status: 500, body: 'introspection unavailable')
      rb = IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
      a = parse_nested_mutation(rb, [
        { field_id: :subject, fixed: 'Test request' },
        { field_id: :category, fixed: 'incident' },
      ])
      expect(a.input_schema.field(:input).type).to eq(:hash) # degraded

      # Do NOT warm the cache — introspection stays broken.
      # In execution mode, re-resolve still gets the degraded schema.
      rb.in_execution_mode do
        expect(a).not_to be_valid
        expect(a.errors[:input_mapping]).to be_present
      end
    end

    it 'mirrors the job.process_action flow: valid? gates run inside in_execution_mode' do
      # Parse with introspection DOWN.
      WebMock.reset!
      stub_request(:post, graphql_endpoint)
        .with { |req| req.body.include?('__schema') }
        .to_return(status: 500, body: 'introspection unavailable')
      rb = IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
      a = parse_nested_mutation(rb, [
        { field_id: :subject, fixed: 'Test request' },
        { field_id: :category, fixed: 'incident' },
      ])

      # Warm the cache (as a sibling Query would in production).
      WebMock.reset!
      stub_introspection
      a.outbound_connection.cache_write('gql_schema', introspection_schema, 3600)
      stub_request(:post, graphql_endpoint)
        .with { |req| !req.body.include?('__schema') && req.body.include?('requestCreate') }
        .to_return(
          status: 200,
          body: { data: { 'requestCreate' => { 'request' => { 'id' => 'r1' }, 'errors' => [] } } }.to_json,
          headers: graphql_response_headers,
        )

      # Reproduce the exact job.process_action path:
      #   action_runner wraps in in_execution_mode, then job calls:
      #     if action.valid? → action.run(output_proc)
      rb.in_execution_mode do
        raise "Expected action to be valid, got: #{a.full_error_messages}" unless a.valid?

        results = a.run
        expect(results).to be_present
        expect(results.first[:output]).to include('request' => { 'id' => 'r1' })
      end
    end
  end

  # The execution-mode gate re-resolved on every call, re-introspecting the multi-MB
  # Xurrent GraphQL schema even when the memoized input was already valid.
  # The gate now trusts a valid memo and only re-resolves when it is invalid, so the healthy path
  # performs no introspection while the recovery path is unchanged.
  describe 'gate skips re-resolution when the memoized input is valid' do
    def parse_mutation(runbook, input_mapping)
      definition = {
        reference: SecureRandom.uuid,
        outbound_connection: { uuid: outbound_connection.uuid },
        action_template: { uuid: action_template_id },
        input_mapping: input_mapping,
      }
      IPaaS::Connector::Action.parse(runbook, definition)
    end

    let(:mapping_with_input) do
      [
        { field_id: :mutation, fixed: 'requestCreate' },
        { field_id: :input,
          nested: [{ field_id: :subject, fixed: 'Test request' }, { field_id: :category, fixed: 'incident' }], },
      ]
    end

    let(:mapping_without_input) { [{ field_id: :mutation, fixed: 'requestCreate' }] }

    # A failing introspection stub: a gate that re-resolves hits the network here,
    # while a gate that trusts a valid memo never does.
    def stub_failing_introspection
      stub_request(:post, graphql_endpoint)
        .with { |req| req.body.include?('__schema') }
        .to_return(status: 500, body: 'introspection unavailable')
    end

    it 'stays valid in execution mode without re-introspecting when the memo is valid' do
      # Parse with a healthy schema: input resolves to :nested and a valid memo
      # is frozen on @input.
      rb = IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
      a = parse_mutation(rb, mapping_with_input)
      expect(a.input_schema.field(:input).type).to eq(:nested) # schema resolved healthy
      expect(a.input).to be_valid # precondition: the memo the gate trusts is valid

      a.outbound_connection.cache_clear('gql_schema')
      WebMock.reset!
      introspection_stub = stub_failing_introspection

      rb.in_execution_mode { expect(a).to be_valid }

      expect(introspection_stub).not_to have_been_requested
    end

    it 're-introspects in execution mode when the memo is invalid (contrast)' do
      # Same healthy parse, but the required :input is unmapped, so the resolved
      # memo is invalid ("Field 'input' is required"). The 200 parse leaves no
      # cached introspection failure to short-circuit the re-resolution.
      rb = IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
      a = parse_mutation(rb, mapping_without_input)
      expect(a.input).not_to be_valid # precondition: the memo is invalid

      a.outbound_connection.cache_clear('gql_schema')
      # Clear the generation token so the invalid-memo re-resolution takes the cold
      # path (a warm bundle would let the gate re-resolve without introspecting).
      a.outbound_connection.cache_clear('gql_bundle_gen')
      WebMock.reset!
      introspection_stub = stub_failing_introspection

      rb.in_execution_mode do
        expect(a).not_to be_valid
        expect(a.errors[:input_mapping]).to be_present # the gate rejected it, not some other validator
      end

      expect(introspection_stub).to have_been_requested
    end

    it 'reads the memo without re-resolving when it is already valid' do
      # Trusting a valid memo means the gate must not route through #input — doing
      # so (e.g. `input.valid?`, or an unconditional `input(resolve: true)`) would
      # re-resolve and re-introspect, the redundant work this change removes.
      rb = IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
      a = parse_mutation(rb, mapping_with_input)
      expect(a.input).to be_valid # precondition: the memo is valid

      allow(a).to receive(:input).and_call_original

      rb.in_execution_mode { expect(a).to be_valid }

      expect(a).not_to have_received(:input) # no second resolution
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
      @mutation_action.outbound_connection.cache_clear('gql_schema')
      # Clear the generation token too: without it the warm bundle would serve the
      # build and run without introspecting, so a truly empty cache has no generation.
      @mutation_action.outbound_connection.cache_clear('gql_bundle_gen')

      introspection_stub = stub_introspection
      @mutation_action.run

      # run triggers a fresh introspection because the derived caches were cleared
      expect(introspection_stub).to have_been_requested

      expect(@mutation_action.outbound_connection.cache_read('gql_schema')).to be_present
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

    # Lock the mapping of JSON to any on both the input and output sides.
    context 'setting a custom field to a non-hash JSON value' do
      let(:written_custom_fields) do
        [
          { 'id' => 'is_boolean', 'value' => false },
          { 'id' => 'affected_teams', 'value' => %w[support security ops] },
          { 'id' => 'my_string', 'value' => 'xyz' },
          { 'id' => 'my_number', 'value' => 2 },
        ]
      end
      let(:read_custom_fields) do
        [
          { 'id' => 'is_boolean', 'value' => true },
          { 'id' => 'my_string', 'value' => 'abc' },
          { 'id' => 'affected_teams', 'value' => %w[network security] },
          { 'id' => 'my_number', 'value' => 1 },
          { 'id' => 'another_boolean', 'value' => false },
        ]
      end
      let(:action_input) do
        {
          mutation: 'requestCreate',
          input: {
            'subject' => 'Laptop request',
            'customFields' => written_custom_fields,
          },
          # Select the nested customFields on the returned record so it is both
          # queried from Xurrent and declared in the generated output schema.
          include_fields: { request: true, request_fields: { customFields: true } },
        }
      end

      it 'sends the value to Xurrent and surfaces the echoed values in the output' do
        received_input = nil
        request_stub = stub_request(:post, graphql_endpoint)
                       .with do |req|
                         body = JSON.parse(req.body)
                         next false if body['query'].include?('__schema')

                         received_input = body.dig('variables', 'input')
                         body['query'].include?('requestCreate')
                       end
          .to_return(
            status: 200,
            body: {
              data: {
                'requestCreate' => {
                  'request' => {
                    'id' => 'req-9001',
                    'subject' => 'Laptop request',
                    'customFields' => read_custom_fields,
                  },
                  'errors' => [],
                },
              },
            }.to_json,
            headers: graphql_response_headers,
          )

        output = run_action(action_input)

        expect(request_stub).to have_been_requested
        expect(received_input['customFields']).to eq(written_custom_fields)

        expect(output[:request]['id']).to eq('req-9001')
        expect(output[:request]['customFields']).to eq(read_custom_fields)
      end
    end

    # Mutation payload objects can contain connection fields whose { nodes: [...] }
    # layer the generated schema does not declare; it must be flattened to the
    # array before output validation strips it.
    context 'payload object with a nested connection (personUpdate)' do
      let(:action_input) do
        { mutation: 'personUpdate', input: { 'id' => 'p1', 'name' => 'Jane' },
          include_fields: { person: true, person_fields: { skills: true } }, }
      end

      before(:each) do
        stub_graphql_query(/personUpdate/, {
          'personUpdate' => {
            'person' => {
              'id' => 'p1', 'name' => 'Jane',
              'undeclaredField' => 'stripped by output validation',
              'skills' => { 'nodes' => [{ 'id' => 's1', 'name' => 'Ruby' }] },
            },
            'errors' => [],
          },
        })
      end

      # Full code path: dynamic output schema generation, response JSON,
      # parsing by run, and validation on the resolved mapping.
      it 'flattens the nested connection in the payload object to an array of records' do
        output = run_action(action_input)

        # the undeclared field is stripped, proving the payload passed output
        # validation — the skills array below survives that same validation
        expect(output[:person]).not_to have_key('undeclaredField')
        # the sibling field proves only the connection is rewritten, not the record
        expect(output[:person]['name']).to eq('Jane')
        expect(output[:person]['skills']).to be_an(Array)
        expect(output[:person]['skills'].map { |s| s['name'] }).to eq(['Ruby'])
      end

      # The generated output schema declares the connection as an array of the
      # node type without the intermediate nodes layer — the reason the
      # response data must be flattened before validation.
      it 'declares the nested connection as an array of records without a nodes layer' do
        person_field = action.output_schemas.first.fields.detect { |f| f.id == :person }
        skills_field = person_field.fields.detect { |f| f.id == :skills }

        expect(skills_field.array).to be_truthy
        expect(skills_field.fields.map(&:id)).to contain_exactly(:id, :name)
      end

      context 'when the nested connection is not included' do
        let(:action_input) do
          { mutation: 'personUpdate', input: { 'id' => 'p1', 'name' => 'Jane' } }
        end

        # Contrast: the response stub still contains skills, but without
        # include_fields the schema does not declare it, so it is stripped.
        it 'omits the nested connection from the payload object' do
          output = run_action(action_input)

          expect(output[:person]['name']).to eq('Jane')
          expect(output[:person]).not_to have_key('skills')
        end
      end
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
