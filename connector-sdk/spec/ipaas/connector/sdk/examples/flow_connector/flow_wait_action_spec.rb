require 'spec_helper'

describe 'Flow Wait Action', :action do
  let(:action_template_id) { '019b0c4b-0789-74be-9b0e-0d8ef303746c' }

  context 'input_schema' do
    it 'should define seconds_to_wait' do
      action.input_schema.field(:seconds_to_wait).tap do |field|
        expect(field.label).to eq('Seconds to wait')
        expect(field.type).to eq(:integer)
        expect(field.min).to eq(0)
        expect(field.required).to be_truthy
        expect(field.visibility).to eq('visible')
        expect(field.hint).to be_present
      end
    end
  end

  describe 'output_schema' do
    it 'should only have one output schema' do
      expect(action.output_schema.map(&:reference)).to contain_exactly('actual')
    end

    describe 'schema content' do
      let(:schema) { action.output_schema.first }

      it 'should define started_at' do
        schema.field(:started_at).tap do |field|
          expect(field.label).to eq('Started at')
          expect(field.type).to eq(:time)
          expect(field.required).to be_truthy
          expect(field.visibility).to eq('visible')
          expect(field.hint).to be_present
        end
      end

      it 'should define requested_wait' do
        schema.field(:requested_wait).tap do |field|
          expect(field.label).to eq('Seconds requested to wait')
          expect(field.type).to eq(:integer)
          expect(field.required).to be_truthy
          expect(field.visibility).to eq('visible')
          expect(field.hint).to be_present
        end
      end

      it 'should define completed_at' do
        schema.field(:completed_at).tap do |field|
          expect(field.label).to eq('Completed at')
          expect(field.type).to eq(:time)
          expect(field.required).to be_truthy
          expect(field.visibility).to eq('visible')
          expect(field.hint).to be_present
        end
      end

      it 'should define actual_wait' do
        schema.field(:actual_wait).tap do |field|
          expect(field.label).to eq('Seconds waited')
          expect(field.type).to eq(:integer)
          expect(field.required).to be_truthy
          expect(field.visibility).to eq('visible')
          expect(field.hint).to be_present
        end
      end
    end
  end

  describe 'iteration_state_schema' do
    it 'should define the started_at field' do
      action.iteration_state_schema.field(:started_at).tap do |field|
        expect(field.label).to eq('Started at')
        expect(field.type).to eq(:time)
      end
    end
  end

  context 'run' do
    it 'should backoff on first run' do
      time = 6.seconds.ago.to_time
      input_data = { seconds_to_wait: 1 }

      Timecop.freeze(time)
      expect(action(input_data)).to receive(:iteration_state_value=).with({ started_at: time })

      reschedule_check = ->(error) { expect(error.reschedule_after).to eq(time + 1.seconds) }
      expect do
        run_action(input_data)
      end.to raise_error(IPaaS::Job::RescheduleJob, &reschedule_check)
    end

    it 'should complete on second run' do
      time = 7.seconds.ago.to_time
      expected_started_at = time.change(usec: 0)
      input_data = { seconds_to_wait: 1 }
      action(input_data).send(:iteration_state_value=, { started_at: time })

      Timecop.freeze(time + 2.seconds)
      expect(action(input_data)).to receive(:iteration_state_value=).with(nil)
      output = run_action(input_data)
      expect(output[:started_at]).to eq(expected_started_at)
      expect(output[:completed_at].change(usec: 0)).to eq(expected_started_at + 2.seconds)
      expect(output[:requested_wait]).to eq(1)
      expect(output[:actual_wait]).to eq(2)
    end

    it 'should complete on first run when time to wait is 0' do
      time = 8.seconds.ago.to_time
      expected_started_at = time.change(usec: 0)
      input_data = { seconds_to_wait: 0 }
      expect(action(input_data)).to receive(:iteration_state_value=).with(nil)

      Timecop.freeze(time)
      output = run_action(input_data)
      expect(output[:started_at].change(usec: 0)).to eq(expected_started_at)
      expect(output[:completed_at].change(usec: 0)).to eq(expected_started_at)
      expect(output[:requested_wait]).to eq(0)
      expect(output[:actual_wait]).to eq(0)
    end
  end
end
