require 'spec_helper'

describe 'Create Schedule Action', :action do
  let(:action_template_id) { '0198990a-a98e-7cce-a3ab-7311c2a22c36' }
  let(:schedule_reference) { 'test-schedule-123' }
  let(:runbook_uuid) { 'test-runbook-uuid' }
  let(:request_body) do
    { sample_key: 'value123' }
  end

  let(:weekly_recurrence) do
    {
      frequency: 'weekly',
      time_zone: 'UTC',
      interval: 1,
      day: %w[monday wednesday friday],
      time_of_day: '09:00:00',
    }
  end

  let(:action_input) do
    {
      schedule: weekly_recurrence,
      runbook_uuid: runbook_uuid,
      schedule_reference: schedule_reference,
      request_body: request_body,
    }
  end

  it 'should be a valid action' do
    expect(action).to be_valid
  end

  context 'input_schema' do
    it 'should require a schedule' do
      expect(action.input_schema.field(:schedule).required).to be_truthy
      expect(action.input_schema.field(:schedule).type).to eq(:recurrence)
    end

    it 'should require a runbook_uuid' do
      expect(action.input_schema.field(:runbook_uuid).required).to be_truthy
      expect(action.input_schema.field(:runbook_uuid).type).to eq(:string)
    end

    it 'should require a schedule_reference' do
      expect(action.input_schema.field(:schedule_reference).required).to be_truthy
      expect(action.input_schema.field(:schedule_reference).type).to eq(:string)
    end

    it 'should not require a request_body' do
      expect(action.input_schema.field(:request_body).required).to be_falsey
      expect(action.input_schema.field(:request_body).type).to eq(:hash)
    end
  end

  context 'output_schema' do
    it 'should have schedule_reference field' do
      expect(action.output_schemas.first.field(:schedule_reference)).to be_present
      expect(action.output_schemas.first.field(:schedule_reference).type).to eq(:string)
      expect(action.output_schemas.first.field(:schedule_reference).required).to be_truthy
    end

    it 'should have next_occurrence_at field' do
      expect(action.output_schemas.first.field(:next_occurrence_at)).to be_present
      expect(action.output_schemas.first.field(:next_occurrence_at).type).to eq(:date_time)
      expect(action.output_schemas.first.field(:next_occurrence_at).required).to be_falsy
    end

    it 'should have next_occurrence_errors field' do
      expect(action.output_schemas.first.field(:next_occurrence_errors)).to be_present
      expect(action.output_schemas.first.field(:next_occurrence_errors).type).to eq(:string)
      expect(action.output_schemas.first.field(:next_occurrence_errors).required).to be_falsy
    end
  end

  context 'run' do
    let(:schedule_attributes) do
      weekly_recurrence.merge({ reference: schedule_reference, request_body: request_body })
                       .deep_stringify_keys
    end
    let(:expected_result) do
      {
        success: true,
        schedule_reference: schedule_reference,
        next_occurrence_at: DateTime.current + 1.hour,
        next_occurrence_errors: nil,
      }
    end

    it 'should create a schedule successfully' do
      solution = double
      allow(solution).to receive(:create_schedule!).with(runbook_uuid, schedule_attributes).and_return(expected_result)

      my_action = action(action_input)
      allow(my_action).to receive(:solution).and_return(solution)
      result = my_action.run

      expect(result).to be_an(Array)
      expect(result.first).to have_key(:output)
      expect(result.first[:output][:schedule_reference]).to eq(schedule_reference)
      expect(result.first[:output][:next_occurrence_at]).to eq(expected_result[:next_occurrence_at])
      expect(solution).to have_received(:create_schedule!).with(runbook_uuid, schedule_attributes)
    end

    it 'should handle schedule creation failure' do
      solution = double
      failed_result = { success: false, error: 'Invalid schedule configuration' }
      allow(solution).to receive(:create_schedule!).with(runbook_uuid, schedule_attributes).and_return(failed_result)

      my_action = action(action_input)
      allow(my_action).to receive(:solution).and_return(solution)

      expect do
        my_action.run
      end.to raise_error(IPaaS::Job::FailJob, 'Failed to create schedule: Invalid schedule configuration')

      expect(solution).to have_received(:create_schedule!).with(runbook_uuid, schedule_attributes)
    end
  end
end
