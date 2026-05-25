require 'spec_helper'

describe 'Update Schedule Action', :action do
  let(:action_template_id) { '6f498dde-8195-494b-95b3-8bb0d2b6eb68' }
  let(:schedule_reference) { 'test-schedule-123' }

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
      schedule_reference: schedule_reference,
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

    it 'should require a schedule_reference' do
      expect(action.input_schema.field(:schedule_reference).required).to be_truthy
      expect(action.input_schema.field(:schedule_reference).type).to eq(:string)
    end
  end

  context 'output_schema' do
    it 'should have success field' do
      expect(action.output_schemas.first.field(:success)).to be_present
      expect(action.output_schemas.first.field(:success).type).to eq(:boolean)
      expect(action.output_schemas.first.field(:success).required).to be_truthy
    end
  end

  context 'run' do
    let(:schedule_attributes) { weekly_recurrence }
    let(:expected_result) do
      {
        success: true,
        next_occurrence_at: DateTime.current + 1.hour,
        next_occurrence_errors: nil,
      }
    end

    it 'should update a schedule successfully' do
      solution = double
      allow(solution).to receive(:update_schedule).with(schedule_reference, weekly_recurrence)
                                                  .and_return(expected_result)

      my_action = action(action_input)
      allow(my_action).to receive(:solution).and_return(solution)
      result = my_action.run

      expect(result).to be_an(Array)
      expect(result.first).to have_key(:output)
      expect(result.first[:output][:success]).to be_truthy
      expect(solution).to have_received(:update_schedule).with(schedule_reference, weekly_recurrence)
    end

    it 'should handle schedule update failure' do
      solution = double
      failed_result = { success: false, error: 'Schedule not found' }
      allow(solution).to receive(:update_schedule).with(schedule_reference, weekly_recurrence).and_return(failed_result)

      my_action = action(action_input)
      allow(my_action).to receive(:solution).and_return(solution)

      expect do
        my_action.run
      end.to raise_error(IPaaS::Job::FailJob, 'Failed to update schedule: Schedule not found')

      expect(solution).to have_received(:update_schedule).with(schedule_reference, weekly_recurrence)
    end

    it 'should handle schedule update failure with different error message' do
      solution = double
      failed_result = { success: false, error: 'Schedule update failed' }
      allow(solution).to receive(:update_schedule).with(schedule_reference, weekly_recurrence).and_return(failed_result)

      my_action = action(action_input)
      allow(my_action).to receive(:solution).and_return(solution)

      expect do
        my_action.run
      end.to raise_error(IPaaS::Job::FailJob, 'Failed to update schedule: Schedule update failed')

      expect(solution).to have_received(:update_schedule).with(schedule_reference, weekly_recurrence)
    end
  end
end
