require 'spec_helper'

describe IPaaS::Job::GraphQL::FieldBuilder do
  # Mock target that mimics the field() method from SchemaMixin.
  # When called with just an id, returns the stored field.
  # When called with id, label, type, and options, stores a new field.
  class MockTarget
    FieldDef = Struct.new(:id, :label, :type, :opts, :sub_fields) do
      alias_method :fields, :sub_fields

      def field(fid = nil, flabel = nil, ftype = nil, **fopts, &block)
        return sub_fields.detect { |f| f.id == fid } if flabel.nil? && ftype.nil?

        MockTarget.create_field(fid, flabel, ftype, fopts, sub_fields, &block)
      end

      attr_accessor :enumeration, :hint
    end

    attr_reader :fields

    def initialize
      @fields = []
    end

    def field(fid = nil, flabel = nil, ftype = nil, **fopts, &block)
      return @fields.detect { |f| f.id == fid } if flabel.nil? && ftype.nil?

      self.class.create_field(fid, flabel, ftype, fopts, @fields, &block)
    end

    class << self
      def create_field(fid, flabel, ftype, fopts, collection, &block)
        new_field = FieldDef.new(id: fid, label: flabel, type: ftype, opts: fopts, sub_fields: [])
        new_field.instance_eval(&block) if block
        collection << new_field
        new_field
      end
    end
  end

  let(:schema_data) { GraphqlSchemaHelper.schema_data }

  let(:target) { MockTarget.new }

  describe '.gql_add_dynamic_fields' do
    it 'adds scalar output fields for a simple type' do
      described_class.gql_add_dynamic_fields(
        target, schema_data, 'Organization', 0,
      )
      ids = target.fields.map(&:id)
      expect(ids).to eq([:id, :name])
    end

    it 'adds scalar fields and skips nested by default' do
      described_class.gql_add_dynamic_fields(
        target, schema_data, 'Person', 0,
      )
      ids = target.fields.map(&:id)
      expect(ids).to eq([:id, :name, :primaryEmail, :disabled])
      expect(ids).not_to include(:organization)
    end

    it 'includes nested fields when listed in include_data' do
      include_data = { include_fields: { organization: true } }
      described_class.gql_add_dynamic_fields(
        target, schema_data, 'Person', 0, include_data: include_data,
      )
      ids = target.fields.map(&:id)
      expect(ids).to include(:organization)

      org_field = target.field(:organization)
      expect(org_field.type).to eq(:nested)
      sub_ids = org_field.sub_fields.map(&:id)
      expect(sub_ids).to eq([:id, :name])
    end

    it 'does nothing for blank type_name' do
      described_class.gql_add_dynamic_fields(target, schema_data, nil, 0)
      expect(target.fields).to be_empty
    end

    it 'does nothing when depth exceeds MAX_FIELD_DEPTH' do
      max = IPaaS::Job::GraphQL::Schema::MAX_FIELD_DEPTH
      described_class.gql_add_dynamic_fields(
        target, schema_data, 'Person', max + 1,
      )
      expect(target.fields).to be_empty
    end

    it 'sets hint from field description' do
      described_class.gql_add_dynamic_fields(
        target, schema_data, 'Person', 0,
      )
      id_field = target.field(:id)
      expect(id_field.opts[:hint]).to eq('Unique identifier.')

      email_field = target.field(:primaryEmail)
      expect(email_field.opts[:hint]).to eq('Primary email.')
    end

    it 'sets boolean type correctly' do
      described_class.gql_add_dynamic_fields(
        target, schema_data, 'Person', 0,
      )
      disabled_field = target.field(:disabled)
      expect(disabled_field.type).to eq(:boolean)
    end

    it 'handles connection nested fields as arrays' do
      include_data = { include_fields: { people: true } }
      described_class.gql_add_dynamic_fields(
        target, schema_data, 'Query', 0, include_data: include_data,
      )
      people_field = target.field(:people)
      expect(people_field).not_to be_nil
      expect(people_field.type).to eq(:nested)
      expect(people_field.opts[:array]).to eq(true)
    end
  end

  describe '.gql_add_dynamic_input_fields' do
    it 'adds input fields for a mutation input type' do
      described_class.gql_add_dynamic_input_fields(
        target, schema_data, 'RequestCreateInput', 0,
      )
      ids = target.fields.map(&:id)
      expect(ids).to include(:subject, :category, :source, :sourceID)
      expect(ids).to include(:customFields)
    end

    it 'skips clientMutationId field' do
      described_class.gql_add_dynamic_input_fields(
        target, schema_data, 'RequestCreateInput', 0,
      )
      ids = target.fields.map(&:id)
      expect(ids).not_to include(:clientMutationId)
    end

    it 'marks required fields' do
      described_class.gql_add_dynamic_input_fields(
        target, schema_data, 'RequestCreateInput', 0,
      )
      subject_field = target.field(:subject)
      expect(subject_field.opts[:required]).to eq(true)

      source_field = target.field(:source)
      expect(source_field.opts[:required]).to eq(false)
    end

    it 'sets enum values for enum input fields' do
      described_class.gql_add_dynamic_input_fields(
        target, schema_data, 'RequestCreateInput', 0,
      )
      category_field = target.field(:category)
      expect(category_field.opts[:enumeration]).to eq(%w[incident rfc])
    end

    it 'creates nested fields for INPUT_OBJECT sub-types' do
      described_class.gql_add_dynamic_input_fields(
        target, schema_data, 'RequestCreateInput', 0,
      )
      custom_field = target.field(:customFields)
      expect(custom_field.type).to eq(:nested)

      sub_ids = custom_field.sub_fields.map(&:id)
      expect(sub_ids).to include(:id, :value)
    end

    it 'maps JSON scalar sub-fields to :any so any value is accepted' do
      described_class.gql_add_dynamic_input_fields(
        target, schema_data, 'RequestCreateInput', 0,
      )
      custom_field = target.field(:customFields)
      value_field = custom_field.sub_fields.detect { |f| f.id == :value }
      expect(value_field.type).to eq(:any)
    end

    it 'marks list fields as array' do
      described_class.gql_add_dynamic_input_fields(
        target, schema_data, 'RequestCreateInput', 0,
      )
      custom_field = target.field(:customFields)
      expect(custom_field.opts[:array]).to eq(true)
    end

    it 'does not set visibility when no visibility proc is given' do
      described_class.gql_add_dynamic_input_fields(
        target, schema_data, 'RequestCreateInput', 0,
      )
      category_field = target.field(:category)
      expect(category_field.opts).not_to have_key(:visibility)

      source_field = target.field(:source)
      expect(source_field.opts).not_to have_key(:visibility)
    end

    it 'applies visibility from a custom proc' do
      vis = ->(name, is_required, depth) {
        next if depth > 0 || is_required
        'optional' unless %w[subject name source sourceID note].include?(name)
      }
      described_class.gql_add_dynamic_input_fields(
        target, schema_data, 'RequestCreateInput', 0, visibility: vis,
      )
      # category is not in the always-visible list
      expect(target.field(:category).opts[:visibility]).to eq('optional')
      # source and sourceID are in the always-visible list
      expect(target.field(:source).opts).not_to have_key(:visibility)
      expect(target.field(:sourceID).opts).not_to have_key(:visibility)
      # subject is required, so visibility is not set
      expect(target.field(:subject).opts).not_to have_key(:visibility)
    end

    it 'applies depth-independent visibility proc to all fields except excluded' do
      vis = ->(name, _, _) { 'optional' unless %w[query].include?(name) }
      described_class.gql_add_dynamic_input_fields(
        target, schema_data, 'PersonFilter', 0, visibility: vis,
      )
      # query is excluded from optional
      expect(target.field(:query).opts).not_to have_key(:visibility)
      # disabled gets optional even though it has no special status
      expect(target.field(:disabled).opts[:visibility]).to eq('optional')
    end

    it 'does nothing for blank type_name' do
      described_class.gql_add_dynamic_input_fields(
        target, schema_data, nil, 0,
      )
      expect(target.fields).to be_empty
    end

    it 'does nothing when depth exceeds MAX_FIELD_DEPTH' do
      max = IPaaS::Job::GraphQL::Schema::MAX_FIELD_DEPTH
      described_class.gql_add_dynamic_input_fields(
        target, schema_data, 'RequestCreateInput', max + 1,
      )
      expect(target.fields).to be_empty
    end

    it 'sorts fields when sort is true' do
      described_class.gql_add_dynamic_input_fields(
        target, schema_data, 'RequestCreateInput', 0, sort: true,
      )
      ids = target.fields.map(&:id)
      expected = [:category, :customFields, :source, :sourceID, :subject]
      expect(ids).to eq(expected)
    end
  end

  describe '.gql_build_order_subfields' do
    it 'adds order fields with enum values' do
      described_class.gql_build_order_subfields(
        target, schema_data, 'PersonOrder',
      )
      ids = target.fields.map(&:id)
      expect(ids).to eq([:field, :direction])
    end

    it 'adds enum enumeration labels for enum order fields' do
      described_class.gql_build_order_subfields(
        target, schema_data, 'PersonOrder',
      )
      field_field = target.field(:field)
      expect(field_field.type).to eq(:string)
      expect(field_field.opts[:enumeration]).to include(
        { id: 'name', label: 'Name' },
        { id: 'createdAt', label: 'Created At' },
      )
      expect(field_field.opts[:required]).to eq(true)
    end

    it 'includes hint from field description' do
      described_class.gql_build_order_subfields(
        target, schema_data, 'PersonOrder',
      )
      field_field = target.field(:field)
      expect(field_field.opts[:hint]).to eq('Field to order by')

      direction_field = target.field(:direction)
      expect(direction_field.opts[:hint]).to eq('Order direction')
    end

    it 'does nothing for unknown type' do
      described_class.gql_build_order_subfields(
        target, schema_data, 'NonExistent',
      )
      expect(target.fields).to be_empty
    end
  end

  describe '.gql_update_include_fields_input' do
    before(:each) do
      target.field :include_fields, 'Include nested fields', :nested
    end

    it 'adds boolean fields for available nested options' do
      described_class.gql_update_include_fields_input(
        target, schema_data, 'Person', {}, 0,
      )

      include_field = target.field(:include_fields)
      sub_ids = include_field.fields.map(&:id)
      expect(sub_ids).to eq([:organization])
      expect(include_field.field(:organization).type).to eq(:boolean)
    end

    it 'generates _fields section when boolean is checked' do
      schema = schema_data.deep_dup
      org_type = schema['types'].detect { |t| t['name'] == 'Organization' }
      org_type['fields'] << {
        'name' => 'parent', 'description' => nil,
        'type' => { 'kind' => 'OBJECT', 'name' => 'Organization', 'ofType' => nil },
        'args' => [],
      }
      schema.delete('_type_index')

      include_data = { include_fields: { organization: true } }
      described_class.gql_update_include_fields_input(
        target, schema, 'Person', include_data, 0,
      )

      include_field = target.field(:include_fields)
      org_fields = include_field.field(:organization_fields)
      expect(org_fields).to be_present
      expect(org_fields.type).to eq(:nested)
      expect(org_fields.field(:parent)).to be_present
      expect(org_fields.field(:parent).type).to eq(:boolean)
    end

    it 'does not generate _fields section when boolean is unchecked' do
      include_data = { include_fields: { organization: false } }
      described_class.gql_update_include_fields_input(
        target, schema_data, 'Person', include_data, 0,
      )

      include_field = target.field(:include_fields)
      expect(include_field.field(:organization_fields)).to be_nil
    end

    it 'does nothing for blank type_name' do
      described_class.gql_update_include_fields_input(
        target, schema_data, nil, {}, 0,
      )
      expect(target.fields.map(&:id)).to eq([:include_fields])
    end

    it 'does nothing when depth exceeds MAX_FIELD_DEPTH' do
      max = IPaaS::Job::GraphQL::Schema::MAX_FIELD_DEPTH
      described_class.gql_update_include_fields_input(
        target, schema_data, 'Person', {}, max + 1,
      )
      expect(target.fields.map(&:id)).to eq([:include_fields])
    end

    it 'does nothing when type has no nested field options' do
      described_class.gql_update_include_fields_input(
        target, schema_data, 'Organization', {}, 0,
      )

      include_field = target.field(:include_fields)
      expect(include_field.fields).to be_empty
    end
  end

  describe '.extract_included_field_names' do
    it 'extracts field names where value is true' do
      include_data = { include_fields: { organization: true, team: true, team_fields: { members: true } } }
      names = described_class.extract_included_field_names(include_data)
      expect(names).to eq(%w[organization team])
    end

    it 'excludes false booleans' do
      include_data = { include_fields: { organization: true, team: false } }
      names = described_class.extract_included_field_names(include_data)
      expect(names).to eq(%w[organization])
    end

    it 'returns empty array for nil include_data' do
      expect(described_class.extract_included_field_names(nil)).to eq([])
    end

    it 'returns empty array when include_fields is missing' do
      expect(described_class.extract_included_field_names({})).to eq([])
    end
  end

  describe '.extract_sub_include' do
    it 'returns sub-include from _fields key' do
      include_data = {
        include_fields: {
          organization: true,
          organization_fields: { parent: true },
          team: true,
        },
      }
      sub = described_class.extract_sub_include(include_data, 'organization')
      expect(sub).to eq({ include_fields: { parent: true } })
    end

    it 'returns empty hash when _fields key not present' do
      include_data = { include_fields: { team: true } }
      expect(described_class.extract_sub_include(include_data, 'organization')).to eq({})
    end

    it 'returns empty hash for nil include_data' do
      expect(described_class.extract_sub_include(nil, 'anything')).to eq({})
    end
  end
end
