require 'spec_helper'

describe IPaaS::Job::GraphQL::QueryBuilder do # -- mirrors GraphQL naming conventions
  let(:schema_data) { GraphqlSchemaHelper.schema_data }

  describe '.gql_build_field_selection' do
    it 'builds scalar fields for a simple type' do
      result = described_class.gql_build_field_selection(
        schema_data, 'Organization', 0,
      )
      expect(result).to eq('id name')
    end

    it 'excludes nested fields by default' do
      result = described_class.gql_build_field_selection(
        schema_data, 'Person', 0,
      )
      expect(result).to eq('id name primaryEmail disabled')
    end

    it 'includes nested fields when listed in include_data' do
      include_data = { include_fields: { organization: true } }
      result = described_class.gql_build_field_selection(
        schema_data, 'Person', 0, include_data: include_data,
      )
      expect(result).to eq(
        'id name primaryEmail disabled organization { id name }',
      )
    end

    it 'returns empty string for blank type_name' do
      r1 = described_class.gql_build_field_selection(schema_data, nil, 0)
      r2 = described_class.gql_build_field_selection(schema_data, '', 0)
      expect(r1).to eq('')
      expect(r2).to eq('')
    end

    it 'returns empty string when depth exceeds MAX_FIELD_DEPTH' do
      max = IPaaS::Job::GraphQL::Schema::MAX_FIELD_DEPTH
      result = described_class.gql_build_field_selection(
        schema_data, 'Person', max + 1,
      )
      expect(result).to eq('')
    end

    it 'returns id for unknown type with no fields' do
      schema = schema_data.deep_dup
      schema['types'] << GraphqlSchemaHelper::TypeRef.obj_type('EmptyType', fields: [])
      schema.delete('_type_index')
      result = described_class.gql_build_field_selection(
        schema, 'EmptyType', 0,
      )
      expect(result).to eq('id')
    end

    it 'handles connection types with nodes wrapping' do
      include_data = { include_fields: { people: true } }
      result = described_class.gql_build_field_selection(
        schema_data, 'Query', 0, include_data: include_data,
      )
      expected = 'people(first: 100) { nodes ' \
                 '{ id name primaryEmail disabled } }'
      expect(result).to include(expected)
    end

    it 'builds payload fields when included via include_data' do
      include_data = { include_fields: { request: true, errors: true } }
      result = described_class.gql_build_field_selection(
        schema_data, 'RequestCreatePayload', 0, include_data: include_data,
      )
      expect(result).to include('request { id subject }')
      expect(result).to include('errors { message path }')
    end
  end

  describe '.gql_type_ref_string' do
    it 'returns name for plain types' do
      ref = { 'kind' => 'SCALAR', 'name' => 'String' }
      expect(described_class.gql_type_ref_string(ref)).to eq('String')
    end

    it 'appends ! for NON_NULL types' do
      ref = {
        'kind' => 'NON_NULL',
        'ofType' => { 'kind' => 'SCALAR', 'name' => 'String' },
      }
      expect(described_class.gql_type_ref_string(ref)).to eq('String!')
    end

    it 'wraps LIST types in brackets' do
      ref = {
        'kind' => 'LIST',
        'ofType' => { 'kind' => 'SCALAR', 'name' => 'String' },
      }
      expect(described_class.gql_type_ref_string(ref)).to eq('[String]')
    end

    it 'handles nested NON_NULL LIST' do
      ref = {
        'kind' => 'NON_NULL',
        'ofType' => {
          'kind' => 'LIST',
          'ofType' => {
            'kind' => 'NON_NULL',
            'ofType' => { 'kind' => 'INPUT_OBJECT', 'name' => 'PersonOrder' },
          },
        },
      }
      expect(described_class.gql_type_ref_string(ref))
        .to eq('[PersonOrder!]!')
    end
  end
end
