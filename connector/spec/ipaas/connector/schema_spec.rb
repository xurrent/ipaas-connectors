require 'spec_helper'

describe IPaaS::Connector::Schema do
  let(:schema) do
    schema_with_connector('reference')
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

  describe 'field_definition' do
    # A partly unresolved schema leaves nils and UnresolvedNodes among the fields. Five presenters
    # and the YAML helper look fields up through here, so a hole must answer nil, not raise.
    let(:unresolved) { IPaaS::Connector::Common::UnresolvedNode.new(String, 'unresolved') }

    before(:each) do
      schema.field :space_id, 'Space', :string
      schema.fields = [nil, unresolved, *schema.fields]
    end

    it 'finds a field past a nil hole and an unresolved node' do
      expect(schema.field_definition(:space_id).label).to eq('Space')
    end

    it 'answers nil for an id no field carries, rather than raising on the holes' do
      expect(schema.field_definition(:nope)).to be_nil
    end

    it 'answers nil when the schema has no fields at all' do
      schema.fields = nil

      expect(schema.field_definition(:space_id)).to be_nil
    end
  end

  describe 'option dependencies' do
    before(:each) do
      skip_function_capture_validation
    end

    it 'accepts an options block whose keywords name sibling fields' do
      schema.field :space_id, 'Space', :string
      schema.field :list_id, 'List', :string do
        options { |space_id:| [space_id] }
      end

      expect(schema).to be_valid
    end

    it 'rejects an options block whose keyword names no sibling field' do
      schema.field :space_id, 'Space', :string
      schema.field :list_id, 'List', :string do
        options { |space_ids:| [space_ids] }
      end

      expect(schema).not_to be_valid
      expect(schema.errors[:base]).to include('Field (list_id) options depend on unknown field(s): space_ids')
    end

    it 'rejects an options block whose dependency is missing its colon' do
      schema.field :space_id, 'Space', :string
      schema.field :list_id, 'List', :string do
        options { |space_id| [space_id] }
      end

      expect(schema).not_to be_valid
      expect(schema.errors[:base].join).to include(
        'Field (list_id) invalid: Options must declare every dependency as a keyword parameter'
      )
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

    it 'should skip non-field entries instead of raising' do
      schema.field :foo, 'Foo', :string, required: true
      schema.fields << 'stray_string'
      expect(schema.example).to eq({ foo: 'Hello World!' })
      expect(schema.example.size).to eq(1)
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

    it 'should report an after_update failure raised on a later pass' do
      after_update = ->(fields, values) {
        raise 'bar was revealed' if values.key?(:bar) # only once a later pass has revealed bar

        fields.detect { |f| f.id == :bar }.disabled(false)
        fields
      }
      schema.field :foo, 'Foo', :string
      schema.field :bar, 'Bar', :string, disabled: true
      schema.after_update(&after_update)

      resolved = schema.resolve(Object.new, [
        { field_id: 'foo', fixed: 'Hello World!' },
        { field_id: 'bar', fixed: 'Hello Moon!' },
      ])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include('bar was revealed')
    end

    it 'should report an after_update that never settles within the pass bound' do
      after_update = ->(fields, _values) {
        fields.detect(&:disabled)&.disabled(false)
        fields
      }
      ladder = (0..(IPaaS::Connector::Schema::MAX_AFTER_UPDATE_PASSES + 2)).to_a
      ladder.each { |i| schema.field :"foo#{i}", "Foo #{i}", :string, disabled: i.positive? }
      schema.after_update(&after_update)

      resolved = schema.resolve(Object.new, ladder.map { |i| { field_id: "foo#{i}", fixed: "v#{i}" } })
      expect(resolved).not_to be_valid
      expect(resolved.base_error).to be_a(IPaaS::Connector::Schema::UnsettledAfterUpdate)
      expect(resolved.errors[:base].join).to match(/never settled/)
    end

    it 'should not report a shallow after_update that settles within the pass bound' do
      after_update = ->(fields, _values) {
        fields.detect(&:disabled)&.disabled(false)
        fields
      }
      ladder = (0..2).to_a
      ladder.each { |i| schema.field :"foo#{i}", "Foo #{i}", :string, disabled: i.positive? }
      schema.after_update(&after_update)

      resolved = schema.resolve(Object.new, ladder.map { |i| { field_id: "foo#{i}", fixed: "v#{i}" } })
      expect(resolved).to be_valid
      expect(resolved.keys.size).to eq(ladder.size)
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
      duped = schema.deep_dup

      expect(duped.object_id).not_to eq(schema.object_id)
      expect(duped.reference).to eq(schema.reference)
      expect(duped.name).to eq(schema.name)
      expect(duped.fields.first.id).to eq(:foo)
      expect(duped.connector).to be(spec_connector)
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

  describe 'declares_secret_string?' do
    def field(id, type, fields: nil, array: false)
      IPaaS::Connector::Schema::Field.new(id: id, label: id.to_s, type: type, fields: fields, array: array)
    end

    def schema_with(fields)
      IPaaS::Connector::Schema.new('output').tap { |schema| schema.fields = fields }
    end

    it 'is true for a secret_string at the top level' do
      expect(schema_with([field(:token, :secret_string)]).declares_secret_string?).to be(true)
    end

    it 'is true for a secret_string below a nested field' do
      inner = [field(:token, :secret_string)]

      expect(schema_with([field(:creds, :nested, fields: inner)]).declares_secret_string?).to be(true)
    end

    it 'is true for a secret_string two nested levels down' do
      inner = [field(:token, :secret_string)]
      middle = [field(:creds, :nested, fields: inner)]

      expect(schema_with([field(:org, :nested, fields: middle)]).declares_secret_string?).to be(true)
    end

    it 'ignores a nil entry among the fields' do
      expect(schema_with([nil, field(:token, :secret_string)]).declares_secret_string?).to be(true)
    end

    it 'is false when no field anywhere declares a secret_string' do
      inner = [field(:name, :string)]

      expect(schema_with([field(:org, :nested, fields: inner)]).declares_secret_string?).to be(false)
    end

    it 'is false for a schema with no fields' do
      expect(schema_with(nil).declares_secret_string?).to be(false)
    end

    it 'is false for a self-referential schema_field rather than recursing forever' do
      expect(schema_with([field(:payload, :schema_field)]).declares_secret_string?).to be(false)
    end

    it 'is false for a schema_field below a nested field' do
      inner = [field(:payload, :schema_field)]

      expect(schema_with([field(:results, :nested, fields: inner)]).declares_secret_string?).to be(false)
    end

    it 'never descends into the sub-schema of a type other than nested' do
      IPaaS::Connector::Types.all.each_key do |type|
        next if [:nested, :secret_string].include?(type)

        schema = schema_with([field(:wrapper, type)])

        expect(schema.declares_secret_string?).to be(false), "#{type} descended into its sub-schema"
      end
    end
  end
end
