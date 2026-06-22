require 'spec_helper'

describe IPaaS::Connector::Action do
  let(:runbook) do
    IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7).tap do |runbook|
      runbook.store_trigger_output({ foo: 'bar' })
      mocked_solution = double(:solution)
      allow(mocked_solution).to receive(:test_cases_for).with(runbook.uuid).and_return([])
      allow(runbook).to receive(:solution).and_return(mocked_solution)
    end
  end

  let(:connector) do
    IPaaS::Connector::Connector.new('unique-connector-id') do
      outbound_connection do
        api_key_authenticator

        config_schema do
          field :foo, 'Foo', :string
        end
      end

      action 'unique-action-id' do
        name 'Calculator'
        nested true

        input_schema do
          field :numbers,
                'Numbers',
                [:integer],
                required: true
          field :operator,
                'Operator',
                :string,
                required: true,
                enumeration: %w[sum min max my_object_id]
          field :multi_output,
                'Multi-output',
                :string
          field :trigger_output,
                'Trigger-output',
                :string
          field :other_action_output,
                'Output from earlier action',
                :string

          after_update do |_fields, values|
            multi_output = values[:multi_output]
            unless multi_output == 'skip_schema_update'
              output_schema('output-2').fields.first.id = multi_output&.to_sym || :foo
            end
          end
        end

        output_schema 'output-1' do
          field :outcome, 'Outcome', :integer
        end

        output_schema 'output-2' do
          field :multi, 'Multi', :string
        end

        run do
          outcome = helpers.compute_outcome(input[:operator])
          result = [{ schema_reference: 'output-1', output: { outcome: outcome } }]
          if input[:multi_output].present?
            result << { schema_reference: 'output-2',
                        output: { input[:multi_output] => outbound_connection.config[:foo] }, }
          end
          result
        end
      end

      helper :compute_outcome do |operator|
        numbers = input[:numbers]
        case operator
        when 'sum'
          numbers.sum
        when 'min'
          numbers.min
        when 'my_object_id'
          object_id
        else
          numbers.max
        end
      end
    end
  end

  let(:outbound_connection) do
    IPaaS::Connector::Connection.parse(
      {
        uuid: 'connection_uuid',
        direction: 'outbound',
        name: 'test outbound connection',
        description: 'Test description',
        connector: {
          uuid: connector.uuid,
        },
        config_mapping: [
          { field_id: 'foo', fixed: 'barbie' },
        ],
      },
    )
  end

  let(:action) do
    @operator ||= 'sum'
    @multi_output ||= nil

    IPaaS::Connector::Action.parse(
      runbook,
      {
        reference: 'action_reference',
        description: 'Test description',
        outbound_connection: {
          uuid: outbound_connection.uuid,
        },
        action_template: {
          uuid: 'unique-action-id',
        },
        input_mapping: [
          { field_id: 'numbers', fixed: [1, 3, 5, 10, 20] },
          { field_id: 'operator', fixed: @operator },
          { field_id: 'multi_output', fixed: @multi_output },
        ],
      },
    )
  end

  context 'validation' do
    it 'should be valid' do
      expect(action).to be_valid
    end

    it 'should validate a runbook is supplied' do
      expect do
        IPaaS::Connector::Action.parse(nil, {})
      end.to raise_error('Action must have a runbook.')
    end

    it 'should validate the given value is a hash' do
      expect do
        IPaaS::Connector::Action.parse(runbook, [1, 2])
      end.to raise_error('Action must be a hash.')
    end

    it 'should validate outbound connection is optional' do
      action.outbound_connection = nil
      expect(action).to be_valid
    end

    it 'should validate outbound connection is valid' do
      connection = double
      expect(connection).to receive(:valid?).and_return(false)
      expect(connection).to receive(:full_error_messages).and_return(['Broken', 'And just wrong'])
      action.outbound_connection = connection

      expect(action).not_to be_valid
      # there is also an error that it is the wrong type

      expect(action.errors[:outbound_connection]).to include('invalid: ["Broken", "And just wrong"]')
    end

    it 'should validate action template is required' do
      expect(action.action_template.uuid).to eq('unique-action-id')
      action.action_template = nil
      expect(action).not_to be_valid
      expect(action.errors[:action_template]).to eq(["can't be blank."])
    end

    it 'should validate the input' do
      invalid_action = IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'action_uuid',
          description: 'Test description',
          outbound_connection: {
            uuid: outbound_connection.uuid,
          },
          action_template: {
            uuid: 'unique-action-id',
          },
          input_mapping: [
            { field_id: 'operator', fixed: 'sum' },
          ],
        }.to_yaml
      )
      expect(invalid_action).not_to be_valid
      expect(invalid_action.errors[:input_mapping]).to include("invalid: Field 'numbers' is required.")
    end

    it 'should validate the procs of the input mapping' do
      invalid_action = IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'action_reference',
          description: 'Test description',
          outbound_connection: {
            uuid: outbound_connection.uuid,
          },
          action_template: {
            uuid: 'unique-action-id',
          },
          input_mapping: [
            { field_id: 'operator', proc: 'unknown(3)' },
          ],
        }.to_yaml
      )
      expect(invalid_action).not_to be_valid
      message = "(operator) invalid: Proc invalid: Method 'unknown' not allowed."
      expect(invalid_action.errors[:input_mapping]).to include(message)
    end
  end

  context 'runbook variables' do
    let(:outbound_connection) do
      IPaaS::Connector::Connection.parse(
        {
          uuid: 'connection_uuid',
          direction: 'outbound',
          name: 'test outbound connection',
          description: 'Test description',
          connector: {
            uuid: connector.uuid,
          },
          config_mapping: [
            { field_id: 'foo', proc: 'runbook.read_variable("my-connection-variable")' },
          ],
        },
      )
    end

    let(:runbook_variable_action) do
      IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'action_reference',
          description: 'Test description',
          outbound_connection: {
            uuid: outbound_connection.uuid,
          },
          action_template: {
            uuid: 'unique-action-id',
          },
          input_mapping: [
            { field_id: 'numbers', runbook_variable: 'my-variable' },
            { field_id: 'operator', runbook_variable: 'my-operator-variable' },
          ],
        },
      )
    end

    before(:each) do
      IPaaS::Connector::Runbook.parse_runbook_variables(runbook, [
        { id: 'my-variable', label: 'My Variable', type: :integer, array: true },
        { id: 'my-operator-variable', label: 'My Operator Variable', type: :string },
        { id: 'my-connection-variable', label: 'My Connection Variable', type: :string },
      ])
    end

    it 'should resolve runbook variables when runbook is present' do
      runbook_variable_action.runbook.write_variable('my-variable', [1, 42])
      runbook_variable_action.runbook.write_variable('my-operator-variable', 'max')
      runbook_variable_action.runbook.write_variable('my-connection-variable', 'bar')

      runbook_variable_action.run # run will update mappings with runbook-variables

      expect(runbook_variable_action.input[:numbers]).to eq([1, 42])
      expect(runbook_variable_action.input[:operator]).to eq('max')
      expect(runbook_variable_action.outbound_connection.config[:foo]).to eq('bar')
    end

    it 'should raise an error when the resolved input mapping is invalid' do
      expect do
        runbook_variable_action.runbook.write_variable('my-variable', 'foo')
      end.to raise_error(IPaaS::Job::FailJob,
                         "Runbook variable 'my-variable': " \
                         "Value Type of field 'my-variable[0]' invalid, expected Integer found String.")
    end

    it 'should raise an error when the resolved outbound connection config mapping is invalid' do
      runbook_variable_action.runbook.write_variable('my-variable', [1, 42])
      runbook_variable_action.runbook.write_variable('my-operator-variable', 'max')

      expect do
        runbook_variable_action.runbook.write_variable('my-connection-variable', { foo: 'bar' })
      end.to raise_error(IPaaS::Job::FailJob,
                         "Runbook variable 'my-connection-variable': " \
                         "Value Type of field 'my-connection-variable' invalid, expected String found Hash.")
    end
  end

  context 'reference' do
    it 'should take the given reference' do
      expect(action.reference).to eq('action_reference')
    end

    it 'should generate a reference when none is provided' do
      allow(SecureRandom).to receive(:hex) { 'abc' }
      action = IPaaS::Connector::Action.parse(runbook, { name: 'foo' })
      expect(action.reference).to eq('abc')
    end

    it 'generates a reference that is unique within the runbook' do
      allow(SecureRandom).to receive(:hex).and_return('action1', 'action2', 'new_one', 'last_one')

      action1 = IPaaS::Connector::Action.parse(runbook, { name: 'action1', reference: 'action1' })
      action2 = IPaaS::Connector::Action.parse(runbook, { name: 'action2', reference: 'action2' })

      runbook.actions = [action1, action2]
      action3 = IPaaS::Connector::Action.parse(runbook, { name: 'foo' })
      expect(action3.reference).to eq('new_one')

      runbook.actions = [action1, action2, action3]
      action4 = IPaaS::Connector::Action.parse(runbook, { name: 'bar' })
      expect(action4.reference).to eq('last_one')
    end

    it 'refuses to update to a syntactically invalid reference' do
      action1 = IPaaS::Connector::Action.parse(runbook, { name: 'action1', reference: 'action1' })
      action2 = IPaaS::Connector::Action.parse(runbook, { name: 'action2', reference: 'action2' })
      runbook.actions = [action1, action2]

      expect { action1.reference = %(This isn't valid) }
        .to raise_error(IPaaS::Error, %(Action reference cannot contain ', ", ♦ or \\: This isn't valid))

      expect { action1.reference = %(This is not "valid") }
        .to raise_error(IPaaS::Error, %(Action reference cannot contain ', ", ♦ or \\: This is not "valid"))

      expect { action1.reference = %(This is alm♦st valid) }
        .to raise_error(IPaaS::Error, %(Action reference cannot contain ', ", ♦ or \\: This is alm♦st valid))

      expect { action1.reference = %(This is still \\not\\ valid) }
        .to raise_error(IPaaS::Error, %(Action reference cannot contain ', ", ♦ or \\: This is still \\not\\ valid))

      expect { action1.reference = %(This is /fine/) }.not_to raise_error
      expect(action1.reference).to eq(%(This is /fine/))
    end

    it 'refuses to update to a non-unique reference' do
      action1 = IPaaS::Connector::Action.parse(runbook, { name: 'action1', reference: 'action1' })
      action2 = IPaaS::Connector::Action.parse(runbook, { name: 'action2', reference: 'action2' })
      runbook.actions = [action1, action2]

      expect { action2.reference = 'action1' }.to raise_error(IPaaS::Error, 'Action reference is not unique: action1')
    end

    it 'updates predecessor action references' do
      action1 = IPaaS::Connector::Action.parse(runbook, { name: 'action1', reference: 'action1' })
      action2 = IPaaS::Connector::Action.parse(
        runbook, { name: 'action2', reference: 'action2', predecessor_action_reference: 'action1' }
      )
      runbook.actions = [action1, action2]

      action1.reference = 'action1-new'
      expect(action2.predecessor_action_reference).to eq('action1-new')
    end

    it 'updates action references in procs' do
      action1 = IPaaS::Connector::Action.parse(runbook, { name: 'action1', reference: 'action1_uuid' })
      action2 = IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'action2_uuid',
          name: 'action2',
          action_template: { uuid: 'unique-action-id' },
          input_mapping: [
            { field_id: 'field1', proc: 'action_output("action1_uuid")&.fetch("schema_1_uuid")' },
            {
              field_id: 'field2', nested: [
                { field_id: 'field2a', proc: '"foo" + action_output(\'action1_uuid\')&.dig("bar")' },
              ],
            },
          ],
        },
      )

      runbook.actions = [action1, action2]

      action1.reference = 'new-ref'
      expect(action2.input_mapping.first.proc).to eq('action_output("new-ref")&.fetch("schema_1_uuid")')
      expect(action2.input_mapping.last.nested.first.proc).to eq('"foo" + action_output(\'new-ref\')&.dig("bar")')
    end

    describe '#update_runbook_variable' do
      it 'updates runbook variables in input_mapping' do
        action = IPaaS::Connector::Action.parse(
          runbook,
          {
            reference: 'action1',
            name: 'action1',
            action_template: { uuid: 'unique-action-id' },
            input_mapping: [
              { field_id: 'field1', runbook_variable: 'old-id' },
              { field_id: 'field2', proc: 'runbook.read_variable("old-id")' },
              {
                field_id: 'field3',
                nested: [
                  { field_id: 'field3a', runbook_variable: 'old-id' },
                ],
              },
            ],
          }
        )

        updated = action.update_runbook_variable('old-id', 'new-id')

        expect(updated).to be_truthy
        expect(action.input_mapping[0].runbook_variable).to eq('new-id')
        expect(action.input_mapping[1].proc).to eq('runbook.read_variable("new-id")')
        expect(action.input_mapping[2].nested[0].runbook_variable).to eq('new-id')
      end

      it 'returns false when nothing is updated' do
        action = IPaaS::Connector::Action.parse(
          runbook,
          {
            reference: 'action1',
            name: 'action1',
            action_template: { uuid: 'unique-action-id' },
            input_mapping: [
              { field_id: 'field1', fixed: 'other-value' },
            ],
          }
        )

        expect(action.update_runbook_variable('old-id', 'new-id')).to be_falsey

        action.input_mapping = []
        expect(action.update_runbook_variable('old-id', 'new-id')).to be_falsey
      end
    end

    describe 'validates references used in procs' do
      let(:outbound_connection) do
        IPaaS::Connector::Connection.parse(
          {
            uuid: 'connection_uuid',
            direction: 'outbound',
            name: 'test outbound connection',
            description: 'Test description',
            connector: {
              uuid: connector.uuid,
            },
            config_mapping: [
              { field_id: 'foo', fixed: 'barbie' },
            ],
          },
        )
      end

      def create_action(reference, input_mapping:)
        IPaaS::Connector::Action.parse(runbook,
                                       {
                                         name: "Name of #{reference}",
                                         reference: reference,
                                         outbound_connection: { uuid: outbound_connection.uuid },
                                         action_template: { uuid: 'unique-action-id' },
                                         input_mapping: input_mapping,
                                       })
      end

      before(:each) do
        action1 = create_action('action1_uuid',
                                input_mapping: [
                                  { field_id: 'operator', fixed: 'sum' },
                                  { field_id: 'numbers', fixed: [1, 3] },
                                ])
        runbook.actions = [action1]
      end

      it 'allows single quoted references' do
        action2 = create_action('action2_uuid',
                                input_mapping: [
                                  { field_id: 'operator', fixed: 'sum' },
                                  { field_id: 'numbers',
                                    proc: <<~RUBY,
                                      [
                                        action_output('action1_uuid', output_schema_reference: 'output-1')&.dig('outcome'),
                                        action_output('action1_uuid', output_schema_reference: 'output-1')&.dig('outcome'),
                                      ]
                                    RUBY
                                    },
                                ])
        action2.valid?
        expect(action2.errors).to be_empty
      end

      it 'rejects bad single quoted references' do
        action2 = create_action('action2_uuid',
                                input_mapping: [
                                  { field_id: 'operator', fixed: 'sum' },
                                  { field_id: 'numbers',
                                    proc: <<~RUBY,
                                      [
                                        action_output('doesnot_exist', output_schema_reference: 'output-1')&.dig('outcome'),
                                        action_output('doesnot_exist_either', output_schema_reference: 'output-1')&.dig('outcome'),
                                      ]
                                    RUBY
                                  },
                                ])

        action2.valid?
        expect(action2.errors).not_to be_empty
        expect(action2.errors[:input_mapping])
          .to contain_exactly("(numbers) invalid action references: 'doesnot_exist', 'doesnot_exist_either'")
      end

      it 'rejects bad double quoted references' do
        action2 = create_action('action2_uuid',
                                input_mapping: [
                                  { field_id: 'operator', fixed: 'sum' },
                                  { field_id: 'numbers',
                                    proc: <<~RUBY,
                                      [
                                        action_output("nope", output_schema_reference: 'output-1')&.dig('outcome'),
                                        action_output("doesnot_exist_either", output_schema_reference: 'output-1')&.dig('outcome'),
                                        action_output('action1_uuid', output_schema_reference: 'output-1')&.dig('outcome'),
                                        action_output("also_not")&.dig('outcome'),
                                      ]
                                    RUBY
                                  },
                                ])

        action2.valid?
        expect(action2.errors).not_to be_empty
        expect(action2.errors[:input_mapping])
          .to contain_exactly("(numbers) invalid action references: 'nope', 'doesnot_exist_either', 'also_not'")
      end
    end
  end

  it 'should define a self reference' do
    expect(action.action).to eq(action)
  end

  context 'trigger_output' do
    it 'can access runbook trigger' do
      expect(action.trigger_output).to eq({ foo: 'bar' }.with_indifferent_access)
    end
  end

  context 'action_output' do
    it 'can access output from other actions' do
      expect(runbook).to receive(:action_output).with('abc').and_return({ bar: :baz })

      expect(action.action_output('abc')).to eq({ bar: :baz })
    end
  end

  context 'predecessor_output_schema_reference' do
    it 'should set the value as string if present' do
      action.predecessor_output_schema_reference = :foo
      expect(action.predecessor_output_schema_reference).to eq('foo')
    end

    it 'should not set blank values' do
      action.predecessor_output_schema_reference = ' '
      expect(action.predecessor_output_schema_reference).to be_nil
    end
  end

  context 'run' do
    it 'should validate the input mapping' do
      @operator = 'sumo'
      expect do
        action.run
      end.to raise_error(IPaaS::Job::FailJob,
                         "Input invalid: Field 'operator' should be one of sum, min, max, my_object_id.")
    end

    it 'should log the input of the action template run method' do
      expect(action)
        .to receive(:log_input)
        .with({ 'multi_output' => nil, 'numbers' => [1, 3, 5, 10, 20], 'operator' => 'sum' })
      action.run
    end

    it 'should store the output of the action template run method' do
      expect(runbook)
        .to receive(:store_action_output)
        .with(action.reference, { 'outcome' => 39 }, output_schema_reference: 'output-1')
      action.run
    end

    it 'should store the multiple outputs of the action template run method' do
      @multi_output = 'another'
      expect(runbook)
        .to receive(:store_action_output)
        .with(action.reference, { 'outcome' => 39 }, output_schema_reference: 'output-1')
      expect(runbook)
        .to receive(:store_action_output)
        .with(action.reference, { 'another' => 'barbie' }, output_schema_reference: 'output-2')
      action.run
    end

    it 'should store encrypted outputs of the action template run method' do
      @multi_output = 'another'
      fields = action.output_schema.last.fields
      fields.first.type = :secret_string
      fields.first.remove_instance_variable(:@type_def)

      expect(runbook)
        .to receive(:store_action_output)
        .with(action.reference, { 'outcome' => 39 }, output_schema_reference: 'output-1')
      expect(runbook).to receive(:store_action_output) do |uuid, values, attrs|
        expect(uuid).to eq(action.reference)
        expect(attrs[:output_schema_reference]).to eq('output-2')
        expect(values[:another]).to be_a(IPaaS::Encryption::SecretString)
        expect(encryptor.decrypt(values[:another])).to eq('barbie')
      end
      action.run
    end

    it 'should validate the output schema and store only fields defined in schema' do
      @multi_output = 'skip_schema_update'
      expect(runbook)
        .to receive(:store_action_output)
        .with(action.reference, { 'outcome' => 39 }, output_schema_reference: 'output-1')
      expect do
        action.run
      end.not_to raise_error
    end

    it 'should return the output' do
      result = action.run
      expect(result).to eq([{ output: { 'outcome' => 39 }, schema_reference: 'output-1' }])
    end

    it 'should have access to helpers with connection as context' do
      @operator = 'my_object_id'
      result = action.run
      expect(result).to eq([{ output: { 'outcome' => action.object_id }, schema_reference: 'output-1' }])
    end

    it 'should return the multi output' do
      @multi_output = 'another'
      result = action.run
      expect(result).to eq([
        { output: { 'outcome' => 39 }, schema_reference: 'output-1' },
        { output: { 'another' => 'barbie' }, schema_reference: 'output-2' },
      ])
    end

    it 'should return the encrypted output' do
      @multi_output = 'another'
      fields = action.output_schema.last.fields
      fields.first.type = :secret_string
      fields.first.remove_instance_variable(:@type_def)

      result = action.run
      expect(result.pluck(:schema_reference)).to eq(%w[output-1 output-2])
      expect(result.second[:output]['another']).to be_a(IPaaS::Encryption::SecretString)
      expect(encryptor.decrypt(result.second[:output][:another])).to eq('barbie')
    end

    context 'dynamic input in mapping' do
      let(:action) do
        @action ||= IPaaS::Connector::Action.parse(
          runbook,
          {
            reference: 'action_reference',
            description: 'Test description',
            outbound_connection: {
              uuid: outbound_connection.uuid,
            },
            action_template: {
              uuid: 'unique-action-id',
            },
            input_mapping: [
              { field_id: 'numbers', fixed: [1, 20] },
              { field_id: 'operator', fixed: 'min' },
              { field_id: 'multi_output', proc: 'action.store.read("multi")' },
              { field_id: 'trigger_output', proc: 'trigger_output[:foo]' },
              { field_id: 'other_action_output', proc: 'action_output("action0_uuid")&.fetch("schema_0_uuid")' },
            ],
          },
        )
      end

      it 'should reevaluate the input mapping before each run' do
        result = action.run
        expect(result).to eq([
          { output: { 'outcome' => 1 }, schema_reference: 'output-1' },
        ])

        action.store.write('multi', 'foo')

        result = action.run
        expect(result).to eq([
          { output: { 'outcome' => 1 }, schema_reference: 'output-1' },
          { output: { 'foo' => 'barbie' }, schema_reference: 'output-2' },
        ])
      end
    end
  end

  context 'proc referring to `input`' do
    let(:action) do
      @action ||= IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'action_reference',
          description: 'Test description',
          outbound_connection: { uuid: outbound_connection.uuid },
          action_template: { uuid: 'unique-action-id' },
          input_mapping: [
            { field_id: 'trigger_output', proc: '{ input: }' },
            { field_id: 'numbers', fixed: [1, 20] },
            { field_id: 'operator', fixed: 'min' },
            { field_id: 'multi_output', proc: 'action.store.read("multi")' },
            { field_id: 'other_action_output', proc: 'action_output("action0_uuid")&.fetch("schema_0_uuid")' },
          ],
        },
      )
    end

    it 'should fail without getting into a loop' do
      expect do
        action.run
      end.to raise_error(IPaaS::Job::FailJob,
                         "Input invalid: Type of field 'trigger_output' invalid, expected String found Hash.")
    end
  end

  context 'when schema resolution block is not yielded' do
    it 'memoizes the resolve return value so @input is never nil' do
      fallback = double(:resolved_mapping)
      # and_return replaces the method entirely, so the block passed by #input is never yielded
      allow(action.input_schema).to receive(:resolve).and_return(fallback)

      result = action.input(resolve: true)

      expect(result).to be(fallback) # object identity proves fallback path
      expect(action.input).to be(fallback) # memoized on subsequent call
    end

    it 'prefers the block-assigned value over the return value when the block is yielded' do
      resolve_return = action.input_schema.resolve(action, action.input_mapping)

      result = action.input(resolve: true)

      expect(result).not_to be(resolve_return) # block set a different object
      expect(result[:numbers]).to eq([1, 3, 5, 10, 20])
      expect(action.input).to be(result) # memoized on subsequent call
    end
  end

  context 'case' do
    let(:case_connector) do
      IPaaS::Connector::Connector.new('flow') do
        action 'case-action-uuid' do
          name 'Case'
          nested true

          input_schema do
            field :expression,
                  'Expression',
                  :string,
                  required: true
            field :matches,
                  'Matches',
                  :string,
                  array: true,
                  required: true,
                  max_length: 50

            after_update do |_fields, values|
              action.output_schemas.clear

              matches = values[:matches]
              matches.each do |match|
                schema_key = "schema_reference #{match}"
                schema_reference = action.store.read(schema_key)
                unless schema_reference
                  schema_reference = SecureRandom.uuid
                  action.store.write(schema_key, schema_reference)
                end
                output_schema schema_reference do
                  name "Expression resolves to #{match}."
                  field :match,
                        'Match',
                        :string,
                        required: true
                end
              end
            end
          end

          run do
            expression = action.input[:expression]
            schema_reference = action.store.read("schema_reference #{expression}")
            unless schema_reference
              log('No match found for expression %<expression>s.', expression: expression)
              return
            end
            schema_reference = 'invalid' if expression == 'test-invalid-ref'
            if expression == 'test-missing-ref'
              [{ output: { match: expression } }]
            else
              [{ schema_reference: schema_reference, output: { match: expression } }]
            end
          end
        end
      end
    end

    let(:case_connection) do
      IPaaS::Connector::Connection.parse(
        {
          uuid: 'case_connection_uuid',
          direction: 'outbound',
          name: 'flow connection',
          connector: {
            uuid: case_connector.uuid,
          },
        },
      )
    end

    let(:case_action) do
      @expression ||= 'bar'
      @matches ||= %w[foo bar baz]

      IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'case_action_reference',
          description: 'Case tester',
          outbound_connection: {
            uuid: case_connection.uuid,
          },
          action_template: {
            uuid: 'case-action-uuid',
          },
          input_mapping: [
            { field_id: 'expression', fixed: @expression },
            { field_id: 'matches', fixed: @matches },
          ],
        },
      )
    end

    it 'should trigger the correct output schema' do
      result = case_action.run
      expect(case_action.output_schemas.map(&:name)).to eq(
        [
          'Expression resolves to foo.',
          'Expression resolves to bar.',
          'Expression resolves to baz.',
        ]
      )
      expect(result).to eq([{ output: { 'match' => 'bar' },
                              schema_reference: case_action.output_schemas.second.reference, }])
    end

    it 'should update the output schemas depending on the input schema' do
      @matches = %w[bar bie]
      result = case_action.run
      expect(case_action.output_schemas.map(&:name)).to eq(
        [
          'Expression resolves to bar.',
          'Expression resolves to bie.',
        ]
      )
      expect(result).to eq([{ output: { 'match' => 'bar' },
                              schema_reference: case_action.output_schemas.first.reference, }])
    end

    it 'should complain when an output schema cannot be found' do
      @matches = %w[bar test-invalid-ref bie]
      @expression = 'test-invalid-ref'
      expect do
        case_action.run
      end.to raise_error(IPaaS::Job::FailJob, "Output schema 'invalid' not found.")
    end

    it 'should complain when an output schema reference is missing in a nested action' do
      @matches = %w[bar test-missing-ref bie]
      @expression = 'test-missing-ref'
      expect do
        case_action.run
      end.to raise_error(IPaaS::Job::FailJob, 'Missing schema_reference, found keys: output.')
    end
  end

  context 'non-nested' do
    let(:mirror_connector) do
      IPaaS::Connector::Connector.new('mirror') do
        action 'mirror-action-uuid' do
          name 'Mirror'

          input_schema do
            field :message,
                  'Message',
                  :string,
                  required: true
          end

          output_schema do
            field :message,
                  'Message',
                  :string,
                  required: true
          end

          run do
            [{ output: { message: action.input[:message] } }]
          end
        end
      end
    end

    let(:mirror_connection) do
      IPaaS::Connector::Connection.parse(
        {
          uuid: 'mirror_connection_uuid',
          direction: 'outbound',
          name: 'mirror connection',
          connector: {
            uuid: mirror_connector.uuid,
          },
        },
      )
    end

    let(:mirror_action) do
      @message ||= 'ping'

      IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'mirror-action-reference',
          description: 'Mirror tester',
          outbound_connection: {
            uuid: mirror_connection.uuid,
          },
          action_template: {
            uuid: 'mirror-action-uuid',
          },
          input_mapping: [
            { field_id: 'message', fixed: @message },
          ],
        },
      )
    end

    it 'should resolve the default output schema' do
      result = mirror_action.run
      expect(result).to eq([{ output: { 'message' => 'ping' } }])
      expect(mirror_action.runbook.action_output(mirror_action.reference)).to eq(result[0][:output])
    end
  end

  context 'iteration state handling' do
    it 'no iteration state allowed for non-nested actions' do
      expect { set_iteration_state_value(IPaaS::Connector::Action.new, {}) }
        .to raise_error(IPaaS::Job::FailJob, 'Iteration state only available for nested actions.')
    end

    it 'iteration state value must be a hash' do
      a = IPaaS::Connector::Action.new
      allow(a).to receive(:nested?).and_return(true)

      expect { set_iteration_state_value(a, 'a') }
        .to raise_error(IPaaS::Job::FailJob, 'Expected iteration state to be a hash, got String.')
    end

    it 'iteration state schema is validated on set' do
      a = IPaaS::Connector::Action.new
      allow(a).to receive(:nested?).and_return(true)
      allow(a).to receive(:runbook).and_return(runbook)

      expect { set_iteration_state_value(a, { last_value: 1 }) }
        .not_to raise_error
    end

    it 'iteration state can be set' do
      skip_function_capture_validation

      IPaaS::Connector::Connector.new('uniquest-connector-id') do
        action 'unique-action-id' do
          name 'Foo'
          nested true

          iteration_state_schema do
            name 'Last'
            field :last_value,
                  'Last value',
                  :integer,
                  visibility: 'hidden',
                  required: true
          end

          run do
            'a'
          end
        end
      end
      a = IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'action_reference',
          description: 'Test description',
          action_template: {
            uuid: 'unique-action-id',
          },
        },
      )
      expect(a.iteration_count).to eq(0)

      set_iteration_state_value(a, { last_value: 1 })
      expect(a.iteration_state_value(:last_value)).to eq(1)
      expect(a.iteration_state_value('last_value')).to eq(1)
      expect(a.iteration_state_value.keys).to contain_exactly('last_value')
      expect(a.iteration_state.deep_symbolize_keys).to eq({ count: 1, value: { last_value: 1 } })
      expect(a.iteration_count).to eq(1)

      set_iteration_state_value(a, { last_value: 4 })
      expect(a.iteration_state_value(:last_value)).to eq(4)
      expect(a.iteration_state_value.keys).to contain_exactly('last_value')
      expect(a.iteration_state.deep_symbolize_keys).to eq({ count: 2, value: { last_value: 4 } })
      expect(a.iteration_count).to eq(2)
    end

    it 'iteration state can be cleared' do
      a = IPaaS::Connector::Action.new
      allow(a).to receive(:nested?).and_return(true)
      allow(a).to receive(:runbook).and_return(runbook)

      set_iteration_state_value(a, nil)
      expect(a.iteration_state).to be_nil
      expect(a.iteration_state_value).to be_nil
    end

    def set_iteration_state_value(action, value)
      action.send(:iteration_state_value=, value)
    end
  end

  describe 'disable_output_schema_name_mapping' do
    let(:action_template_with_disabled_mapping) do
      IPaaS::Connector::ActionTemplate.new('disabled-mapping-template') do
        name 'Test Action'
        disable_output_schema_name_mapping true

        run do
          'test'
        end
      end
    end

    let(:action_template_with_enabled_mapping) do
      IPaaS::Connector::ActionTemplate.new('enabled-mapping-template') do
        name 'Test Action'
        disable_output_schema_name_mapping false

        run do
          'test'
        end
      end
    end

    let(:action_with_disabled_mapping) do
      IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'test_action',
          action_template: { uuid: 'disabled-mapping-template' },
        }
      )
    end

    let(:action_with_enabled_mapping) do
      IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'test_action',
          action_template: { uuid: 'enabled-mapping-template' },
        }
      )
    end

    before do
      action_template_with_disabled_mapping.call_function(:run, nil)
      action_template_with_enabled_mapping.call_function(:run, nil)
    end

    it 'should not apply output schema name mappings when disabled' do
      output_schema = double('output_schema')
      allow(output_schema).to receive(:reference).and_return('test_schema')
      allow(output_schema).to receive(:name).and_return('Original Name')
      allow(action_with_disabled_mapping).to receive(:output_schema).and_return([output_schema])

      custom_mapping = double('custom_mapping')
      allow(custom_mapping).to receive(:schema_reference).and_return('test_schema')
      allow(custom_mapping).to receive(:name_mapping).and_return('Custom Name')
      allow(action_with_disabled_mapping).to receive(:output_schema_name_mapping).and_return([custom_mapping])

      result = action_with_disabled_mapping.output_schema_name(output_schema)

      expect(result).to eq('Original Name')
    end

    it 'should apply output schema name mappings when enabled' do
      output_schema = double('output_schema')
      allow(output_schema).to receive(:reference).and_return('test_schema')
      allow(output_schema).to receive(:name).and_return('Original Name')
      allow(action_with_enabled_mapping).to receive(:output_schema).and_return([output_schema])

      custom_mapping = double('custom_mapping')
      allow(custom_mapping).to receive(:schema_reference).and_return('test_schema')
      allow(custom_mapping).to receive(:name_mapping).and_return('Custom Name')
      allow(action_with_enabled_mapping).to receive(:output_schema_name_mapping).and_return([custom_mapping])

      result = action_with_enabled_mapping.output_schema_name(output_schema)

      expect(result).to eq('Custom Name')
    end

    it 'should return original name when output_schema is not present' do
      output_schema = double('output_schema')
      allow(output_schema).to receive(:reference).and_return('test_schema')
      allow(output_schema).to receive(:name).and_return('Original Name')
      allow(action_with_disabled_mapping).to receive(:output_schema).and_return(nil)

      result = action_with_disabled_mapping.output_schema_name(output_schema)

      expect(result).to eq('Original Name')
    end

    it 'should return original name when output_schema is empty' do
      output_schema = double('output_schema')
      allow(output_schema).to receive(:reference).and_return('test_schema')
      allow(output_schema).to receive(:name).and_return('Original Name')
      allow(action_with_disabled_mapping).to receive(:output_schema).and_return([])

      result = action_with_disabled_mapping.output_schema_name(output_schema)

      expect(result).to eq('Original Name')
    end
  end

  describe 'output_schema_name_mapping' do
    let(:action_template_with_mapping) do
      IPaaS::Connector::ActionTemplate.new('mapping-template') do
        name 'Test Action'

        output_schema 'schema1' do
          name 'Original Schema 1'
        end

        output_schema 'schema2' do
          name 'Original Schema 2'
        end

        run do
          'test'
        end
      end
    end

    let(:action_with_mapping) do
      IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'test_action',
          action_template: { uuid: 'mapping-template' },
          output_schema_name_mapping: [
            {
              schema_reference: 'schema1',
              name_mapping: 'Custom Schema 1 Name',
            },
            {
              schema_reference: 'schema2',
              name_mapping: 'Custom Schema 2 Name',
            },
          ],
        }
      )
    end

    before do
      action_template_with_mapping.call_function(:run, nil)
    end

    it 'should apply custom name mappings to output schemas' do
      output_schemas = action_with_mapping.output_schema

      schema1 = output_schemas.find { |s| s.reference == 'schema1' }
      schema2 = output_schemas.find { |s| s.reference == 'schema2' }

      expect(action_with_mapping.output_schema_name(schema1)).to eq('Custom Schema 1 Name')
      expect(action_with_mapping.output_schema_name(schema2)).to eq('Custom Schema 2 Name')
    end

    it 'should fall back to original schema names when no custom mapping exists' do
      action_without_mapping = IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'test_action_no_mapping',
          action_template: { uuid: 'mapping-template' },
        }
      )

      output_schemas = action_without_mapping.output_schema
      schema1 = output_schemas.find { |s| s.reference == 'schema1' }
      schema2 = output_schemas.find { |s| s.reference == 'schema2' }

      expect(action_without_mapping.output_schema_name(schema1)).to eq('Original Schema 1')
      expect(action_without_mapping.output_schema_name(schema2)).to eq('Original Schema 2')
    end

    it 'should handle partial custom mappings' do
      action_with_partial_mapping = IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'test_action_partial',
          action_template: { uuid: 'mapping-template' },
          output_schema_name_mapping: [
            {
              schema_reference: 'schema1',
              name_mapping: 'Only Schema 1 Custom',
            },
          ],
        }
      )

      output_schemas = action_with_partial_mapping.output_schema
      schema1 = output_schemas.find { |s| s.reference == 'schema1' }
      schema2 = output_schemas.find { |s| s.reference == 'schema2' }

      expect(action_with_partial_mapping.output_schema_name(schema1)).to eq('Only Schema 1 Custom')
      expect(action_with_partial_mapping.output_schema_name(schema2)).to eq('Original Schema 2')
    end

    it 'should handle empty output_schema_name_mapping array' do
      action_with_empty_mapping = IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'test_action_empty',
          action_template: { uuid: 'mapping-template' },
          output_schema_name_mapping: [],
        }
      )

      output_schemas = action_with_empty_mapping.output_schema
      schema1 = output_schemas.find { |s| s.reference == 'schema1' }
      schema2 = output_schemas.find { |s| s.reference == 'schema2' }

      expect(action_with_empty_mapping.output_schema_name(schema1)).to eq('Original Schema 1')
      expect(action_with_empty_mapping.output_schema_name(schema2)).to eq('Original Schema 2')
    end

    it 'should handle nil output_schema_name_mapping' do
      action_with_nil_mapping = IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'test_action_nil',
          action_template: { uuid: 'mapping-template' },
          output_schema_name_mapping: nil,
        }
      )

      output_schemas = action_with_nil_mapping.output_schema
      schema1 = output_schemas.find { |s| s.reference == 'schema1' }
      schema2 = output_schemas.find { |s| s.reference == 'schema2' }

      expect(action_with_nil_mapping.output_schema_name(schema1)).to eq('Original Schema 1')
      expect(action_with_nil_mapping.output_schema_name(schema2)).to eq('Original Schema 2')
    end

    it 'should handle custom mapping for non-existent schema reference' do
      action_with_invalid_mapping = IPaaS::Connector::Action.parse(
        runbook,
        {
          reference: 'test_action_invalid',
          action_template: { uuid: 'mapping-template' },
          output_schema_name_mapping: [
            {
              schema_reference: 'non_existent_schema',
              name_mapping: 'This Should Not Apply',
            },
          ],
        }
      )

      output_schemas = action_with_invalid_mapping.output_schema
      schema1 = output_schemas.find { |s| s.reference == 'schema1' }
      schema2 = output_schemas.find { |s| s.reference == 'schema2' }

      expect(action_with_invalid_mapping.output_schema_name(schema1)).to eq('Original Schema 1')
      expect(action_with_invalid_mapping.output_schema_name(schema2)).to eq('Original Schema 2')
    end
  end
end
