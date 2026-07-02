require 'spec_helper'

describe IPaaS::Job::GraphQL::ArtifactCache do
  # In-memory store mimicking the connection cache: writes serialize to JSON and reads
  # parse it back, so stored symbol keys surface as strings exactly like the real cache.
  class FakeStore
    attr_reader :ttls

    def initialize
      @store = {}
      @ttls = {}
    end

    def cache_read(key)
      raw = @store[key]
      raw.nil? ? nil : JSON.parse(raw)
    end

    def cache_write(key, value, ttl)
      @store[key] = JSON.generate(value)
      @ttls[key] = ttl
      value
    end

    def cache_clear(key)
      @store.delete(key)
      @ttls.delete(key)
    end
  end

  subject(:cache) { described_class }

  let(:store) { FakeStore.new }
  let(:keys_in) { %w[is_connection field_selection input_fields] }
  let(:keys_out) { %w[output_fields] }

  def valid_in_bundle(extra = {})
    { 'is_connection' => false, 'field_selection' => 'id name', 'input_fields' => [] }.merge(extra)
  end

  describe 'generation lifecycle' do
    it 'returns nil when no generation is established' do
      expect(cache.gql_bundle_generation(store)).to be_nil
    end

    it 'writes 1 on the first bump and increments after' do
      expect(cache.gql_bump_bundle_generation(store)).to eq(1)
      expect(cache.gql_bundle_generation(store)).to eq(1)
      expect(cache.gql_bump_bundle_generation(store)).to eq(2)
      expect(cache.gql_bundle_generation(store)).to eq(2)
    end

    it 'writes the generation under BUNDLE_TTL' do
      cache.gql_bump_bundle_generation(store)
      expect(store.ttls['gql_bundle_gen']).to eq(described_class::BUNDLE_TTL)
    end
  end

  describe 'gql_invalidate' do
    it 'clears the given keys and bumps the generation, orphaning prior derived entries' do
      store.cache_write('gql_schema', { '__schema' => {} }, 10)
      store.cache_write('introspection_failure_abc', 'boom', 10)
      cache.gql_write_root_options(store, :query, [{ id: 'people', label: 'People' }]) # establishes gen 1
      gen_before = cache.gql_bundle_generation(store)

      cache.gql_invalidate(store, 'gql_schema', 'introspection_failure_abc')

      expect(store.cache_read('gql_schema')).to be_nil
      expect(store.cache_read('introspection_failure_abc')).to be_nil
      expect(cache.gql_bundle_generation(store)).to eq(gen_before + 1)
      expect(cache.gql_read_root_options(store, :query)).to be_nil # orphaned by the bump
    end
  end

  describe 'fail-closed reads when no generation is established' do
    it 'gql_load_bundle returns nil' do
      expect(cache.gql_load_bundle(store, :query, 'in',
                                   selection_name: 'people', include_fields: {},
                                   required_keys: keys_in)).to be_nil
    end

    it 'gql_read_root_options returns nil' do
      expect(cache.gql_read_root_options(store, :query)).to be_nil
    end

    it 'gql_warm_for_regeneration? returns false' do
      expect(cache.gql_warm_for_regeneration?(store, :query,
                                              selection_present: true, selection_name: 'people',
                                              include_fields: {}, required_keys_in: keys_in,
                                              required_keys_out: keys_out)).to be(false)
    end
  end

  describe 'bundle write/read round-trip' do
    before { cache.gql_bump_bundle_generation(store) }

    it 'reads back a written bundle part for the same selection and include_fields' do
      cache.gql_write_bundle_part(store, :query, 'in',
                                  selection_name: 'people', include_fields: { team: true },
                                  bundle: valid_in_bundle)
      loaded = cache.gql_load_bundle(store, :query, 'in',
                                     selection_name: 'people', include_fields: { team: true },
                                     required_keys: keys_in)
      expect(loaded).to include('is_connection' => false, 'field_selection' => 'id name')
    end

    it 'writes the bundle under BUNDLE_TTL' do
      cache.gql_write_bundle_part(store, :query, 'in',
                                  selection_name: 'people', include_fields: {},
                                  bundle: valid_in_bundle)
      written_key = store.ttls.keys.find { |k| k.start_with?('gql_bundle_in_') }
      expect(store.ttls[written_key]).to eq(described_class::BUNDLE_TTL)
    end

    it 'does not read a bundle orphaned by a later generation bump' do
      cache.gql_write_bundle_part(store, :query, 'in',
                                  selection_name: 'people', include_fields: {},
                                  bundle: valid_in_bundle)
      cache.gql_bump_bundle_generation(store)
      expect(cache.gql_load_bundle(store, :query, 'in',
                                   selection_name: 'people', include_fields: {},
                                   required_keys: keys_in)).to be_nil
    end

    it 'does not read a bundle for a different include_fields selection' do
      cache.gql_write_bundle_part(store, :query, 'in',
                                  selection_name: 'people', include_fields: { team: true },
                                  bundle: valid_in_bundle)
      expect(cache.gql_load_bundle(store, :query, 'in',
                                   selection_name: 'people', include_fields: { team: false },
                                   required_keys: keys_in)).to be_nil
    end
  end

  describe 'digest keying' do
    it 'collapses logically-equal include_fields to one key' do
      k1 = cache.gql_bundle_cache_key(:query, 'in', 'people', { a: true, b: false }, 1)
      k2 = cache.gql_bundle_cache_key(:query, 'in', 'people', { 'b' => false, 'a' => true }, 1)
      expect(k1).to eq(k2)
    end

    it 'keeps {a: false} distinct from {} (explicit false leaf preserved)' do
      with_false = cache.gql_bundle_cache_key(:query, 'in', 'people', { a: false }, 1)
      empty = cache.gql_bundle_cache_key(:query, 'in', 'people', {}, 1)
      expect(with_false).not_to eq(empty)
    end

    it 'embeds the part and generation in the key' do
      expect(cache.gql_bundle_cache_key(:query, 'in', 'people', {}, 7)).to start_with('gql_bundle_in_7_')
    end
  end

  describe 'gql_stable_json' do
    it 'sorts hash keys regardless of insertion order or key class' do
      expect(cache.gql_stable_json({ b: 1, a: 2 })).to eq(cache.gql_stable_json({ 'a' => 2, 'b' => 1 }))
    end

    it 'keeps {a: false} distinct from {}' do
      expect(cache.gql_stable_json({ a: false })).not_to eq(cache.gql_stable_json({}))
    end
  end

  describe 'defensive shape validation' do
    before { cache.gql_bump_bundle_generation(store) }

    it 'rejects a non-hash bundle entry' do
      key = cache.gql_bundle_cache_key(:query, 'in', 'people', {}, cache.gql_bundle_generation(store))
      store.cache_write(key, [1, 2, 3], 10)
      expect(cache.gql_load_bundle(store, :query, 'in',
                                   selection_name: 'people', include_fields: {},
                                   required_keys: keys_in)).to be_nil
    end

    it 'rejects a bundle missing a required key' do
      cache.gql_write_bundle_part(store, :query, 'in',
                                  selection_name: 'people', include_fields: {},
                                  bundle: { 'is_connection' => false, 'input_fields' => [] })
      expect(cache.gql_load_bundle(store, :query, 'in',
                                   selection_name: 'people', include_fields: {},
                                   required_keys: keys_in)).to be_nil
    end

    it 'rejects a bundle whose descriptor list is malformed' do
      cache.gql_write_bundle_part(store, :query, 'in',
                                  selection_name: 'people', include_fields: {},
                                  bundle: valid_in_bundle('input_fields' => [{}]))
      expect(cache.gql_load_bundle(store, :query, 'in',
                                   selection_name: 'people', include_fields: {},
                                   required_keys: keys_in)).to be_nil
    end

    it 'accepts a bundle whose descriptor list is well-formed' do
      good = valid_in_bundle('input_fields' => [{ 'id' => 'x', 'label' => 'X', 'type' => 'string' }])
      cache.gql_write_bundle_part(store, :query, 'in', selection_name: 'people', include_fields: {}, bundle: good)
      expect(cache.gql_load_bundle(store, :query, 'in',
                                   selection_name: 'people', include_fields: {},
                                   required_keys: keys_in)).not_to be_nil
    end
  end

  describe 'gql_valid_descriptor_list?' do
    it 'accepts a valid nested descriptor list' do
      list = [{ 'id' => 'a', 'label' => 'A', 'type' => 'nested',
                'fields' => [{ 'id' => 'b', 'label' => 'B', 'type' => 'string' }], }]
      expect(cache.gql_valid_descriptor_list?(list)).to be(true)
    end

    it 'accepts a well-formed enumeration' do
      list = [{ 'id' => 'a', 'label' => 'A', 'type' => 'string', 'enumeration' => [{ 'id' => 'x', 'label' => 'X' }] }]
      expect(cache.gql_valid_descriptor_list?(list)).to be(true)
    end

    it 'rejects a non-array' do
      expect(cache.gql_valid_descriptor_list?({ 'id' => 'a' })).to be(false)
    end

    it 'rejects an entry missing id, label, or type' do
      expect(cache.gql_valid_descriptor_list?([{ 'id' => 'a', 'label' => 'A' }])).to be(false)
    end

    it 'rejects a non-string id' do
      expect(cache.gql_valid_descriptor_list?([{ 'id' => 1, 'label' => 'A', 'type' => 'string' }])).to be(false)
    end

    it 'rejects a malformed enumeration entry' do
      list = [{ 'id' => 'a', 'label' => 'A', 'type' => 'string', 'enumeration' => [{ 'id' => 'x' }] }]
      expect(cache.gql_valid_descriptor_list?(list)).to be(false)
    end

    it 'rejects a malformed nested fields list' do
      list = [{ 'id' => 'a', 'label' => 'A', 'type' => 'nested', 'fields' => [{}] }]
      expect(cache.gql_valid_descriptor_list?(list)).to be(false)
    end
  end

  describe 'root-field options' do
    it 'fails closed when no generation is established' do
      expect(cache.gql_read_root_options(store, :query)).to be_nil
    end

    it 'round-trips written options normalized to id/label symbol keys' do
      cache.gql_write_root_options(store, :query, [{ id: 'people', label: 'People' }])
      expect(cache.gql_read_root_options(store, :query)).to eq([{ id: 'people', label: 'People' }])
    end

    it 'does not read options orphaned by a later generation bump' do
      cache.gql_write_root_options(store, :query, [{ id: 'people', label: 'People' }])
      cache.gql_bump_bundle_generation(store)
      expect(cache.gql_read_root_options(store, :query)).to be_nil
    end
  end

  describe 'gql_warm_for_regeneration?' do
    before { cache.gql_bump_bundle_generation(store) }

    def warm_root_options
      cache.gql_write_root_options(store, :query, [{ id: 'people', label: 'People' }])
    end

    it 'is false when root options are absent (even with both bundle parts warm)' do
      cache.gql_write_bundle_part(store, :query, 'in',
                                  selection_name: 'people', include_fields: {},
                                  bundle: valid_in_bundle)
      cache.gql_write_bundle_part(store, :query, 'out',
                                  selection_name: 'people', include_fields: {},
                                  bundle: { 'output_fields' => [] })
      expect(cache.gql_warm_for_regeneration?(store, :query,
                                              selection_present: true, selection_name: 'people',
                                              include_fields: {}, required_keys_in: keys_in,
                                              required_keys_out: keys_out)).to be(false)
    end

    it 'is true with root options when no selection has been made yet' do
      warm_root_options
      expect(cache.gql_warm_for_regeneration?(store, :query,
                                              selection_present: false, selection_name: nil,
                                              include_fields: {}, required_keys_in: keys_in,
                                              required_keys_out: keys_out)).to be(true)
    end

    it 'is false when a selection is made but a bundle part is missing' do
      warm_root_options
      cache.gql_write_bundle_part(store, :query, 'in',
                                  selection_name: 'people', include_fields: {},
                                  bundle: valid_in_bundle)
      expect(cache.gql_warm_for_regeneration?(store, :query,
                                              selection_present: true, selection_name: 'people',
                                              include_fields: {}, required_keys_in: keys_in,
                                              required_keys_out: keys_out)).to be(false)
    end

    it 'is true when root options and both bundle parts are warm' do
      warm_root_options
      cache.gql_write_bundle_part(store, :query, 'in',
                                  selection_name: 'people', include_fields: {},
                                  bundle: valid_in_bundle)
      cache.gql_write_bundle_part(store, :query, 'out',
                                  selection_name: 'people', include_fields: {},
                                  bundle: { 'output_fields' => [] })
      expect(cache.gql_warm_for_regeneration?(store, :query,
                                              selection_present: true, selection_name: 'people',
                                              include_fields: {}, required_keys_in: keys_in,
                                              required_keys_out: keys_out)).to be(true)
    end
  end

  describe 'nil store (unconfigured action)' do
    it 'reads degrade to nil' do
      expect(cache.gql_cache_read(nil, 'k')).to be_nil
      expect(cache.gql_bundle_generation(nil)).to be_nil
      expect(cache.gql_load_bundle(nil, :query, 'in',
                                   selection_name: 'people', include_fields: {},
                                   required_keys: keys_in)).to be_nil
      expect(cache.gql_read_root_options(nil, :query)).to be_nil
    end

    it 'writes are a no-op returning the value' do
      expect(cache.gql_cache_write(nil, 'k', 'v', 10)).to eq('v')
    end

    it 'clears are a no-op returning nil' do
      expect(cache.gql_cache_clear(nil, 'k')).to be_nil
    end
  end
end
