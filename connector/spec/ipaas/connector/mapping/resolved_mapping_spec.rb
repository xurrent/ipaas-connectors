require 'spec_helper'

describe IPaaS::Connector::Mapping::ResolvedMapping do
  let(:example_schema) do
    IPaaS::Connector::Schema.new('reference') do
      field :foo, 'Foo', :string
      field :cars, 'Cars', [:nested] do
        field :name, 'Name', :string
        field :nr, 'Nr', :integer
      end
      field :invisible, 'Invisible', :string,
            required: true,
            disabled: true,
            default: 'Unseen'
    end
  end

  def resolve(field_mapping, context: Object.new, schema: example_schema)
    IPaaS::Connector::Mapping::ResolvedMapping.new(context, schema.fields, field_mapping).resolve
  end

  context 'resolve' do
    it 'should resolve a fixed string value' do
      resolved = resolve([{ field_id: :foo, fixed: 'Fixed Foo' }])
      expect(resolved[:foo]).to eq 'Fixed Foo'
    end

    it 'should resolve a proc value' do
      resolved = resolve([{ field_id: :foo, proc: '["Hello", " ", "World!"].join' }])
      expect(resolved[:foo]).to eq 'Hello World!'
    end

    it 'should resolve a variable value by string key' do
      context = double
      expect(context).to receive(:environment) { { bar: 'Foo Bar' } }
      resolved = resolve([{ field_id: :foo, variable: 'bar' }], context: context)
      expect(resolved[:foo]).to eq 'Foo Bar'
    end

    it 'should resolve a variable value by symbol key' do
      context = double
      expect(context).to receive(:environment) { { bar: 'Foo Bar' } }
      resolved = resolve([{ field_id: :foo, variable: :bar }], context: context)
      expect(resolved[:foo]).to eq 'Foo Bar'
    end

    it 'should resolve a runbook variable value by string key' do
      context = double
      runbook = double
      allow(runbook).to receive(:read_variable).with('my-variable').and_return('my-value')
      expect(context).to receive(:runbook) { runbook }
      resolved = resolve([{ field_id: :foo, runbook_variable: 'my-variable' }], context: context)
      expect(resolved[:foo]).to eq 'my-value'
    end

    it 'should resolve a runbook variable value by symbol key' do
      context = double
      runbook = double
      allow(runbook).to receive(:read_variable).with('my-variable').and_return('my-value')
      expect(context).to receive(:runbook) { runbook }
      resolved = resolve([{ field_id: :foo, runbook_variable: :'my-variable' }], context: context)
      expect(resolved[:foo]).to eq 'my-value'
    end

    it 'should resolve nested values with arrays' do
      mv = [
        { field_id: :name, fixed: 'MV' },
        { field_id: :nr, proc: '30 + 3' },
      ]
      lh = [
        { field_id: :name, fixed: 'LH' },
        { field_id: :nr, proc: '40 + 4' },
      ]
      resolved = resolve(
        [
          { field_id: :cars, nested: mv },
          { field_id: :cars, nested: lh },
        ]
      )
      expect(resolved[:cars].size).to eq(2)
      expect(resolved[:cars].first[:name]).to eq('MV')
      expect(resolved[:cars].first[:nr]).to eq(33)
      expect(resolved[:cars].last[:name]).to eq('LH')
      expect(resolved[:cars].last[:nr]).to eq(44)
    end

    it 'should resolve nested values with arrays and procs' do
      mv = [
        { field_id: :name, fixed: 'MV' },
        { field_id: :nr, proc: '30 + 3' },
      ]
      ferrari_proc = '[{ name: "LC", nr: 10 + 6 }, { name: "CS", nr: 50 + 5 }]'
      resolved = resolve(
        [
          { field_id: :cars, nested: mv },
          { field_id: :cars, proc: ferrari_proc },
        ]
      )
      expect(resolved[:cars].size).to eq(3)
      expect(resolved[:cars].first[:name]).to eq('MV')
      expect(resolved[:cars].first[:nr]).to eq(33)
      expect(resolved[:cars].second[:name]).to eq('LC')
      expect(resolved[:cars].second[:nr]).to eq(16)
      expect(resolved[:cars].last[:name]).to eq('CS')
      expect(resolved[:cars].last[:nr]).to eq(55)
    end

    it 'should skip fields that are not part of the schema' do
      resolved = resolve([{ field_id: :unknown, fixed: 'Fixed Bar' }])
      expect(resolved[:unknown]).to be_nil
    end

    it 'should skip fields that are disabled' do
      resolved = resolve([{ field_id: :invisible, fixed: 'Hello' }])
      expect(resolved[:invisible]).to be_nil
    end

    it 'should resolve default fields from the schema' do
      example_schema.field :boo, 'Boo', :string, default: 'Boohoo'
      resolved = resolve([{ field_id: :foo, fixed: 'Fixed Foo' }])
      expect(resolved[:boo]).to eq 'Boohoo'
    end

    it 'should not set the default value for mapped fields' do
      example_schema.field :boo, 'Boo', :string, default: 'Boohoo'
      resolved = resolve([{ field_id: :boo, fixed: nil }])
      expect(resolved[:boo]).to be_nil
    end

    it 'should not set the default value for disabled fields' do
      resolved = resolve([])
      expect(resolved[:invisible]).to be_nil
    end

    context 'recurrence' do
      let(:recurrence_schema) do
        IPaaS::Connector::Schema.new('recurrence') do
          field :schedule, 'Schedule', :recurrence,
                required: true
        end
      end

      def resolve_recurrence(field_mapping)
        resolve(field_mapping, schema: recurrence_schema)
      end

      it 'should resolve a recurrence' do
        weekly = {
          frequency: 'weekly',
          time_zone: 'UTC',
          interval: 2,
          day: %w[saturday sunday],
          time_of_day: '16:55:50',
        }
        resolved = resolve_recurrence([{ field_id: :schedule, fixed: weekly }])
        expect(resolved).to be_valid
      end

      it 'should validate nested fields' do
        weekly = {
          frequency: 'weekly',
          time_zone: 'UTC',
          interval: 2,
          day: %w[saturday sunday],
          time_of_day: '35:55:50',
        }
        resolved = resolve_recurrence([{ field_id: :schedule, fixed: weekly }])
        expect(resolved).not_to be_valid
        error_message = "Nested field 'schedule' invalid: Field 'time_of_day' is invalid."
        expect(resolved.full_error_messages).to eq(error_message)
        expect(resolved.mapping.first.errors[:base]).to include(error_message)
      end
    end
  end

  context 'validation' do
    let(:restricted_schema) do
      IPaaS::Connector::Schema.new('reference') do
        field :foo, 'Foo', :string,
              required: true,
              pattern: /\A[a-z]*\z/,
              min_length: 4,
              max_length: 42
        field :bar, 'Bar', :integer,
              min: 4,
              max: 42
        field :date, 'Date', :date,
              min: Date.parse('2024-01-01'),
              max: Date.parse('2024-12-31')
        field :bounded_date, 'Bounded Date', :date,
              min_date: '2024-01-01',
              max_date: '2024-12-31'
        field :baz, 'Baz', :string,
              enumeration: %w[FOO BAR BAZ]
        field :invisible, 'Invisible', :string,
              required: true,
              disabled: true
        field :cars, 'Cars', [:nested], min_length: 2, max_length: 3 do
          field :name, 'Name', :string,
                required: true,
                pattern: /\A[A-Z]{2}\z/
          field :nr, 'Nr', :integer,
                min: 1,
                max: 99
        end
      end
    end

    let :designer_context do
      double('context').tap do |context|
        allow(context).to receive(:runbook) { double(designer_mode?: true) }
      end
    end

    def resolve_restricted(field_mapping, context: nil)
      resolve(field_mapping, schema: restricted_schema, context: context)
    end

    it 'should approve a valid full mapping' do
      resolved = resolve_restricted(
        [
          { field_id: :foo, fixed: 'fixedfoo' },
          { field_id: :bar, fixed: 20 },
          { field_id: :baz, proc: '"BAZ"' },
          { field_id: :date, fixed: Date.parse('2024-06-05') },
          { field_id: :cars, nested: [
            { field_id: :name, fixed: 'MV' },
            { field_id: :nr, fixed: 33 },
          ], },
          { field_id: :cars, nested: [
            { field_id: :name, fixed: 'LH' },
            { field_id: :nr, fixed: 44 },
          ], },
        ]
      )
      expect(resolved).to be_valid
    end

    it 'should approve a valid minimal mapping' do
      resolved = resolve_restricted([{ field_id: :foo, fixed: 'fixed' }])
      expect(resolved).to be_valid
    end

    it 'should validate fields that are mapped twice' do
      resolved = resolve_restricted(
        [
          { field_id: :foo, fixed: 'first' },
          { field_id: :foo, proc: '"second"' },
        ]
      )
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Field 'foo' is mapped twice.")
    end

    it 'should validate procs' do
      resolved = resolve_restricted([{ field_id: :foo, proc: 'eval("second")' }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Field 'foo' code invalid: Method 'eval' not allowed.")
    end

    it 'should handle exceptions during proc validation' do
      resolved = resolve_restricted([{ field_id: :foo, proc: 'nil + []' }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base])
        .to contain_exactly("Field 'foo' code raised NoMethodError: undefined method '+' for nil")
    end

    it 'should handle exceptions in procs in nested values' do
      resolved = resolve_restricted(
        [
          { field_id: :foo, fixed: 'valid' },
          { field_id: :cars,
            nested: [
              { field_id: :nr, fixed: 101 },
              { field_id: :name, proc: '10 + nil' },
            ],  },
        ]
      )
      expect(resolved).not_to be_valid

      nr_msg = "Field 'nr' should be at most 99."
      name_msg = "Field 'name' code raised TypeError: nil can't be coerced into Integer"
      base_errors = resolved.errors[:base]
      expect(base_errors)
        .to contain_exactly("Length of field 'cars' should be at least 2.",
                            "Nested field 'cars[0]' invalid: #{name_msg}",
                            "Nested field 'cars[0]' invalid: #{nr_msg}")

      cars_mapping = resolved.mapping.second
      cars_errors = cars_mapping.errors[:base]
      expect(cars_errors)
        .to contain_exactly("Length of field 'cars' should be at least 2.",
                            "Nested field 'cars[0]' invalid: #{name_msg}",
                            "Nested field 'cars[0]' invalid: #{nr_msg}")

      expect(cars_mapping.nested.first.errors[:base]).to include(nr_msg)
      expect(cars_mapping.nested.second.errors[:base]).to include(name_msg)
    end

    it 'should accept duplicate runbook variable mappings with the same type' do
      context = double
      runbook = double
      allow(context).to receive(:runbook) { runbook }
      allow(runbook).to receive(:read_variable).with('my-variable') { 33 }
      resolved = resolve_restricted(
        [
          { field_id: :foo, fixed: 'fixed' },
          { field_id: :bar, runbook_variable: 'my-variable' },
          {
            field_id: :cars, nested: [
              { field_id: :name, fixed: 'MV' },
              { field_id: :nr, runbook_variable: 'my-variable' },
            ],
          },
          {
            field_id: :cars, nested: [
              { field_id: :name, fixed: 'LH' },
              { field_id: :nr, runbook_variable: 'my-variable' },
            ],
          },
        ],
        context: context,
      )
      expect(resolved).to be_valid
      expect(resolved[:bar]).to eq(33)
      expect(resolved[:cars].first[:nr]).to eq(33)
      expect(resolved[:cars].last[:nr]).to eq(33)
    end

    it 'should validate type of nested values' do
      resolved = resolve_restricted([{ field_id: :cars, fixed: 'MV' }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Type of field 'cars[0]' invalid, expected Hash found String.")
    end

    it 'should validate subfields of nested values' do
      resolved = resolve_restricted(
        [
          { field_id: :foo, fixed: 'valid' },
          { field_id: :cars, nested: [{ field_id: :nr, fixed: 101 }] },
        ]
      )
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to contain_exactly(
        "Nested field 'cars[0]' invalid: Field 'name' is required.",
        "Nested field 'cars[0]' invalid: Field 'nr' should be at most 99.",
        "Length of field 'cars' should be at least 2.",
      )
      expect(resolved.mapping.second.errors[:base])
        .to include("Nested field 'cars[0]' invalid: Field 'name' is required.")
      expect(resolved.mapping.second.nested.first.errors[:base]).to include("Field 'nr' should be at most 99.")
    end

    it 'should indicate correct index for array fields' do
      resolved = resolve_restricted(
        [
          { field_id: :foo, fixed: 'valid' },
          { field_id: :cars, fixed: [{ name: 'MV', nr: 33 }, { nr: 101 }, { nr: 22 }] },
        ]
      )
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to contain_exactly(
        "Nested field 'cars[1]' invalid: Field 'name' is required.",
        "Nested field 'cars[1]' invalid: Field 'nr' should be at most 99.",
        "Nested field 'cars[2]' invalid: Field 'name' is required.",
      )
    end

    it 'should not complain about required dynamically mapped fields in designer mode' do
      resolved = resolve_restricted(
        [
          { field_id: :foo, fixed: 'valid' },
          { field_id: :cars, nested:
            [
              { field_id: :name, proc: 'nil' },
              { field_id: :nr, proc: 'nil' },
            ],  },
        ], context: designer_context
      )
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to eq(["Length of field 'cars' should be at least 2."])
      expect(resolved.mapping.second.errors[:base]).to eq(["Length of field 'cars' should be at least 2."])
      expect(resolved.mapping.second.nested.first.errors[:base]).to eq([])
    end

    it 'should validate required' do
      resolved = resolve_restricted([{ field_id: :bar, fixed: 20 }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Field 'foo' is required.")
    end

    context 'required booleans' do
      let(:restricted_schema) do
        IPaaS::Connector::Schema.new('reference') do
          field :foo, 'Foo', :boolean,
                required: true
        end
      end

      it 'should validate required for boolean' do
        resolved = resolve_restricted([{ field_id: :foo, fixed: nil }])
        expect(resolved).not_to be_valid
        expect(resolved.errors[:base]).to include("Field 'foo' is required.")
      end

      it 'should accept false as a valid value' do
        resolved = resolve_restricted([{ field_id: :foo, fixed: false }])
        expect(resolved).to be_valid
        expect(resolved[:foo]).to eq(false)
      end
    end

    it 'should validate min length of string' do
      resolved = resolve_restricted([{ field_id: :foo, fixed: 'foo' }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Length of field 'foo' should be at least 4.")
    end

    it 'should validate min length of array' do
      resolved = resolve_restricted([{ field_id: :cars, fixed: [{ name: 'MV', nr: 33 }] }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Length of field 'cars' should be at least 2.")
    end

    it 'should validate max length of string' do
      resolved = resolve_restricted(
        [
          { field_id: :foo, fixed: 'foobarbazetceteraandsoforthuntilitistoolong' },
        ]
      )
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Length of field 'foo' should be at most 42.")
    end

    it 'should validate max length of array' do
      resolved = resolve_restricted(
        [
          { field_id: :cars, fixed: [
            { name: 'MV', nr: 33 },
            { name: 'LH', nr: 44 },
            { name: 'CL', nr: 16 },
            { name: 'CS', nr: 55 },
          ], },
        ]
      )
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Length of field 'cars' should be at most 3.")
    end

    it 'should validate pattern' do
      resolved = resolve_restricted([{ field_id: :foo, fixed: 'FOOBAR' }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Field 'foo' should confirm to pattern /\\A[a-z]*\\z/.")
    end

    it 'should validate min value' do
      resolved = resolve_restricted([{ field_id: :bar, fixed: 2 }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Field 'bar' should be at least 4.")
    end

    it 'should validate max value' do
      resolved = resolve_restricted([{ field_id: :bar, fixed: 44 }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Field 'bar' should be at most 42.")
    end

    it 'should validate min value of dates' do
      resolved = resolve_restricted([{ field_id: :date, fixed: Date.parse('2023-01-01') }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Field 'date' should be at least 2024-01-01.")
    end

    it 'should validate max value of dates' do
      resolved = resolve_restricted([{ field_id: :date, fixed: Date.parse('2025-01-01') }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Field 'date' should be at most 2024-12-31.")
    end

    it 'should validate min_date' do
      resolved = resolve_restricted([{ field_id: :bounded_date, fixed: Date.parse('2023-12-31') }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Field 'bounded_date' should be on or after 2024-01-01.")
    end

    it 'should validate max_date' do
      resolved = resolve_restricted([{ field_id: :bounded_date, fixed: Date.parse('2025-01-01') }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Field 'bounded_date' should be on or before 2024-12-31.")
    end

    it 'should accept a date within min_date and max_date' do
      resolved = resolve_restricted([{ field_id: :foo, fixed: 'fixed' },
                                     { field_id: :bounded_date, fixed: Date.parse('2024-06-15') },])
      expect(resolved.errors[:base]).not_to include(a_string_matching(/bounded_date/))
    end

    it 'should validate the ruby class' do
      resolved = resolve_restricted([{ field_id: :date, fixed: 'Foo' }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to contain_exactly("Type of field 'date' invalid, expected Date found String.",
                                                        "Field 'foo' is required.")
    end

    context 'validator' do
      before(:each) do
        skip_function_capture_validation
      end

      it 'should validate the validator proc' do
        validator = ->(value) { value.invalid_method(environment[:foo]) }
        validator_schema = IPaaS::Connector::Schema.new('reference2') do
          field :foo, 'Foo', :string, validator: validator
        end

        resolved = resolve([{ field_id: :foo, fixed: 'foo me' }], schema: validator_schema)
        expect(resolved).not_to be_valid
        message = "Field 'foo' validator code invalid: Method 'invalid_method' not allowed."
        expect(resolved.errors[:base]).to include(message)
      end

      it 'should accept correct values' do
        validator = ->(value) { value.starts_with?('foo') }
        validator_schema = IPaaS::Connector::Schema.new('reference2') do
          field :foo, 'Foo', :string, validator: validator
        end

        resolved = resolve([{ field_id: :foo, fixed: 'foo me' }], schema: validator_schema)
        expect(resolved).to be_valid
      end

      it 'should validate using a validator proc' do
        validator = ->(value) { value.starts_with?('foo') }
        validator_schema = IPaaS::Connector::Schema.new('reference2') do
          field :foo, 'Foo', :string, validator: validator
        end

        resolved = resolve([{ field_id: :foo, fixed: 'bar me' }], schema: validator_schema)
        expect(resolved).not_to be_valid
        expect(resolved.errors[:base]).to include("Field 'foo' is not valid.")
      end

      it 'should retrieve environment variables' do
        validator = ->(value) { value.starts_with?(environment[:foo]) }
        validator_schema = IPaaS::Connector::Schema.new('reference2') do
          field :foo, 'Foo', :string, validator: validator
        end

        context = double
        expect(context).to receive(:environment) { { foo: 'foo' } }
        resolved = resolve([{ field_id: :foo, fixed: 'foo me' }], schema: validator_schema, context: context)
        expect(resolved).to be_valid

        expect(context).to receive(:environment) { { foo: 'bar' } }
        resolved = resolve([{ field_id: :foo, fixed: 'foo me' }], schema: validator_schema, context: context)
        expect(resolved).not_to be_valid
        expect(resolved.errors[:base]).to include("Field 'foo' is not valid.")
      end

      context 'on nested field' do
        it 'should accept correct values' do
          validator = ->(value) { value[:foo].starts_with?('foo') }
          validator_schema = IPaaS::Connector::Schema.new('reference3') do
            field :top, 'Top', :nested,
                  validator: validator do
              field :foo, 'Foo', :string
            end
          end

          resolved = resolve([{ field_id: :top, nested: [{ field_id: :foo, fixed: 'foo me' }] }],
                             schema: validator_schema)
          expect(resolved).to be_valid
        end

        it 'should validate using a validator proc' do
          validator = ->(value) { value[:foo].starts_with?('foo') }
          validator_schema = IPaaS::Connector::Schema.new('reference3') do
            field :top, 'Top', :nested,
                  validator: validator do
              field :foo, 'Foo', :string
            end
          end

          resolved = resolve([{ field_id: :top, nested: [{ field_id: :foo, fixed: 'bar me' }] }],
                             schema: validator_schema)
          expect(resolved).not_to be_valid
          expect(resolved.errors[:base]).to include("Field 'top' is not valid.")
        end
      end
    end

    context 'fixed nested mapping' do
      before(:each) do
        @nested_schema = IPaaS::Connector::Schema.new('reference3') do
          field :headers, 'Headers', :nested do
            field :optional_header, 'Optional', :string
            field :required_header, 'Required', :string, required: true
            field :multiple_headers, 'Multiple', :string, array: true
          end
          field :body, 'Body', :nested do
            field :pet, 'Pet', :string, required: true
            field :cars, 'Cars', [:nested] do
              field :nr, 'Nr', :integer, required: true, min: 1, max: 100
              field :driver, 'Driver', :string, required: true
            end
          end
        end
        @nested_value = {
          headers: { required_header: 'Present' },
          body: {
            pet: 'Zuzu',
            cars: [{ nr: 33, driver: 'MV' }],
          },
        }
      end

      it 'should validate nested fields with fixed values' do
        mapping = IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(@nested_value)
        context = double
        resolved = resolve(mapping, schema: @nested_schema, context: context)
        expect(resolved).to be_valid
      end

      it 'should detect when required value in nested field is missing' do
        @nested_value[:headers] = { optional_header: 'Optional' }
        mapping = IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(@nested_value)
        context = double
        resolved = resolve(mapping, schema: @nested_schema, context: context)
        expect(resolved).not_to be_valid
        message = "Nested field 'headers' invalid: Field 'required_header' is required."
        expect(resolved.errors[:base]).to include(message)
      end

      it 'should detect when deeply nested integer is too high' do
        @nested_value[:body][:cars].first[:nr] = 777
        mapping = IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(@nested_value)
        context = double
        resolved = resolve(mapping, schema: @nested_schema, context: context)
        expect(resolved).not_to be_valid
        message = "Nested field 'body' invalid: Nested field 'cars[0]' invalid: Field 'nr' should be at most 100."
        expect(resolved.errors[:base]).to include(message)
      end
    end

    context 'nested mapping with runbook variables' do
      before(:each) do
        @nested_schema = IPaaS::Connector::Schema.new('reference3') do
          field :headers, 'Headers', :nested do
            field :optional_header, 'Optional', :string
            field :required_header, 'Required', :string, required: true
            field :multiple_headers, 'Multiple', :string, array: true
          end
          field :body, 'Body', :nested do
            field :pet, 'Pet', :string, required: true
            field :cars, 'Cars', [:nested] do
              field :nr, 'Nr', :integer, required: true, min: 1, max: 100
              field :driver, 'Driver', :string, required: true
            end
          end
        end
        @nested_mapping =
          [
            {
              field_id: :headers, nested:
                [
                  { field_id: :required_header, runbook_variable: 'my-header-variable' },
                ],
            },
            {
              field_id: :body, nested:
              [
                { field_id: :pet, fixed: 'Zuzu' },
                {
                  field_id: :cars, nested:
                  [
                    { field_id: :nr, fixed: 11 },
                    { field_id: :driver, runbook_variable: 'my-car-driver-1-variable' },
                  ],
                },
                {
                  field_id: :cars, nested:
                  [
                    { field_id: :nr, fixed: 22 },
                    { field_id: :driver, fixed: 'Driver #2' },
                  ],
                },
                {
                  field_id: :cars, nested:
                  [
                    { field_id: :nr, fixed: 33 },
                    { field_id: :driver, runbook_variable: 'my-car-driver-3-variable' },
                  ],
                },
              ],
            },
          ]
      end

      it 'should resolve nested fields with runbook variables' do
        context = double
        runbook = double
        allow(context).to receive(:runbook) { runbook }
        allow(runbook).to receive(:read_variable).with('my-header-variable') { 'foo' }
        allow(runbook).to receive(:read_variable).with('my-car-driver-1-variable') { 'Driver #1' }
        allow(runbook).to receive(:read_variable).with('my-car-driver-3-variable') { 'Driver #3' }

        resolved = resolve(@nested_mapping, schema: @nested_schema, context: context)
        expect(resolved).to be_valid
        expect(resolved[:headers][:required_header]).to eq('foo')
        expect(resolved[:body][:cars]).to eq(
          [
            { 'driver' => 'Driver #1', 'nr' => 11 },
            { 'driver' => 'Driver #2', 'nr' => 22 },
            { 'driver' => 'Driver #3', 'nr' => 33 },
          ]
        )
      end

      it 'should detect when required value in nested field are missing' do
        context = double
        runbook = double
        allow(context).to receive(:runbook) { runbook }
        allow(runbook).to receive(:read_variable).with('my-header-variable') { 'foo' }
        allow(runbook).to receive(:read_variable).with('my-car-driver-1-variable') # missing
        allow(runbook).to receive(:read_variable).with('my-car-driver-3-variable') { 'Driver #3' }
        allow(runbook).to receive(:designer_mode?) { false }

        resolved = resolve(@nested_mapping, schema: @nested_schema, context: context)
        expect(resolved).not_to be_valid
        message = "Nested field 'body' invalid: Nested field 'cars[0]' invalid: Field 'driver' is required."
        expect(resolved.errors[:base]).to include(message)
      end

      it 'should not complain about required fields in designer mode' do
        context = double
        runbook = double
        allow(context).to receive(:runbook) { runbook }
        allow(runbook).to receive(:read_variable).with('my-header-variable') { 'foo' }
        allow(runbook).to receive(:read_variable).with('my-car-driver-1-variable') # missing
        allow(runbook).to receive(:read_variable).with('my-car-driver-3-variable') { 'Driver #3' }
        allow(runbook).to receive(:designer_mode?) { true }

        resolved = resolve(@nested_mapping, schema: @nested_schema, context: context)
        expect(resolved).to be_valid
      end
    end

    context 'variable on nested field mismatch' do
      let(:nested_field_schema) do
        IPaaS::Connector::Schema.new('nested_mismatch') do
          field :filter, 'Filter', :nested do
            field :query, 'Query', :string
          end
        end
      end

      it 'should report error when environment variable is mapped to a nested field and resolves to a string' do
        context = double
        allow(context).to receive(:environment) { { my_var: 'some_value' } }
        allow(context).to receive(:runbook) { nil }

        mapping = [{ field_id: :filter, variable: 'my_var' }]
        resolved = resolve(mapping, schema: nested_field_schema, context: context)
        expect(resolved).not_to be_valid
        expect(resolved.errors[:base]).to include(
          "Field 'filter' expects nested values but a variable was provided. " \
          'Use the Nested option to map variables to individual sub-fields.'
        )
      end

      it 'should report error when runbook variable is mapped to a nested field and resolves to nil' do
        context = double
        runbook = double
        allow(context).to receive(:runbook) { runbook }
        allow(runbook).to receive(:read_variable).with('my_runbook_var') { nil }
        allow(runbook).to receive(:designer_mode?) { true }

        mapping = [{ field_id: :filter, runbook_variable: 'my_runbook_var' }]
        resolved = resolve(mapping, schema: nested_field_schema, context: context)
        expect(resolved).not_to be_valid
        expect(resolved.errors[:base]).to include(
          "Field 'filter' expects nested values but a variable was provided. " \
          'Use the Nested option to map variables to individual sub-fields.'
        )
      end

      it 'should report error when runbook variable is mapped to a nested field and resolves to a non-blank string' do
        context = double
        runbook = double
        allow(context).to receive(:runbook) { runbook }
        allow(runbook).to receive(:read_variable).with('my_runbook_var') { 'some_string_value' }

        mapping = [{ field_id: :filter, runbook_variable: 'my_runbook_var' }]
        resolved = resolve(mapping, schema: nested_field_schema, context: context)
        expect(resolved).not_to be_valid
        expect(resolved.errors[:base]).to include(
          "Field 'filter' expects nested values but a variable was provided. " \
          'Use the Nested option to map variables to individual sub-fields.'
        )
      end

      it 'should not report mismatch error when nested mapping is used correctly' do
        context = double
        runbook = double
        allow(context).to receive(:runbook) { runbook }
        allow(runbook).to receive(:read_variable).with('my_query_var') { 'search_term' }

        mapping = [{ field_id: :filter, nested: [{ field_id: :query, runbook_variable: 'my_query_var' }] }]
        resolved = resolve(mapping, schema: nested_field_schema, context: context)
        expect(resolved).to be_valid
        expect(resolved[:filter][:query]).to eq('search_term')
      end
    end

    context 'variable on date_time field (variable_resolvable)' do
      let(:datetime_field_schema) do
        IPaaS::Connector::Schema.new('datetime_variable') do
          field :cutoff_time, 'Cutoff Time', :date_time
        end
      end

      it 'should accept a valid datetime string from environment variable' do
        context = double
        allow(context).to receive(:environment) { { my_var: 'Tue, 11 Jun 2024 16:55:50 +0200' } }
        allow(context).to receive(:runbook) { nil }

        mapping = [{ field_id: :cutoff_time, variable: 'my_var' }]
        resolved = resolve(mapping, schema: datetime_field_schema, context: context)
        expect(resolved).to be_valid
        expect(resolved[:cutoff_time]).to be_a(DateTime)
      end

      it 'should accept a nil runbook variable in designer mode' do
        context = double
        runbook = double
        allow(context).to receive(:runbook) { runbook }
        allow(runbook).to receive(:read_variable).with('my_datetime_var') { nil }
        allow(runbook).to receive(:designer_mode?) { true }

        mapping = [{ field_id: :cutoff_time, runbook_variable: 'my_datetime_var' }]
        resolved = resolve(mapping, schema: datetime_field_schema, context: context)
        expect(resolved).to be_valid
      end

      it 'should accept a nil runbook variable at runtime without nesting mismatch' do
        context = double
        runbook = double
        allow(context).to receive(:runbook) { runbook }
        allow(runbook).to receive(:read_variable).with('my_datetime_var') { nil }
        allow(runbook).to receive(:designer_mode?) { false }

        mapping = [{ field_id: :cutoff_time, runbook_variable: 'my_datetime_var' }]
        resolved = resolve(mapping, schema: datetime_field_schema, context: context)
        expect(resolved).to be_valid
        expect(resolved.errors[:base]).not_to include(a_string_matching(/expects nested values/))
      end

      it 'should report type mismatch (not nesting mismatch) for invalid datetime string' do
        context = double
        allow(context).to receive(:environment) { { my_var: 'not-a-date' } }
        allow(context).to receive(:runbook) { nil }

        mapping = [{ field_id: :cutoff_time, variable: 'my_var' }]
        resolved = resolve(mapping, schema: datetime_field_schema, context: context)
        expect(resolved).not_to be_valid
        expect(resolved.errors[:base]).to include(
          "Type of field 'cutoff_time' invalid, expected DateTime found String."
        )
      end
    end

    it 'should validate enumeration' do
      resolved = resolve_restricted([{ field_id: :baz, fixed: 'BAk' }])
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include("Field 'baz' should be one of FOO, BAR, BAZ.")
    end

    context 'time_zone' do
      it 'should accept valid time zones' do
        time_zone_schema = IPaaS::Connector::Schema.new('reference2') do
          field :foo, 'Foo', :time_zone
        end

        resolved = resolve([{ field_id: :foo, fixed: 'amsterdam' }], schema: time_zone_schema)
        expect(resolved).to be_valid
      end

      it 'should validate the time zone' do
        time_zone_schema = IPaaS::Connector::Schema.new('reference2') do
          field :foo, 'Foo', :time_zone
        end

        resolved = resolve([{ field_id: :foo, fixed: 'utrecht' }], schema: time_zone_schema)
        expect(resolved).not_to be_valid
        expect(resolved.errors[:base]).to include("Field 'foo' is invalid.")
      end
    end

    context 'uri' do
      it 'should accept valid URI' do
        time_zone_schema = IPaaS::Connector::Schema.new('reference2') do
          field :foo, 'Foo', :uri
        end

        resolved = resolve([{ field_id: :foo, fixed: 'http://foo.example.com' }], schema: time_zone_schema)
        expect(resolved).to be_valid
      end

      it 'should validate the URI' do
        time_zone_schema = IPaaS::Connector::Schema.new('reference2') do
          field :foo, 'Foo', :uri
        end

        resolved = resolve([{ field_id: :foo, fixed: 'utrecht' }], schema: time_zone_schema)
        expect(resolved).not_to be_valid
        expect(resolved.errors[:base]).to include("Field 'foo' is invalid.")
      end
    end

    context 'date_time' do
      it 'should accept valid date time' do
        test_schema = IPaaS::Connector::Schema.new('reference2') do
          field :foo, 'Foo', :date_time
        end

        resolved = resolve([{ field_id: :foo, fixed: '2024-08-27T12:16:56+02:00' }], schema: test_schema)
        expect(resolved).to be_valid
        expect(resolved.to_json).to eq({ foo: '2024-08-27T12:16:56+02:00' }.to_json)
      end
    end

    context 'to_json' do
      it 'should return the resolved hash, not the field definitions' do
        test_schema = IPaaS::Connector::Schema.new('reference2') do
          field :foo, 'Foo', :string
        end

        resolved = resolve([{ field_id: :foo, fixed: 'bar' }], schema: test_schema)
        expect(resolved.to_json).to eq({ foo: 'bar' }.to_json)
      end
    end

    context 'with_indifferent_access' do
      it 'should return the hash' do
        test_schema = IPaaS::Connector::Schema.new('reference2') do
          field :foo, 'Foo', :string
        end

        resolved = resolve([{ field_id: :foo, fixed: 'bar' }], schema: test_schema)
        expect(resolved.with_indifferent_access['foo']).to eq('bar')
        expect(resolved.with_indifferent_access[:foo]).to eq('bar')
      end
    end

    context 'delegation of manipulation' do
      before(:each) do
        test_schema = IPaaS::Connector::Schema.new('reference2') do
          field :foo, 'Foo', :string
          field :bar, 'Bar', :string
        end

        @resolved = resolve([{ field_id: :foo, fixed: 'foo' }, { field_id: :bar, fixed: 'bar' }], schema: test_schema)
      end

      context 'slice' do
        it 'should slice a plain version of the resolved hash' do
          expect(@resolved.slice(:foo)).to eq({ foo: 'foo' }.with_indifferent_access)
          expect(@resolved.slice(:bar)).to eq({ bar: 'bar' }.with_indifferent_access)
        end

        it 'should not update the resolved hash even when slice! is used' do
          @resolved.slice!(:foo)
          expect(@resolved.keys).to eq(%w[foo bar])
        end
      end

      context 'except' do
        it 'should except a plain version of the resolved hash' do
          expect(@resolved.except(:foo)).to eq({ bar: 'bar' }.with_indifferent_access)
          expect(@resolved.except(:bar)).to eq({ foo: 'foo' }.with_indifferent_access)
        end

        it 'should not update the resolved hash even when except! is used' do
          @resolved.except!(:foo)
          expect(@resolved.keys).to eq(%w[foo bar])
        end
      end
    end

    context 'field_mapping errors' do
      it 'should add errors to the field mapping' do
        resolved = resolve_restricted([{ field_id: :bar, fixed: 2 }])
        expect(resolved).not_to be_valid
        expect(resolved.errors[:base]).to include("Field 'bar' should be at least 4.")
        expect(resolved.mapping.first.errors[:base]).to include("Field 'bar' should be at least 4.")
      end
    end

    it 'should add base error details' do
      resolved = resolve_restricted([{ field_id: :foo, fixed: 'fixed' }])
      exception = RuntimeError.new('Test exception')
      exception.set_backtrace(<<~TRACE.split("\n"))
        /Users/john.doe/Documents/dev/ipaas-gui/../ipaas-demo/accounts/1/solution-0193543a-dc23-73eb-8a6e-a46b73d3aa77/connectors/xurrent_webhook_connector.rb:192:in `+'
        /Users/john.doe/.asdf/installs/ruby/3.3.4/lib/ruby/gems/3.3.0/bundler/gems/ipaas-connector-5df57d095cf4/lib/ipaas/connector/common/proc_helper.rb:76:in `instance_exec'
        /Users/john.doe/.asdf/installs/ruby/3.3.4/lib/ruby/gems/3.3.0/gems/activesupport-7.2.1/lib/active_support/callbacks.rb:362:in `block in make_lambda'
        <internal:kernel>:90:in `tap'
        /Users/john.doe/.asdf/installs/ruby/3.3.4/lib/ruby/gems/3.3.0/bundler/gems/ipaas-connector-5df57d095cf4/lib/ipaas/connector/trigger.rb:42:in `parse'
        /Users/john.doe/Documents/dev/ipaas-gui/app/models/concerns/yaml_based_model.rb:90:in `find'
        /Users/john.doe/Documents/dev/ipaas-gui/app/models/concerns/yaml_based_model.rb:79:in `block in all'
        /Users/john.doe/Documents/dev/ipaas-gui/app/models/concerns/yaml_based_model.rb:79:in `map'
      TRACE
      resolved.base_error = exception
      expect(resolved).not_to be_valid
      expect(resolved.errors[:base]).to include('Test exception')
      expect(resolved.errors[:base]).to include(<<~TRACE.strip)
        /connectors/xurrent_webhook_connector.rb:192:in `+'
        /connector/common/proc_helper.rb:76:in `instance_exec'
        /connector/trigger.rb:42:in `parse'
      TRACE
    end

    context 'individual nested field errors' do
      let(:scheduler_schema) do
        IPaaS::Connector::Schema.new('scheduler') do
          field :schedule, 'Schedule', :recurrence, required: true do
            field :frequency, 'Frequency', :string,
                  required: true,
                  enumeration: %w[no_repeat hourly daily weekly monthly yearly]
            field :time_zone, 'Time Zone', :string, required: true
            field :interval, 'Interval', :integer, required: true
            field :time_of_day, 'Time of Day', :string, required: true
          end
        end
      end

      let(:deeply_nested_schema) do
        IPaaS::Connector::Schema.new('deeply_nested') do
          field :level1, 'Level 1', :nested do
            field :level2, 'Level 2', :nested do
              field :level3, 'Level 3', :nested do
                field :deep_field, 'Deep Field', :string,
                      required: true,
                      enumeration: %w[valid_value]
              end
            end
          end
        end
      end

      let(:deeply_nested_field_mapping) do
        [
          {
            field_id: :level1,
            nested: [
              {
                field_id: :level2,
                nested: [
                  {
                    field_id: :level3,
                    nested: [
                      { field_id: :deep_field, fixed: 'invalid_value' },
                    ],
                  },
                ],
              },
            ],
          },
        ]
      end

      def resolve_scheduler(field_mapping)
        resolve(field_mapping, schema: scheduler_schema)
      end

      it 'should populate individual nested field errors when validation fails' do
        field_mapping = [
          {
            field_id: :schedule,
            nested: [
              { field_id: :frequency, fixed: 'invalid_frequency' },
              { field_id: :time_zone, fixed: 'UTC' },
              { field_id: :interval, fixed: 1 },
              { field_id: :time_of_day, fixed: '12:00:00' },
            ],
          },
        ]

        resolved = resolve_scheduler(field_mapping)
        expect(resolved).not_to be_valid

        # Check that the parent field has the nested error
        expect(resolved.errors[:base])
          .to include(
            "Nested field 'schedule' invalid: Field 'frequency' should be one of no_repeat, " \
            'minutely, hourly, daily, weekly, monthly, yearly.'
          )

        # Check that the individual nested field has the error
        schedule_mapping = resolved.mapping.first
        expect(schedule_mapping.nested.first.errors[:base])
          .to include("Field 'frequency' should be one of no_repeat, minutely, hourly, daily, weekly, monthly, yearly.")

        expect(schedule_mapping.nested[1].errors[:base]).to be_empty
        expect(schedule_mapping.nested[2].errors[:base]).to be_empty
        expect(schedule_mapping.nested[3].errors[:base]).to be_empty
      end

      it 'should clear nested field errors before validation to prevent duplicates' do
        field_mapping = [
          {
            field_id: :schedule,
            nested: [
              { field_id: :frequency, fixed: 'invalid_frequency' },
              { field_id: :time_zone, fixed: 'UTC' },
              { field_id: :interval, fixed: 1 },
              { field_id: :time_of_day, fixed: '12:00:00' },
            ],
          },
        ]

        resolved = resolve_scheduler(field_mapping)
        expect(resolved).not_to be_valid

        schedule_mapping = resolved.mapping.first
        expect(schedule_mapping.nested.first.errors[:base])
          .to include("Field 'frequency' should be one of no_repeat, minutely, hourly, daily, weekly, monthly, yearly.")

        resolved2 = resolve_scheduler(field_mapping)
        expect(resolved2).not_to be_valid

        # Check that the error is not duplicated
        schedule_mapping2 = resolved2.mapping.first
        frequency_errors = schedule_mapping2.nested.first.errors[:base]
        message = "Field 'frequency' should be one of no_repeat, minutely, hourly, daily, weekly, monthly, yearly."
        expect(frequency_errors.count(message)).to eq(1)
      end

      it 'should handle multiple nested field errors correctly' do
        field_mapping = [
          {
            field_id: :schedule,
            nested: [
              { field_id: :frequency, fixed: 'invalid_frequency' },
              { field_id: :time_zone, fixed: 'invalid_timezone' },
              { field_id: :interval, fixed: 1 },
              { field_id: :time_of_day, fixed: '12:00:00' },
            ],
          },
        ]

        resolved = resolve_scheduler(field_mapping)
        expect(resolved).not_to be_valid

        # Check that both nested fields have their respective errors
        schedule_mapping = resolved.mapping.first
        expect(schedule_mapping.nested.first.errors[:base])
          .to include("Field 'frequency' should be one of no_repeat, minutely, hourly, daily, weekly, monthly, yearly.")
        expect(schedule_mapping.nested[1].errors[:base]).to include("Field 'time_zone' is invalid.")
      end

      it 'should not populate errors for nested fields when validation passes' do
        field_mapping = [
          {
            field_id: :schedule,
            nested: [
              { field_id: :frequency, fixed: 'daily' },
              { field_id: :time_zone, fixed: 'UTC' },
              { field_id: :interval, fixed: 1 },
              { field_id: :time_of_day, fixed: '12:00:00' },
            ],
          },
        ]

        resolved = resolve_scheduler(field_mapping)
        expect(resolved).to be_valid

        schedule_mapping = resolved.mapping.first
        expect(schedule_mapping.nested.first.errors[:base]).to be_empty
        expect(schedule_mapping.nested[1].errors[:base]).to be_empty
        expect(schedule_mapping.nested[2].errors[:base]).to be_empty
        expect(schedule_mapping.nested[3].errors[:base]).to be_empty
      end

      it 'should handle deeply nested field errors correctly' do
        resolved = resolve(deeply_nested_field_mapping, schema: deeply_nested_schema)
        expect(resolved).not_to be_valid

        # Check that the error is propagated to the deeply nested field
        level1_mapping = resolved.mapping.first
        level2_mapping = level1_mapping.nested.first
        level3_mapping = level2_mapping.nested.first
        deep_field_mapping = level3_mapping.nested.first

        expect(deep_field_mapping.errors[:base]).to include("Field 'deep_field' should be one of valid_value.")
      end

      it 'should store errors in all parent levels for deeply nested fields' do
        resolved = resolve(deeply_nested_field_mapping, schema: deeply_nested_schema)
        expect(resolved).not_to be_valid

        level1_mapping = resolved.mapping.first
        level2_mapping = level1_mapping.nested.first
        level3_mapping = level2_mapping.nested.first

        expect(level1_mapping.errors[:base])
          .to include(
            "Nested field 'level1' invalid: Nested field 'level2' invalid: Nested field 'level3' invalid: " \
            "Field 'deep_field' should be one of valid_value."
          )

        expect(level2_mapping.errors[:base])
          .to include("Nested field 'level2' invalid: Nested field 'level3' invalid: Field 'deep_field' " \
                      'should be one of valid_value.')

        expect(level3_mapping.errors[:base])
          .to include("Nested field 'level3' invalid: Field 'deep_field' should be one of valid_value.")

        deep_field_mapping = level3_mapping.nested.first
        expect(deep_field_mapping.errors[:base]).to include("Field 'deep_field' should be one of valid_value.")
      end

      it 'should prune unknown fields' do
        resolved = resolve_restricted([{ field_id: :unknown, fixed: 20 }, { field_id: :foo, fixed: 'food' }])
        expect(resolved).to be_valid
        expect(resolved).to eq({ 'foo' => 'food' })
      end

      it 'should prune deeply nested schema fields' do
        field_mapping = [
          {
            field_id: :level1,
            nested: [
              {
                field_id: :level2,
                nested: [
                  {
                    field_id: :level3,
                    nested: [
                      { field_id: :extra, fixed: 'hi' },
                      { field_id: :deep_field, fixed: 'valid_value' },
                    ],
                  },
                ],
              },
            ],
          },
        ]
        resolved = resolve(field_mapping, schema: deeply_nested_schema)
        expect(resolved).to be_valid
        expect(resolved).to eq({ 'level1' => { 'level2' => { 'level3' => { 'deep_field' => 'valid_value' } } } })
      end

      it 'should prune unknown fields from array elements' do
        resolved = resolve([
          { field_id: :foo, fixed: 'valid_foo' },
          { field_id: :cars, fixed: [
            { name: 'MV', nr: 33, unknown_field: 'should_be_pruned' },
            { name: 'LH', nr: 44 },
            { name: 'CS', nr: 55, invalid_prop: 'remove_me' },
          ], },
        ])
        expect(resolved).to be_valid
        expect(resolved[:cars]).to eq([
          { 'name' => 'MV', 'nr' => 33 },
          { 'name' => 'LH', 'nr' => 44 },
          { 'name' => 'CS', 'nr' => 55 },
        ])
        expect(resolved[:foo]).to eq('valid_foo')
      end

      context 'complex nested structures with arrays' do
        let(:complex_schema) do
          IPaaS::Connector::Schema.new('complex') do
            field :organization, 'Organization', :nested do
              field :name, 'Name', :string, required: true
              field :departments, 'Departments', [:nested] do
                field :dept_name, 'Department Name', :string, required: true
                field :employees, 'Employees', [:nested] do
                  field :emp_name, 'Employee Name', :string, required: true
                  field :role, 'Role', :string
                  field :skills, 'Skills', [:string]
                end
                field :budget, 'Budget', :integer
              end
              field :location, 'Location', :string
            end
            field :metadata, 'Metadata', :nested do
              field :version, 'Version', :string
              field :tags, 'Tags', [:string]
            end
          end
        end

        def resolve_complex(field_mapping)
          resolve(field_mapping, schema: complex_schema)
        end

        it 'should prune unknown fields from deeply nested arrays and objects' do
          field_mapping = [
            {
              field_id: :organization,
              nested: [
                { field_id: :name, fixed: 'ACME Corp' },
                { field_id: :location, fixed: 'New York' },
                { field_id: :departments, fixed: [
                  {
                    dept_name: 'Engineering',
                    budget: 100_000,
                    unknown_field: 'should_be_removed',
                    employees: [
                      {
                        emp_name: 'Alice',
                        role: 'Senior Developer',
                        skills: %w[Ruby JavaScript],
                        salary: 80_000,  # unknown field
                        office_number: 'A123',  # unknown field
                      },
                      {
                        emp_name: 'Bob',
                        role: 'Junior Developer',
                        experience_years: 2,  # unknown field
                        skills: ['Python'],
                      },
                    ],
                    head_count: 15,  # unknown field
                  },
                  {
                    dept_name: 'Marketing',
                    budget: 50_000,
                    employees: [
                      {
                        emp_name: 'Charlie',
                        role: 'Marketing Manager',
                        previous_company: 'XYZ Inc',  # unknown field
                        skills: ['SEO', 'Content Marketing'],
                      },
                    ],
                    office_floor: 3,  # unknown field
                  },
                ], },
              ],
            },
            {
              field_id: :metadata,
              nested: [
                { field_id: :version, fixed: '1.0.0' },
                { field_id: :tags, fixed: %w[production enterprise] },
              ],
            },
          ]

          resolved = resolve_complex(field_mapping)
          expect(resolved).to be_valid

          expected_result = {
            'organization' => {
              'name' => 'ACME Corp',
              'location' => 'New York',
              'departments' => [
                {
                  'dept_name' => 'Engineering',
                  'budget' => 100_000,
                  'employees' => [
                    {
                      'emp_name' => 'Alice',
                      'role' => 'Senior Developer',
                      'skills' => %w[Ruby JavaScript],
                    },
                    {
                      'emp_name' => 'Bob',
                      'role' => 'Junior Developer',
                      'skills' => ['Python'],
                    },
                  ],
                },
                {
                  'dept_name' => 'Marketing',
                  'budget' => 50_000,
                  'employees' => [
                    {
                      'emp_name' => 'Charlie',
                      'role' => 'Marketing Manager',
                      'skills' => ['SEO', 'Content Marketing'],
                    },
                  ],
                },
              ],
            },
            'metadata' => {
              'version' => '1.0.0',
              'tags' => %w[production enterprise],
            },
          }

          expect(resolved).to eq(expected_result)
        end

        it 'should handle empty arrays and null values while pruning unknown fields' do
          field_mapping = [
            {
              field_id: :organization,
              nested: [
                { field_id: :name, fixed: 'Empty Corp' },
                { field_id: :departments, fixed: [] },  # empty array
                { field_id: :unknown_org_field, fixed: 'should_be_pruned' },
              ],
            },
            {
              field_id: :metadata,
              nested: [
                { field_id: :version, fixed: nil },  # null value
                { field_id: :tags, fixed: [] },  # empty array
                { field_id: :unknown_meta_field, fixed: 'also_pruned' },
              ],
            },
            { field_id: :completely_unknown, fixed: 'top_level_unknown' },
          ]

          resolved = resolve_complex(field_mapping)
          expect(resolved).to be_valid

          expected_result = {
            'organization' => {
              'name' => 'Empty Corp',
              'departments' => [],
            },
            'metadata' => {
              'version' => nil,
              'tags' => [],
            },
          }

          expect(resolved).to eq(expected_result)
        end

        it 'should prune unknown fields from proc-generated arrays' do
          field_mapping = [
            {
              field_id: :organization,
              nested: [
                { field_id: :name, fixed: 'Proc Corp' },
                { field_id: :departments, proc: '[
                  {
                    dept_name: "Generated Dept",
                    budget: 75000,
                    employees: [
                      {
                        emp_name: "Generated Employee",
                        role: "Developer",
                        skills: ["Ruby"],
                        generated_field: "should_be_pruned"
                      }
                    ],
                    proc_generated_field: "also_pruned"
                  }
                ]', },
              ],
            },
          ]

          resolved = resolve_complex(field_mapping)
          expect(resolved).to be_valid

          expected_result = {
            'organization' => {
              'name' => 'Proc Corp',
              'departments' => [
                {
                  'dept_name' => 'Generated Dept',
                  'budget' => 75_000,
                  'employees' => [
                    {
                      'emp_name' => 'Generated Employee',
                      'role' => 'Developer',
                      'skills' => ['Ruby'],
                    },
                  ],
                },
              ],
            },
          }

          expect(resolved).to eq(expected_result)
        end

        it 'should prune unknown fields from nested mappings with variable references' do
          context = double
          runbook = double
          allow(context).to receive(:runbook) { runbook }
          allow(runbook).to receive(:read_variable).with('cars_data') do
            [
              {
                name: 'Variable Car',
                nr: 42,
                unknown_from_variable: 'should_be_pruned',
                extra_data: { nested: 'structure' },
              },
            ]
          end

          resolved = resolve([
            { field_id: :foo, fixed: 'test' },
            { field_id: :cars, runbook_variable: 'cars_data' },
          ], context: context)

          expect(resolved).to be_valid
          expect(resolved[:cars]).to eq([{ 'name' => 'Variable Car', 'nr' => 42 }])
        end
      end
    end

    context 'remove_unmapped_fields: false behavior' do
      let(:no_prune_schema) do
        IPaaS::Connector::Schema.new('no_prune') do
          field :organization, 'Organization', :nested, remove_unmapped_fields: false do
            field :name, 'Name', :string, required: true
            field :departments, 'Departments', [:nested], remove_unmapped_fields: true do
              field :dept_name, 'Department Name', :string, required: true
              field :employees, 'Employees', [:nested], remove_unmapped_fields: false do
                field :emp_name, 'Employee Name', :string, required: true
                field :role, 'Role', :string
              end
            end
            field :location, 'Location', :string
          end
          field :metadata, 'Metadata', :nested do
            field :version, 'Version', :string
            field :tags, 'Tags', [:string]
          end
        end
      end

      let(:deeply_nested_no_prune_schema) do
        IPaaS::Connector::Schema.new('deeply_nested_no_prune') do
          field :level1, 'Level 1', :nested, remove_unmapped_fields: false do
            field :level2, 'Level 2', :nested, remove_unmapped_fields: true do
              field :level3, 'Level 3', :nested, remove_unmapped_fields: false do
                field :deep_field, 'Deep Field', :string, required: true
              end
            end
          end
        end
      end

      def resolve_no_prune(field_mapping)
        resolve(field_mapping, schema: no_prune_schema)
      end

      def resolve_deeply_nested_no_prune(field_mapping)
        resolve(field_mapping, schema: deeply_nested_no_prune_schema)
      end

      it 'should keep unknown fields in nested structure when remove_unmapped_fields is false' do
        field_mapping = [
          {
            field_id: :organization,
            fixed: {
              name: 'ACME Corp',
              location: 'New York',
              unknown_org_field: 'should_be_kept',  # This should be kept
              extra_data: { nested: 'structure' },  # This should be kept
            },
          },
          {
            field_id: :metadata,
            fixed: {
              version: '1.0.0',
              unknown_meta_field: 'should_be_pruned',  # This should be pruned
            },
          },
        ]

        resolved = resolve_no_prune(field_mapping)
        expect(resolved).to be_valid

        expected_result = {
          'organization' => {
            'name' => 'ACME Corp',
            'location' => 'New York',
            'unknown_org_field' => 'should_be_kept',
            'extra_data' => { 'nested' => 'structure' },
          },
          'metadata' => {
            'version' => '1.0.0',
          },
        }

        expect(resolved).to eq(expected_result)
      end

      it 'should keep unknown fields in nested arrays when remove_unmapped_fields is false' do
        field_mapping = [
          {
            field_id: :organization,
            fixed: {
              name: 'Array Corp',
              departments: [
                {
                  dept_name: 'Engineering',
                  unknown_dept_field: 'should_be_kept',  # pruned
                  budget_info: { amount: 100_000, currency: 'USD' },  # pruned
                  employees: [
                    {
                      emp_name: 'Alice',
                      role: 'Senior Developer',
                      salary: 80_000,  # kept
                    },
                    {
                      emp_name: 'Bob',
                      role: 'Junior Developer',
                      experience_years: 2,  # kept
                    },
                  ],
                },
                {
                  dept_name: 'Marketing',
                  team_lead: 'Charlie',  # pruned
                  employees: [],
                },
              ],
            },
          },
        ]

        resolved = resolve_no_prune(field_mapping)
        expect(resolved).to be_valid

        expected_result = {
          'organization' => {
            'name' => 'Array Corp',
            'departments' => [
              {
                'dept_name' => 'Engineering',
                'employees' => [
                  {
                    'emp_name' => 'Alice',
                    'role' => 'Senior Developer',
                    'salary' => 80_000,
                  },
                  {
                    'emp_name' => 'Bob',
                    'role' => 'Junior Developer',
                    'experience_years' => 2,
                  },
                ],
              },
              {
                'dept_name' => 'Marketing',
                'employees' => [],
              },
            ],
          },
        }

        expect(resolved).to eq(expected_result)
      end

      context 'when nested field sub-fields contain nil entries' do
        let(:nil_subfields_schema) do
          schema = IPaaS::Connector::Schema.new('nil_subfields') do
            field :data, 'Data', :nested do
              field :name, 'Name', :string
            end
          end
          schema.tap do |s|
            data_field = s.field(:data)
            data_field.fields = [nil, *data_field.fields_without_nested_schema]
          end
        end

        it 'does not crash when pruning unmapped fields' do
          resolved = resolve(
            [{ field_id: :data, fixed: { name: 'Alice', extra: 'unexpected' } }],
            schema: nil_subfields_schema,
          )
          expect(resolved['data']['name']).to eq('Alice')
        end

        it 'does not crash when recursively resolving nested values' do
          resolved = resolve(
            [{ field_id: :data, fixed: { name: 'Alice' } }],
            schema: nil_subfields_schema,
          )
          expect(resolved['data']['name']).to eq('Alice')
        end
      end

      it 'should keep unknown fields in deeply nested structures when remove_unmapped_fields is false' do
        field_mapping = [
          {
            field_id: :level1,
            fixed: {
              level2: {
                level3: {
                  deep_field: 'valid_value',
                  extra_level3_field: 'should_be_kept',
                },
                extra_level2_field: 'also_kept',
              },
              extra_level1_field: { complex: 'data' },
            },
          },
        ]

        resolved = resolve_deeply_nested_no_prune(field_mapping)
        expect(resolved).to be_valid

        expected_result = {
          'level1' => {
            'level2' => {
              'level3' => {
                'deep_field' => 'valid_value',
                'extra_level3_field' => 'should_be_kept',
              },
            },
            'extra_level1_field' => { 'complex' => 'data' },
          },
        }

        expect(resolved).to eq(expected_result)
      end
    end
  end
end
