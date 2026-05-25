require 'spec_helper'

describe 'Delete Schedule Action', :action do
  let(:action_template_id) { '0198990a-c37a-706d-b7c4-9859f95d6685' }
  let(:schedule_reference) { 'test-schedule-123' }

  let(:action_input) do
    {
      schedule_reference: schedule_reference,
    }
  end

  it 'should be a valid action' do
    expect(action).to be_valid
  end

  context 'input_schema' do
    it 'should require a schedule_reference' do
      expect(action.input_schema.field(:schedule_reference)).to be_present
      expect(action.input_schema.field(:schedule_reference).type).to eq(:string)
      expect(action.input_schema.field(:schedule_reference).required).to be_truthy
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
    it 'should delete a schedule successfully' do
      solution = double
      allow(solution).to receive(:soft_delete_schedule).with(schedule_reference)

      my_action = action(action_input)
      allow(my_action).to receive(:solution).and_return(solution)
      result = my_action.run

      expect(result).to be_an(Array)
      expect(result.first).to have_key(:output)
      expect(result.first[:output][:success]).to be_truthy
      expect(solution).to have_received(:soft_delete_schedule).with(schedule_reference)
    end
  end
end
