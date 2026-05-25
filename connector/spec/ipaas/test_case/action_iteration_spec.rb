require 'spec_helper'

RSpec.describe IPaaS::TestCase::ActionIteration do
  describe 'validations' do
    it 'validates input expectations' do
      hash = {
        input_expectations: [
          { field_id: :method, matcher: :foo, fixed: 'GET' },
        ],
      }
      obj = IPaaS::TestCase::ActionIteration.parse(hash)
      expect(obj).not_to be_valid
      expect(obj.errors[:input_expectations])
        .to eq(['Input expectation 1 has errors: Matcher must be one of: ' \
                'equals, contains, includes, starts_with, ends_with, is_present, nested, custom.'])
    end

    it 'validates expected outputs' do
      output = { schema_reference: 'foo', expectations: [{ field_id: :bar, matcher: :foo, fixed: 'BAZ' }] }
      hash = { expected_outputs: [output] }
      obj = IPaaS::TestCase::ActionIteration.parse(hash)
      expect(obj).not_to be_valid
      expect(obj.errors[:expected_outputs])
        .to eq(['has errors (output 1): ' \
                'Expectations has errors (expectation 1): ' \
                'Matcher must be one of: ' \
                'equals, contains, includes, starts_with, ends_with, is_present, nested, custom.'])
    end

    it 'validates expected iteration state' do
      state_expectations = [{ field_id: :bar, matcher: :foo, fixed: 'BAZ' }]
      hash = { iteration_state_expectations: state_expectations }
      obj = IPaaS::TestCase::ActionIteration.parse(hash)
      expect(obj).not_to be_valid
      expect(obj.errors[:iteration_state_expectations])
        .to eq(['Iteration state expectation 1 has errors: ' \
                'Matcher must be one of: ' \
                'equals, contains, includes, starts_with, ends_with, is_present, nested, custom.'])
    end

    it 'validates job_context_identifier_expectations' do
      hash = {
        job_context_identifier_expectations: [{ matcher: 'a' }],
      }
      obj = IPaaS::TestCase::ActionIteration.parse(hash)
      expect(obj).not_to be_valid
      expect(obj.errors[:job_context_identifier_expectations])
        .to eq(['Job context identifier expectation 1 has errors: Matcher must be one of: ' \
                'equals, contains, includes, starts_with, ends_with, is_present, nested, custom.'])
    end
  end

  describe '#update_runbook_variable' do
    it 'updates runbook variable in all attribute arrays' do
      hash = {
        input_expectations: [
          { field_id: :foo, proc: 'runbook.read_variable("old-id")' },
        ],
        expected_outputs: [
          {
            expectations: [
              { field_id: :bar, proc: 'runbook.write_variable("old-id", x)' },
            ],
          },
        ],
        mocked_outputs: [
          {
            output: [
              { field_id: :baz, runbook_variable: 'old-id' },
            ],
          },
        ],
      }
      obj = IPaaS::TestCase::ActionIteration.parse(hash)
      updated = obj.update_runbook_variable('old-id', 'new-id')

      expect(updated).to be_truthy
      expect(obj.input_expectations.first.proc).to eq('runbook.read_variable("new-id")')
      expect(obj.expected_outputs.first.expectations.first.proc).to eq('runbook.write_variable("new-id", x)')
      expect(obj.mocked_outputs.first.output.first.runbook_variable).to eq('new-id')
    end

    it 'returns false when nothing is updated' do
      hash = {
        input_expectations: [
          { field_id: :foo, fixed: 'other-value' },
        ],
      }
      obj = IPaaS::TestCase::ActionIteration.parse(hash)
      expect(obj.update_runbook_variable('old-id', 'new-id')).to be_falsey

      obj = IPaaS::TestCase::ActionIteration.parse({})
      expect(obj.update_runbook_variable('old-id', 'new-id')).to be_falsey
    end
  end

  describe 'passing schema' do
    it 'passes input schema' do
      hash = {
        input_expectations: [
          { field_id: :foo, fixed: 'other-value' },
        ],
      }
      obj = IPaaS::TestCase::ActionIteration.parse(hash)
      action = double(:action)
      schema = double(:schema)
      expect(action).to receive(:input_schema).and_return(schema)

      actual = double(:actual)
      expect(obj).to receive(:check_expectations).with(action, actual, obj.input_expectations, schema: schema)

      obj.check_input_expectations(action, actual)
    end

    it 'passes iteration state schema' do
      hash = {
        iteration_state_expectations: [
          { field_id: :foo, fixed: 'other-value' },
        ],
      }
      obj = IPaaS::TestCase::ActionIteration.parse(hash)
      action = double(:action)
      schema = double(:schema)
      expect(action).to receive(:iteration_state_schema).and_return(schema)

      actual = double(:actual)
      expect(obj).to receive(:check_expectations).with(action, actual, obj.iteration_state_expectations, schema: schema)

      obj.check_iteration_state_expectations(action, actual)
    end

    it 'passes non-nested output schema' do
      output1 = { expectations: [{ field_id: :foo, matcher: :equals, fixed: 'bar' }] }
      hash = { expected_outputs: [output1] }
      obj = IPaaS::TestCase::ActionIteration.parse(hash)
      expectations = obj.expected_outputs.first.expectations

      action = double(:action)
      schema = double(:schema)
      allow(action).to receive(:nested?).and_return(false)
      expect(action).to receive(:output_schema).and_return([schema])
      actual_output = double(:actual)
      actual = [{ output: actual_output }]
      expect(obj).to receive(:check_expectations).with(action, actual_output, expectations, schema: schema)

      obj.check_expected_outputs(action, actual)
    end
  end
end
