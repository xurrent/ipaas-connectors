require 'spec_helper'

describe IPaaS::Connector::Action do
  let(:runbook) do
    IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7).tap do |runbook|
      runbook.name = 'Runbook 1'
      runbook.actions = []

      trigger_hash = {
        description: 'Test trigger',
        inbound_connection: {
          uuid: inbound_connection.uuid,
        },
        trigger_template: {
          uuid: connector.trigger('unique-trigger-id').uuid,
        },
        config_mapping: [
          { field_id: :root_key, fixed: 'test' },
        ],
      }

      runbook.trigger = IPaaS::Connector::Trigger.parse(runbook, trigger_hash)
    end
  end

  let(:connector) do
    IPaaS::Connector::Connector.new('unique-connector-id') do
      trigger 'unique-trigger-id' do
        name 'Test Trigger'

        config_schema do
          field :root_key, 'Root key', :string, required: true
        end

        output_schema 'trigger-output' do
          field :root, 'Root', :hash
        end

        parse do |request|
          { root: request.params }
        end
      end

      outbound_connection do
        api_key_authenticator

        config_schema do
          field :foo, 'Foo', :string
        end
      end

      action 'max-action-id' do
        name 'Max action'

        input_schema do
          field :numbers,
                'Numbers',
                [:integer],
                required: true
        end

        output_schema 'max-output-schema-id' do
          field :max, 'Max', :integer
        end

        run do
          [{ schema_reference: 'max-output-schema-id', output: { max: input[:numbers].max } }]
        end
      end

      action 'if-else-action-id' do
        name 'If-then-else'
        avatar 'https://ipaas.eu.xurrent.com/avatars/ipaas/if-then-else.svg'
        description 'Decision to execute an action based on a condition.'
        nested true

        input_schema do
          field :condition,
                'Condition',
                :boolean,
                required: true
        end

        output_schema 'condition-met-output-schema-id' do
          name 'Condition is met'
          field :result,
                'Result',
                :boolean,
                required: true
        end

        output_schema 'condition-not-met-output-schema-id' do
          name 'Condition is not met'
          field :result,
                'Result',
                :boolean,
                required: true
        end

        run do
          condition = action.input.fetch(:condition)
          output = { result: condition }
          schema_uuid = if condition
                          'condition-met-output-schema-id'
                        else
                          'condition-not-met-output-schema-id'
                        end
          [{ schema_reference: schema_uuid, output: output }]
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

  def max_action(number, predecessor_action_reference: nil, predecessor_output_schema_reference: nil)
    IPaaS::Connector::Action.parse(
      runbook,
      {
        reference: "max#{number}_action_reference",
        predecessor_action_reference: predecessor_action_reference,
        predecessor_output_schema_reference: predecessor_output_schema_reference,
        outbound_connection: {
          uuid: outbound_connection.uuid,
        },
        action_template: {
          uuid: 'max-action-id',
        },
        input_mapping: [
          { field_id: 'numbers', fixed: [1, 3, 5, 10, number] },
        ],
      },
    )
  end

  def if_else_action(condition, predecessor_action_reference: nil, predecessor_output_schema_reference: nil)
    IPaaS::Connector::Action.parse(
      runbook,
      {
        reference: "if_else_#{condition}_action_reference",
        predecessor_action_reference: predecessor_action_reference,
        predecessor_output_schema_reference: predecessor_output_schema_reference,
        outbound_connection: {
          uuid: outbound_connection.uuid,
        },
        action_template: {
          uuid: 'if-else-action-id',
        },
        input_mapping: [
          { field_id: 'condition', proc: condition },
        ],
      },
    )
  end

  context 'validation' do
    context 'predecessor action' do
      context 'duplicate predecessors' do
        it 'should validate only one action succeeds the trigger' do
          runbook.actions << max_action(20)
          expect(runbook).to be_valid

          runbook.actions << max_action(30)
          expect(runbook).not_to be_valid
          expect(runbook.full_error_messages).to include(
            'Action (max30_action_reference) invalid: ' \
            'Predecessor (trigger) also connected to: max20_action_reference.'
          )
        end

        it 'should validate only one action succeeds nested action without setting the predecessor output schema' do
          runbook.actions << if_else_action('true')
          runbook.actions << max_action(20, predecessor_action_reference: runbook.actions.first.reference)
          expect(runbook).to be_valid

          runbook.actions << max_action(30, predecessor_action_reference: runbook.actions.first.reference)
          expect(runbook).not_to be_valid
          expect(runbook.full_error_messages).to include(
            'Action (max30_action_reference) invalid: ' \
            'Predecessor action If-then-else (if_else_true_action_reference) also ' \
            'connected to: max20_action_reference.'
          )
        end

        it 'should validate only one action succeeds nested action with setting the predecessor output schema' do
          runbook.actions << if_else_action('true')
          runbook.actions << max_action(
            20,
            predecessor_action_reference: runbook.actions.first.reference,
            predecessor_output_schema_reference: runbook.actions.first.output_schemas.first.reference
          )
          expect(runbook).to be_valid

          runbook.actions << max_action(
            30,
            predecessor_action_reference: runbook.actions.first.reference,
            predecessor_output_schema_reference: runbook.actions.first.output_schemas.first.reference
          )
          expect(runbook).not_to be_valid
          expect(runbook.full_error_messages).to include(
            'Action (max30_action_reference) invalid: ' \
            'Predecessor action If-then-else (if_else_true_action_reference - ' \
            'condition-met-output-schema-id) also connected to: max20_action_reference.'
          )
        end

        it 'should accept two actions nested on different output schemas and connected to the action itself' do
          runbook.actions << if_else_action('true')
          runbook.actions << max_action(
            20,
            predecessor_action_reference: runbook.actions.first.reference,
            predecessor_output_schema_reference: runbook.actions.first.output_schemas.first.reference
          )
          expect(runbook).to be_valid

          runbook.actions << max_action(
            30,
            predecessor_action_reference: runbook.actions.first.reference,
            predecessor_output_schema_reference: runbook.actions.first.output_schemas.last.reference
          )
          expect(runbook).to be_valid

          runbook.actions << max_action(
            40,
            predecessor_action_reference: runbook.actions.first.reference,
          )
          expect(runbook).to be_valid
        end
      end

      context 'presence of predecessor' do
        it 'should validate the predecessor action is known' do
          runbook.actions << max_action(20, predecessor_action_reference: 'foo')
          expect(runbook).not_to be_valid
          expect(runbook.full_error_messages).to include(
            'Action (max20_action_reference) invalid: Predecessor action foo is unknown.'
          )
        end

        it 'should validate the predecessor does not self-reference' do
          runbook.actions << max_action(20, predecessor_action_reference: 'max20_action_reference')
          expect(runbook).not_to be_valid
          expect(runbook.full_error_messages).to include(
            'Action (max20_action_reference) invalid: cannot be its own predecessor.'
          )
        end
      end

      it 'should validate the predecessor action is not a descendent' do
        runbook.actions << max_action(
          20,
          predecessor_action_reference: 'max30_action_reference',
        )
        runbook.actions << max_action(
          30,
          predecessor_action_reference: 'max20_action_reference',
        )
        expect(runbook).not_to be_valid
        expect(runbook.full_error_messages).to include(
          'Actions (max20_action_reference) invalid: Predecessor action cannot be a descendant.'
        )
        expect(runbook.full_error_messages).to include(
          'Actions (max30_action_reference) invalid: Predecessor action cannot be a descendant.'
        )
      end
    end

    context 'predecessor output schema' do
      it 'should validate the output schema is known' do
        runbook.actions << if_else_action('true')
        expect(runbook).to be_valid

        runbook.actions << max_action(
          30,
          predecessor_action_reference: runbook.actions.first.reference,
          predecessor_output_schema_reference: 'foo',
        )
        expect(runbook).not_to be_valid
        expect(runbook.full_error_messages).to include(
          'Actions (max30_action_reference) invalid: Predecessor output schema foo is unknown.'
        )
      end

      it 'should deny the successor of a non-nested action to define the output schema uuid' do
        runbook.actions << max_action(20)
        expect(runbook).to be_valid

        runbook.actions << max_action(
          30,
          predecessor_action_reference: runbook.actions.first.reference,
          predecessor_output_schema_reference: 'max-output-schema-id',
        )
        expect(runbook).not_to be_valid
        expect(runbook.full_error_messages).to include(
          'Predecessor output schema is only available for nested actions.'
        )
      end
    end
  end

  describe 'nested?' do
    it 'should return true for actions where the action template is nested' do
      expect(if_else_action('false').nested?).to be_truthy
    end

    it 'should return false for actions where the action template is not nested' do
      expect(max_action(20).nested?).to be_falsey
    end
  end

  describe 'predecessor_action' do
    it 'should retrieve the predecessor action' do
      runbook.actions << if_else_action('true')
      runbook.actions << max_action(20, predecessor_action_reference: runbook.actions.first.reference)
      expect(runbook.actions.last.predecessor_action).to eq(runbook.actions.first)
    end

    it 'should return nil if no predecessor action is defined' do
      runbook.actions << if_else_action('true')
      expect(runbook.actions.first.predecessor_action).to be_nil
    end

    it 'should return nil if the action cannot be found' do
      runbook.actions << if_else_action('true')
      runbook.actions << max_action(20, predecessor_action_reference: 'foo')
      expect(runbook.actions.last.predecessor_action).to be_nil
    end

    describe 'predecessor_output_schema' do
      it 'should retrieve the predecessor output schema' do
        runbook.actions << if_else_action('true')
        runbook.actions << max_action(
          20,
          predecessor_action_reference: runbook.actions.first.reference,
          predecessor_output_schema_reference: 'condition-met-output-schema-id',
        )
        expect(runbook.actions.last.predecessor_output_schema).to eq(runbook.actions.first.output_schemas.first)
      end

      it 'should return nil if no predecessor output schema is defined' do
        runbook.actions << if_else_action('true')
        expect(runbook.actions.first.predecessor_output_schema).to be_nil
      end

      it 'should return nil if the action cannot be found' do
        runbook.actions << if_else_action('true')
        runbook.actions << max_action(20, predecessor_action_reference: 'foo')
        expect(runbook.actions.last.predecessor_output_schema).to be_nil
      end

      it 'should return nil if the output schema cannot be found' do
        runbook.actions << if_else_action('true')
        runbook.actions << max_action(
          20,
          predecessor_action_reference: runbook.actions.first.reference,
          predecessor_output_schema_reference: 'foo',
        )
        expect(runbook.actions.last.predecessor_output_schema).to be_nil
      end
    end
  end

  describe 'successor' do
    it 'should retrieve the successor action for an output schema' do
      runbook.actions << max_action(20)
      runbook.actions << max_action(30, predecessor_action_reference: runbook.actions.first.reference)
      expect(runbook.actions.first.successor).to eq(runbook.actions.last)
    end

    it 'should retrieve the successor action for a nested output schema' do
      runbook.actions << if_else_action('true')
      runbook.actions << max_action(
        20,
        predecessor_action_reference: runbook.actions.first.reference,
        predecessor_output_schema_reference: 'condition-met-output-schema-id',
      )
      expect(runbook.actions.first.successor('condition-met-output-schema-id')).to eq(runbook.actions.last)
    end

    it 'should retrieve the successor action for a nested action' do
      runbook.actions << if_else_action('true')
      runbook.actions << max_action(
        20,
        predecessor_action_reference: runbook.actions.first.reference,
      )
      expect(runbook.actions.first.successor).to eq(runbook.actions.last)
    end

    it 'should raise an error when calling successor without an output schema id on a non-nested action' do
      action = max_action(20)
      expect do
        action.successor('max-output-schema-id')
      end.to raise_error('output_schema_reference only available for nested actions')
    end
  end

  context '100% coverage' do
    it 'should call the run actions' do
      max_action(20).run
      if_else_action('false').run
      if_else_action('true').run
    end
  end
end
