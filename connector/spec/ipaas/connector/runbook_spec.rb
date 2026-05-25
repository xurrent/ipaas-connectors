require 'spec_helper'

describe IPaaS::Connector::Runbook do
  let(:connector) do
    IPaaS::Connector::Connector.new('unique-connector-id') do
      trigger 'unique-trigger-id' do
        name 'JSON'

        config_schema do
          field :root_key,
                'Root key',
                :string,
                required: true

          after_update do |_fields|
            root_key = trigger.config[:root_key]
            output_schema.fields.first.id = root_key&.to_sym
          end
        end

        output_schema 'unique-trigger-output-id' do
          field :root, 'Root', :hash
        end

        parse do |request|
          root_key = config[:root_key]
          { root_key.to_sym => request.params }
        end
      end

      action 'unique-action-id' do
        name 'Concat'

        input_schema do
          field :params,
                'Params',
                :hash,
                required: true
        end

        output_schema 'action-output' do
          field :result, 'Result', :string
        end

        run do
          [{ schema_reference: 'action-output', output: { result: input[:params].to_a.join(' ') } }]
        end
      end

      action 'nested-action-id' do
        name 'Nested Action'
        nested true

        input_schema do
          field :data,
                'Data',
                :hash,
                required: true
        end

        output_schema 'page' do
          field :items, 'Items', :array
        end

        output_schema 'true' do
          field :result, 'Result', :string
        end

        output_schema 'false' do
          field :result, 'Result', :string
        end

        output_schema 'loop' do
          field :item, 'Item', :string
        end

        run do
          [
            { schema_reference: 'page', output: { items: input[:data][:items] || [] } },
            { schema_reference: 'true', output: { result: 'success' } },
            { schema_reference: 'false', output: { result: 'failure' } },
            { schema_reference: 'loop', output: { item: 'default' } },
          ]
        end
      end
    end
  end

  let(:inbound_connection) do
    IPaaS::Connector::Connection.parse(
      {
        uuid: 'inbound_connection_uuid',
        direction: 'inbound',
        name: 'test inbound connection',
        description: 'Test description',
        connector: {
          uuid: connector.uuid,
        },
      },
    )
  end

  let(:outbound_connection) do
    IPaaS::Connector::Connection.parse(
      {
        uuid: 'outbound_connection_uuid',
        direction: 'outbound',
        name: 'test outbound connection',
        description: 'Test description',
        connector: {
          uuid: connector.uuid,
        },
      },
    )
  end

  let(:runbook_hash) do
    {
      uuid: 'runbook_uuid',
      name: 'Runbook One',
      description: 'Test runbook description',
      runbook_variables: [
        { id: :foo, label: 'Foo Label', type: :string },
        { id: :bar, label: 'Bar Label', type: :string },
        {
          id: :baz, label: 'Baz Label', type: :nested,
          fields: [
            { id: :'baz-nested', label: 'Baz Nested Label', type: :integer },
          ],
        },
      ],
      trigger: {
        description: 'Test description',
        inbound_connection: {
          uuid: inbound_connection.uuid,
        },
        trigger_template: {
          uuid: connector.trigger('unique-trigger-id').uuid,
        },
        config_mapping: [
          { field_id: :root_key, fixed: @root_key },
        ],
      },
      actions: [
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
            { field_id: :params, proc: 'step("trigger-output").output[:beetroot]' },
          ],
        },
      ],
    }
  end

  let(:runbook) do
    @root_key ||= 'beetroot'

    @runbook = IPaaS::Connector::Runbook.parse(runbook_hash)
  end

  let(:action) do
    runbook.actions.first
  end

  let(:trigger) do
    runbook.trigger
  end

  def create_action(runbook, reference, predecessor_reference = nil, predecessor_output_schema = nil)
    action = IPaaS::Connector::Action.new(reference)
    action.predecessor_action_reference = predecessor_reference
    action.predecessor_output_schema_reference = predecessor_output_schema
    action.runbook = runbook
    action.input_mapping = []
    runbook.actions << action
    action
  end

  context 'validation' do
    before(:each) do
      action.step_output('trigger-output', { beetroot: { foo: 'bar' } })
    end

    it 'should be valid' do
      expect(runbook).to be_valid
    end

    it 'should validate the given value is a hash' do
      expect do
        IPaaS::Connector::Runbook.parse([1, 2])
      end.to raise_error('Runbook must be a hash.')
    end

    it 'should validate trigger is required' do
      runbook.trigger = nil
      expect(runbook).not_to be_valid
      expect(runbook.errors[:trigger]).to eq(["can't be blank."])
    end

    it 'should validate actions are required' do
      expect(runbook.actions.map(&:reference)).to eq(['action_reference'])
      runbook.actions = []
      expect(runbook).not_to be_valid
      expect(runbook.errors[:actions]).to eq(["can't be blank."])
    end

    it 'should validate the trigger' do
      runbook.trigger.inbound_connection = nil
      expect(runbook).not_to be_valid
      expect(runbook.errors[:trigger]).to include("invalid: Inbound connection can't be blank.")
    end

    it 'should validate the actions' do
      runbook.actions.first.action_template = nil
      expect(runbook).not_to be_valid
      expect(runbook.errors[:actions]).to include("(action_reference) invalid: Action template can't be blank.")
    end

    it 'should validate the actions are connected to the trigger' do
      runbook.actions.first.predecessor_action_reference = 'foo'
      expect(runbook).not_to be_valid
      expect(runbook.errors[:base]).to include('No actions are connected to the trigger.')
    end

    context 'invalid action validation' do
      it 'should validate actions with non-existent predecessor references' do
        create_action(runbook, 'invalid-action', 'non-existent-action')
        expect(runbook).not_to be_valid
        expect(runbook.errors[:base]).to include('Action (invalid-action) invalid: Predecessor action ' \
                                                 'non-existent-action is unknown.')
      end

      it 'should validate actions that reference themselves' do
        create_action(runbook, 'self-ref-action', 'self-ref-action')
        expect(runbook).not_to be_valid
        expect(runbook.errors[:base]).to include('Action (self-ref-action) invalid: cannot be its own predecessor.')
      end

      it 'should validate duplicate predecessor actions' do
        create_action(runbook, 'duplicate-action-1', 'action_reference')
        create_action(runbook, 'duplicate-action-2', 'action_reference')
        expect(runbook).not_to be_valid
        expect(runbook.errors[:base]).to include('Action (duplicate-action-2) invalid: ' \
                                                 'Predecessor action Concat (action_reference) also connected to: ' \
                                                 'duplicate-action-1.')
      end

      it 'should validate duplicate root action' do
        create_action(runbook, 'duplicate-root')
        expect(runbook).not_to be_valid
        expect(runbook.errors[:base]).to include('Action (duplicate-root) invalid: ' \
                                                 'Predecessor (trigger) also connected to: action_reference.')
      end

      it 'should validate multiple types of invalid actions together' do
        create_action(runbook, 'duplicate-root')
        create_action(runbook, 'self-ref-action', 'self-ref-action')
        create_action(runbook, 'invalid-action', 'non-existent-action')
        create_action(runbook, 'duplicate-action-1', 'action_reference')
        create_action(runbook, 'duplicate-action-2', 'action_reference')

        expect(runbook).not_to be_valid
        expect(runbook.errors[:base]).to include('Action (duplicate-root) invalid: ' \
                                                 'Predecessor (trigger) also connected to: action_reference.')

        expect(runbook.errors[:base]).to include('Action (duplicate-action-2) invalid: ' \
                                                 'Predecessor action Concat (action_reference) also connected to: ' \
                                                 'duplicate-action-1.')
        expect(runbook.errors[:base]).to include('Action (self-ref-action) invalid: cannot be its own predecessor.')
        expect(runbook.errors[:base]).to include('Action (invalid-action) invalid: Predecessor action ' \
                                                 'non-existent-action is unknown.')
      end

      it 'should validate unconnected cycle' do
        create_action(runbook, 'new-action-1', 'new-action-3')
        create_action(runbook, 'new-action-2', 'new-action-1')
        create_action(runbook, 'new-action-3', 'new-action-2')

        expect(runbook).not_to be_valid
        expect(runbook.errors[:base]).to include('Action (new-action-1) is unreachable',
                                                 'Action (new-action-2) is unreachable',
                                                 'Action (new-action-3) is unreachable')
      end
    end
  end

  it 'should set the designer mode' do
    expect(runbook.designer_mode?).to be_truthy
    runbook.in_designer_mode do
      expect(runbook.designer_mode?).to be_truthy
      runbook.in_designer_mode do
        expect(runbook.designer_mode?).to be_truthy
      end
      expect(runbook.designer_mode?).to be_truthy
    end
    expect(runbook.designer_mode?).to be_truthy
  end

  it 'should set the execution mode' do
    expect(runbook.designer_mode?).to be_truthy
    runbook.in_execution_mode do
      expect(runbook.designer_mode?).to be_falsey
      runbook.in_execution_mode do
        expect(runbook.designer_mode?).to be_falsey
      end
      expect(runbook.designer_mode?).to be_falsey
    end
    expect(runbook.designer_mode?).to be_truthy
  end

  context 'concurrency' do
    it 'concurrency can be nil' do
      expect(runbook.concurrency).to be_nil
    end

    it 'concurrency is nil for empty hash' do
      runbook_hash[:concurrency] = {}
      r = IPaaS::Connector::Runbook.parse(runbook_hash)
      expect(r.concurrency).to be_nil
    end

    it 'concurrency must have a type' do
      runbook_hash[:concurrency] = { a: 'foo' }
      expect do
        IPaaS::Connector::Runbook.parse(runbook_hash)
      end.to raise_error(IPaaS::Error, 'Concurrency must indicate type.')
    end

    it 'concurrency must have supported type' do
      runbook_hash[:concurrency] = { type: 'foo' }
      r = IPaaS::Connector::Runbook.parse(runbook_hash)
      expect(r).not_to be_valid
      expect(r.errors[:concurrency])
        .to contain_exactly('Concurrency type must be one of: [per_runbook, per_job_context_identifier]')
    end

    it 'should symbolize per_job_context_identifier type' do
      runbook_hash[:concurrency] = { type: 'per_job_context_identifier' }
      r = IPaaS::Connector::Runbook.parse(runbook_hash)
      expect(r.concurrency).to eq({ type: :per_job_context_identifier })
    end

    it 'should symbolize per_runbook type' do
      runbook_hash[:concurrency] = { type: 'per_runbook' }
      r = IPaaS::Connector::Runbook.parse(runbook_hash)
      expect(r.concurrency).to eq({ type: :per_runbook })
    end
  end

  context 'runbook variables' do
    it 'should have a list of runbook variable declarations' do
      fields = runbook.runbook_variables
      expect(fields.size).to eq(3)

      expect(fields.first.to_h_ref).to eq({ id: :foo, label: 'Foo Label', type: :string })
      baz_field = fields.last
      expect(baz_field.id).to eq(:baz)
      expect(baz_field.type).to eq(:nested)
      expect(baz_field.fields.size).to eq(1)
      expect(baz_field.fields.first.to_h_ref).to eq(id: :'baz-nested', label: 'Baz Nested Label', type: :integer)
    end

    it 'checks for duplicate runbook variable declarations' do
      IPaaS::Connector::Runbook.parse_runbook_variables(runbook, [
        { id: :foo, label: 'Foo Label', type: :string },
        { id: 'foo', label: 'Another Foo', type: :string },
      ])
      expect(runbook).not_to be_valid
      expect(runbook.errors[:runbook_variables]).to include("Runbook variable 'foo' is defined more than once")
    end

    describe 'variable_field' do
      it 'should retrieve a runbook variable field (definition)' do
        foo_field = runbook.runbook_variables.first
        expect(runbook.variable_field('foo').id).to eq(foo_field.id)
      end

      it 'should retrieve a runbook variable field (definition) by symbol' do
        foo_field = runbook.runbook_variables.first
        expect(runbook.variable_field(:foo).id).to eq(foo_field.id)
      end

      it 'should return nil when variable field is unknown' do
        expect(runbook.variable_field('unknown')).to be_nil
      end
    end

    it 'stores variables in the job state' do
      job_state_store = ActiveSupport::Cache::MemoryStore.new
      allow(job_state_store).to receive(:write).and_call_original
      runbook.job_state = job_state_store

      runbook.write_variable('foo', 'bar')
      expect(runbook.read_variable('foo')).to eq('bar')
      expect(job_state_store.read('variable:foo')).to eq('bar')
      expect(job_state_store).to have_received(:write)
    end

    it 'allows variables ids as symbol' do
      runbook.job_state = ActiveSupport::Cache::MemoryStore.new

      runbook.write_variable(:foo, 'bar')
      expect(runbook.read_variable('foo')).to eq('bar')
      expect(runbook.read_variable(:foo)).to eq('bar')
    end

    context 'write validation' do
      it 'validates the variable ID is not too long' do
        long_id = 'a' * 258
        expect do
          runbook.write_variable(long_id, 'bar')
        end.to raise_error("Runbook variable '#{long_id}': Id is too long (maximum is 256 characters)")
      end

      it 'validates the value is of the correct type' do
        foo_field = runbook.runbook_variables.first
        foo_field.type = :integer
        expect do
          runbook.write_variable('foo', 'bar')
        end.to raise_error("Runbook variable 'foo': Value Type of field 'foo' invalid, expected Integer found String.")
      end
    end
  end

  context 'uuid' do
    it 'should take the given UUID' do
      expect(runbook.uuid).to eq('runbook_uuid')
    end

    it 'should generate a UUID when none is provided' do
      expect(SecureRandom).to receive(:uuid_v7) { 'foo-uuid' }
      uuid_trigger = IPaaS::Connector::Runbook.parse({ name: 'foo' })
      expect(uuid_trigger.uuid).to eq('foo-uuid')
    end
  end

  context 'store' do
    it 'should define a store' do
      runbook.store.write('foo', 'bar')
      expect(runbook.store.read('foo')).to eq('bar')
    end

    it 'should use a different store than the job state (store)' do
      runbook.store.write('foo', 'bar')
      expect(runbook.store.read('foo')).to eq('bar')
      runbook.job_state = ActiveSupport::Cache::MemoryStore.new
      expect(runbook.store.read('foo')).to eq('bar')
    end
  end

  context 'to_h' do
    it 'should define to_h' do
      @root_key = 'abc'
      runbook_hash[:concurrency] = { type: :per_job_context_identifier }
      hash = runbook.to_h
      expect(hash).to eq(runbook_hash)
      # check order of children in yaml
      expect(hash.keys).to eq([:uuid, :name, :description, :concurrency, :runbook_variables, :trigger, :actions])
    end
  end

  context 'trigger output' do
    it 'allows trigger output to be set' do
      expect(runbook.trigger_output).to be_nil

      runbook.store_trigger_output({ a: :foo, b: 1 })
      expect(runbook.trigger_output).to eq({ a: 'foo', b: 1 }.with_indifferent_access)
    end

    it 'stores trigger output in the job state' do
      job_state_store = ActiveSupport::Cache::MemoryStore.new
      allow(job_state_store).to receive(:write).and_call_original
      runbook.job_state = job_state_store

      runbook.store_trigger_output({ a: :foo, b: 1 })
      expect(runbook.trigger_output).to eq(a: :foo, b: 1)
      expect(job_state_store.read('trigger_output')).to eq(a: :foo, b: 1)

      expect(job_state_store).to have_received(:write)
    end
  end

  context 'action outputs' do
    it 'is nil for unknown action' do
      expect(runbook.action_output('abc')).to be_nil
    end

    it 'allows action outputs to be set' do
      action_reference = SecureRandom.uuid
      action_output = { a: { bar: 'foo' }, b: { foo: 'bar' } }.with_indifferent_access
      runbook.store_action_output(action_reference, action_output)
      expect(runbook.action_output(action_reference)).to eq(action_output)

      other_action_reference = SecureRandom.uuid
      other_action_output = { c: { bar: 'foo' }, b: { foo: 'baz' } }.with_indifferent_access
      runbook.store_action_output(other_action_reference, other_action_output)
      expect(runbook.action_output(other_action_reference)).to eq(other_action_output)

      # first action's outputs not changed
      expect(runbook.action_output(action_reference)).to eq(action_output)
    end

    it 'stores separate output for each output_schema_reference' do
      action_reference = SecureRandom.uuid
      output_schema_ref1 = SecureRandom.uuid
      action_output = { a: { bar: 'foo' }, b: { foo: 'bar' } }.with_indifferent_access
      runbook.store_action_output(action_reference, action_output, output_schema_reference: output_schema_ref1)
      expect(runbook.action_output(action_reference, output_schema_reference: output_schema_ref1)).to eq(action_output)
      expect(runbook.action_output(action_reference)).to be_nil

      output_schema_ref2 = SecureRandom.uuid
      other_action_output = { c: { bar: 'foo' }, b: { foo: 'baz' } }.with_indifferent_access
      runbook.store_action_output(action_reference, other_action_output, output_schema_reference: output_schema_ref2)
      expect(runbook.action_output(action_reference,
                                   output_schema_reference: output_schema_ref2)).to eq(other_action_output)
      expect(runbook.action_output(action_reference)).to be_nil

      expect(runbook.action_output(action_reference, output_schema_reference: output_schema_ref1)).to eq(action_output)
    end

    it 'stores action output in the job state' do
      job_state_store = ActiveSupport::Cache::MemoryStore.new
      allow(job_state_store).to receive(:write).and_call_original
      runbook.job_state = job_state_store

      action_reference = SecureRandom.uuid
      action_output = { a: { bar: :foo }, b: { foo: :bar } }
      runbook.store_action_output(action_reference, action_output)
      expect(runbook.action_output(action_reference)).to eq(action_output)

      expect(job_state_store).to have_received(:write)
    end

    it 'resolves output schema reference implicitly when there is exactly one output schema' do
      output_schema_ref = runbook.actions.first.output_schemas.first.reference
      output = { result: 'foo' }.with_indifferent_access

      runbook.store_action_output(runbook.actions.first.reference, output, output_schema_reference: output_schema_ref)

      expect(runbook.action_output(runbook.actions.first.reference)).to eq(output)
    end

    it 'does not resolve output schema reference implicitly when there are multiple output schemas' do
      action = IPaaS::Connector::Action.new('multi-output-action')
      action.output_schema('first') { field :value, 'Value', :string }
      action.output_schema('second') { field :value, 'Value', :string }
      action.runbook = runbook
      runbook.actions << action

      runbook.store_action_output(action.reference, { value: 'first' }, output_schema_reference: 'first')
      runbook.store_action_output(action.reference, { value: 'second' }, output_schema_reference: 'second')

      expect(runbook.action_output(action.reference)).to be_nil
      expect(runbook.action_output(action.reference, output_schema_reference: 'first'))
        .to eq({ value: 'first' }.with_indifferent_access)
      expect(runbook.action_output(action.reference, output_schema_reference: 'second'))
        .to eq({ value: 'second' }.with_indifferent_access)
    end
  end

  context 'solution support' do
    it 'can handle no solution' do
      expect(runbook.solution).to be_nil
      expect(runbook.account_id).to be_nil
      expect(runbook.version).to be_nil
    end

    it 'delegates to solution' do
      solution = double(:solution)
      expect(solution).to receive(:account_id).and_return(123)
      expect(solution).to receive(:version).and_return('abs')

      runbook.solution = solution
      expect(runbook.account_id).to eq(123)
      expect(runbook.version).to eq('abs')
    end
  end

  # for 100% code coverage
  context 'parse and run' do
    it 'should parse requests and run actions' do
      request = double(params: { foo: 'barbie', bar: { baz: 'qux' } }, body: StringIO.new)

      result = trigger.parse_request(request)
      expect(result).to eq({ 'beetroot' => { 'bar' => { 'baz' => 'qux' }, 'foo' => 'barbie' } })

      action.step_output('trigger-output', result)
      action_results = action.run
      action_output = action_results.first[:output]
      expect(action_output[:result]).to eq('foo barbie bar {"baz" => "qux"}')
    end
  end

  context 'to_json' do
    it 'should create a hash with id and name' do
      expect(runbook.to_json).to eq({ uuid: runbook.uuid, name: 'Runbook One' }.to_json)
    end
  end

  context 'endpoint' do
    it 'provides endpoint' do
      expect(trigger.endpoint).not_to be_nil
      expect(runbook.endpoint).to eq(trigger.endpoint)

      runbook.trigger = nil
      expect(runbook.endpoint).to be_nil
    end
  end

  context 'sort and remove unreachable actions' do
    let(:runbook_single_level) do
      runbook_hash = {
        name: 'Single level runbook',
        trigger: {
          description: 'Receive a note',
          inbound_connection: {
            uuid: inbound_connection.uuid,
          },
          trigger_template: {
            uuid: connector.trigger('unique-trigger-id').uuid,
          },
        },
        actions: [
          {
            reference: 'action-2',
            predecessor_action_reference: 'action-1',
            outbound_connection: {
              uuid: outbound_connection.uuid,
            },
            action_template: {
              uuid: connector.action('unique-action-id').uuid,
            },
          },
          {
            reference: 'action-1',
            outbound_connection: {
              uuid: outbound_connection.uuid,
            },
            action_template: {
              uuid: connector.action('unique-action-id').uuid,
            },
          },
        ],
      }

      IPaaS::Connector::Runbook.parse(runbook_hash)
    end

    let(:runbook_nested) do
      runbook_hash = {
        name: 'Runbook with multiple levels',
        trigger: {
          description: 'Start',
          inbound_connection: {
            uuid: inbound_connection.uuid,
          },
          trigger_template: {
            uuid: connector.trigger('unique-trigger-id').uuid,
          },
        },
        actions: [
          {
            reference: 'retrieve-service-instances',
            outbound_connection: {
              uuid: outbound_connection.uuid,
            },
            action_template: {
              uuid: connector.action('nested-action-id').uuid,
            },
          },
          {
            reference: 'log-total-count',
            predecessor_action_reference: 'if-instances-found',
            outbound_connection: {
              uuid: outbound_connection.uuid,
            },
            action_template: {
              uuid: connector.action('unique-action-id').uuid,
            },
          },
          {
            reference: 'if-instances-found',
            predecessor_action_reference: 'retrieve-service-instances',
            predecessor_output_schema_reference: 'page',
            outbound_connection: {
              uuid: outbound_connection.uuid,
            },
            action_template: {
              uuid: connector.action('nested-action-id').uuid,
            },
          },
          {
            reference: 'each-service-instance',
            predecessor_action_reference: 'if-instances-found',
            predecessor_output_schema_reference: 'true',
            outbound_connection: {
              uuid: outbound_connection.uuid,
            },
            action_template: {
              uuid: connector.action('nested-action-id').uuid,
            },
          },
          {
            reference: 'log-name',
            predecessor_action_reference: 'each-service-instance',
            predecessor_output_schema_reference: 'loop',
            outbound_connection: {
              uuid: outbound_connection.uuid,
            },
            action_template: {
              uuid: connector.action('unique-action-id').uuid,
            },
          },
          {
            reference: 'log-action',
            predecessor_action_reference: 'log-name',
            outbound_connection: {
              uuid: outbound_connection.uuid,
            },
            action_template: {
              uuid: connector.action('unique-action-id').uuid,
            },
          },
          {
            reference: 'log-false',
            predecessor_action_reference: 'if-instances-found',
            predecessor_output_schema_reference: 'false',
            outbound_connection: {
              uuid: outbound_connection.uuid,
            },
            action_template: {
              uuid: connector.action('unique-action-id').uuid,
            },
          },
          {
            reference: 'log-last',
            description: 'log-last',
            predecessor_action_reference: 'retrieve-service-instances',
            outbound_connection: {
              uuid: outbound_connection.uuid,
            },
            action_template: {
              uuid: connector.action('unique-action-id').uuid,
            },
          },
        ],
      }

      IPaaS::Connector::Runbook.parse(runbook_hash)
    end

    it 'runbook (single level) should have sorted actions as shown in gui' do
      reachable_actions = runbook_single_level.ordered_reachable_actions

      sorted_references = reachable_actions.map(&:reference)
      expected_references = %w[action-1 action-2]

      expect(sorted_references).to eq(expected_references)
    end

    it 'runbook (multi level) should have sorted actions as shown in gui' do
      reachable_actions = runbook_nested.ordered_reachable_actions

      sorted_references = reachable_actions.map(&:reference)
      expected_references = %w[
        retrieve-service-instances
        if-instances-found
        each-service-instance
        log-name
        log-action
        log-false
        log-total-count
        log-last
      ]

      expect(sorted_references).to eq(expected_references)
    end

    it 'remove unconnected actions' do
      create_action(runbook_single_level, 'new-action-1', 'new-action-3')
      create_action(runbook_single_level, 'new-action-2', 'new-action-1')

      expect(runbook_single_level.actions.length).to eq(4)

      reachable_actions = runbook_single_level.ordered_reachable_actions

      expect(reachable_actions.length).to eq(2)
    end

    it 'remove unconnected cycle' do
      create_action(runbook_single_level, 'new-action-1', 'new-action-3')
      create_action(runbook_single_level, 'new-action-2', 'new-action-1')
      create_action(runbook_single_level, 'new-action-3', 'new-action-2')

      expect(runbook_single_level.actions.length).to eq(5)

      reachable_actions = runbook_single_level.ordered_reachable_actions

      expect(reachable_actions.length).to eq(2)
    end

    it 'retains orphaned output schema actions' do
      nested_action = create_action(runbook_nested, 'nested-parent', 'log-last')
      nested_action.action_template = connector.action('nested-action-id')

      # Create child actions with valid schema references (should be reachable)
      valid_child = create_action(runbook_nested, 'valid-child', 'nested-parent', 'page')
      valid_child.action_template = connector.action('unique-action-id')

      # Create child action with orphaned schema reference (should be retained)
      orphaned_child = create_action(runbook_nested, 'orphaned-child', 'nested-parent', 'unknown-schema')
      orphaned_child.action_template = connector.action('unique-action-id')

      # Create grandchild of orphaned action (should also be retained)
      orphaned_grandchild = create_action(runbook_nested, 'orphaned-grandchild', 'orphaned-child')
      orphaned_grandchild.action_template = connector.action('unique-action-id')

      expect(runbook_nested.actions.length).to eq(12)
      reachable_actions = runbook_nested.ordered_reachable_actions

      expect(reachable_actions.length).to eq(12)
      expect(reachable_actions.map(&:reference)).to include('nested-parent', 'valid-child', 'orphaned-child',
                                                            'orphaned-grandchild')
      expect(runbook_nested.actions.map(&:reference)).to include('orphaned-child', 'orphaned-grandchild')
    end
  end

  describe '#first_action' do
    it 'returns trigger successor when trigger has a successor' do
      expect(runbook.first_action).to eq(runbook.trigger.successor)
      expect(runbook.first_action.reference).to eq('action_reference')
    end

    it 'returns nil when runbook has trigger but no actions' do
      runbook_with_trigger_no_actions = IPaaS::Connector::Runbook.parse({
        uuid: 'runbook_uuid_1',
        name: 'Runbook First',
        description: 'Test runbook description',
        runbook_variables: [],
        trigger: {
          description: 'Test description',
          inbound_connection: {
            uuid: inbound_connection.uuid,
          },
          trigger_template: {
            uuid: connector.trigger('unique-trigger-id').uuid,
          },
          config_mapping: [
            { field_id: :root_key, fixed: 'test' },
          ],
        },
        actions: [],
      })

      expect(runbook_with_trigger_no_actions.first_action).to be_nil
    end

    it 'returns first action with nil predecessor when multiple actions exist' do
      runbook.trigger = nil
      expect(runbook.first_action.reference).to eq('action_reference')
      expect(runbook.first_action.predecessor_action_reference).to be_nil
    end
  end

  describe '#reconstruct_field_value' do
    let(:encrypted_string) do
      secret_string = make_secret_string('test encrypted value')
      secret_string.encrypted
    end

    let(:plain_string) { 'plain text value' }

    context 'with secret_string field type' do
      it 'converts string to SecretString' do
        field = IPaaS::Connector::Schema::Field.new(id: :email, label: 'Email', type: :secret_string)
        result = runbook.send(:reconstruct_field_value, encrypted_string, field)
        expect(result).to be_a(IPaaS::Encryption::SecretString)
        expect(runbook.decrypt_secret_string(result)).to eq('test encrypted value')
      end

      it 'handles nil value' do
        field = IPaaS::Connector::Schema::Field.new(id: :email, label: 'Email', type: :secret_string)
        result = runbook.send(:reconstruct_field_value, nil, field)
        expect(result).to be_nil
      end

      it 'handles empty string' do
        field = IPaaS::Connector::Schema::Field.new(id: :email, label: 'Email', type: :secret_string)
        result = runbook.send(:reconstruct_field_value, '', field)
        expect(result).to be_a(IPaaS::Encryption::SecretString)
      end
    end

    context 'with string field type' do
      it 'leaves string unchanged' do
        field = IPaaS::Connector::Schema::Field.new(id: :name, label: 'Name', type: :string)
        result = runbook.send(:reconstruct_field_value, plain_string, field)
        expect(result).to eq(plain_string)
        expect(result).to be_a(String)
      end
    end

    context 'with array field type' do
      it 'processes array of strings' do
        field = IPaaS::Connector::Schema::Field.new(id: :items, label: 'Items', type: :string, array: true)
        value = [plain_string, 'another string']
        result = runbook.send(:reconstruct_field_value, value, field)
        expect(result).to eq([plain_string, 'another string'])
      end

      it 'processes array of secret_strings' do
        field = IPaaS::Connector::Schema::Field.new(id: :items, label: 'Items', type: :secret_string, array: true)
        value = [encrypted_string, encrypted_string]
        result = runbook.send(:reconstruct_field_value, value, field)
        expect(result[0]).to be_a(IPaaS::Encryption::SecretString)
        expect(result[1]).to be_a(IPaaS::Encryption::SecretString)
      end

      it 'handles empty array' do
        field = IPaaS::Connector::Schema::Field.new(id: :items, label: 'Items', type: :string, array: true)
        result = runbook.send(:reconstruct_field_value, [], field)
        expect(result).to eq([])
      end

      it 'handles array with nil values' do
        field = IPaaS::Connector::Schema::Field.new(id: :items, label: 'Items', type: :secret_string, array: true)
        value = [encrypted_string, nil, encrypted_string]
        result = runbook.send(:reconstruct_field_value, value, field)
        expect(result[0]).to be_a(IPaaS::Encryption::SecretString)
        expect(result[1]).to be_nil
        expect(result[2]).to be_a(IPaaS::Encryption::SecretString)
      end
    end

    context 'with nested field type' do
      it 'processes nested hash structure' do
        nested_fields = [
          IPaaS::Connector::Schema::Field.new(id: :email, label: 'Email', type: :secret_string),
          IPaaS::Connector::Schema::Field.new(id: :name, label: 'Name', type: :string),
        ]
        field = IPaaS::Connector::Schema::Field.new(id: :user, label: 'User', type: :nested, fields: nested_fields)
        value = { email: encrypted_string, name: plain_string }
        result = runbook.send(:reconstruct_field_value, value, field)

        expect(result[:email]).to be_a(IPaaS::Encryption::SecretString)
        expect(result[:name]).to eq(plain_string)
      end

      it 'handles empty nested hash' do
        nested_fields = [
          IPaaS::Connector::Schema::Field.new(id: :email, label: 'Email', type: :secret_string),
        ]
        field = IPaaS::Connector::Schema::Field.new(id: :user, label: 'User', type: :nested, fields: nested_fields)
        result = runbook.send(:reconstruct_field_value, {}, field)
        expect(result).to eq({})
      end
    end

    context 'with array of nested objects' do
      it 'processes array of nested hashes' do
        nested_fields = [
          IPaaS::Connector::Schema::Field.new(id: :email_address, label: 'Email Address', type: :secret_string),
          IPaaS::Connector::Schema::Field.new(id: :device_id, label: 'Device ID', type: :string),
        ]
        field = IPaaS::Connector::Schema::Field.new(id: :devices, label: 'Devices', type: :nested, array: true,
                                                    fields: nested_fields)
        value = [
          { email_address: encrypted_string, device_id: '1' },
          { email_address: '', device_id: '2' },
          { email_address: encrypted_string, device_id: '3' },
        ]
        result = runbook.send(:reconstruct_field_value, value, field)

        expect(result[0][:email_address]).to be_a(IPaaS::Encryption::SecretString)
        expect(result[0][:device_id]).to eq('1')
        expect(result[1][:email_address]).to be_a(IPaaS::Encryption::SecretString)
        expect(result[2][:email_address]).to be_a(IPaaS::Encryption::SecretString)
      end

      it 'handles deeply nested structures' do
        level3_fields = [
          IPaaS::Connector::Schema::Field.new(id: :secret, label: 'Secret', type: :secret_string),
        ]
        level2_fields = [
          IPaaS::Connector::Schema::Field.new(id: :level3, label: 'Level 3', type: :nested, fields: level3_fields),
        ]
        level1_fields = [
          IPaaS::Connector::Schema::Field.new(id: :level2, label: 'Level 2', type: :nested, fields: level2_fields),
        ]
        field = IPaaS::Connector::Schema::Field.new(id: :level1, label: 'Level 1', type: :nested, fields: level1_fields)
        value = { level2: { level3: { secret: encrypted_string } } }
        result = runbook.send(:reconstruct_field_value, value, field)

        expect(result[:level2][:level3][:secret]).to be_a(IPaaS::Encryption::SecretString)
      end
    end

    context 'with other field types' do
      it 'leaves integer values unchanged' do
        field = IPaaS::Connector::Schema::Field.new(id: :age, label: 'Age', type: :integer)
        result = runbook.send(:reconstruct_field_value, 30, field)
        expect(result).to eq(30)
      end
    end

    context 'integration with action_output' do
      it 'converts secret_string fields when reading action outputs' do
        runbook.job_state = ActiveSupport::Cache::MemoryStore.new

        action = runbook.actions.first
        allow(action).to receive(:output_schemas).and_return([
          IPaaS::Connector::Schema.new('test-output') do
            field :items, 'Items', :secret_string, array: true
            field :metadata, 'Metadata', :nested do
              field :secret, 'Secret', :secret_string
              field :public, 'Public', :string
            end
          end,
        ])

        action_reference = action.reference
        output = {
          items: [encrypted_string, plain_string, ''],
          metadata: {
            secret: encrypted_string,
            public: plain_string,
          },
        }
        runbook.store_action_output(action_reference, output)

        result = runbook.action_output(action_reference)
        expect(result[:items][0]).to be_a(IPaaS::Encryption::SecretString)
        expect(result[:items][1]).to be_a(IPaaS::Encryption::SecretString)
        expect(result[:items][2]).to be_a(IPaaS::Encryption::SecretString)
        expect(result[:metadata][:secret]).to be_a(IPaaS::Encryption::SecretString)
        expect(result[:metadata][:public]).to eq(plain_string)
      end
    end
  end
end
