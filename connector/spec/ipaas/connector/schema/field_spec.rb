require 'spec_helper'

describe IPaaS::Connector::Schema::Field do
  let(:field) do
    IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo label', type: :string)
  end

  describe 'attributes' do
    it 'should define the id attribute' do
      expect(field.id).to eq(:foo)
    end

    it 'should define the label attribute' do
      expect(field.label).to eq('Foo label')
    end

    it 'should define the disabled attribute' do
      expect(field.disabled).to be_falsey
      field.disabled = true
      expect(field.disabled).to be_truthy
    end

    it 'should define the type attribute' do
      expect(field.type).to eq(:string)
    end

    it 'should define the array attribute' do
      expect(field.array).to be_falsey
      field.array = true
      expect(field.array).to be_truthy
    end

    it 'should define the default attribute' do
      expect(field.default).to be_nil
      field.default = 'Bar'
      expect(field.default).to eq('Bar')
    end

    it 'should define the sample attribute' do
      expect(field.sample).to be_nil
      field.sample = 'Bar'
      expect(field.sample).to eq('Bar')
    end

    it 'should define the hint attribute' do
      expect(field.hint).to be_nil
      field.hint = 'Bar'
      expect(field.hint).to eq('Bar')
    end

    it 'should define the notice attribute' do
      expect(field.notice).to be_nil
      field.notice = 'Configure the connection first.'
      expect(field.notice).to eq('Configure the connection first.')
    end

    it 'should define the visibility attribute' do
      expect(field.visibility).to eq('visible')
      field.visibility = 'optional'
      expect(field.visibility).to eq('optional')
    end

    it 'should define the required attribute' do
      expect(field.required).to be_falsey
      field.required = true
      expect(field.required).to be_truthy
    end

    it 'should define the pattern attribute' do
      expect(field.pattern).to be_nil
      field.pattern = /\w+/
      expect(field.pattern).to eq(/\w+/)
    end

    it 'should define the min attribute' do
      expect(field.min).to be_nil
      field.min = 42
      expect(field.min).to eq(42)
    end

    it 'should define the max attribute' do
      expect(field.max).to be_nil
      field.max = 42
      expect(field.max).to eq(42)
    end

    it 'should define the min_length attribute' do
      expect(field.min_length).to be_nil
      field.min_length = 5
      expect(field.min_length).to eq(5)
    end

    it 'should define the max_length attribute' do
      expect(field.max_length).to be_nil
      field.max_length = 42
      expect(field.max_length).to eq(42)
    end

    it 'should define the enumeration attribute' do
      expect(field.enumeration).to be_nil
      field.enumeration = [{ id: 'foo', label: 'Foo' }, { id: 'bar', label: 'Bar' }]
      expect(field.enumeration.first[:label]).to eq('Foo')
    end

    it 'should define the fields' do
      expect(field.fields).to eq([])
      field.field :bar, 'Bar', :integer, required: true
      sub_field = field.field(:bar)
      expect(field.fields).to eq([sub_field])
      expect(sub_field).to be_an_instance_of(IPaaS::Connector::Schema::Field)
      expect(sub_field.type).to eq(:integer)
    end
  end

  context 'validation' do
    [:id, :label, :type].each do |attribute|
      it "should validate the :#{attribute} is required" do
        field.send(attribute, nil)
        expect(field).to be_invalid
        expect(field.errors[attribute]).to eq(["can't be blank."])
      end
    end

    it 'should validate the :id length' do
      field.id = :alongnamethatisoverfourtycharacterslongsothatthevalidationfails
      expect(field).to be_invalid
      expect(field.errors[:id]).to eq(['is too long (maximum is 40 characters)'])
    end

    it 'should validate the :label length' do
      field.label = 'a' * 125
      expect(field).to be_invalid
      expect(field.errors[:label]).to eq(['is too long (maximum is 120 characters)'])
    end

    [:default, :sample].each do |attribute|
      it "should validate the :#{attribute} type" do
        field.send(attribute, Date.today)
        expect(field).to be_invalid
        expect(field.errors[attribute]).to eq(['Invalid type. Found Date, expected String.'])
      end

      it "should validate the :#{attribute} type against integer enumerations" do
        field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo label', type: :integer)
        field.send(attribute, Date.today)
        expect(field).to be_invalid
        expect(field.errors[attribute]).to eq(['Invalid type. Found Date, expected Integer.'])
      end

      it "should validate the :#{attribute} type when it is an array" do
        field.array = true
        field.send(attribute, 'Foo')
        expect(field).to be_invalid
        expect(field.errors[attribute]).to eq(['Invalid type. Expected array.'])
      end

      it "should validate the :#{attribute} type values in an array" do
        field.type = :float
        field.array = true
        field.send(attribute, ['Foo', 42])
        expect(field).to be_invalid
        expect(field.errors[attribute]).to eq(['Invalid type. Found String ("Foo"), expected Float.'])
      end
    end

    context 'date_time field with string sample' do
      let(:date_time_field) do
        IPaaS::Connector::Schema::Field.new(id: :started_at, label: 'Started at', type: :date_time)
      end

      it 'coerces a string sample to DateTime' do
        date_time_field.sample = '2023-03-01T16:08:54.210Z'
        expect(date_time_field.sample).to be_a(DateTime)
        expect(date_time_field).to be_valid
      end

      it 'coerces a string default to DateTime' do
        date_time_field.default = '2023-03-01T16:08:54.210Z'
        expect(date_time_field.default).to be_a(DateTime)
        expect(date_time_field).to be_valid
      end
    end

    context 'visibility' do
      it 'should validate the visibility' do
        field.visibility = 'foo'
        expect(field).to be_invalid
        expect(field.errors[:visibility]).to eq(['is invalid.'])
      end

      it 'should ignore blank visibility' do
        field.visibility = ''
        expect(field).to be_valid
      end
    end

    context 'enumeration' do
      it 'should generate the enumeration from integers' do
        field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo label', type: :integer)
        field.enumeration = [1, 2, 3]
        expect(field).to be_valid
        expect(field.enumeration).to eq([{ id: 1, label: '1' }, { id: 2, label: '2' }, { id: 3, label: '3' }])
      end

      it 'should generate the enumeration from strings' do
        field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo label', type: :string)
        field.enumeration = %w[One Two Three]
        expect(field.enumeration).to eq([{ id: 'One', label: 'One' }, { id: 'Two', label: 'Two' },
                                         { id: 'Three', label: 'Three' },])
      end

      it 'should restrict enumerations to string and integer types' do
        field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo label', type: :float)
        field.enumeration = [{ id: 'a', label: 'A' }, { id: 'b', label: 'B' }]
        expect(field).to be_invalid
        expect(field.errors[:enumeration]).to eq(['Enumeration is restricted to string and integer types.'])
      end

      it 'should validate an id is present in each hash of the enumeration' do
        field.enumeration = [{ id: 'a', label: 'A' }, { id: '', label: 'B' }]
        expect(field).to be_invalid
        expect(field.errors[:enumeration]).to eq(['is invalid.'])
      end

      it 'should validate a label is present in each hash of the enumeration' do
        field.enumeration = [{ id: 'a', label: 'A' }, { id: 'b', label: '' }]
        expect(field).to be_invalid
        expect(field.errors[:enumeration]).to eq(['is invalid.'])
      end

      it 'should still validate each element in the enumeration when the first one is a Hash' do
        field.enumeration = [{ id: 'a', label: 'A' }, Date.current]
        expect(field).to be_invalid
        expect(field.errors[:enumeration]).to eq(["Invalid type. Found Date (#{Date.current.inspect}), expected Hash."])
      end

      it 'should not fail when empty enumeration is provided' do
        field.enumeration = []
        expect(field).to be_valid
      end

      it 'should not parse enumerations for fields that are of a different type' do
        field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo label', type: :date)
        field.enumeration = [Date.current]
        expect(field).not_to be_valid
        expect(field.errors[:enumeration]).to eq(["Invalid type. Found Date (#{Date.current.inspect}), expected Hash."])
      end
    end

    context 'type' do
      IPaaS::Connector::Types.all.each_key do |type|
        it "should accept :#{type} type" do
          field.type = type
          expect(field).to be_valid
        end
      end

      it 'should accept generic types, like any_item_type' do
        field.type = :any_item_type
        expect(field).to be_valid
      end

      it 'should fail for invalid types' do
        field.type = :any_item
        expect(field).to be_invalid
        error_msg = 'should be one of :any_..._type, :base64, :binary, :boolean, :date, :date_time, ' \
                    ':float, :hash, :integer, :job, :nested, :recurrence, :regexp, :ruby, ' \
                    ':runbook, :runbook_action, :runbook_variable, ' \
                    ':schema_field, :secret_string, :string, :time, :time_of_day, :time_zone, :uri.'
        expect(field.errors[:type]).to eq([error_msg])
      end
    end

    context 'subfields' do
      it 'should allow subfields when type is nested' do
        field.type = :nested
        field.field :bar, 'Bar', :integer, required: true
        expect(field).to be_valid
      end

      it 'should allow subfields when type definition is nested' do
        field.type = :schema_field
        field.field :bar, 'Bar', :integer, required: true
        expect(field).to be_valid
      end

      it 'should only allow subfields when type is nested' do
        field.type = :integer
        field.field :bar, 'Bar', :integer, required: true
        expect(field).to be_invalid
        expect(field.errors[:fields]).to eq(['Subfields are only available when the type is nested.'])
      end
    end
  end

  context 'pattern validation' do
    describe 'pattern=' do
      it 'converts string to Regexp object' do
        field.pattern = '[a-z]+'
        expect(field.pattern).to be_a(Regexp)
        expect(field.pattern.source).to eq('[a-z]+')
      end

      it 'adds error and keeps original value for invalid regexp string' do
        field.pattern = '[invalid'
        expect(field.errors[:pattern]).to include('Invalid regexp pattern: premature end of char-class: /[invalid/')
        expect(field.pattern).to eq('[invalid')
      end

      it 'leaves non-string values unchanged' do
        regexp = /\w+/
        field.pattern = regexp
        expect(field.pattern).to eq(regexp)
        expect(field.pattern).to be_a(Regexp)
      end

      it 'leaves empty strings unchanged' do
        field.pattern = ''
        expect(field.pattern).to eq('')
        expect(field.pattern).not_to be_a(Regexp)
      end

      it 'leaves nil values unchanged' do
        field.pattern = nil
        expect(field.pattern).to be_nil
      end
    end

    describe 'pattern_valid?' do
      it 'returns true when pattern is blank' do
        field.pattern = nil
        expect(field.pattern_valid?).to be true
        expect(field.errors[:pattern]).to be_empty
      end

      it 'returns true when pattern is empty string' do
        field.pattern = ''
        expect(field.pattern_valid?).to be true
        expect(field.errors[:pattern]).to be_empty
      end

      it 'compiles string patterns and returns true on success' do
        field.pattern = '[a-z]+'
        expect(field.pattern_valid?).to be true
        expect(field.errors[:pattern]).to be_empty
      end

      it 'returns true for valid Regexp objects' do
        field.pattern = /\w+/
        expect(field.pattern_valid?).to be true
        expect(field.errors[:pattern]).to be_empty
      end

      it 'adds errors and returns false for invalid regexp strings' do
        field.pattern = '[invalid'
        expect(field.pattern_valid?).to be false
        expect(field.errors[:pattern]).to include('Invalid regexp pattern: premature end of char-class: /[invalid/')
      end

      it 'adds errors and returns false for non-string/non-Regexp types' do
        field.pattern = 42
        expect(field.pattern_valid?).to be false
        expect(field.errors[:pattern]).to include('Pattern must be a string or Regexp, got Integer')
      end

      it 'adds errors and returns false for Date objects' do
        field.pattern = Date.today
        expect(field.pattern_valid?).to be false
        expect(field.errors[:pattern]).to include('Pattern must be a string or Regexp, got Date')
      end
    end
  end

  context 'recurrence' do
    let(:recurrence_field) do
      IPaaS::Connector::Schema::Field.new(id: :recurrence, label: 'Recurrence', type: :recurrence)
    end

    it 'should return nested fields' do
      expect(recurrence_field.fields.size).to be > 5
      expect(recurrence_field.fields.map(&:id)).to include(:frequency, :interval, :day, :time_of_day)
    end
  end

  describe 'type_def' do
    it 'returns the type class of the field 1' do
      expect(field.type_def).to eq(IPaaS::Connector::Types::StringType)
    end

    it 'returns the type class of the field 2' do
      field.type = :secret_string
      expect(field.type_def).to eq(IPaaS::Connector::Types::SecretStringType)
    end

    it 'falls back to AnyType' do
      field.type = :foobar
      expect(field.type_def).to eq(IPaaS::Connector::Types::AnyType)
    end
  end

  describe 'example' do
    it 'should provide an example' do
      expect(field.example).to eq('Hello World!')
    end

    it 'should prefer the sample' do
      field.sample = 'Hello Moon!'
      field.default = '---'
      expect(field.example).to eq('Hello Moon!')
    end

    it 'should fallback to the default' do
      field.sample = nil
      field.default = '---'
      expect(field.example).to eq('---')
    end

    it 'should respond differently when a pattern is set' do
      field.pattern = /foo/
      expect(field.example).to eq('no-example-for-pattern')
    end

    it 'should provide an example as an array' do
      field.array = true
      expect(field.example).to eq(['Hello World!'])
    end

    it 'should provide an example for deeply nested nested fields' do
      field.array = true
      field.type = :nested
      field.field :foo, 'Foo', :nested do
        field :bar, 'Bar', :integer
      end
      expect(field.example).to eq([{ foo: { bar: 42 } }])
    end

    it 'should provide an example for nested primitive fields' do
      field.type = :recurrence
      expect(field.example[:day]).to eq(%w[monday thursday])
      expect(field.example[:day_of_month]).to eq([1, 16, -1])
      expect(field.example[:disabled]).to eq(false)
      expect(field.example[:frequency]).to eq('monthly')
    end

    {
      string: 'Hello World!',
      binary: 'Hello World!',
      base64: Base64.strict_encode64('Hello World!'),
      integer: 42,
      float: 3.14159265359,
      boolean: true,
      hash: { foo: 'bar' },
      uri: 'https://xurrent.com',
      date: Date.current,
      time: IPaaS.use_time_zone('central_time') { Time.now.in_time_zone.change(hour: 12, min: 0) },
      date_time: IPaaS.use_time_zone('central_time') { DateTime.now.in_time_zone.change(hour: 12, min: 0) },
      time_zone: 'central_time',
    }.each_pair do |type, example|
      it "should return #{example.inspect} for the :#{type} type" do
        field.type = type
        expect(field.example).to eq(example)
      end
    end
  end

  describe 'hash' do
    let(:field) do
      described_class.new(
        id: :name,
        type: :string,
        array: false,
        label: 'Name'
      )
    end

    it 'returns the same hash for equal fields' do
      field2 = described_class.new(
        id: :name,
        type: :string,
        array: false,
        label: 'Different Label' # shouldn't affect hash
      )

      expect(field.hash).to eq(field2.hash)
    end

    it 'returns different hash when id differs' do
      field2 = field.deep_dup.tap { |f| f.id = :email }
      expect(field.hash).not_to eq(field2.hash)
    end

    it 'returns different hash when type differs' do
      field2 = field.deep_dup.tap { |f| f.type = :integer }
      expect(field.hash).not_to eq(field2.hash)
    end

    it 'returns different hash when array differs' do
      field2 = field.deep_dup.tap { |f| f.array = true }
      expect(field.hash).not_to eq(field2.hash)
    end

    context 'with nested fields' do
      let(:nested_field) do
        described_class.new(
          id: :address,
          type: :nested,
          array: false,
          label: 'Address',
          fields: [
            described_class.new(id: :street, type: :string, label: 'Street'),
          ]
        )
      end

      it 'returns the same hash for equal nested structures' do
        field2 = nested_field.deep_dup
        expect(nested_field.hash).to eq(field2.hash)
      end

      it 'returns different hash when nested fields differ' do
        field2 = nested_field.deep_dup
        field2.fields.first.type = :integer
        expect(nested_field.hash).not_to eq(field2.hash)
      end

      it 'prevent stack level too deep error for "fields" field' do
        nested_field.id = :fields
        nested_field.fields = [nested_field]
        expect(nested_field.hash).not_to be_nil
      end
    end
  end

  context 'to_h_ref' do
    it 'should define to_h_ref for non-nested field' do
      attrs = {
        id: :foo,
        label: 'Foo label',
        type: :string,
        disabled: false,
        array: true,
        default: 'Foo default',
        sample: 'X',
        hint: 'No hint',
        visibility: 'hidden',
        required: true,
        pattern: /[a-z]*/,
        min: 'a',
        max: 'z',
        min_length: 3,
        max_length: 42,
        enumeration: [{ id: 'a', label: 'Aha' }, { id: 'b', label: 'Abba' }],
      }

      field = IPaaS::Connector::Schema::Field.new(attrs)
      expect(field.to_h_ref).to eq(attrs)
    end

    it 'should define to_h_ref for nested field, omitting remove_unmapped_fields when true (the default)' do
      field_attrs = { id: :street, type: :string, label: 'Street' }
      attrs = {
        id: :address,
        label: 'Address',
        type: :nested,
        remove_unmapped_fields: true,
        array: false,
        fields: [described_class.new(field_attrs)],
      }

      nested_field = IPaaS::Connector::Schema::Field.new(attrs)
      expect(nested_field.to_h_ref).to eq(attrs.except(:fields, :remove_unmapped_fields).merge(fields: [field_attrs]))
    end

    it 'should include remove_unmapped_fields in to_h_ref when false' do
      field_attrs = { id: :street, type: :string, label: 'Street' }
      attrs = {
        id: :address,
        label: 'Address',
        type: :nested,
        remove_unmapped_fields: false,
        array: false,
        fields: [described_class.new(field_attrs)],
      }

      nested_field = IPaaS::Connector::Schema::Field.new(attrs)
      expect(nested_field.to_h_ref).to eq(attrs.except(:fields).merge(fields: [field_attrs]))
    end

    it 'should not include type schema fields for date_time field' do
      field = described_class.new(id: :created_at, label: 'Created at', type: :date_time)
      result = field.to_h_ref
      expect(result).to eq(id: :created_at, label: 'Created at', type: :date_time)
      expect(result).not_to have_key(:fields)
    end
  end

  describe 'eql?' do
    let(:field) do
      described_class.new(
        id: :name,
        type: :string,
        array: false,
        label: 'Name'
      )
    end

    it 'is an alias of ==' do
      expect(field.method(:eql?)).to eq(field.method(:==))
    end

    it 'returns true for the same object' do
      expect(field.eql?(field)).to be true
    end

    it 'returns true for equal fields' do
      field2 = described_class.new(
        id: :name,
        type: :string,
        array: false,
        label: 'Different Label' # shouldn't affect equality
      )

      expect(field.eql?(field2)).to be true
    end

    it 'is not the same as equal?' do
      field2 = described_class.new(
        id: :name,
        type: :string,
        array: false,
      )

      expect(field.equal?(field2)).to be false
      expect(field.eql?(field2)).to be true
    end

    it 'returns false for different class' do
      expect(field.eql?(double(id: :name, type: :string, array: false))).to be false
    end

    it 'returns false when id differs' do
      field2 = field.deep_dup.tap { |f| f.id = :email }
      expect(field.eql?(field2)).to be false
    end

    it 'returns false when type differs' do
      field2 = field.deep_dup.tap { |f| f.type = :integer }
      expect(field.eql?(field2)).to be false
    end

    it 'returns false when array differs' do
      field2 = field.deep_dup.tap { |f| f.array = true }
      expect(field.eql?(field2)).to be false
    end

    context 'with nested fields' do
      let(:nested_field) do
        described_class.new(
          id: :address,
          type: :nested,
          array: false,
          label: 'Address',
          fields: [
            described_class.new(id: :street, type: :string, label: 'Street'),
          ]
        )
      end

      it 'returns true for equal nested structures' do
        field2 = nested_field.deep_dup
        expect(nested_field.eql?(field2)).to be true
      end

      it 'returns false when nested fields differ' do
        field2 = nested_field.deep_dup
        field2.fields.first.type = :integer
        expect(nested_field.eql?(field2)).to be false
      end

      it 'returns false when one has nested fields and other does not' do
        field2 = nested_field.deep_dup
        field2.fields = nil
        expect(nested_field.eql?(field2)).to be false
      end

      it 'returns true when both have no nested fields' do
        field1 = described_class.new(id: :name, type: :string, label: 'Name')
        field2 = described_class.new(id: :name, type: :string, label: 'Name')
        expect(field1.eql?(field2)).to be true
      end
    end

    context 'when used with Array#uniq' do
      it 'removes duplicate fields' do
        field2 = field.deep_dup
        array = [field, field2]
        expect(array.uniq.length).to eq(1)
      end

      it 'keeps different fields' do
        field2 = field.deep_dup.tap { |f| f.id = :email }
        array = [field, field2]
        expect(array.uniq.length).to eq(2)
      end
    end
  end
end
