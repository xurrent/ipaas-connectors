require 'spec_helper'

describe 'GraphQL Artifact Cache', :action do
  include GraphqlIntrospectionHelper

  let(:connector_id) { 'd5bbb2a2-4a95-4b49-b490-56711e4455f8' }
  let(:action_template_id) { 'eb80d943-e0a3-44c7-97aa-640e243f9320' } # GraphQL Query
  let(:outbound_connection_config) { graphql_connector_outbound_connection_config }
  let(:graphql_endpoint) { graphql_connector_endpoint }
  let(:action_input) { { object: 'users' } }
  let(:bundle_ttl) { IPaaS::Job::GraphQL::ArtifactCache::BUNDLE_TTL }
  let(:users_response) do
    { 'users' => { 'totalCount' => 0, 'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil }, 'nodes' => [] } }
  end

  def introspection_request_count
    WebMock::RequestRegistry.instance.requested_signatures.hash
                            .select { |signature, _count| signature.body.to_s.include?('__schema') }
                            .values.sum
  end

  # Warms the connection's bundle the way production does: a cold run that introspects
  # once and writes the 'in'/'out' bundles and root options under the current generation.
  def warm_the_bundle
    stub_graphql_connector_introspection
    stub_graphql_connector_query(/users/, users_response)
    run_action(action_input, schema_reference: 'query_result')
  end

  describe 'warm path' do
    it 'builds and runs from the bundle without introspecting or reading the schema' do
      warm_the_bundle

      # Drop the schema entirely; only the small derived bundle remains.
      outbound_connection.cache_clear('gql_schema')
      WebMock.reset!
      stub_graphql_connector_query(/users/, users_response) # no introspection stub on purpose

      output = run_action(action_input, schema_reference: 'query_result')

      expect(introspection_request_count).to eq(0)
      expect(outbound_connection.cache_read('gql_schema')).to be_nil # never re-fetched
      expect(output[:total_count]).to eq(0) # ran correctly from the bundle
    end

    it 'does not consult the introspection failure cache on the warm path' do
      warm_the_bundle

      outbound_connection.cache_clear('gql_schema')
      WebMock.reset!
      # Introspection would 500 if attempted; only the data query is stubbed. The warm
      # path must run from the bundle and never reach introspection or its failure cache.
      stub_request(:post, graphql_endpoint).with { |req| req.body.include?('__schema') }.to_return(status: 500)
      stub_graphql_connector_query(/users/, users_response)

      # Record every cache key the run reads, to assert directly that the negative-cache
      # key (read only on the cold introspection path) is never consulted on the warm path.
      read_keys = []
      allow(outbound_connection).to receive(:cache_read).and_wrap_original do |orig, key|
        read_keys << key
        orig.call(key)
      end

      output = run_action(action_input, schema_reference: 'query_result')

      expect(read_keys).to include(a_string_starting_with('gql_bundle_')) # spy is wired to the run's store
      expect(read_keys).not_to include(a_string_starting_with('introspection_failure_'))
      expect(introspection_request_count).to eq(0)
      expect(output[:total_count]).to eq(0)
    end

    it 'restores the input schema from the bundle without introspecting' do
      warm_the_bundle

      outbound_connection.cache_clear('gql_schema')
      WebMock.reset! # no introspection available: the input fields must come from the bundle

      schema = action(action_input).input_schema

      expect(introspection_request_count).to eq(0)
      expect(schema.field(:object).enumeration.map { |e| e[:id] }).to include('users')
      expect(schema.field(:status)).to be_present # the dynamic arg restored from the bundle
    end

    it 'restores the output schema from the bundle without introspecting' do
      warm_the_bundle

      outbound_connection.cache_clear('gql_schema')
      WebMock.reset!

      output_schema = action(action_input).output_schema('query_result')

      expect(introspection_request_count).to eq(0)
      expect(output_schema.field(:total_count)).to be_present # restored from the 'out' bundle
      expect(output_schema.field(:nodes)).to be_present
    end
  end

  describe 'shape-incompatible bundle' do
    # The 'in' key for object 'users' with no include_fields under the current generation,
    # computed by the production method so the spec never drifts from the real key formula.
    def in_bundle_key
      gen = outbound_connection.cache_read('gql_bundle_gen')
      IPaaS::Job::GraphQL::ArtifactCache.gql_bundle_cache_key(:query, 'in', 'users', {}, gen)
    end

    it 'is ignored so the build rebuilds from the schema instead of reading an incompatible shape' do
      warm_the_bundle

      # Replace the 'in' entry with one missing required keys (as an older connector
      # that shaped bundles differently would have left), and remove the schema so a
      # rebuild must re-introspect — proving the bad entry was not used.
      outbound_connection.cache_write(in_bundle_key, { 'is_connection' => true }, bundle_ttl)
      outbound_connection.cache_clear('gql_schema')
      WebMock.reset!
      introspection_stub = stub_graphql_connector_introspection
      stub_graphql_connector_query(/users/, users_response)

      output = run_action(action_input, schema_reference: 'query_result')

      expect(introspection_stub).to have_been_requested # rebuilt rather than using the bad bundle
      expect(output[:total_count]).to eq(0)
    end

    it 'is ignored when a descriptor is malformed so restore never raises mid-build' do
      warm_the_bundle

      # All required keys present, but a descriptor lacks the id/label/type restore
      # dereferences — the kind of value a cross-version shape change can leave. The
      # build must fail closed and rebuild from the schema rather than raise on restore.
      outbound_connection.cache_write(
        in_bundle_key,
        { 'is_connection' => true, 'field_selection' => 'id', 'arg_type_refs' => {}, 'input_fields' => [{}] },
        bundle_ttl
      )
      outbound_connection.cache_clear('gql_schema')
      WebMock.reset!
      introspection_stub = stub_graphql_connector_introspection
      stub_graphql_connector_query(/users/, users_response)

      output = run_action(action_input, schema_reference: 'query_result')

      expect(introspection_stub).to have_been_requested # rebuilt rather than restoring a malformed descriptor
      expect(output[:total_count]).to eq(0)
    end

    it 'is ignored when is_list is missing so a simple-query bundle cannot skip list flattening' do
      warm_the_bundle

      # Every other required key present but no is_list — run reads is_list to decide list
      # flattening for simple (non-connection) queries, so a bundle missing it must fail
      # closed and rebuild from the schema rather than silently diverge from the cold path.
      outbound_connection.cache_write(
        in_bundle_key,
        { 'is_connection' => false, 'field_selection' => 'id', 'arg_type_refs' => {}, 'input_fields' => [] },
        bundle_ttl
      )
      outbound_connection.cache_clear('gql_schema')
      WebMock.reset!
      introspection_stub = stub_graphql_connector_introspection
      stub_graphql_connector_query(/users/, users_response)

      output = run_action(action_input, schema_reference: 'query_result')

      expect(introspection_stub).to have_been_requested # rebuilt rather than using the is_list-less bundle
      expect(output[:total_count]).to eq(0)
    end
  end

  describe 'refresh schema bumps the generation' do
    def parse_query(runbook, input)
      IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: SecureRandom.uuid,
          outbound_connection: { uuid: outbound_connection.uuid },
          action_template: { uuid: action_template_id },
          input_mapping: field_mapping(input, schema: action_template.input_schema),
        },
      )
    end

    it 'orphans the prior bundles so a refresh re-introspects and writes a fresh generation' do
      warm_the_bundle
      gen_before = outbound_connection.cache_read('gql_bundle_gen')

      # A refresh-schema build clears the schema, bumps the generation, and re-introspects.
      WebMock.reset!
      refresh_stub = stub_graphql_connector_introspection
      runbook = IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
      parse_query(runbook, action_input.merge(refresh_schema: true)).input_schema

      expect(refresh_stub).to have_been_requested # the bump orphaned the warm bundle
      expect(outbound_connection.cache_read('gql_bundle_gen')).to eq(gen_before + 1)
    end
  end

  describe 'root options eviction' do
    it 'rebuilds the selector enumeration from the schema rather than serving it empty' do
      warm_the_bundle

      # Evict the root-field options but keep the bundle, generation, and schema: the
      # build must not serve an empty selector — it fails closed on the missing options
      # and rebuilds the enumeration from the still-cached schema, without introspecting.
      gen = outbound_connection.cache_read('gql_bundle_gen')
      outbound_connection.cache_clear("gql_root_fields_query_#{gen}")
      WebMock.reset! # no introspection stub: the schema is still cached

      field = action(action_input).input_schema.field(:object)

      expect(field.enumeration.map { |e| e[:id] }).to include('users')
      expect(introspection_request_count).to eq(0)
    end
  end

  describe 'mutation warm path' do
    let(:action_template_id) { 'f7d7f36f-4746-460a-ba28-30f817be3698' } # GraphQL Mutation
    let(:action_input) { { mutation: 'createPost', input: { 'title' => 'Test' } } }
    let(:mutation_response) { { 'createPost' => { 'post' => { 'id' => 'p1' }, 'errors' => [] } } }

    # Warms the connection's mutation bundle the way production does. Mutations run in
    # execution mode (the :input field resolves to :nested there, not :hash), so warm and
    # run share that mode and therefore the same bundle shape.
    def warm_the_mutation_bundle
      stub_graphql_connector_introspection
      stub_graphql_connector_query(/createPost/, mutation_response)
      runbook.in_execution_mode { run_action(action_input) }
    end

    it 'builds and runs from the bundle without introspecting or reading the schema' do
      warm_the_mutation_bundle

      # Drop the schema entirely; only the small derived bundle remains.
      outbound_connection.cache_clear('gql_schema')
      WebMock.reset!
      stub_graphql_connector_query(/createPost/, mutation_response) # no introspection stub on purpose

      # In execution mode the run returns the mapped output directly (no schema_reference),
      # so take the single result's output rather than filtering by reference.
      output = runbook.in_execution_mode { run_action(action_input) }

      expect(introspection_request_count).to eq(0)
      expect(outbound_connection.cache_read('gql_schema')).to be_nil # never re-fetched
      expect(output).to include('post' => { 'id' => 'p1' }) # ran correctly from the bundle
    end
  end

  describe 'mutation recovery after a degraded parse' do
    let(:action_template_id) { 'f7d7f36f-4746-460a-ba28-30f817be3698' } # GraphQL Mutation
    let(:action_input) { { mutation: 'createPost', input: { 'title' => 'Test' } } }

    def parse_mutation_action(runbook)
      IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: SecureRandom.uuid,
          outbound_connection: { uuid: outbound_connection.uuid },
          action_template: { uuid: action_template_id },
          input_mapping: field_mapping(action_input, schema: action_template.input_schema),
        },
      )
    end

    it 'persists a complete input bundle so a later warm build is not degraded' do
      WebMock.reset!
      stub_request(:post, graphql_endpoint).with { |req| req.body.include?('__schema') }.to_return(status: 500)
      runbook = IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
      degraded = parse_mutation_action(runbook)
      expect(degraded.input_schema.field(:input).type).to eq(:hash) # degraded precondition: bare hash

      # Recovery: a sibling action warms the shared schema (as in production), so the run
      # regenerates the schemas against it and warms a complete bundle.
      WebMock.reset!
      degraded.outbound_connection.cache_write('gql_schema', graphql_connector_introspection_schema, 3600)
      stub_graphql_connector_query(/createPost/, { 'createPost' => { 'post' => { 'id' => 'p1' }, 'errors' => [] } })
      degraded.run

      # Drop the schema so the warm build's only source for the typed input is the bundle.
      WebMock.reset!
      degraded.outbound_connection.cache_clear('gql_schema')
      warm = parse_mutation_action(runbook)

      input_field = warm.input_schema.field(:input)
      expect(introspection_request_count).to eq(0)
      expect(input_field.type).to eq(:nested)
      expect(input_field.fields.map(&:id)).to include(:title)
    end
  end
end
