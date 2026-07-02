require 'spec_helper'
require 'digest'

describe 'Xurrent Artifact Cache', :action do
  include XurrentIntrospectionHelper

  let(:action_template_id) { '019ce240-76c9-75d1-beac-8c07b2325e76' } # Xurrent Query
  let(:outbound_connection_config) { xurrent_outbound_connection_config }
  let(:graphql_endpoint) { xurrent_graphql_endpoint }
  let(:action_input) { { object: 'people', page_size: 25 } }
  let(:people_response) do
    { 'people' => { 'totalCount' => 0, 'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil }, 'nodes' => [] } }
  end

  # Warms the connection's bundle the way production does: a cold run that introspects
  # once and writes the 'in'/'out' bundles and root options under the current generation.
  def warm_the_bundle
    stub_introspection
    stub_graphql_query(/people/, people_response)
    run_action(action_input, schema_reference: 'query_result')
  end

  describe 'warm path' do
    it 'builds and runs from the bundle without introspecting or reading the schema' do
      warm_the_bundle

      # Drop the schema entirely; only the small derived bundle remains.
      outbound_connection.cache_clear('gql_schema')
      WebMock.reset!
      stub_graphql_query(/people/, people_response) # no introspection stub on purpose

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
      stub_graphql_query(/people/, people_response)

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
  end

  describe 'shape-incompatible bundle' do
    # The 'in' key for object 'people' with no include_fields under the current generation.
    def in_bundle_key
      gen = outbound_connection.cache_read('gql_bundle_gen')
      digest = Digest::SHA256.hexdigest(['query', 'people', '{}'].join("\n"))
      "gql_bundle_in_#{gen}_#{digest}"
    end

    it 'is ignored so the build rebuilds from the schema instead of reading an incompatible shape' do
      warm_the_bundle

      # Replace the 'in' entry with one missing required keys (as an older connector
      # that shaped bundles differently would have left), and remove the schema so a
      # rebuild must re-introspect — proving the bad entry was not used.
      outbound_connection.cache_write(in_bundle_key, { 'is_connection' => true }, 3600)
      outbound_connection.cache_clear('gql_schema')
      WebMock.reset!
      introspection_stub = stub_introspection
      stub_graphql_query(/people/, people_response)

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
        { 'is_connection' => true, 'field_selection' => 'id', 'input_fields' => [{}] }, 3600
      )
      outbound_connection.cache_clear('gql_schema')
      WebMock.reset!
      introspection_stub = stub_introspection
      stub_graphql_query(/people/, people_response)

      output = run_action(action_input, schema_reference: 'query_result')

      expect(introspection_stub).to have_been_requested # rebuilt rather than restoring a malformed descriptor
      expect(output[:total_count]).to eq(0)
    end
  end

  describe 'warm restore reproduces field defaults' do
    def parse_query(runbook)
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

    # [path, default] for every boolean field, so cold and warm builds can be compared
    # exactly: include_fields booleans default to false; any other boolean field must
    # stay defaultless (nil) rather than be flipped to false by the restore.
    def boolean_defaults(schema, prefix = '')
      schema.fields.flat_map do |f|
        path = "#{prefix}#{f.id}"
        rows = f.type == :boolean ? [[path, f.default]] : []
        rows + (f.fields.is_a?(Array) ? boolean_defaults(f, "#{path}.") : [])
      end
    end

    it 'reproduces boolean defaults on the warm path without inventing new ones' do
      stub_introspection
      stub_graphql_query(/people/, people_response)
      runbook = IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7)
      cold = boolean_defaults(parse_query(runbook).input_schema)
      skip 'fixture schema exposes no boolean input fields' if cold.empty?
      # Cold mix: include_fields booleans default false, while a plain Boolean input field
      # has no default (nil). The warm restore must preserve both — not flip nil to false.
      expect(cold.map(&:last)).to include(false, nil)

      outbound_connection.cache_clear('gql_schema')
      WebMock.reset! # warm build: no introspection available

      warm = boolean_defaults(parse_query(runbook).input_schema)

      expect(introspection_request_count).to eq(0)
      expect(warm).to eq(cold) # every boolean default survived the bundle round-trip
    end
  end

  describe 'stale _schema_present marker from a prior connector version' do
    it 'is ignored so a missing schema still re-introspects rather than returning nil' do
      warm_the_bundle

      # Simulate a pre-upgrade leftover: schema payload and bundle generation gone (so the
      # cold path runs, not the warm bundle), the old marker remains. It must re-introspect.
      outbound_connection.cache_clear('gql_schema')
      outbound_connection.cache_clear('gql_bundle_gen')
      outbound_connection.cache_write('_schema_present', true, 3600)
      WebMock.reset!
      introspection_stub = stub_introspection
      stub_graphql_query(/people/, people_response)

      output = run_action(action_input, schema_reference: 'query_result')

      expect(introspection_stub).to have_been_requested # re-introspected; the stale marker did not short-circuit
      expect(output[:total_count]).to eq(0)
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

      expect(field.enumeration.map { |e| e[:id] }).to include('people')
      expect(introspection_request_count).to eq(0)
    end
  end

  describe 'selector enumeration with no selection and a lapsed schema' do
    # gql_schema expires after 1h while the root options survive for the bundle TTL (1 week).
    # A build with no object selected must populate the dropdown from the surviving root
    # options rather than serve it empty or re-introspect.
    it 'populates the object enumeration from the root options when the schema has expired' do
      warm_the_bundle # warms root options + bundle + generation for 'people'

      outbound_connection.cache_clear('gql_schema')
      WebMock.reset! # no introspection stub: the dropdown must come from the root options

      field = action({}).input_schema.field(:object)

      expect(introspection_request_count).to eq(0)
      expect(field.enumeration.map { |e| e[:id] }).to include('people')
    end
  end

  describe 'recovery after a degraded parse' do
    # A cold worker can parse while introspection is down: the input schema degrades to the
    # static fields only. When run later introspects successfully it must persist a COMPLETE
    # bundle, so a subsequent warm build is not stuck with the degraded parse-time schema.
    def parse_query_action(runbook)
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
      degraded = parse_query_action(runbook)
      expect(degraded.input_schema.field(:view)).to be_nil # degraded precondition: no dynamic fields

      # Recovery: a sibling action warms the shared schema (as in production), so the run
      # regenerates the schemas against it and warms a complete bundle.
      WebMock.reset!
      degraded.outbound_connection.cache_write('gql_schema', introspection_schema, 3600)
      stub_graphql_query(/people/, people_response)
      degraded.run

      # Drop the shared schema so the warm build's ONLY possible source for view/filter is the
      # persisted bundle, proving the run wrote a COMPLETE bundle (built from the recovered
      # schema), not the degraded parse-time one.
      WebMock.reset!
      degraded.outbound_connection.cache_clear('gql_schema')
      warm = parse_query_action(runbook)

      expect(introspection_request_count).to eq(0)
      expect(warm.input_schema.field(:view)).to be_present
      expect(warm.input_schema.field(:filter)).to be_present
    end
  end

  describe 'mutation warm path' do
    let(:action_template_id) { '019ce240-76c9-7847-9dfa-a48d104515b3' } # Xurrent Mutation
    let(:action_input) { { mutation: 'requestCreate', input: { 'subject' => 'Test' } } }
    let(:mutation_response) { { 'requestCreate' => { 'request' => { 'id' => 'r1' }, 'errors' => [] } } }

    # Warms the connection's mutation bundle the way production does: a cold run that
    # introspects once and writes the 'in'/'out' bundles and root options. Mutations run
    # in execution mode (the :input field resolves to :nested there, not :hash), so warm
    # and run share that mode and therefore the same bundle shape.
    def warm_the_mutation_bundle
      stub_introspection
      stub_graphql_query(/requestCreate/, mutation_response)
      runbook.in_execution_mode { run_action(action_input) }
    end

    it 'builds and runs from the bundle without introspecting or reading the schema' do
      warm_the_mutation_bundle

      # Drop the schema entirely; only the small derived bundle remains.
      outbound_connection.cache_clear('gql_schema')
      WebMock.reset!
      stub_graphql_query(/requestCreate/, mutation_response) # no introspection stub on purpose

      # In execution mode the run returns the mapped output directly (no schema_reference),
      # so take the single result's output rather than filtering by reference.
      output = runbook.in_execution_mode { run_action(action_input) }

      expect(introspection_request_count).to eq(0)
      expect(outbound_connection.cache_read('gql_schema')).to be_nil # never re-fetched
      expect(output).to include('request' => { 'id' => 'r1' }) # ran correctly from the bundle
    end
  end

  describe 'mutation recovery after a degraded parse' do
    let(:action_template_id) { '019ce240-76c9-7847-9dfa-a48d104515b3' } # Xurrent Mutation
    let(:action_input) { { mutation: 'requestCreate', input: { 'subject' => 'Test' } } }

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

      WebMock.reset!
      degraded.outbound_connection.cache_write('gql_schema', introspection_schema, 3600)
      stub_graphql_query(/requestCreate/, { 'requestCreate' => { 'request' => { 'id' => 'r1' }, 'errors' => [] } })
      degraded.run

      # Drop the schema so the warm build's only source for the typed input is the bundle.
      WebMock.reset!
      degraded.outbound_connection.cache_clear('gql_schema')
      warm = parse_mutation_action(runbook)

      input_field = warm.input_schema.field(:input)
      expect(introspection_request_count).to eq(0)
      expect(input_field.type).to eq(:nested)
      expect(input_field.fields.map(&:id)).to include(:subject)
    end
  end
end
