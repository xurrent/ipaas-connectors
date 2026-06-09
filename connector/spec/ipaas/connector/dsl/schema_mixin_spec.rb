require 'spec_helper'

describe IPaaS::Connector::Dsl::SchemaMixin do
  it 'allows to set a schema' do
    foo_tester = Class.new(DslTester) do
      schema :foo
    end.new
    foo_tester.foo do
      field :bar, 'bar', :integer
    end
    expect(foo_tester.foo.fields.first.id).to eq(:bar)
    expect(foo_tester.foo.fields.first.label).to eq('bar')
    expect(foo_tester.foo.fields.first.type).to eq(:integer)
  end

  it 'allows default fields on a schema' do
    foo_tester = Class.new(DslTester) do
      schema :foo do
        field :baz, 'baz', :string
      end
    end.new
    foo_tester.foo do
      field :bar, 'bar', :integer
    end
    expect(foo_tester.foo.fields.size).to eq(2)
    expect(foo_tester.foo.fields.first.id).to eq(:bar)
    expect(foo_tester.foo.fields.last.id).to eq(:baz)
    expect(foo_tester.foo.fields.last.label).to eq('baz')
    expect(foo_tester.foo.fields.last.type).to eq(:string)
  end

  it 'sets default fields on a schema even when schema is not customized' do
    foo_tester = Class.new(DslTester) do
      schema :foo do
        field :baz, 'baz', :string
      end
    end.new
    foo_tester.foo do
    end
    expect(foo_tester.foo.fields.size).to eq(1)
    expect(foo_tester.foo.fields.first.id).to eq(:baz)
    expect(foo_tester.foo.fields.first.label).to eq('baz')
    expect(foo_tester.foo.fields.first.type).to eq(:string)
  end

  it 'validates schema' do
    foo_tester = Class.new(DslTester) do
      schema :foo
    end.new
    foo_tester.foo do
      field :bar, nil, :integer
    end
    expect(foo_tester).to be_invalid
    expect(foo_tester.errors[:foo].first).to eq("Schema (foo) invalid: Field (bar) invalid: Label can't be blank.")
  end

  it 'validates type of schema fields' do
    foo_tester = Class.new(DslTester) do
      schema :foo
    end.new
    foo_tester.foo do
      fields << 'Baz'
    end
    expect(foo_tester).to be_invalid
    expect(foo_tester.errors[:foo].first).to eq('Schema (foo) invalid: Fields Invalid type. Found String ("Baz"), ' \
                                                'expected IPaaS::Connector::Schema::Field.')
  end

  it 'validates schema code' do
    foo_tester = Class.new(DslTester) do
      schema :foo
    end.new
    foo_tester.foo do
      instance_eval('"Hello World!"', __FILE__, __LINE__)
    end
    expect(foo_tester).to be_invalid
    expect(foo_tester.errors[:foo].first).to eq("Schema (foo) invalid: Method 'instance_eval' not allowed.")
    # calling the invalid code for 100% coverage
    foo_tester.send(:_foo_blocks_by_reference).first.last.call
  end

  it 'allows local variables' do
    allow(SecureRandom).to receive(:uuid).and_return('uuid')
    foo_tester = Class.new(DslTester) do
      schema :foo
    end.new
    foo_tester.foo do
      integer = :integer
      field :bar, 'Bar', :nested do
        field :nr, 'Nr', integer
      end
    end
    expect(foo_tester).to be_valid
  end

  context 'schemas' do
    it 'allows to set schemas' do
      foo_tester = Class.new(DslTester) do
        schema :output_schema, array: true
      end.new
      foo_tester.output_schema('foo') do
        field :foo, 'foo', :integer
      end
      foo_tester.output_schema('bar') do
        field :bar, 'bar', :date
      end
      expect(foo_tester.output_schemas.size).to eq(2)
      expect(foo_tester.output_schemas.first.fields.first.id).to eq(:foo)
      expect(foo_tester.output_schemas.last.fields.first.id).to eq(:bar)
      expect(foo_tester.output_schema('foo').fields.first.id).to eq(:foo)
      expect(foo_tester.output_schema('bar').fields.first.id).to eq(:bar)
    end

    it 'allows default fields on a schema' do
      foo_tester = Class.new(DslTester) do
        schema :output_schema, array: true do
          field :baz, 'baz', :string
        end
      end.new
      foo_tester.output_schema('foo') do
        field :foo, 'foo', :integer
      end
      foo_tester.output_schema('bar') do
        field :bar, 'bar', :date
      end
      expect(foo_tester.output_schemas.size).to eq(2)
      expect(foo_tester.output_schemas.first.fields.first.id).to eq(:foo)
      expect(foo_tester.output_schemas.first.fields.last.id).to eq(:baz)
      expect(foo_tester.output_schemas.first.fields.last.label).to eq('baz')
      expect(foo_tester.output_schemas.last.fields.first.id).to eq(:bar)
      expect(foo_tester.output_schemas.last.fields.last.id).to eq(:baz)
      expect(foo_tester.output_schemas.last.fields.last.label).to eq('baz')
    end

    it 'validates all schemas' do
      foo_tester = Class.new(DslTester) do
        schema :output_schema, array: true
      end.new
      foo_tester.output_schema('foo') do
        field :foo, 'foo', :integer
      end
      foo_tester.output_schema('bar') do
        field :bar, nil, :date
      end
      expect(foo_tester).to be_invalid
      expected_msg = "Schema (bar) invalid: Field (bar) invalid: Label can't be blank."
      expect(foo_tester.errors[:output_schema].first).to eq(expected_msg)
    end

    it 'defines the plural accessor' do
      foo_tester = Class.new(DslTester) do
        schema :output_schema, array: true
      end.new
      foo_tester.output_schema('foo') do
        field :foo, 'foo', :integer
      end
      foo_tester.output_schema('bar') do
        field :bar, 'bar', :date
      end
      expect(foo_tester.output_schemas.size).to eq(2)
      expect(foo_tester.output_schemas.map(&:reference)).to eq(%w[foo bar])
    end

    it 'allows to redefine the schemas after the array was cleared' do
      foo_tester = Class.new(DslTester) do
        schema :output_schema, array: true
      end.new
      foo_tester.output_schema('foo') do
        field :foo, 'foo', :string
      end
      expect(foo_tester.output_schemas.size).to eq(1)
      expect(foo_tester.output_schemas.map(&:reference)).to eq(%w[foo])
      expect(foo_tester.output_schemas.first.fields.first.type).to eq(:string)

      expect do
        foo_tester.output_schema('foo') {}
      end.to raise_error(IPaaS::Error, 'Duplicate schema reference: foo.')

      foo_tester.output_schemas.clear
      expect(foo_tester.output_schemas.size).to eq(0)

      foo_tester.output_schema('foo') do
        field :foo, 'bar', :date
      end
      expect(foo_tester.output_schemas.size).to eq(1)
      expect(foo_tester.output_schemas.map(&:reference)).to eq(%w[foo])
      expect(foo_tester.output_schemas.first.fields.first.type).to eq(:date)
    end
  end

  context 'schema fields' do
    {
      array: true,
      default: 42,
      hint: 'It is a number',
      notice: 'This is important',
      notice_type: 'error',
      notice_action: 'edit_connection',
      sample: 33,
      visibility: 'optional',
      required: true,
      pattern: /\d+/,
      min: 12,
      max: 100,
      min_length: 1,
      max_length: 3,
      validator: ->(value) { value == 42 },
      enumeration: [{ id: 'a', label: 'Aha' }, { id: 'b', label: 'Abba' }],
    }.each do |property, value|
      it "should set field property #{property}" do
        foo_tester = Class.new(DslTester) do
          schema :foo
        end.new
        foo_tester.foo do
          field :bar, 'bar', :integer, property => value
        end
        property_value = foo_tester.foo.field(:bar).send(property)
        expect(property_value).to eq(value)
        expect(property_value.call(42)).to be_truthy if property == :validator # for 100% coverage
      end
    end

    it 'should allow array short-hand notation' do
      foo_tester = Class.new(DslTester) do
        schema :foo
      end.new
      foo_tester.foo do
        field :bar, 'bar', [:integer]
      end
      expect(foo_tester.foo.field(:bar).type).to eq(:integer)
      expect(foo_tester.foo.field(:bar).array).to be_truthy
    end

    it 'should allow for subfields' do
      foo_tester = Class.new(DslTester) do
        schema :foo
      end.new
      foo_tester.foo do
        field :bar, 'bar', :nested do
          field :sub, 'sub', :integer, hint: 'Sub field'
        end
      end
      expect(foo_tester.foo.field(:bar).field(:sub).type).to eq(:integer)
      expect(foo_tester.foo.field(:bar).field(:sub).hint).to eq('Sub field')
    end

    it 'should validate subfields' do
      foo_tester = Class.new(DslTester) do
        schema :foo
      end.new
      foo_tester.foo do
        field :bar, 'bar', :nested do
          field :sub, 'sub', :date, sample: 'Not an integer'
        end
      end
      expect(foo_tester).to be_invalid
      field_message = 'Field (bar) invalid: Field (sub) invalid: Sample Invalid type. Found String, expected Date.'
      expect(foo_tester.errors[:foo].first).to eq("Schema (#{foo_tester.foo.reference}) invalid: #{field_message}")
    end
  end

  context 'regenerate' do
    let(:foo_tester) do
      foo_tester = Class.new(DslTester) do
        schema :foo
      end.new
      foo_tester.foo do
        field @dynamic_field || :bar, 'bar', :integer
      end
      foo_tester
    end

    it 'does not regenerate the schema by default' do
      expect(foo_tester.foo.fields.first.id).to eq(:bar)
      expect(foo_tester.foo.fields.first.label).to eq('bar')
      expect(foo_tester.foo.fields.first.type).to eq(:integer)

      # change the value of @dynamic_field but schema is not regenerated, so the field remains :bar
      foo_tester.foo.instance_variable_set(:@dynamic_field, :updated)
      expect(foo_tester.foo.fields.first.id).to eq(:bar)
    end

    it 'does regenerate the schema when explicitly asked' do
      expect(foo_tester.foo.fields.first.id).to eq(:bar)
      expect(foo_tester.foo.fields.first.label).to eq('bar')
      expect(foo_tester.foo.fields.first.type).to eq(:integer)

      # change the value of @dynamic_field and schema is regenerated
      foo_tester.foo.instance_variable_set(:@dynamic_field, :updated)
      expect(foo_tester.regenerate_schema(foo_tester.foo)).to be_nil

      expect(foo_tester.foo.fields.first.id).to eq(:updated)
    end
  end
end
