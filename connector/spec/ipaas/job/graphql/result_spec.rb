require 'spec_helper'

describe IPaaS::Job::GraphQL::Result do
  describe '.gql_flatten_nodes' do
    it 'replaces a single-key nodes hash with its array' do
      value = { 'notes' => { 'nodes' => [{ 'id' => 'n1' }, { 'id' => 'n2' }] } }
      expect(described_class.gql_flatten_nodes(value)).to eq(
        { 'notes' => [{ 'id' => 'n1' }, { 'id' => 'n2' }] },
      )
    end

    it 'flattens a connection inside the records of another connection' do
      value = {
        'team' => {
          'members' => {
            'nodes' => [
              { 'name' => 'Alice', 'skills' => { 'nodes' => [{ 'name' => 'Ruby' }, { 'name' => 'SQL' }] } },
              { 'name' => 'Bob', 'skills' => { 'nodes' => [] } },
            ],
          },
        },
      }
      expect(described_class.gql_flatten_nodes(value)).to eq(
        {
          'team' => {
            'members' => [
              { 'name' => 'Alice', 'skills' => [{ 'name' => 'Ruby' }, { 'name' => 'SQL' }] },
              { 'name' => 'Bob', 'skills' => [] },
            ],
          },
        },
      )
    end

    it 'replaces an empty connection with an empty array' do
      expect(described_class.gql_flatten_nodes({ 'notes' => { 'nodes' => [] } })).to eq({ 'notes' => [] })
    end

    it 'leaves a connection hash with more keys than nodes untouched' do
      value = { 'notes' => { 'totalCount' => 2, 'nodes' => [{ 'id' => 'n1' }] } }
      expect(described_class.gql_flatten_nodes(value)).to eq(value)
    end

    it 'leaves a nodes key with a non-array value untouched' do
      value = { 'graph' => { 'nodes' => { 'count' => 3 } } }
      expect(described_class.gql_flatten_nodes(value)).to eq(value)
    end

    it 'flattens connections inside array elements' do
      value = [
        { 'notes' => { 'nodes' => [{ 'id' => 'n1' }] } },
        { 'notes' => { 'nodes' => [{ 'id' => 'n2' }] } },
      ]
      expect(described_class.gql_flatten_nodes(value)).to eq(
        [{ 'notes' => [{ 'id' => 'n1' }] }, { 'notes' => [{ 'id' => 'n2' }] }],
      )
    end

    it 'returns scalars and nil unchanged' do
      expect(described_class.gql_flatten_nodes('text')).to eq('text')
      expect(described_class.gql_flatten_nodes(42)).to eq(42)
      expect(described_class.gql_flatten_nodes(nil)).to be_nil
    end

    it 'does not mutate the input value' do
      # covers both branches: the flattened single-key hash and the untouched multi-key hash
      value = {
        'flattened' => { 'nodes' => [{ 'id' => 'n1' }] },
        'untouched' => { 'totalCount' => 1, 'nodes' => [{ 'id' => 'n2' }] },
      }
      original = value.deep_dup
      described_class.gql_flatten_nodes(value)
      expect(value).to eq(original)
    end
  end
end
