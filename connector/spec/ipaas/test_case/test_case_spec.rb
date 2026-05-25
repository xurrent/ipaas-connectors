require 'spec_helper'

RSpec.describe IPaaS::TestCase::TestCase do
  describe '#parse' do
    it 'parses a test case' do
      trigger = { mocked_output: [{ field_id: :method, fixed: 'GET' }] }
      action = {
        reference: 'my-action',
        iterations: [
          { input_expectations: [{ field_id: :foo, matcher: :contains, fixed: 'bar' }] },
        ],
      }
      test_case = {
        name: 'Awesome test',
        description: 'Clear description',
        runbook_uuid: 'best-runbook-ever',
        trigger: trigger,
        actions: [action],
      }

      obj = IPaaS::TestCase::TestCase.parse(test_case)
      expect(obj).to be_a(IPaaS::TestCase::TestCase)
      expect(obj).to be_valid
      expect(obj.uuid).to be_present
      expect(obj.to_h.except(:uuid)).to eq(test_case.except('uuid'))
    end
  end

  describe 'validations' do
    it 'fails with invalid input' do
      expect do
        IPaaS::TestCase::TestCase.parse([{ name: 'Oops' }])
      end.to raise_error(IPaaS::Error, 'TestCase must be a hash.')
    end

    it 'validates presence of name and trigger' do
      obj = IPaaS::TestCase::TestCase.parse({ runbook_uuid: 'best-runbook-ever' })
      expect(obj).not_to be_valid
      expect(obj.errors[:name]).to eq(["can't be blank."])
      expect(obj.errors[:trigger]).to eq(["can't be blank."])
    end

    it 'validates trigger' do
      test_case = {
        name: 'Awesome test',
        description: 'Clear description',
        runbook_uuid: 'best-runbook-ever',
        trigger: {},
      }
      obj = IPaaS::TestCase::TestCase.parse(test_case)
      expect(obj).not_to be_valid
      expect(obj.errors[:trigger]).to eq(["invalid: Mocked output can't be blank."])
    end

    it 'validates actions' do
      output = { schema_reference: 'foo', expectations: [{ field_id: :bar, matcher: :equals, fixed: 'BAZ' }] }
      action = {
        reference: 'my-action',
        iterations: [
          {
            mocked_outputs: [output],
            expected_outputs: [output],
          },
        ],
      }

      test_case = {
        name: 'Awesome test',
        description: 'Clear description',
        runbook_uuid: 'best-runbook-ever',
        trigger: { mocked_output: [{ field_id: :method, fixed: 'GET' }] },
        actions: [action],
      }
      obj = IPaaS::TestCase::TestCase.parse(test_case)
      expect(obj).not_to be_valid
      expect(obj.errors[:actions])
        .to eq(['(my-action) invalid: Iterations has errors (iteration 1): ' \
                'Expected outputs Cannot set expectations on mocked output.'])

      mocked_outputs_was = obj.actions.first.iterations[0].mocked_outputs
      obj.actions.first.iterations[0].mocked_outputs = nil
      expect(obj).to be_valid

      obj.actions.first.iterations[0].mocked_outputs = mocked_outputs_was
      expect(obj).not_to be_valid

      obj.actions.first.iterations[0].expected_outputs = nil
      expect(obj).to be_valid
    end
  end

  describe '#update_action_reference' do
    it 'updates action reference in trigger' do
      test_case = {
        name: 'Awesome test',
        description: 'Clear description',
        runbook_uuid: 'best-runbook-ever',
        trigger: { mocked_output: [{ field_id: :baz, proc: 'action_output("foo")&.dig(:bar)' }] },
      }
      obj = IPaaS::TestCase::TestCase.parse(test_case)
      obj.update_action_reference('foo', 'quux')

      expect(obj.trigger.to_h_ref).to eq({
        mocked_output: [{ field_id: :baz, proc: 'action_output("quux")&.dig(:bar)' }],
      })
    end

    it 'updates action reference in actions' do
      output = { schema_reference: 'foo', expectations: [{ field_id: :baz, proc: 'action_output("foo")&.dig(:bar)' }] }
      action = {
        reference: 'my-action',
        iterations: [{ expected_outputs: [output] }],
      }

      test_case = {
        name: 'Awesome test',
        description: 'Clear description',
        runbook_uuid: 'best-runbook-ever',
        actions: [action],
      }
      obj = IPaaS::TestCase::TestCase.parse(test_case)
      obj.update_action_reference('foo', 'quux')

      expected = {
        schema_reference: 'foo',
        expectations: [{ field_id: :baz, matcher: :equals, proc: 'action_output("quux")&.dig(:bar)' }],
      }
      expect(obj.actions.first.to_h_ref).to eq({
        reference: 'my-action',
        iterations: [{ expected_outputs: [expected] }],
      })

      obj.update_action_reference('my-action', 'my-updated-action')
      expect(obj.actions.first.to_h_ref).to eq({
        reference: 'my-updated-action',
        iterations: [{ expected_outputs: [expected] }],
      })
    end
  end

  describe '#update_runbook_variable' do
    it 'updates runbook variable in actions' do
      test_case = {
        name: 'Awesome test',
        description: 'Clear description',
        runbook_uuid: 'best-runbook-ever',
        trigger: {
          mocked_output: [
            { field_id: :baz, runbook_variable: 'old-id' },
            { field_id: :qux, proc: 'runbook.read_variable("old-id")' },
          ],
        },
        actions: [
          {
            reference: 'my-action',
            iterations: [
              {
                mocked_outputs: [
                  {
                    output: [
                      { field_id: :baz, runbook_variable: 'old-id' },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      }
      obj = IPaaS::TestCase::TestCase.parse(test_case)
      updated = obj.update_runbook_variable('old-id', 'new-id')

      expect(updated).to be_truthy
      expect(obj.actions.first.iterations.first.mocked_outputs.first.output.first.runbook_variable).to eq('new-id')
    end

    it 'returns false when nothing is updated' do
      test_case = {
        name: 'Awesome test',
        description: 'Clear description',
        runbook_uuid: 'best-runbook-ever',
        trigger: { mocked_output: [{ field_id: :baz, fixed: 'other-value' }] },
      }
      obj = IPaaS::TestCase::TestCase.parse(test_case)
      expect(obj.update_runbook_variable('old-id', 'new-id')).to be_falsey

      obj.trigger = nil
      expect(obj.update_runbook_variable('old-id', 'new-id')).to be_falsey
    end
  end
end
