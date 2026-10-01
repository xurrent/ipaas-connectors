require 'spec_helper'

describe IPaaS::Connector::Schema::Field do
  let(:field) do
    owned_field(id: :foo, label: 'Foo label', type: :string)
  end

  def owned_field(**attributes)
    owned_by_spec_connector(IPaaS::Connector::Schema::Field.new(**attributes))
  end

  # A block built inside a method so its binding holds no locals: the options function rejects
  # blocks that capture them.
  def no_dependencies = -> { [] }
  def one_required = ->(workspace_id:) { [workspace_id] }
  def required_and_optional = ->(space_id:, folder_id: nil) { [space_id, folder_id] }
  # `options do |x| end` is a proc, not a lambda, so a missing colon binds nil instead of raising.
  # The proc form is what a connector actually ships, so the rejected shapes are built that way.
  def positional_dependency = proc { |space_id| [space_id] }
  def keyword_catch_all = proc { |**dependencies| [dependencies] }
  def block_parameter = proc { |&callback| [callback] }

  describe 'option_dependencies' do
    it 'is empty when the field declares no options function at all' do
      expect(field.option_dependencies).to eq([])
    end

    it 'is empty when the options block takes no keywords' do
      field.options(&no_dependencies)

      expect(field.option_dependencies).to eq([])
    end

    it 'reads a required keyword off the block' do
      field.options(&one_required)

      expect(field.option_dependencies).to eq([:workspace_id])
    end

    it 'reports an optional keyword as a dependency too' do
      field.options(&required_and_optional)

      expect(field.option_dependencies).to eq([:space_id, :folder_id])
    end
  end

  describe 'required_option_dependencies' do
    it 'is empty when the field declares no options function at all' do
      expect(field.required_option_dependencies).to eq([])
    end

    it 'is empty when the options block takes no keywords' do
      field.options(&no_dependencies)

      expect(field.required_option_dependencies).to eq([])
    end

    it 'reads a keyword written without a default' do
      field.options(&one_required)

      expect(field.required_option_dependencies).to eq([:workspace_id])
    end

    it 'leaves out a keyword that carries a default, because the block can run without it' do
      field.options(&required_and_optional)

      expect(field.required_option_dependencies).to eq([:space_id])
    end
  end

  # An options block and an enumeration build the same control from the same three types, so a
  # block on any other type would replace that type's own editor with a string picker.
  describe 'options on a type that cannot hold a picked id' do
    # Built in a method so the lambda's binding holds no locals; the options function rejects a
    # block that captures them.
    def picker_options
      -> { ['one'] }
    end

    def field_with_options(type)
      field = owned_field(id: :picker, label: 'Picker', type: type)
      field.options(&picker_options)
      field
    end

    IPaaS::Connector::Schema::Field::ENUMERABLE_TYPES.each do |type|
      it "accepts an options block on a #{type} field" do
        expect(field_with_options(type)).to be_valid
      end
    end

    [:hash, :date, :boolean, :binary].each do |type|
      it "rejects an options block on a #{type} field, as an enumeration already is" do
        field = field_with_options(type)

        expect(field).to be_invalid
        expect(field.errors[:options].join).to include('string, integer, and time zone')
      end
    end
  end

  describe 'options on a field inside an array' do
    # dependency_values carries one value per sibling id, so it cannot say "row 3's space_id".
    # A field under an array has no addressable dependencies, so the endpoint could never serve it.
    let(:array_nesting_error) { 'cannot provide dynamic options inside an array field' }

    def array_field_with(child)
      IPaaS::Connector::Schema::Field.new(id: :rows, label: 'Rows', type: :nested, array: true)
                                     .tap { |parent| parent.fields = [child] }
    end

    def child_with_options
      owned_field(id: :list_id, label: 'List', type: :string)
        .tap { |child| child.options(&no_dependencies) }
    end

    def child_without_options
      IPaaS::Connector::Schema::Field.new(id: :list_id, label: 'List', type: :string)
    end

    it 'rejects an options block on a field nested inside an array field' do
      parent = array_field_with(child_with_options)
      parent.valid?

      expect(parent.errors[:fields].join).to include("#{array_nesting_error}, so list_id")
    end

    it 'accepts the same nesting when the child declares no options' do
      parent = array_field_with(child_without_options)
      parent.valid?

      expect(parent.errors[:fields].join).not_to include(array_nesting_error)
    end

    # The guard walks descendants, so an extra level between the array and the block is still caught.
    it 'rejects an options block one level deeper inside an array field' do
      group = described_class.new(id: :group, label: 'Group', type: :nested)
                             .tap { |field| field.fields = [child_with_options] }
      parent = array_field_with(group)
      parent.valid?

      expect(parent.errors[:fields].join).to include("#{array_nesting_error}, so list_id")
    end

    it 'accepts an options block on a field nested inside a non-array field' do
      parent = IPaaS::Connector::Schema::Field.new(id: :group, label: 'Group', type: :nested)
                                              .tap { |field| field.fields = [child_with_options] }
      parent.valid?

      expect(parent.errors[:fields].join).not_to include(array_nesting_error)
    end
  end

  describe 'inspect' do
    it 'names the field without following the connector it belongs to' do
      list = owned_field(id: :tags, label: 'Tags', type: :string, array: true)

      expect(field.inspect).to eq('Field (foo) - string')
      expect(list.inspect).to eq('Field (tags) - string[]')
      expect(field.inspect).not_to include(spec_connector.uuid)
    end
  end

  describe 'connector' do
    let(:schema) { schema_with_connector('owned') { field :foo, 'Foo', :string } }

    def expression(source)
      IPaaS::Connector::Common::ProcHelper.new(schema, source)
    end

    def identity_validator = ->(value) { value }

    it 'is read-only: no writer, and the reader takes no value' do
      expect(field).not_to respond_to(:connector=)
      expect { field.connector(spec_connector) }.to raise_error(ArgumentError)
    end

    it 'is refused as an assignment target in an expression' do
      helper = expression('fields.first.connector = connector')

      expect(helper.valid?).to be(false)
      expect(helper.errors).to include("Method 'connector=' not allowed.")
    end

    it 'is refused in an op-assign too, which is judged as the setter it expands to' do
      helper = expression('fields.first.connector &&= connector')

      expect(helper.valid?).to be(false)
      expect(helper.errors).to include("Method 'connector=' not allowed.")
      expect(schema.fields.first.connector).to be(spec_connector)
    end

    it 'is dropped with the blocks when a field is rebuilt from its hash form' do
      with_options = owned_field(id: :picker, label: 'Picker', type: :string)
      with_options.options(&no_dependencies)
      with_options.validator(&identity_validator)

      rebuilt = IPaaS::Connector::Types::SchemaFieldType.resolve(with_options.to_h_ref)

      expect(rebuilt.options).to be_nil
      expect(rebuilt.validator).to be_nil
      expect(rebuilt.connector).to be_nil
    end
  end

  describe 'options_for' do
    before(:each) do
      skip_function_capture_validation
    end

    # call_function opens with valid?, which clears errors on a field shared by every concurrent
    # request for its solution. options_for must run the block without that pass.
    it 'runs the block and leaves an error another request planted in place' do
      field.options { ['ran'] }
      field.errors.add(:base, 'PLANTED BY ANOTHER REQUEST')

      expect(field.options_for(Object.new)).to eq(['ran'])
      expect(field.errors[:base]).to eq(['PLANTED BY ANOTHER REQUEST'])
    end

    it 'passes the declared keywords through to the block' do
      field.options { |space_id:, folder_id: nil| [space_id, folder_id] }

      expect(field.options_for(Object.new, space_id: '5')).to eq(['5', nil])
    end

    it 'answers nil when the field declares no options block' do
      expect(field.options_for(Object.new)).to be_nil
    end
  end

  describe 'options parameter validation' do
    let(:parameter_error) { 'must declare every dependency as a keyword parameter' }

    # Scoped to the options errors: a block defined in a spec method also trips the proc source
    # rules, which is unrelated to the parameter kinds under test here.
    def options_errors(block)
      field.options(&block)
      field.valid?
      field.errors[:options].join(' ')
    end

    it 'accepts a block that takes no parameters' do
      expect(options_errors(no_dependencies)).not_to include(parameter_error)
    end

    it 'accepts a block whose parameters are all keywords' do
      expect(options_errors(required_and_optional)).not_to include(parameter_error)
    end

    it 'rejects a positional parameter, which is a keyword missing its colon' do
      expect(options_errors(positional_dependency))
        .to include('must declare every dependency as a keyword parameter, so space_id cannot be used.')
    end

    it 'rejects a keyword catch-all, which names no dependency' do
      expect(options_errors(keyword_catch_all)).to include('so dependencies cannot be used')
    end

    it 'rejects a block parameter' do
      expect(options_errors(block_parameter)).to include('so callback cannot be used')
    end
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

    it 'should define the notice_type attribute' do
      expect(field.notice_type).to be_nil
      field.notice_type = 'error'
      expect(field.notice_type).to eq('error')
    end

    it 'should define the notice_action attribute' do
      expect(field.notice_action).to be_nil
      field.notice_action = 'edit_connection'
      expect(field.notice_action).to eq('edit_connection')
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
      max = IPaaS::Connector::Schema::Field::MAX_ID_LENGTH
      field.id = :"#{'a' * (max + 1)}"
      expect(field).to be_invalid
      expect(field.errors[:id]).to eq(["is too long (maximum is #{max} characters)"])
    end

    # The cap is a product decision, so one example pins the number itself. Every other example
    # reads the constant, which keeps them honest about the wiring but blind to its value.
    it 'should cap an :id at 64 characters' do
      expect(described_class::MAX_ID_LENGTH).to eq(64)
    end

    # The Jamf key the cap was raised for. Deriving the id from the key rather than from a literal
    # keeps the key, the transform and the length pinned together.
    it 'should accept the :id a real API key snake_cases to' do
      field.id = 'locationServicesForSelfServiceMobileEnabled'.underscore.to_sym

      expect(field.id.to_s.length).to eq(49)
      expect(field).to be_valid, -> { field.full_error_messages }
    end

    it 'should accept an :id at exactly the maximum length' do
      field.id = :"#{'a' * IPaaS::Connector::Schema::Field::MAX_ID_LENGTH}"
      expect(field).to be_valid, -> { field.full_error_messages }
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

    context 'regexp field with a default' do
      let(:regexp_field) do
        IPaaS::Connector::Schema::Field.new(id: :my_regex, label: 'My Regex', type: :regexp, default: '\d+')
      end

      it 'coerces the string default to a Regexp' do
        expect(regexp_field.default).to be_a(Regexp)
      end

      it 'survives a YAML serialize -> parse round-trip' do
        parsed = IPaaS::Connector::Common::Serializer.parse(regexp_field.to_h_ref.to_yaml)

        expect(IPaaS::Connector::Schema::Field.new(parsed).default).to eq(/\d+/)
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

    context 'notice_type' do
      it 'should accept an allowed notice_type' do
        field.notice_type = 'error'
        expect(field).to be_valid
      end

      it 'should validate the notice_type' do
        field.notice_type = 'foo'
        expect(field).to be_invalid
        expect(field.errors[:notice_type]).to eq(['is invalid.'])
      end

      it 'should ignore blank notice_type' do
        field.notice_type = ''
        expect(field).to be_valid
      end
    end

    context 'notice_action' do
      it 'should accept an allowed notice_action' do
        field.notice_action = 'edit_connection'
        expect(field).to be_valid
      end

      it 'should validate the notice_action' do
        field.notice_action = 'foo'
        expect(field).to be_invalid
        expect(field.errors[:notice_action]).to eq(['is invalid.'])
      end

      it 'should ignore blank notice_action' do
        field.notice_action = ''
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

      it 'should restrict enumerations to string, integer, and time zone types' do
        field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo label', type: :float)
        field.enumeration = [{ id: 'a', label: 'A' }, { id: 'b', label: 'B' }]
        expect(field).to be_invalid
        expect(field.errors[:enumeration]).to eq(['Enumeration is restricted to string, integer, and time zone types.'])
      end

      it 'should allow enumerations on time zone types' do
        field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo label', type: :time_zone)
        field.enumeration = [{ id: 'UTC', label: 'UTC' }, { id: 'London', label: 'London' }]
        expect(field).to be_valid
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
                    ':float, :hash, :hashed_credential, :integer, :job, :nested, :recurrence, :regexp, :ruby, ' \
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
    it 'returns a copy of the default, so changing the example leaves the default intact' do
      tags = described_class.new(id: :tags, label: 'Tags', type: :string, array: true, default: %w[a b])
      example = tags.example
      example.first << '-changed'

      expect(example).to eq(%w[a-changed b])
      expect(tags.default).to eq(%w[a b])
    end

    it 'returns a copy of the sample, so changing the example leaves the sample intact' do
      tags = described_class.new(id: :tags, label: 'Tags', type: :string, array: true, sample: %w[a b])
      example = tags.example
      example.first << '-changed'

      expect(example).to eq(%w[a-changed b])
      expect(tags.sample).to eq(%w[a b])
    end

    it 'returns a copy of a recurrence sample, so changing the example leaves the sample intact' do
      schedule = described_class.new(id: :schedule, label: 'Schedule', type: :recurrence,
                                     sample: { frequency: 'daily' })
      example = schedule.example
      example[:frequency] = 'weekly'

      expect(example[:frequency]).to eq('weekly')
      expect(schedule.sample[:frequency]).to eq('daily')
    end

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

  describe 'deep_dup' do
    let(:original) do
      described_class.new(id: :colour, label: 'Colour', type: :string, default: 'red', sample: 'crimson',
                          enumeration: [{ id: 'red', label: 'Red' }])
    end

    it 'gives the copy an equal option list' do
      expect(original.deep_dup.enumeration).to eq([{ id: 'red', label: 'Red' }])
    end

    it 'keeps absent containers absent' do
      copy = described_class.new(id: :plain, label: 'Plain', type: :string).deep_dup

      expect([copy.enumeration, copy.sample, copy.default]).to eq([nil, nil, nil])
    end

    it 'leaves the original option list untouched when the copy changes its own' do
      copy = original.deep_dup
      copy.enumeration << { id: 'blue', label: 'Blue' }
      copy.enumeration.first[:label] << ' (dark)'

      expect(copy.enumeration).to eq([{ id: 'red', label: 'Red (dark)' }, { id: 'blue', label: 'Blue' }])
      expect(original.enumeration).to eq([{ id: 'red', label: 'Red' }])
    end

    it 'leaves the original default untouched when the copy changes its own' do
      copy = original.deep_dup
      copy.default << '-ish'

      expect(copy.default).to eq('red-ish')
      expect(original.default).to eq('red')
    end

    it 'leaves the original label untouched when the copy changes its own' do
      copy = original.deep_dup
      copy.label << ' (dark)'

      expect(copy.label).to eq('Colour (dark)')
      expect(original.label).to eq('Colour')
    end

    it 'leaves the original sample untouched when the copy changes its own' do
      copy = original.deep_dup
      copy.sample << '-ish'

      expect(copy.sample).to eq('crimson-ish')
      expect(original.sample).to eq('crimson')
    end

    it "copies a typed field's own subfields, not those its type provides" do
      note = described_class.new(id: :note, label: 'Note', type: :string)
      schedule = described_class.new(id: :schedule, label: 'Schedule', type: :recurrence).tap { |f| f.fields = [note] }
      copy = schedule.deep_dup

      expect(copy.fields_without_nested_schema.map(&:id)).to eq([:note])
      expect(copy.fields_without_nested_schema.first).not_to equal(note)
      expect(copy.to_h_ref).to eq(schedule.to_h_ref)
    end

    it 'gives a field named fields its own subfield list' do
      filter = described_class.new(id: :fields, label: 'Fields filter', type: :string).tap { |f| f.fields = [] }
      copy = filter.deep_dup
      copy.fields_without_nested_schema << described_class.new(id: :planted, label: 'Planted', type: :string)

      expect(copy.fields_without_nested_schema.map(&:id)).to eq([:planted])
      expect(filter.fields_without_nested_schema).to eq([])
    end

    it 'leaves an Array default untouched, down to its elements, when the copy changes its own' do
      tags = described_class.new(id: :tags, label: 'Tags', type: :string, array: true, default: %w[a b])
      copy = tags.deep_dup
      copy.default.first << '-changed'
      copy.default << 'c'

      expect(copy.default).to eq(%w[a-changed b c])
      expect(tags.default).to eq(%w[a b])
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

  describe 'unresolved values' do
    let(:node) { unresolved_node }
    let(:field) { IPaaS::Connector::Schema::Field.new(id: :api_key, label: 'API Key', type: :secret_string) }

    it 'preserves an UnresolvedNode default instead of coercing it through the type' do
      field.default = node
      expect(field.default).to be(node)
    end

    [
      [:default, :secret_string, ->(n) { n }],
      [:sample, :secret_string, ->(n) { n }],
      [:hint, :ruby, ->(n) { n }],
      [:notice, :ruby, ->(n) { n }],
      [:min_date, :ruby, ->(n) { n }],
      [:enumeration, :string, ->(n) { [n] }],
    ].each do |attr, type, build|
      it "marks the field invalid when #{attr} is unresolved" do
        field = IPaaS::Connector::Schema::Field.new(id: :api_key, label: 'API Key', type: type)
        field.send(:"#{attr}=", build.call(node))

        expect(field).not_to be_valid
        expect(field.errors.full_messages.grep(/#{Regexp.escape(node.message)}/)).not_to be_empty
      end
    end

    it 're-emits the original node losslessly via to_h_ref' do
      field.default = node

      dumped = IPaaS::Connector::Common::Serializer.dump(field.to_h_ref)
      expect(dumped).to include("!ruby/object:#{UnresolvedNodeHelper::UNPERMITTED_CLASS}", 'encrypted: gAAAA_blob==')
      expect(IPaaS::Connector::Common::Serializer.parse(dumped, tolerant: true)[:default].unresolved_class)
        .to eq(UnresolvedNodeHelper::UNPERMITTED_CLASS)
    end

    it 'reports an unresolved value nested in a sub-field on the parent' do
      parent = IPaaS::Connector::Schema::Field.new(id: :creds, label: 'Creds', type: :nested)
      parent.fields = [field.tap { |f| f.default = node }]

      expect(parent).not_to be_valid
      expect(parent.errors[:base]).to include("Field (api_key) invalid: Default #{node.message}")
    end

    it 'accepts a bare placeholder for enumeration and reports it instead of raising' do
      enum_field = IPaaS::Connector::Schema::Field.new(id: :pick, label: 'Pick', type: :string)

      expect { enum_field.enumeration = node }.not_to raise_error
      expect(enum_field).not_to be_valid
      expect(enum_field.errors[:enumeration]).to include(node.message)
    end

    it 'keeps a sub-field that is itself a placeholder instead of dropping it' do
      parent = IPaaS::Connector::Types::SchemaFieldType.resolve(
        { id: 'creds', label: 'Creds', type: 'nested', fields: [node] }
      )

      expect(parent.fields_without_nested_schema).to eq([node])
      expect(parent).not_to be_valid
      expect(parent.errors[:fields]).to include(node.message)
    end

    it 'reports unloadable values through a sub-field that is itself a placeholder' do
      parent = IPaaS::Connector::Types::SchemaFieldType.resolve(
        { id: 'creds', label: 'Creds', type: 'nested', fields: [node] }
      )

      expect(parent).to be_unloadable_values
    end

    it 'reports no unloadable values on a field that merely fails another validation' do
      nameless = IPaaS::Connector::Types::SchemaFieldType.resolve({ id: 'nameless', type: 'string' })

      expect(nameless).not_to be_valid
      expect(nameless).not_to be_unloadable_values
    end

    it 'leaves an enumeration that is itself a placeholder alone rather than converting it' do
      node = unresolved_node
      field = IPaaS::Connector::Schema::Field.new(id: :pick, label: 'Pick', type: :string)

      field.enumeration = node

      expect(field.enumeration).to be(node)
    end

    it 'leaves an enumeration holding a placeholder unconverted rather than labelling the error' do
      node = unresolved_node
      field = IPaaS::Connector::Schema::Field.new(id: :pick, label: 'Pick', type: :string)

      field.enumeration = ['a', node]

      expect(field.enumeration).to eq(['a', node])
    end

    it 'converts a plain enumeration to id/label pairs as before' do
      field = IPaaS::Connector::Schema::Field.new(id: :pick, label: 'Pick', type: :string)

      field.enumeration = %w[a b]

      expect(field.enumeration).to eq([{ id: 'a', label: 'a' }, { id: 'b', label: 'b' }])
    end

    it 'keeps the fast path off the placeholder scan for an already-converted enumeration' do
      converted = IPaaS::Connector::Schema::Field.new(id: :pick, label: 'Pick', type: :string,
                                                      enumeration: [{ id: 'a', label: 'A' }])

      expect(IPaaS::Connector::Common::UnresolvedNode).not_to receive(:within?)

      converted.enumeration = [{ id: 'b', label: 'B' }]
    end

    it 'keeps the fast path off the placeholder list when validating a value that holds none' do
      big = IPaaS::Connector::Schema::Field.new(id: :blob, label: 'Blob', type: :hash)
      big.default = { 'k' => (1..50).map { |i| { 'i' => i } } }

      expect(IPaaS::Connector::Common::UnresolvedNode).not_to receive(:all_within)

      expect(big).to be_valid
    end

    [
      ['an Array', ->(n) { [n] }],
      ['a Hash', ->(n) { { 'k' => n } }],
      ['a nested container', ->(n) { { 'k' => [{ 'deep' => n }] } }],
    ].each do |description, build|
      it "does not resolve or drop an UnresolvedNode inside #{description}" do
        container_field = IPaaS::Connector::Schema::Field.new(id: :blob, label: 'Blob', type: :string)
        container_field.default = build.call(node)

        expect(container_field.default).to eq(build.call(node))
        expect(container_field).not_to be_valid
        expect(container_field.errors[:default]).to include(node.message)
      end
    end
  end
end
