require 'spec_helper'

RSpec.describe IPaaS::Connector::Schema::FieldBuilder do
  def create_structure(*json_samples)
    IPaaS::Connector::Schema::StructureInferrer.infer(*json_samples)
  end

  describe '.build' do
    describe 'flat object' do
      let(:structure) { create_structure('{"name": "John", "age": 30}') }

      it 'builds Field instances with correct attributes' do
        fields = described_class.build(structure)
        expect(fields.length).to eq(2)
        expect(fields.map(&:class).uniq).to eq([IPaaS::Connector::Schema::Field])
        expect(fields).to all(be_valid)

        name_field = fields.detect { |f| f.id == :name }
        expect(name_field.type).to eq(:string)
        expect(name_field.label).to eq('Name')
        expect(name_field.sample).to eq('John')
        expect(name_field.hint).to eq('For example: John')

        age_field = fields.detect { |f| f.id == :age }
        expect(age_field.type).to eq(:integer)
        expect(age_field.sample).to eq(30)
      end
    end

    describe 'nested object' do
      let(:structure) { create_structure('{"user": {"name": "John"}}') }

      it 'builds nested Field with sub-fields' do
        fields = described_class.build(structure)
        user_field = fields.first
        expect(user_field.id).to eq(:user)
        expect(user_field.type).to eq(:nested)
        expect(user_field.fields.length).to eq(1)
        expect(user_field.fields.first.id).to eq(:name)
        expect(user_field.fields.first.type).to eq(:string)
        expect(user_field.fields.map(&:class).uniq).to eq([IPaaS::Connector::Schema::Field])
        expect(user_field.fields).to all(be_valid)
      end
    end

    describe 'array field' do
      let(:structure) { create_structure('{"tags": ["a", "b"]}') }

      it 'builds Field with array: true' do
        fields = described_class.build(structure)
        expect(fields.map(&:class).uniq).to eq([IPaaS::Connector::Schema::Field])
        expect(fields).to all(be_valid)

        tags_field = fields.first
        expect(tags_field.id).to eq(:tags)
        expect(tags_field.type).to eq(:string)
        expect(tags_field.array).to eq(true)
        expect(tags_field.sample).to eq(%w[a b])
      end
    end

    describe 'array of objects' do
      let(:structure) { create_structure('{"items": [{"id": 1}]}') }

      it 'builds nested array Field with sub-fields' do
        fields = described_class.build(structure)
        items_field = fields.first
        expect(items_field.type).to eq(:nested)
        expect(items_field.array).to eq(true)
        expect(items_field.fields.first.id).to eq(:id)
        expect(items_field.fields.first.type).to eq(:integer)
        expect(items_field.fields.map(&:class).uniq).to eq([IPaaS::Connector::Schema::Field])
        expect(items_field.fields).to all(be_valid)
      end
    end

    describe 'null type' do
      let(:structure) { create_structure('{"val": null}') }

      it 'resolves to :string' do
        fields = described_class.build(structure)
        expect(fields.first.type).to eq(:string)
        expect(fields.first).to be_valid
      end
    end

    describe 'type inference' do
      {
        'integer' => ['{"v": 42}', :integer],
        'float' => ['{"v": 3.14}', :float],
        'boolean' => ['{"v": true}', :boolean],
        'uri' => ['{"v": "https://example.com"}', :uri],
        'date_time' => ['{"v": "2024-01-15T10:30:00Z"}', :date_time],
        'date' => ['{"v": "2024-01-15"}', :date],
        'time_of_day' => ['{"v": "14:30:00"}', :time_of_day],
      }.each do |label, (json, expected_type)|
        it "builds #{label} field" do
          fields = described_class.build(create_structure(json))
          expect(fields.first.type).to eq(expected_type)
          expect(fields.first).to be_valid
        end
      end
    end

    describe 'sample and hint' do
      it 'sets sample from first non-null value' do
        fields = described_class.build(create_structure('{"name": null}', '{"name": "John"}'))
        expect(fields.first.sample).to eq('John')
      end

      it 'sets hint with unique values ordered by frequency then alphabetically' do
        fields = described_class.build(create_structure('{"s": "open"}', '{"s": "closed"}'))
        expect(fields.first.hint).to eq('For example: closed, open')
      end

      it 'omits sample and hint for nested fields' do
        fields = described_class.build(create_structure('{"user": {"name": "John"}}'))
        expect(fields.first.sample).to be_nil
        expect(fields.first.hint).to be_nil
      end

      it 'sets array hint prefix' do
        fields = described_class.build(create_structure('{"tags": ["a", "b"]}'))
        expect(fields.first.hint).to eq('A list of values, for example: a, b')
      end
    end

    describe 'digit-leading keys' do
      let(:structure) { create_structure('{"3d_view": "x"}') }

      it 'builds field with digit-leading ID' do
        fields = described_class.build(structure)
        expect(fields.first.id).to eq(:'3d_view')
      end
    end

    describe 'case-sensitive keys' do
      let(:structure) { create_structure('{"Asset": "my asset", "firstName": "John"}') }

      it 'preserves original key case in field ID' do
        fields = described_class.build(structure)
        asset_field = fields.detect { |f| f.id == :Asset }
        expect(asset_field).not_to be_nil
        expect(asset_field.label).to eq('Asset')

        first_name_field = fields.detect { |f| f.id == :firstName }
        expect(first_name_field).not_to be_nil
        expect(first_name_field.label).to eq('First name')
      end
    end

    describe 'empty structure' do
      it 'returns empty array for empty JSON' do
        expect(described_class.build(create_structure('{}'))).to eq([])
      end
    end

    describe 'deep nesting' do
      let(:structure) { create_structure('{"a": {"b": {"c": "deep"}}}') }

      it 'recursively builds nested fields' do
        fields = described_class.build(structure)
        a = fields.first
        expect(a.type).to eq(:nested)
        b = a.fields.first
        expect(b.type).to eq(:nested)
        c = b.fields.first
        expect(c.id).to eq(:c)
        expect(c.type).to eq(:string)
        expect(c.sample).to eq('deep')
      end
    end
  end

  describe '.to_field_id' do
    {
      'firstName' => :firstName,
      'some.thing' => :some_thing,
      '@type' => :type,
      'my field' => :my_field,
      'HTTPResponse' => :HTTPResponse,
      'customer_account_id' => :customer_account_id,
      'Asset' => :Asset,
    }.each do |input, expected|
      it "converts '#{input}' to :#{expected}" do
        expect(described_class.to_field_id(input)).to eq(expected)
      end
    end

    it 'truncates to 40 characters' do
      long_key = 'a_very_long_key_name_that_exceeds_forty_characters_total'
      result = described_class.to_field_id(long_key)
      expect(result.to_s.length).to be <= 40
    end
  end

  describe 'ID deduplication on truncation collision' do
    # 'a' * 50 and 'a' * 49 + 'b' both truncate to 'a' * 40 via to_field_id
    it 'appends _N suffix (trimming base to stay within 40 chars) for colliding IDs' do
      structure = create_structure("{\"#{'a' * 50}\": \"val1\", \"#{'a' * 49}b\": \"val2\"}")
      fields = described_class.build(structure)
      ids = fields.map { |f| f.id.to_s }
      expect(ids.first).to eq('a' * 40)
      expect(ids.second).to eq("#{'a' * 38}_2")
      expect(ids.map(&:length)).to all(be <= 40)
      expect(fields).to all(be_valid)
    end

    it 'skips a generated candidate that collides with a naturally occurring key' do
      # Three keys: two that truncate to the same base, plus one that naturally maps
      # to the first candidate suffix (_2). The dedup must skip _2 and use _3.
      base = 'a' * 50         # truncates to 'a' * 40
      base_alt = "#{'a' * 49}b" # also truncates to 'a' * 40
      natural_collision = "#{'a' * 38}_2" # naturally maps to the first candidate

      json = { base => 'v1', base_alt => 'v2', natural_collision => 'v3' }.to_json
      fields = described_class.build(create_structure(json))
      ids = fields.map { |f| f.id.to_s }

      expect(ids).to all(satisfy { |id| id.length <= 40 })
      expect(ids.uniq.length).to eq(ids.length), "expected all IDs to be unique, got: #{ids}"
    end
  end

  describe '.to_label' do
    {
      'first_name' => 'First name',
      'customer_account_id' => 'Customer account ID',
      'cpu_cores' => 'CPU cores',
      'host_name' => 'Host name',
    }.each do |input, expected|
      it "converts '#{input}' to '#{expected}'" do
        expect(described_class.to_label(input)).to eq(expected)
      end
    end
  end

  describe '.resolved_type' do
    it 'resolves :null to :string' do
      expect(described_class.resolved_type({ type: :null })).to eq(:string)
    end

    it 'preserves non-null types' do
      expect(described_class.resolved_type({ type: :integer })).to eq(:integer)
    end
  end

  describe '.extract_sample' do
    it 'returns most frequent value for scalars' do
      expect(described_class.extract_sample({ type: :string, values: { 'John' => 1 } })).to eq('John')
    end

    it 'returns nil for nested fields' do
      expect(described_class.extract_sample({ type: :nested })).to be_nil
    end

    it 'returns nil for empty values hash' do
      expect(described_class.extract_sample({ type: :string, values: {} })).to be_nil
    end

    it 'returns nil when values key is absent' do
      expect(described_class.extract_sample({ type: :string })).to be_nil
    end

    it 'returns values sorted by frequency for arrays' do
      result = described_class.extract_sample({ type: :string, array: true, values: { 'a' => 2, 'b' => 1 } })
      expect(result).to eq(%w[a b])
    end

    it 'picks the most frequent value over others' do
      expect(described_class.extract_sample({ type: :string, values: { 'rare' => 1, 'common' => 5 } })).to eq('common')
    end

    it 'sorts array sample by descending frequency and limits to default of 3' do
      values = { 'a' => 1, 'b' => 4, 'c' => 3, 'd' => 2, 'e' => 5 }
      result = described_class.extract_sample({ type: :string, array: true, values: values })
      expect(result).to eq(%w[e b c])
    end

    it 'limits array sample with max_sample_values keyword' do
      values = { 'a' => 1, 'b' => 3, 'c' => 2 }
      result = described_class.extract_sample({ type: :string, array: true, values: values }, max_sample_values: 2)
      expect(result).to eq(%w[b c])
    end

    it 'returns nil for arrays when max_sample_values is 0' do
      field_struct = { type: :string, array: true, values: { 'a' => 1 } }
      expect(described_class.extract_sample(field_struct, max_sample_values: 0)).to be_nil
    end

    it 'breaks ties alphabetically' do
      values = { 'beta' => 2, 'alpha' => 2 }
      expect(described_class.extract_sample({ type: :string, values: values })).to eq('alpha')
    end
  end

  describe '.extract_hint' do
    it 'returns hint string for scalars' do
      result = described_class.extract_hint({ type: :string, values: { 'open' => 1, 'closed' => 1 } })
      expect(result).to eq('For example: closed, open')
    end

    it 'returns nil for nested fields' do
      expect(described_class.extract_hint({ type: :nested })).to be_nil
    end

    it 'returns nil for empty values hash' do
      expect(described_class.extract_hint({ type: :string, values: {} })).to be_nil
    end

    it 'returns nil when values key is absent' do
      expect(described_class.extract_hint({ type: :string })).to be_nil
    end

    it 'returns array hint prefix' do
      result = described_class.extract_hint({ type: :string, array: true, values: { 'a' => 1, 'b' => 1 } })
      expect(result).to eq('A list of values, for example: a, b')
    end

    it 'orders hint values by frequency' do
      result = described_class.extract_hint({ type: :string, values: { 'rare' => 1, 'common' => 5 } })
      expect(result).to eq('For example: common, rare')
    end

    it 'limits hint values with max_hint_values keyword' do
      values = { 'a' => 5, 'b' => 4, 'c' => 3, 'd' => 2, 'e' => 1 }
      result = described_class.extract_hint({ type: :string, values: values }, max_hint_values: 2)
      expect(result).to eq('For example: a, b')
    end

    it 'defaults to 10 values maximum' do
      values = (1..15).to_h { |v| [v.to_s, 16 - v] }
      result = described_class.extract_hint({ type: :string, values: values })
      expect(result.split(': ', 2).last.split(', ').length).to eq(10)
    end

    it 'returns nil when max_hint_values is 0' do
      expect(described_class.extract_hint({ type: :string, values: { 'a' => 1 } }, max_hint_values: 0)).to be_nil
    end
  end
end
