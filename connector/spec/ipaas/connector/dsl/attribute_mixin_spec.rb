require 'spec_helper'

describe IPaaS::Connector::Dsl::AttributeMixin do
  it 'allows single attribute' do
    foo_tester = Class.new(DslTester) do
      attribute :foo
    end.new
    foo_tester.foo 'bar'
    expect(foo_tester.foo).to eq('bar')
  end

  it 'accepts a default value' do
    foo_tester = Class.new(DslTester) do
      attribute :foo, default: 'bar'
    end.new
    expect(foo_tester.foo).to eq('bar')

    foo_tester.foo = nil
    expect(foo_tester.foo).to be_nil

    foo_tester.foo = 'baz'
    expect(foo_tester.foo).to eq('baz')
  end

  it 'validates presence if required' do
    foo_tester = Class.new(DslTester) do
      attribute :foo, required: true
    end.new
    expect(foo_tester).not_to be_valid
    expect(foo_tester.errors[:foo].first).to eq("can't be blank.")

    foo_tester.foo 'bar'
    expect(foo_tester).to be_valid
  end

  it 'validates the type' do
    foo_tester = Class.new(DslTester) do
      attribute :foo
    end.new
    foo_tester.foo :bar
    expect(foo_tester).not_to be_valid
    expect(foo_tester.errors[:foo].first).to eq('Invalid type. Found Symbol, expected String.')

    foo_tester.foo 'bar'
    expect(foo_tester).to be_valid
  end

  it 'validates array type' do
    foo_tester = Class.new(DslTester) do
      attribute :foo, type: [Integer]
    end.new
    foo_tester.foo 1
    expect(foo_tester).not_to be_valid
    expect(foo_tester.errors[:foo].first).to eq('Invalid type. Expected array.')

    foo_tester.foo [1]
    expect(foo_tester).to be_valid

    foo_tester.foo ['Bar', 1, :baz]
    expect(foo_tester).not_to be_valid
    expect(foo_tester.errors[:foo].first).to eq('Invalid type. Found String ("Bar"), expected Integer.')
    expect(foo_tester.errors[:foo].second).to eq('Invalid type. Found Symbol (:baz), expected Integer.')

    foo_tester.foo []
    expect(foo_tester).to be_valid
  end

  describe 'using type_def to validate' do
    it 'validates the type' do
      foo_tester = Class.new(DslTester) do
        def type_def
          IPaaS::Connector::Types::DateTimeType
        end

        attribute :foo, type: DateTime
      end.new
      foo_tester.foo Time.now
      expect(foo_tester).to be_valid

      foo_tester.foo DateTime.now
      expect(foo_tester).to be_valid

      foo_tester.foo 'bar'
      expect(foo_tester).not_to be_valid

      foo_tester.foo '2016-01-01T00:00:00.000Z'
      expect(foo_tester).to be_valid
    end

    it 'returns invalid without raising when type_def.resolve raises (e.g. invalid calendar date)' do
      foo_tester = Class.new(DslTester) do
        def type_def
          IPaaS::Connector::Types::DateTimeType
        end

        attribute :foo, type: DateTime
      end.new
      # "2024-02-30T10:00:00Z" matches DATE_TIME_PATTERN but Feb 30 does not exist —
      # DateTimeType.resolve raises Date::Error; try_resolve should rescue and return nil.
      expect { foo_tester.foo '2024-02-30T10:00:00Z' }.not_to raise_error
      expect(foo_tester).not_to be_valid
    end

    it 'validates array type' do
      foo_tester = Class.new(DslTester) do
        def type_def
          IPaaS::Connector::Types::DateTimeType
        end

        attribute :foo, type: [DateTime]
      end.new
      foo_tester.foo DateTime.now
      expect(foo_tester).not_to be_valid
      expect(foo_tester.errors[:foo].first).to eq('Invalid type. Expected array.')

      foo_tester.foo [Time.now, DateTime.now]
      expect(foo_tester).to be_valid

      foo_tester.foo ['Bar', DateTime.now, :baz]
      expect(foo_tester).not_to be_valid
      expect(foo_tester.errors[:foo].first).to eq('Invalid type. Found String ("Bar"), expected DateTime.')
      expect(foo_tester.errors[:foo].second).to eq('Invalid type. Found Symbol (:baz), expected DateTime.')

      foo_tester.foo []
      expect(foo_tester).to be_valid
    end
  end

  it 'validates dynamic type' do
    foo_tester = Class.new(DslTester) do
      attribute :custom_type, type: Class
      attribute :foo, type: -> { custom_type }
    end.new
    foo_tester.custom_type Date
    foo_tester.foo 1
    expect(foo_tester).not_to be_valid
    expect(foo_tester.errors[:foo].first).to eq('Invalid type. Found Integer, expected Date.')

    foo_tester.custom_type Integer
    expect(foo_tester).to be_valid
  end

  it 'validates the format' do
    foo_tester = Class.new(DslTester) do
      attribute :foo, format: { with: /\A[ab]+\z/ }
    end.new
    foo_tester.foo 'bar'
    expect(foo_tester).not_to be_valid
    expect(foo_tester.errors[:foo].first).to eq('is invalid.')

    foo_tester.foo 'baba'
    expect(foo_tester).to be_valid
  end

  it 'validates the length' do
    foo_tester = Class.new(DslTester) do
      attribute :foo, length: { in: 6..10 }
    end.new
    foo_tester.foo 'bar'
    expect(foo_tester).not_to be_valid
    expect(foo_tester.errors[:foo].first).to eq('is too short (minimum is 6 characters)')

    foo_tester.foo 'bar bar'
    expect(foo_tester).to be_valid

    foo_tester.foo 'rhubarb stew'
    expect(foo_tester).not_to be_valid
    expect(foo_tester.errors[:foo].first).to eq('is too long (maximum is 10 characters)')
  end

  it 'should keep track of the attributes' do
    foo_tester = Class.new(DslTester) do
      attribute :foo
      attribute :bar
      attribute :baz
    end.new
    foo_tester.foo 'foo value'
    foo_tester.bar 'bar value'
    expect(foo_tester.class.attribute_names).to eq([:foo, :bar, :baz])
    expect(foo_tester.attributes).to eq({ foo: 'foo value', bar: 'bar value', baz: nil })
  end

  it 'should mass assign attributes' do
    foo_tester = Class.new(DslTester) do
      attribute :foo
      attribute :bar
      attribute :baz
    end.new
    foo_tester.attributes = { foo: 'foo value', bar: 'bar value' }
    expect(foo_tester.attributes).to eq({ foo: 'foo value', bar: 'bar value', baz: nil })
  end

  it 'should mass assign function attributes' do
    skip_function_capture_validation

    foo_tester = Class.new(DslTester) do
      function :foo
    end.new
    foo_tester.attributes = { foo: -> { 'foo value' } }
    expect(foo_tester.foo.call).to eq('foo value')
  end

  it 'should allow nested attributes' do
    foo_tester = Class.new(DslTester) do
      attribute :foo
      attribute :bar
    end.new
    bar_tester = Class.new(DslTester) do
      attribute :barbie
      attribute :ken
    end.new
    foo_tester.foo 'Foo'
    bar_tester.barbie 'Barbie'
    bar_tester.ken 'Ken'
    foo_tester.bar bar_tester
    expect(foo_tester.attributes).to eq({ foo: 'Foo', bar: { barbie: 'Barbie', ken: 'Ken' } })
  end

  it 'should define to_json' do
    foo_tester = Class.new(DslTester) do
      attribute :foo
      attribute :bar
    end.new
    foo_tester.foo 'foo value'
    foo_tester.bar 'bar value'
    expect(foo_tester.to_json).to eq({ foo: 'foo value', bar: 'bar value' }.to_json)
  end
end
