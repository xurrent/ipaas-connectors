require 'spec_helper'

describe IPaaS::Connector::Schema do
  let(:schema) do
    IPaaS::Connector::Schema.new('reference')
  end

  describe 'attributes' do
    it 'should define a name' do
      schema.name 'foo'
      expect(schema.name).to eq('foo')
    end
  end

  describe 'fields' do
    it 'should define the fields' do
      expect(schema.fields).to eq([])
      schema.field :foo, 'Foo', :string, required: true
      foo_field = schema.field(:foo)
      expect(schema.fields).to eq([foo_field])
      expect(foo_field).to be_an_instance_of(IPaaS::Connector::Schema::Field)
      expect(foo_field.type).to eq(:string)
    end
  end

  describe 'functions' do
    before(:each) do
      skip_function_capture_validation
    end

    [:after_update].each do |function_name|
      it "should define the #{function_name} function" do
        schema = IPaaS::Connector::Schema.new('reference')
        expect(schema.send(function_name)).to be_nil
        schema.send(function_name) do
          'Hello World!'
        end
        expect(schema.send(function_name).call).to eq('Hello World!')
      end
    end
  end

  describe 'function context' do
    it 'should reference the connector' do
      load_minimal_fixture
      expect(@trigger.config_schema.connector.uuid).to eq(@connector.uuid)
    end

    it 'should reference the trigger (template)' do
      load_minimal_fixture
      expect(@trigger.config_schema.trigger.uuid).to eq(@trigger.uuid)
    end
  end

  describe 'example' do
    it 'should provide an empty hash when no fields are defined' do
      expect(schema.example).to eq({})
    end

    it 'should provide an example of the given fields' do
      expect(schema.example).to eq({})
      schema.field :foo, 'Foo', :string, required: true
      schema.field :bar, 'Bar', :integer
      expect(schema.example).to eq({ foo: 'Hello World!', bar: 42 })
    end

    it 'should provide an example with nested fields' do
      expect(schema.example).to eq({})
      schema.field :foo, 'Foo', :nested do
        field :bar, 'Bar', :integer
      end
      expect(schema.example).to eq({ foo: { bar: 42 } })
    end
  end

  describe 'resolve' do
    before(:each) do
      skip_function_capture_validation
    end

    it 'should resolve the schema' do
      schema.field :foo, 'Foo', :string
      values = schema.resolve(Object.new, [{ field_id: 'foo', fixed: 'Hello World!' }])
      expect(values).to eq({ 'foo' => 'Hello World!' })
    end

    it 'should execute after_update code' do
      after_update = ->(fields, values) {
        fields.detect { |f| f.id == :bar }.disabled(values[:foo] == 'Nope')
        fields
      }
      schema.field :foo, 'Foo', :string
      schema.field :bar, 'Bar', :string
      schema.after_update(&after_update)

      values = schema.resolve(Object.new, [
        { field_id: 'foo', fixed: 'Hello World!' },
        { field_id: 'bar', fixed: 'Hello Moon!' },
      ])
      expect(values).to eq({ 'foo' => 'Hello World!', 'bar' => 'Hello Moon!' })

      values = schema.resolve(Object.new, [
        { field_id: 'foo', fixed: 'Nope' },
        { field_id: 'bar', fixed: 'Hello Moon!' },
      ])
      expect(values).to eq({ 'foo' => 'Nope' })
    end

    it 'should call the block each time the intermediary values as they are resolved' do
      after_update = ->(fields, values) {
        fields.detect { |f| f.id == :bar }.disabled(values[:foo] == 'Nope')
        fields
      }
      schema.field :foo, 'Foo', :string
      schema.field :bar, 'Bar', :string
      schema.after_update(&after_update)

      @values = []
      schema.resolve(Object.new, [
        { field_id: 'foo', fixed: 'Nope' },
        { field_id: 'bar', fixed: 'Hello Moon!' },
      ]) do |values|
        @values << values
      end
      expect(@values.first).to eq({ 'foo' => 'Nope', 'bar' => 'Hello Moon!' })
      expect(@values.last).to eq({ 'foo' => 'Nope' })
    end

    it 'should return an invalid mapping when after_update code fails during execution' do
      after_update = ->(_fields, _values) {
        'foo'.after_update # error
      }
      schema.field :foo, 'Foo', :string
      schema.after_update(&after_update)

      resolved = schema.resolve(Object.new, [{ field_id: 'foo', fixed: 'Hello World!' }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include(%(undefined method 'after_update' for an instance of String))
      expect(schema.instance_variable_get(:@resolving)).to be_falsey
    end

    context 'when resolve raises (regression: @resolving latch must not leak)' do
      it 'restores @resolving when resolved_mapping raises on a non-Hash field_mapping' do
        schema.field :foo, 'Foo', :string

        expect { schema.resolve(Object.new, 'not a hash') }
          .to raise_error(IPaaS::Error, 'Field mapping must be a hash.')
        expect(schema.instance_variable_get(:@resolving)).to be_falsey
      end

      it 'still runs after_update on subsequent resolves after a parse failure' do
        after_update = ->(fields, values) {
          fields.detect { |f| f.id == :bar }.disabled(values[:foo] == 'Nope')
          fields
        }
        schema.field :foo, 'Foo', :string
        schema.field :bar, 'Bar', :string
        schema.after_update(&after_update)

        expect { schema.resolve(Object.new, 'not a hash') }.to raise_error(IPaaS::Error)

        values = schema.resolve(Object.new, [
          { field_id: 'foo', fixed: 'Nope' },
          { field_id: 'bar', fixed: 'Hello Moon!' },
        ])
        expect(schema.field(:bar).disabled).to be_truthy
        expect(values).to eq({ 'foo' => 'Nope' })
      end

      it 'preserves an outer @resolving=true across a nested resolve' do
        schema.field :foo, 'Foo', :string
        schema.instance_variable_set(:@resolving, true)

        schema.resolve(Object.new, [{ field_id: 'foo', fixed: 'Hello World!' }])

        expect(schema.instance_variable_get(:@resolving)).to be(true)
      end
    end
  end

  describe 'inspect' do
    it 'should show the name, reference and field ids' do
      schema.name = 'Barry'
      schema.field :foo, 'Foo', :string, required: true
      expect(schema.inspect).to eq("Schema 'Barry' (reference) - [:foo]")
    end

    it 'should work with minimal example' do
      expect(schema.inspect).to eq('Schema (reference) - []')
    end
  end

  describe 'deep_dup' do
    it 'should duplicate the attributes' do
      schema.name 'Bar'
      schema.field :foo, 'Foo', :string
      schema.connector = 'Connector'
      duped = schema.deep_dup

      expect(duped.object_id).not_to eq(schema.object_id)
      expect(duped.reference).to eq(schema.reference)
      expect(duped.name).to eq(schema.name)
      expect(duped.fields.first.id).to eq(:foo)
      expect(duped.connector).to eq('Connector')
    end
  end

  describe 'includes' do
    it 'should include valid schema extensions' do
      module FooFieldExtension
        include IPaaS::Connector::Schema::Extension

        schema do
          field :included_foo, 'Included Foo', :string
        end
      end
      schema.includes(FooFieldExtension)
      expect(schema.fields.last.id).to eq(:included_foo)
      expect(schema.fields.last.label).to eq('Included Foo')
      expect(schema.fields.last.type).to eq(:string)
    end

    it 'should complain when includes is called with incorrect module' do
      expect do
        schema.includes(IPaaS)
      end.to raise_error('Schema extension IPaaS must include IPaaS::Connector::Schema::Extension.')
    end
  end
end
