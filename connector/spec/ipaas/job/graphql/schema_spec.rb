require 'spec_helper'

describe IPaaS::Job::GraphQL::Schema do # -- mirrors GraphQL naming conventions
  let(:t) { GraphqlSchemaHelper::TypeRef }
  let(:schema_data) { GraphqlSchemaHelper.schema_data }

  describe '.gql_find_type' do
    it 'finds a type by name' do
      result = described_class.gql_find_type(schema_data, 'Person')
      expect(result['name']).to eq('Person')
      expect(result['kind']).to eq('OBJECT')
    end

    it 'returns nil for unknown type' do
      expect(described_class.gql_find_type(schema_data, 'Unknown')).to be_nil
    end

    it 'builds type index on first call and reuses it' do
      described_class.gql_find_type(schema_data, 'Person')
      expect(schema_data['_type_index']).to be_a(Hash)
      expect(schema_data['_type_index']['Person']['name']).to eq('Person')
    end
  end

  describe '.gql_find_root_field' do
    it 'finds a query root field' do
      field = described_class.gql_find_root_field(schema_data, 'query', 'people')
      expect(field['name']).to eq('people')
      expect(field['description']).to eq('List of people')
    end

    it 'finds a mutation root field' do
      field = described_class.gql_find_root_field(schema_data, 'mutation', 'requestCreate')
      expect(field['name']).to eq('requestCreate')
    end

    it 'returns nil for unknown field' do
      result = described_class.gql_find_root_field(schema_data, 'query', 'unknown')
      expect(result).to be_nil
    end

    it 'returns nil for unknown operation' do
      result = described_class.gql_find_root_field(schema_data, 'subscription', 'x')
      expect(result).to be_nil
    end
  end

  describe '.gql_unwrap_type' do
    it 'unwraps a plain scalar type' do
      type_ref = t.scalar('String')
      result = described_class.gql_unwrap_type(type_ref)

      expect(result).to eq(
        { kind: 'SCALAR', name: 'String', list: false, required: false },
      )
    end

    it 'unwraps a NON_NULL wrapper' do
      type_ref = t.non_null(t.scalar('ID'))
      result = described_class.gql_unwrap_type(type_ref)

      expect(result).to eq(
        { kind: 'SCALAR', name: 'ID', list: false, required: true },
      )
    end

    it 'unwraps a LIST wrapper' do
      type_ref = t.list(t.object('Person'))
      result = described_class.gql_unwrap_type(type_ref)

      expect(result).to eq(
        { kind: 'OBJECT', name: 'Person', list: true, required: false },
      )
    end

    it 'unwraps nested NON_NULL inside LIST' do
      type_ref = t.list(t.non_null(t.input_object('PersonOrder')))
      result = described_class.gql_unwrap_type(type_ref)

      expect(result[:kind]).to eq('INPUT_OBJECT')
      expect(result[:name]).to eq('PersonOrder')
      expect(result[:list]).to eq(true)
      expect(result[:required]).to eq(true)
    end

    it 'falls back to String scalar for nil inner type' do
      type_ref = { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => nil }
      result = described_class.gql_unwrap_type(type_ref)

      expect(result).to eq(
        { kind: 'SCALAR', name: 'String', list: false, required: true },
      )
    end
  end

  describe '.gql_resolve_return_type_name' do
    it 'resolves the return type for a query field' do
      result = described_class.gql_resolve_return_type_name(
        schema_data, 'query', 'people',
      )
      expect(result).to eq('PersonConnection')
    end

    it 'resolves the return type for me field' do
      result = described_class.gql_resolve_return_type_name(
        schema_data, 'query', 'me',
      )
      expect(result).to eq('Person')
    end

    it 'returns nil for unknown field' do
      result = described_class.gql_resolve_return_type_name(
        schema_data, 'query', 'unknown',
      )
      expect(result).to be_nil
    end
  end

  describe '.gql_resolve_connection_node_type' do
    it 'resolves the node type for a connection field' do
      result = described_class.gql_resolve_connection_node_type(
        schema_data, 'query', 'people',
      )
      expect(result).to eq('Person')
    end

    it 'returns nil for non-connection field' do
      result = described_class.gql_resolve_connection_node_type(
        schema_data, 'query', 'me',
      )
      expect(result).to be_nil
    end

    it 'returns nil for unknown field' do
      result = described_class.gql_resolve_connection_node_type(
        schema_data, 'query', 'unknown',
      )
      expect(result).to be_nil
    end
  end

  describe '.gql_mutation_input_type_name' do
    it 'resolves the input type for a mutation' do
      result = described_class.gql_mutation_input_type_name(
        schema_data, 'requestCreate',
      )
      expect(result).to eq('RequestCreateInput')
    end

    it 'falls back to ucfirst name for unknown mutation, preserving camelCase' do
      result = described_class.gql_mutation_input_type_name(
        schema_data, 'unknownMutation',
      )
      expect(result).to eq('UnknownMutationInput')
    end

    it 'falls back when mutation exists but has no input arg' do
      schema = schema_data.deep_dup
      mutation_type = schema['types'].detect { |tp| tp['name'] == 'Mutation' }
      no_input_mutation = { 'name' => 'simpleDelete', 'description' => nil,
                            'type' => t.object('DeletePayload'),
                            'args' => [{ 'name' => 'id', 'description' => nil,
                                         'type' => t.non_null(t.scalar('ID')),
                                         'defaultValue' => nil, }], }
      mutation_type['fields'] << no_input_mutation
      schema.delete('_type_index')
      result = described_class.gql_mutation_input_type_name(schema, 'simpleDelete')
      expect(result).to eq('SimpleDeleteInput')
    end
  end

  describe '.gql_list_root_fields' do
    it 'lists query root fields with humanized labels' do
      result = described_class.gql_list_root_fields(schema_data, 'query')
      expect(result).to contain_exactly(
        { id: 'people', label: 'People' },
        { id: 'me', label: 'Me' },
      )
    end

    it 'lists mutation root fields' do
      result = described_class.gql_list_root_fields(schema_data, 'mutation')
      expect(result).to contain_exactly(
        { id: 'requestCreate', label: 'Request Create' },
      )
    end

    it 'returns empty array for blank schema_data or nil fields' do
      expect(described_class.gql_list_root_fields({}, 'query')).to eq([])
      expect(described_class.gql_list_root_fields(nil, 'query')).to eq([])

      schema = { 'queryType' => { 'name' => 'Query' },
                 'types' => [{ 'kind' => 'OBJECT', 'name' => 'Query', 'fields' => nil }], }
      expect(described_class.gql_list_root_fields(schema, 'query')).to eq([])
    end

    it 'skips fields with names longer than 40 characters' do
      long_name = 'a' * 41
      schema = schema_data.deep_dup
      query_type = schema['types'].detect { |tp| tp['name'] == 'Query' }
      query_type['fields'] << {
        'name' => long_name, 'description' => nil,
        'type' => t.scalar('String'), 'args' => [],
      }
      schema.delete('_type_index')
      result = described_class.gql_list_root_fields(schema, 'query')
      expect(result.map { |r| r[:id] }).not_to include(long_name)
    end
  end

  describe '.gql_collect_fields' do
    it 'collects fields for an object type' do
      fields = described_class.gql_collect_fields(schema_data, 'Person')
      names = fields.map { |f| f['name'] }
      expect(names).to eq(%w[id name primaryEmail disabled organization])
    end

    it 'returns empty array for unknown type' do
      result = described_class.gql_collect_fields(schema_data, 'NonExistent')
      expect(result).to eq([])
    end

    it 'merges possible type fields for union/interface types' do
      schema = schema_data.deep_dup
      schema['types'] << {
        'kind' => 'UNION', 'name' => 'TestUnion',
        'fields' => [],
        'possibleTypes' => [
          { 'name' => 'Person' },
          { 'name' => 'Organization' },
        ],
        'inputFields' => nil, 'enumValues' => nil,
      }
      schema.delete('_type_index')
      fields = described_class.gql_collect_fields(schema, 'TestUnion')
      names = fields.map { |f| f['name'] }
      expect(names).to include('id', 'name', 'primaryEmail')
    end
  end

  describe '.gql_required_args?' do
    it 'returns false for field with no required args' do
      field = {
        'args' => [
          { 'type' => t.scalar('Int'), 'defaultValue' => nil },
        ],
      }
      expect(described_class.gql_required_args?(field)).to eq(false)
    end

    it 'returns true for field with required arg without default' do
      field = {
        'args' => [{
          'type' => t.non_null(t.scalar('ID')),
          'defaultValue' => nil,
        }],
      }
      expect(described_class.gql_required_args?(field)).to eq(true)
    end

    it 'returns false for required arg with default value' do
      field = {
        'args' => [{
          'type' => t.non_null(t.scalar('Int')),
          'defaultValue' => '10',
        }],
      }
      expect(described_class.gql_required_args?(field)).to eq(false)
    end

    it 'returns false for field with no args' do
      expect(described_class.gql_required_args?({ 'args' => [] })).to eq(false)
    end
  end

  describe '.gql_to_ipaas_type' do
    it 'maps known scalar types' do
      m = described_class.method(:gql_to_ipaas_type)
      expect(m.call({ kind: 'SCALAR', name: 'Int' })).to eq(:integer)
      expect(m.call({ kind: 'SCALAR', name: 'Float' })).to eq(:float)
      expect(m.call({ kind: 'SCALAR', name: 'Boolean' })).to eq(:boolean)
      expect(m.call({ kind: 'SCALAR', name: 'ISO8601DateTime' }))
        .to eq(:date_time)
      expect(m.call({ kind: 'SCALAR', name: 'ISO8601Timestamp' }))
        .to eq(:date_time)
      expect(m.call({ kind: 'SCALAR', name: 'ISO8601Date' })).to eq(:date)
      expect(m.call({ kind: 'SCALAR', name: 'JSON' })).to eq(:any)
    end

    it 'maps unknown scalar to string' do
      m = described_class.method(:gql_to_ipaas_type)
      expect(m.call({ kind: 'SCALAR', name: 'String' })).to eq(:string)
      expect(m.call({ kind: 'SCALAR', name: 'ID' })).to eq(:string)
    end

    it 'maps nested kinds to :nested' do
      %w[OBJECT INTERFACE UNION INPUT_OBJECT].each do |kind|
        result = described_class.gql_to_ipaas_type(
          { kind: kind, name: 'Foo' },
        )
        expect(result).to eq(:nested)
      end
    end

    it 'maps ENUM to :string' do
      result = described_class.gql_to_ipaas_type(
        { kind: 'ENUM', name: 'Status' },
      )
      expect(result).to eq(:string)
    end
  end

  describe '.gql_find_nodes_field' do
    it 'finds nodes field on a connection type' do
      field = described_class.gql_find_nodes_field(schema_data, 'PersonConnection')
      expect(field['name']).to eq('nodes')
    end

    it 'returns nil for non-connection type' do
      result = described_class.gql_find_nodes_field(schema_data, 'Person')
      expect(result).to be_nil
    end

    it 'returns nil for unknown type' do
      result = described_class.gql_find_nodes_field(schema_data, 'Unknown')
      expect(result).to be_nil
    end
  end

  describe '.gql_skip_field?' do
    it 'skips pageInfo field' do
      f = { 'name' => 'pageInfo', 'args' => [] }
      expect(described_class.gql_skip_field?(f)).to eq(true)
    end

    it 'skips totalCount field' do
      f = { 'name' => 'totalCount', 'args' => [] }
      expect(described_class.gql_skip_field?(f)).to eq(true)
    end

    it 'skips field with required args' do
      field = {
        'name' => 'items',
        'args' => [{
          'type' => t.non_null(t.scalar('ID')),
          'defaultValue' => nil,
        }],
      }
      expect(described_class.gql_skip_field?(field)).to eq(true)
    end

    it 'skips field with name longer than 40 characters' do
      f = { 'name' => 'a' * 41, 'args' => [] }
      expect(described_class.gql_skip_field?(f)).to eq(true)
    end

    it 'does not skip normal field' do
      f = { 'name' => 'id', 'args' => [] }
      expect(described_class.gql_skip_field?(f)).to eq(false)
    end
  end

  describe 'INTROSPECTION_QUERY' do
    it 'is a frozen string with whitespace collapged containing __schema' do
      expect(described_class::INTROSPECTION_QUERY).to be_frozen
      expect(described_class::INTROSPECTION_QUERY).to include('__schema')
      expect(described_class::INTROSPECTION_QUERY).not_to match(/\s\s+/)
    end
  end
end
