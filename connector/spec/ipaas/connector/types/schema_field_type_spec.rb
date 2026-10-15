require 'spec_helper'

describe IPaaS::Connector::Types::SchemaFieldType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(IPaaS::Connector::Schema::Field)
  end

  it 'should return true for nested?' do
    expect(subject.nested?).to be_truthy
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :schema_field)
    example = subject.example(field)
    expect(example.id).to eq(:given_name)
    expect(example.label).to eq('Given name')
    expect(example.type).to eq(:string)
    expect(example.disabled).to eq(false)
    expect(example.array).to eq(false)
    expect(example.default).to eq('')
    expect(example.hint).to eq('Please provide your given name.')
    expect(example.sample).to eq('Mary')
    expect(example.visibility).to eq('visible')
    expect(example.required).to eq(true)
    expect(example.pattern).to eq(/\A[\w ]+\Z/)
    expect(example.min).to eq(2)
    expect(example.max).to eq(10)
    expect(example.min_length).to eq(2)
    expect(example.max_length).to eq(120)
    expect(example.enumeration).to eq([])
    expect(example.fields).to eq([])
  end

  describe 'schema' do
    let(:schema) { subject.schema }

    [:id, :label, :type, :fields]
      .each do |field_id|
      it "should mark #{field_id} as required" do
        expect(schema.field(field_id).required).to be_truthy
      end
    end

    {
      id: 'given_name',
      label: 'Given name',
      type: 'string',
      hint: 'Please provide your given name.',
      sample: 'Mary',
      pattern: /\A[\w ]+\Z/,
      min_length: 2,
      max_length: 120,
    }.each do |field_id, sample|
      it "should define sample of #{field_id} as #{sample.inspect}" do
        expect(schema.field(field_id).sample).to eq(sample)
      end
    end

    it 'should define a min_length of 1 for fields' do
      expect(schema.field(:fields).min_length).to eq(1)
    end

    {
      id: IPaaS::Connector::Schema::Field::MAX_ID_LENGTH,
      label: 120,
    }.each do |field_id, max_length|
      it "should define max_length of #{field_id} as #{max_length}" do
        expect(schema.field(field_id).max_length).to eq(max_length)
      end
    end

    [:id, :label, :type, :disabled, :array, :default, :required, :visibility, :fields]
      .each do |field_id|
      it "should mark #{field_id} as visible" do
        expect(schema.field(field_id).visibility).to eq('visible')
      end
    end

    [:hint, :sample, :pattern, :min, :max, :min_length, :max_length, :enumeration]
      .each do |field_id|
      it "should mark #{field_id} as optionally visible" do
        expect(schema.field(field_id).visibility).to eq('optional')
      end
    end

    it 'should define a default for visibility' do
      expect(schema.field(:visibility).default).to eq('visible')
    end

    it 'should mark fields as disabled by default' do
      expect(schema.field(:fields).disabled).to eq(true)
    end

    it 'should set the visibility enumeration' do
      types = schema.field(:visibility).enumeration.pluck(:id).sort
      expect(types).to include('visible')
      expect(types).to include('optional')
      expect(types).to include('hidden')
    end

    context 'on config update' do
      let(:context) do
        double(connector: IPaaS::Connector::Connector.new('uuid'))
      end

      # The schema is process-global, so its after_update acts on a copy and the result carries the copy's fields,
      # leaving the global as it was.
      def resolved_field(resolved, id)
        resolved.fields.detect { |field| field.id == id }
      end

      it 'should enable the fields only when type is nested' do
        nested, flat = %w[nested float].map do |type|
          resolved_field(schema.resolve(context, [{ field_id: 'type', fixed: type }]), :fields)
        end
        expect(nested.disabled).to be_falsey
        expect(flat.disabled).to be(true)
        expect(schema.field(:fields).disabled).to be(true)
      end

      it 'should set the type enumeration' do
        types = resolved_field(schema.resolve(context, []), :type).enumeration.pluck(:id).sort
        expect(types).to include('string')
        expect(types).to include('nested')
        expect(types).to include('recurrence')
        expect(types).to include('runbook')
        expect(schema.field(:type).enumeration).to be_empty
      end

      it 'should set the type of the default and sample' do
        resolved = schema.resolve(context, [
          { field_id: 'type', fixed: 'float' },
        ])
        expect(resolved_field(resolved, :default).type).to eq('float')
        expect(resolved_field(resolved, :sample).type).to eq('float')
      end

      it 'should resolve nested fields' do
        resolved = schema.resolve(context, [
          { field_id: 'id', fixed: 'cars' },
          { field_id: 'type', fixed: 'nested' },
          { field_id: 'array', fixed: true },
          { field_id: 'fields', nested: [
            { field_id: 'id', fixed: 'name' },
            { field_id: 'type', fixed: 'string' },
          ], },
          { field_id: 'fields', nested: [
            { field_id: 'id', fixed: 'nr' },
            { field_id: 'type', fixed: 'integer' },
          ], },
        ])
        expect(resolved[:id]).to eq('cars')
        expect(resolved[:array]).to eq(true)
        expect(resolved[:type]).to eq('nested')
        expect(resolved[:fields].first.type).to eq(:string)
        expect(resolved[:fields].first.id).to eq(:name)
        expect(resolved[:fields].last.id).to eq(:nr)
        expect(resolved[:fields].last.type).to eq(:integer)
      end
    end
  end

  describe 'resolve' do
    # A template's default or sample is frozen for a sealed connector, and validation resolves it again.
    it 'works on a frozen hash' do
      value = { id: 'nr', label: 'Nr', type: 'integer' }.freeze

      resolved = IPaaS::Connector::Types::SchemaFieldType.resolve(value)

      expect([resolved.id, resolved.type]).to eq([:nr, :integer])
    end

    it 'should resolve nested fields' do
      resolved = IPaaS::Connector::Types::SchemaFieldType.resolve({
        id: 'cars',
        type: 'nested',
        array: true,
        fields: [
          { id: 'nr', type: 'integer', min: 1, max: 99 },
        ],
      },)

      expect(resolved.id).to eq(:cars)
      expect(resolved.array).to eq(true)
      expect(resolved.type).to eq(:nested)
      expect(resolved.fields.first.id).to eq(:nr)
      expect(resolved.fields.first.type).to eq(:integer)
      expect(resolved.fields.first.min).to eq(1)
      expect(resolved.fields.first.max).to eq(99)
    end

    it 'should resolve deeply nested fields' do
      resolved = IPaaS::Connector::Types::SchemaFieldType.resolve({
        id: 'cars',
        type: 'nested',
        fields: [{
          id: 'owner',
          type: 'nested',
          fields: [{
            id: 'dog',
            type: 'nested',
            fields: [{ id: 'name', type: 'string' }, { id: 'age', type: 'integer' }],
          }],
        }],
      },)

      owner = resolved.fields.first
      dog = owner.fields.first
      expect([owner.id, owner.type]).to eq([:owner, :nested])
      expect([dog.id, dog.type]).to eq([:dog, :nested])
      expect(dog.fields.map { |field| [field.id, field.type] }).to eq([[:name, :string], [:age, :integer]])
    end

    it 'should filter out nil entries in fields' do
      resolved = IPaaS::Connector::Types::SchemaFieldType.resolve({
        id: 'cars',
        type: 'nested',
        fields: [nil, { id: 'nr', type: 'integer' }],
      },)
      expect(resolved.fields.length).to eq(1)
      expect(resolved.fields.first.id).to eq(:nr)
    end

    it 'returns a Field unchanged' do
      field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :string)
      expect(subject.resolve(field)).to be(field)
    end

    it 'coerces a bare string into a string field rather than leaking a raw String' do
      resolved = subject.resolve('noteText')
      expect(resolved).to be_a(IPaaS::Connector::Schema::Field)
      expect(resolved.id).to eq(:noteText)
      expect(resolved.label).to eq('noteText')
      expect(resolved.type).to eq(:string)
    end

    it 'coerces a bare symbol into a string field' do
      resolved = subject.resolve(:noteText)
      expect(resolved).to be_a(IPaaS::Connector::Schema::Field)
      expect(resolved.id).to eq(:noteText)
      expect(resolved.label).to eq('noteText')
      expect(resolved.type).to eq(:string)
    end

    it 'coerces bare-string entries nested under fields, preserving valid siblings' do
      resolved = subject.resolve({
        id: 'item', label: 'Item', type: 'nested',
        fields: ['noteText', { id: 'price', label: 'Price', type: 'integer' }],
      },)
      expect(resolved.fields.length).to eq(2)
      expect(resolved.fields[0].id).to eq(:noteText)
      expect(resolved.fields[0].type).to eq(:string)
      expect(resolved.fields[1].id).to eq(:price)
      expect(resolved.fields[1].type).to eq(:integer)
    end

    it 'drops scalar entries that cannot be a field' do
      expect(subject.resolve(42)).to be_nil
      expect(subject.resolve(nil)).to be_nil
    end

    it 'drops blank bare scalars rather than coercing them into a phantom field' do
      expect(subject.resolve('')).to be_nil
      expect(subject.resolve('   ')).to be_nil
    end

    it 'passes an array through unchanged so array-field defaults resolve to the array' do
      expect(subject.resolve([])).to eq([])
    end

    it 'should whitelist attribute names' do
      resolved = IPaaS::Connector::Types::SchemaFieldType.resolve({ output: true })
      expect(resolved.id).to be_nil
      expect(resolved.type).to be_nil
      expect(resolved.fields).to be_empty
    end
  end
end
