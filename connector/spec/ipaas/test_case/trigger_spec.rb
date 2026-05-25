require 'spec_helper'

RSpec.describe IPaaS::TestCase::Trigger do
  describe '#parse' do
    it 'parses a trigger with mocked outputs' do
      trigger = {
        mocked_output: [
          { field_id: :method, fixed: 'GET' },
          {
            field_id: :query_parameters,
            nested: [
              { field_id: :name, proc: '"connect" + "ion"' },
              { field_id: :value, fixed: 'keep-alive' },
            ],
          },
        ],
      }
      parsed = IPaaS::TestCase::Trigger.parse(trigger)
      expect(parsed).to be_a(IPaaS::TestCase::Trigger)
      expect(parsed.to_h_ref).to eq(trigger)
    end

    it 'fails with invalid input' do
      trigger = [{ mocked_output: [] }]
      expect do
        IPaaS::TestCase::Trigger.parse(trigger)
      end.to raise_error(IPaaS::Error, 'Trigger must be a hash.')
    end

    it 'parses a trigger with mocked job context identifier' do
      trigger = {
        mocked_output: [
          { field_id: :method, fixed: 'GET' },
        ],
        mocked_job_context_identifier: 1,
      }
      parsed = IPaaS::TestCase::Trigger.parse(trigger)
      expect(parsed).to be_a(IPaaS::TestCase::Trigger)
      expect(parsed.to_h_ref[:mocked_job_context_identifier]).to eq('1')
    end
  end

  describe 'validations' do
    it 'validates mocked_job_context_identifier' do
      trigger = {
        mocked_output: [
          { field_id: :method, fixed: 'GET' },
        ],
        mocked_job_context_identifier: 'a' * 256,
      }
      obj = IPaaS::TestCase::Trigger.parse(trigger)
      expect(obj).not_to be_valid
      expect(obj.errors[:mocked_job_context_identifier])
        .to eq(['is too long (maximum is 255 characters)'])
    end
  end
end
