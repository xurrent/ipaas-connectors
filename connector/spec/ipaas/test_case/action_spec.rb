require 'spec_helper'

RSpec.describe IPaaS::TestCase::Action do
  describe '#parse' do
    it 'parses an action with expected inputs' do
      action = {
        reference: 'my-action',
        iterations: [
          {
            input_expectations: [
              { field_id: :method, matcher: :equals, fixed: 'GET' },
              {
                field_id: :query_parameters,
                matcher: :nested,
                nested: [
                  { field_id: :name, matcher: :starts_with, fixed: 'tex' },
                  { field_id: :name, matcher: :contains, fixed: 'ex' },
                  { field_id: :value, matcher: :equals, proc: 'trigger_output&.dig(:body, :note)' },
                ],
              },
            ],
          },
        ],
      }
      obj = IPaaS::TestCase::Action.parse(action)
      expect(obj).to be_a(IPaaS::TestCase::Action)
      expect(obj.to_h_ref).to eq(action)
    end

    it 'parses an action with expected outputs' do
      action = {
        reference: 'my-action',
        iterations: [
          {
            expected_outputs: [
              {
                schema_reference: 'foo',
                expectations: [
                  { field_id: :method, matcher: :equals, fixed: 'GET' },
                  {
                    field_id: :query_parameters,
                    matcher: :nested,
                    nested: [
                      { field_id: :name, matcher: :custom, proc: 'actual_value.nil?' },
                      { field_id: :value, matcher: :equals, proc: 'trigger_output&.dig(:body, :note)' },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      }
      obj = IPaaS::TestCase::Action.parse(action)
      expect(obj).to be_a(IPaaS::TestCase::Action)
      expect(obj.to_h_ref).to eq(action)
    end

    it 'parses a nested action with mocked outputs' do
      action = {
        reference: 'my-action',
        iterations: [
          {
            mocked_outputs: [
              {
                schema_reference: 'foo',
                output: [
                  { field_id: :method, fixed: 'GET' },
                  {
                    field_id: :query_parameters,
                    nested: [
                      { field_id: :name, proc: '"connect" + "ion"' },
                      { field_id: :value, fixed: 'keep-alive' },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      }
      obj = IPaaS::TestCase::Action.parse(action)
      expect(obj).to be_a(IPaaS::TestCase::Action)
      expect(obj.to_h_ref).to eq(action)

      # For test coverage:
      expect(obj.mocked_outputs(0).first.schema_reference).to eq('foo')
      expect(obj.mocked_outputs(1)).to eq([])
    end

    it 'parses a non-nested action with mocked outputs' do
      action = {
        reference: 'my-action',
        iterations: [{ mocked_outputs: [{ output: [{ field_id: :method, fixed: 'GET' }] }] }],
      }
      obj = IPaaS::TestCase::Action.parse(action)
      expect(obj).to be_a(IPaaS::TestCase::Action)
      expect(obj.to_h_ref).to eq(action)
    end

    it 'parses a non-nested action with job context identifier expectations' do
      action = {
        reference: 'my-action',
        iterations: [
          {
            mocked_outputs: [{ output: [{ field_id: :method, fixed: 'GET' }] }],
            job_context_identifier_expectations: [{ matcher: :contains, fixed: 'foo' }],
          },
        ],
      }
      obj = IPaaS::TestCase::Action.parse(action)
      expect(obj).to be_a(IPaaS::TestCase::Action)
      expect(obj.to_h_ref).to eq(action)
    end

    it 'fails on invalid input' do
      expect do
        IPaaS::TestCase::Action.parse([{ reference: 'my-action' }])
      end.to raise_error(IPaaS::Error, 'Action must be a hash.')
    end
  end

  describe 'validations' do
    it 'cannot set iteration expectations when mocked iteration state is present' do
      action = {
        reference: 'my-action',
        iterations: [{
          mocked_iteration_state: [{ field_id: :cursor, fixed: 'foo' }],
          iteration_state_expectations: [{ field_id: :cursor, fixed: 'foo' }],
        }],
      }
      obj = IPaaS::TestCase::Action.parse(action)
      expect(obj).to be_a(IPaaS::TestCase::Action)
      expect(obj).not_to be_valid
      expect(obj.errors[:iterations])
        .to contain_exactly('has errors (iteration 1): ' \
                            'Iteration state expectations Cannot set expectations on mocked iteration state.')

      # For test coverage:
      expect(obj.mocked_iteration_state(0).first.field_id).to eq(:cursor)
      expect(obj.mocked_iteration_state(1)).to eq([])
    end

    describe 'job_context_identifier_expectations' do
      it 'allows matcher to be set' do
        action = {
          reference: 'my-action',
          iterations: [{
            mocked_iteration_state: [{ field_id: :cursor, fixed: 'foo' }],
            job_context_identifier_expectations: [{ matcher: :equals, fixed: 'foo' }],
          }],
        }
        obj = IPaaS::TestCase::Action.parse(action)
        expect(obj).to be_a(IPaaS::TestCase::Action)
        expect(obj).to be_valid
        expect(obj.to_h_ref).to eq(action)
        expect(obj.errors[:iterations]).to be_empty
      end

      it 'rejects bad matcher' do
        action = {
          reference: 'my-action',
          iterations: [{
            mocked_iteration_state: [{ field_id: :cursor, fixed: 'foo' }],
            job_context_identifier_expectations: [{ matcher: 'a', fixed: 'foo' }],
          }],
        }
        obj = IPaaS::TestCase::Action.parse(action)
        expect(obj).to be_a(IPaaS::TestCase::Action)
        expect(obj).not_to be_valid
        expect(obj.errors[:iterations])
          .to contain_exactly('has errors (iteration 1): ' \
                              'Job context identifier expectations Job context identifier expectation 1 has errors: ' \
                              'Matcher must be one of: equals, contains, includes, starts_with, ends_with, ' \
                              'is_present, nested, custom.')
      end
    end
  end

  describe '#check_input_expectations' do
    def action_double(input_schema: nil)
      action = double
      allow(action).to receive(:input_schema).and_return(input_schema)
      action
    end

    it 'passes empty expectations' do
      hash = { reference: 'my-action', iterations: [{ input_expectations: [] }] }
      obj = IPaaS::TestCase::Action.parse(hash)

      result = obj.check_input_expectations(action_double, { method: 'GET' }, 0)
      expect(result).to be_nil
    end

    it 'passes when there are no expectations for the current index' do
      hash = {
        reference: 'my-action',
        iterations: [{ input_expectations: [{ field_id: :method, fixed: 'POST' }] }],
      }
      obj = IPaaS::TestCase::Action.parse(hash)

      result = obj.check_input_expectations(action_double, { method: 'GET' }, 1)
      expect(result).to be_nil
    end

    it 'passes given expectations' do
      hash = {
        reference: 'my-action',
        iterations: [
          {
            input_expectations: [
              { field_id: :method, matcher: :equals, fixed: 'GET' },
              {
                field_id: :query_parameters,
                matcher: :nested,
                nested: [
                  { field_id: :name, matcher: :starts_with, fixed: 'tex' },
                  { field_id: :name, matcher: :contains, fixed: 'ex' },
                  { field_id: :value, matcher: :equals, proc: 'trigger_output&.dig(:body, :note)' },
                ],
              },
            ],
          },
        ],
      }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = action_double
      allow(action).to receive(:trigger_output).and_return({ body: { note: 'Foo Bar' } })
      actual = {
        method: 'GET',
        query_parameters: { name: 'text', value: 'Foo Bar' },
        some_other_input: 'Not checked',
      }

      result = obj.check_input_expectations(action, actual, 0)
      expect(result.passed?).to be_truthy
      expect(result.failed?).to be_falsey
    end

    it 'fails simple expectations' do
      hash = {
        reference: 'my-action',
        iterations: [{ input_expectations: [{ field_id: :method, matcher: :equals, fixed: 'POST' }] }],
      }
      obj = IPaaS::TestCase::Action.parse(hash)

      result = obj.check_input_expectations(action_double, { method: 'GET' }, 0)
      expect(result.passed?).to be_falsey
      expect(result.failed?).to be_truthy
      expect(result.errors).to contain_exactly("Expectation failed for field 'method' with equals matcher.\n" \
                                               "Actual value: 'GET'\nExpected value: 'POST'")
    end

    it 'fails nested expectations' do
      hash = {
        reference: 'my-action',
        iterations: [
          {
            input_expectations: [
              {
                field_id: :query_parameters,
                matcher: :nested,
                nested: [{ field_id: :name, matcher: :starts_with, proc: '"t" + "ex"' }],
              },
            ],
          },
        ],
      }
      obj = IPaaS::TestCase::Action.parse(hash)

      result = obj.check_input_expectations(action_double, { query_parameters: { name: 'tax' } }, 0)
      expect(result.passed?).to be_falsey
      expect(result.failed?).to be_truthy
      expect(result.errors).to contain_exactly(
        "Expectation failed for field 'query_parameters.name' with starts_with matcher.\n" \
        "Actual value: 'tax'\n" \
        "Expected value: 'tex'"
      )
    end
  end

  describe '#check_output_expectations' do
    def action_double(nested:)
      action = double
      allow(action).to receive(:nested?).and_return(nested)
      allow(action).to receive(:find_output_schema)
      action
    end

    it 'passes empty expectations' do
      hash = { reference: 'my-action', iterations: [{ expected_outputs: [] }] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = action_double(nested: false)

      result = obj.check_output_expectations(action, [{ output: { method: 'GET' } }], 0)
      expect(result).to be_nil
    end

    it 'passes when there are no expectations for the current index' do
      hash = {
        reference: 'my-action',
        iterations: [{ expected_outputs: [{ field_id: :method, fixed: 'POST' }] }],
      }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = action_double(nested: false)

      result = obj.check_output_expectations(action, [{ output: { method: 'GET' } }], 1)
      expect(result).to be_nil
    end

    it 'evaluates expectations for non-nested actions' do
      output = { expectations: [{ field_id: :foo, matcher: :equals, fixed: 'bar' }] }
      hash = { reference: 'my-action', iterations: [{ expected_outputs: [output] }] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = action_double(nested: false)
      schema = double(:schema)
      expect(schema).to receive(:field).with(:foo).twice
      allow(action).to receive(:output_schema).and_return([schema])

      expect(obj.check_output_expectations(action, [{ output: { foo: 'bar' } }], 0).passed?).to be_truthy
      expect(obj.check_output_expectations(action, [{ output: { foo: 'quux' } }], 0).passed?).to be_falsey
    end

    it 'evaluates expectations for nested actions' do
      output1 = { schema_reference: 'scheme1', expectations: [{ field_id: :foo, matcher: :equals, fixed: 'bar' }] }
      output2 = { schema_reference: 'scheme2', expectations: [{ field_id: :baz, matcher: :equals, fixed: 'quux' }] }
      hash = { reference: 'my-action', iterations: [{ expected_outputs: [output1, output2] }] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = action_double(nested: true)
      actual = [
        { schema_reference: 'scheme1', output: { foo: 'bar' } },
        { schema_reference: 'scheme2', output: { baz: 'quux' } },
      ]
      expect(obj.check_output_expectations(action, actual, 0).passed?).to be_truthy

      actual[0][:output][:foo] = 'baz'
      expect(obj.check_output_expectations(action, actual, 0).passed?).to be_falsey

      actual[0][:output][:foo] = 'bar'
      actual[0][:schema_reference] = 'some-other-scheme'
      expect(obj.check_output_expectations(action, actual, 0).passed?).to be_falsey
    end

    it 'evaluates expectations for nested actions with multiple outputs for the same schema' do
      output1 = { schema_reference: 'scheme', expectations: [{ field_id: :foo, matcher: :equals, fixed: 'bar' }] }
      output2 = { schema_reference: 'scheme', expectations: [{ field_id: :baz, matcher: :equals, fixed: 'quux' }] }
      hash = { reference: 'my-action', iterations: [{ expected_outputs: [output1, output2] }] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = action_double(nested: true)
      actual = [
        { schema_reference: 'scheme', output: { foo: 'bar' } },
        { schema_reference: 'scheme', output: { baz: 'quux' } },
      ]
      expect(obj.check_output_expectations(action, actual, 0).passed?).to be_truthy
    end

    it 'requires number of outputs per schema to match' do
      output1 = { schema_reference: 'scheme', expectations: [{ field_id: :foo, matcher: :equals, fixed: 'bar' }] }
      output2 = { schema_reference: 'scheme', expectations: [{ field_id: :baz, matcher: :equals, fixed: 'quux' }] }
      hash = { reference: 'my-action', iterations: [{ expected_outputs: [output1, output2] }] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = action_double(nested: true)
      actual = [
        { schema_reference: 'scheme', output: { foo: 'bar' } },
        { schema_reference: 'scheme', output: { baz: 'quux' } },
        { schema_reference: 'scheme', output: { bie: 'boo' } },
      ]
      result = obj.check_output_expectations(action, actual, 0)
      expect(result.passed?).to be_falsey
      expect(result.errors).to contain_exactly("Expectation failed for number of outputs for schema 'scheme'.\n" \
                                               "Actual value: 3\nExpected value: 2\n")
    end

    it 'evaluates expectations for nested actions with multiple outputs for the same schema' do
      output1 = { schema_reference: 'scheme', expectations: [{ field_id: :foo, matcher: :equals, fixed: 'bar' }] }
      output2 = { schema_reference: 'scheme', expectations: [{ field_id: :baz, matcher: :equals, fixed: 'quux' }] }
      hash = { reference: 'my-action', iterations: [{ expected_outputs: [output1, output2] }] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = action_double(nested: true)
      schema = double(:schema)
      expect(action).to receive(:find_output_schema).with('scheme').and_return(schema)
      actual = [
        { schema_reference: 'scheme', output: { foo: 'bar' } },
        { schema_reference: 'scheme', output: { baz: 'quux' } },
      ]
      result1 = double(:result1)
      expect(result1).to receive(:errors).and_return([])
      result2 = double(:result2)
      expect(result2).to receive(:errors).and_return([])
      iteration = obj.iterations.first
      expect(iteration).to receive(:check_expectations)
        .with(action, { foo: 'bar' }, anything, schema: schema)
        .and_return(result1)
      expect(iteration).to receive(:check_expectations)
        .with(action, { baz: 'quux' }, anything, schema: schema)
        .and_return(result2)
      obj.check_output_expectations(action, actual, 0)
    end
  end

  describe '#check_iteration_state_expectations' do
    def action_double(nested: false)
      action = double(:action)
      allow(action).to receive(:nested?).and_return(nested)
      allow(action).to receive(:iteration_state_schema)
      action
    end

    it 'passes empty expectations' do
      iteration = { iteration_state_expectations: [] }
      hash = { reference: 'my-action', iterations: [iteration] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = action_double

      result = obj.check_iteration_state_expectations(action, {}, 0)
      expect(result).to be_nil
    end

    it 'passes when there are no expectations for the current index' do
      state_expectations = { field_id: :bar, matcher: :equals, fixed: 'BAZ' }
      iteration = { iteration_state_expectations: [state_expectations] }
      hash = { reference: 'my-action', iterations: [iteration] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = action_double

      result = obj.check_output_expectations(action, { bar: 'BAZ' }, 1)
      expect(result).to be_nil
    end

    it 'evaluates expectations' do
      state_expectations = { field_id: :bar, matcher: :equals, fixed: 'BAZ' }
      iteration = { iteration_state_expectations: [state_expectations] }
      hash = { reference: 'my-action', iterations: [iteration] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = action_double

      expect(obj.check_iteration_state_expectations(action, { bar: 'BAZ' }, 0).passed?).to be_truthy
      expect(obj.check_iteration_state_expectations(action, { bar: 'QUUX' }, 0).passed?).to be_falsey
    end

    it 'fails if iteration state is not expected but present' do
      iteration = { iteration_state_expectations: [] }
      hash = { reference: 'my-action', iterations: [iteration] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = action_double

      expect(obj.iteration_state_expected?(0)).to be_falsey
      result = obj.check_iteration_state_expectations(action, { bar: 'BAZ' }, 0)
      expect(result.passed?).to be_falsey
      expect(result.errors).to contain_exactly('No iteration state expected, got: {bar: "BAZ"}')
    end
  end

  describe '#check_job_context_identifier_expectations' do
    it 'passes when there are no expectations for the current index and no value is set' do
      iteration = { job_context_identifier_expectations: [] }
      hash = { reference: 'my-action', iterations: [iteration] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = double

      result = obj.check_job_context_identifier_expectations(action, nil, 0)
      expect(result).to be_nil
    end

    it 'passes when the value set matches the expected value' do
      context_id_expectation = { matcher: :equals, fixed: 'BAZ' }
      iteration = { job_context_identifier_expectations: [context_id_expectation] }
      hash = { reference: 'my-action', iterations: [iteration] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = double

      result = obj.check_job_context_identifier_expectations(action, 'BAZ', 0)
      expect(result.passed?).to eq(true)
    end

    it 'fails when the value set does not match the expected value' do
      context_id_expectation = { matcher: :equals, fixed: 'BAZ' }
      iteration = { job_context_identifier_expectations: [context_id_expectation] }
      hash = { reference: 'my-action', iterations: [iteration] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = double

      result = obj.check_job_context_identifier_expectations(action, 'foo', 0)
      expect(result.passed?).to eq(false)
      expect(result.errors).to contain_exactly("Expectation failed with equals matcher.\n" \
                                               "Actual value: 'foo'\nExpected value: 'BAZ'")
    end

    it 'fails when cleared and there was an expected value' do
      context_id_expectation = { matcher: :equals, fixed: 'BAZ' }
      iteration = { job_context_identifier_expectations: [context_id_expectation] }
      hash = { reference: 'my-action', iterations: [iteration] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = double

      result = obj.check_job_context_identifier_expectations(action, nil, 0)
      expect(result.passed?).to eq(false)
      expect(result.errors).to contain_exactly("Expectation failed with equals matcher.\n" \
                                               "Actual value: ''\nExpected value: 'BAZ'")
    end

    it 'fails when there was no expectation and a value was set' do
      hash = { reference: 'my-action', iterations: [{}] }
      obj = IPaaS::TestCase::Action.parse(hash)
      action = double

      result = obj.check_job_context_identifier_expectations(action, 'foo', 0)
      expect(result.passed?).to eq(false)
      expect(result.errors).to contain_exactly('No job context identifier change expected, got: foo')
    end
  end

  describe '#update_action_reference' do
    it 'updates action reference in mocked outputs' do
      action = {
        reference: 'my-action',
        iterations: [{ mocked_outputs: [{ output: [{ field_id: :baz, proc: 'action_output("foo")&.dig(:bar)' }] }] }],
      }
      obj = IPaaS::TestCase::Action.parse(action)
      obj.update_action_reference('foo', 'quux')

      expected = {
        output: [{ field_id: :baz, proc: 'action_output("quux")&.dig(:bar)' }],
      }
      expect(obj.to_h_ref).to eq({
        reference: 'my-action',
        iterations: [{ mocked_outputs: [expected] }],
      })

      obj.update_action_reference('my-action', 'my-updated-action')
      expect(obj.to_h_ref).to eq({
        reference: 'my-updated-action',
        iterations: [{ mocked_outputs: [expected] }],
      })
    end
  end

  describe '#update_runbook_variable' do
    it 'updates runbook variable in iterations' do
      action = {
        reference: 'my-action',
        iterations: [
          {
            mocked_outputs: [
              {
                output: [
                  { field_id: :baz, runbook_variable: 'old-id' },
                  { field_id: :qux, proc: 'runbook.read_variable("old-id")' },
                ],
              },
            ],
            expected_outputs: [
              {
                expectations: [
                  { field_id: :bar, proc: 'runbook.write_variable("old-id", x)' },
                ],
              },
            ],
          },
        ],
      }
      obj = IPaaS::TestCase::Action.parse(action)
      updated = obj.update_runbook_variable('old-id', 'new-id')

      expect(updated).to be_truthy
      expect(obj.iterations.first.mocked_outputs.first.output[0].runbook_variable).to eq('new-id')
      expect(obj.iterations.first.mocked_outputs.first.output[1].proc).to eq('runbook.read_variable("new-id")')
      expected_proc = 'runbook.write_variable("new-id", x)'
      expect(obj.iterations.first.expected_outputs.first.expectations.first.proc).to eq(expected_proc)
    end

    it 'returns false when nothing is updated' do
      action = {
        reference: 'my-action',
        iterations: [
          {
            mocked_outputs: [
              {
                output: [
                  { field_id: :baz, fixed: 'other-value' },
                ],
              },
            ],
          },
        ],
      }
      obj = IPaaS::TestCase::Action.parse(action)
      expect(obj.update_runbook_variable('old-id', 'new-id')).to be_falsey

      obj.iterations = []
      expect(obj.update_runbook_variable('old-id', 'new-id')).to be_falsey
    end
  end
end
