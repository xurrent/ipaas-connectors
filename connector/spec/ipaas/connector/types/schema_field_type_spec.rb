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
      id: 40,
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

      it 'should enable the fields when type is nested' do
        expect(schema.field(:fields).disabled).to be_truthy
        schema.resolve(context, [
          { field_id: 'type', fixed: 'nested' },
        ])
        expect(schema.field(:fields).disabled).to be_falsey
      end

      it 'should set the type enumeration' do
        schema.resolve(context, [])
        types = schema.field(:type).enumeration.pluck(:id).sort
        expect(types).to include('string')
        expect(types).to include('nested')
        expect(types).to include('recurrence')
        expect(types).to include('runbook')
      end

      it 'should set the type of the default and sample' do
        schema.resolve(context, [
          { field_id: 'type', fixed: 'float' },
        ])
        expect(schema.field(:default).type).to eq('float')
        expect(schema.field(:sample).type).to eq('float')
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

      it 'should resolve deeply nested fields' do
        resolved = schema.resolve(context, [
          { field_id: 'id', fixed: 'cars' },
          { field_id: 'type', fixed: 'nested' },
          { field_id: 'fields', nested: [
            { field_id: 'id', fixed: 'owner' },
            { field_id: 'type', fixed: 'nested' },
            { field_id: 'fields', nested: [
              { field_id: 'id', fixed: 'dog' },
              { field_id: 'type', fixed: 'nested' },
              { field_id: 'fields', nested: [
                { field_id: 'id', fixed: 'name' },
                { field_id: 'type', fixed: 'string' },
              ], },
              { field_id: 'fields', nested: [
                { field_id: 'id', fixed: 'age' },
                { field_id: 'type', fixed: 'integer' },
              ], },
            ], },
          ], },
        ])
        expect(resolved[:id]).to eq('cars')
        owner = resolved[:fields].first
        expect(owner.type).to eq(:nested)
        dog = owner.fields.first
        expect(dog.type).to eq(:nested)
        dog_name = dog.fields.first
        expect(dog_name.id).to eq(:name)
        expect(dog_name.type).to eq(:string)
        dog_age = dog.fields.last
        expect(dog_age.id).to eq(:age)
        expect(dog_age.type).to eq(:integer)
      end
    end
  end

  describe 'resolve' do
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

    it 'should filter out nil entries in fields' do
      resolved = IPaaS::Connector::Types::SchemaFieldType.resolve({
        id: 'cars',
        type: 'nested',
        fields: [nil, { id: 'nr', type: 'integer' }],
      },)
      expect(resolved.fields.length).to eq(1)
      expect(resolved.fields.first.id).to eq(:nr)
    end

    it 'should not fail when an invalid type is provided' do
      resolved = IPaaS::Connector::Types::SchemaFieldType.resolve('foo')
      expect(resolved).to eq('foo')
    end

    it 'should whitelist attribute names' do
      resolved = IPaaS::Connector::Types::SchemaFieldType.resolve({ output: true })
      expect(resolved.id).to be_nil
      expect(resolved.type).to be_nil
      expect(resolved.fields).to be_empty
    end
  end
end
