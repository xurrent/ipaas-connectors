require 'spec_helper'

describe 'Scheduler Trigger', :trigger do
  let(:trigger_template_id) { 'd7a8f78f-0909-4269-9473-0b3fdf6fb163' }

  let(:weekly_recurrence) do
    {
      frequency: 'weekly',
      time_zone: 'UTC',
      interval: 2,
      day: %w[saturday sunday],
      time_of_day: '16:55:50',
    }
  end

  let(:trigger_config) do
    { schedule: weekly_recurrence }
  end

  it 'should be a valid trigger' do
    expect(trigger).to be_valid
  end

  it 'should be an internal_only trigger' do
    expect(trigger.trigger_template.internal_only).to be_truthy
  end

  it 'should not have outbound traffic' do
    expect(trigger.trigger_template.outbound_traffic).to be_falsey
  end

  context 'config_schema' do
    it 'should require a schedule' do
      expect(trigger.config_schema.field(:schedule).required).to be_truthy
      expect(trigger.config_schema.field(:schedule).type).to eq(:recurrence)
    end

    it 'should not require a request_body' do
      expect(trigger.config_schema.field(:request_body).required).to be_falsey
      expect(trigger.config_schema.field(:request_body).type).to eq(:hash)
    end
  end

  context 'output_schema' do
    it 'should have body field' do
      expect(trigger.output_schema.field(:body)).to be_present
      expect(trigger.output_schema.field(:body).type).to eq(:hash)
    end

    it 'should have triggered_at field' do
      expect(trigger.output_schema.field(:triggered_at)).to be_present
      expect(trigger.output_schema.field(:triggered_at).type).to eq(:date_time)
      expect(trigger.output_schema.field(:triggered_at).required).to be_truthy
    end
  end

  context 'provision' do
    it 'should call the scheduler to create a new schedule' do
      solution = double
      allow(trigger).to receive(:solution).and_return(solution)
      allow(trigger.solution).to receive(:create_schedule!).and_return({
        success: true,
        schedule_reference: 'schedule-reference-123',
      })

      trigger.provision

      expect(trigger.store.read('schedule_reference')).to eq('schedule-reference-123')
    end

    it 'should skip if schedule already exists' do
      trigger.store.write('schedule_reference', 'existing-schedule')

      solution = double
      allow(trigger).to receive(:solution).and_return(solution)
      expect(trigger.solution).not_to receive(:create_schedule!)

      trigger.provision

      expect(trigger.store.read('schedule_reference')).to eq('existing-schedule')
    end
  end

  context 'deprovision' do
    before(:each) do
      trigger.store.write('schedule_reference', 'schedule_ref_123')
    end

    it 'should call the scheduler to delete schedule' do
      solution = double
      allow(trigger).to receive(:solution).and_return(solution)
      allow(trigger.solution).to receive(:soft_delete_schedule).with('schedule_ref_123')

      trigger.deprovision

      expect(trigger.store.read('schedule_reference')).to be_nil
      expect(trigger.solution).to have_received(:soft_delete_schedule).with('schedule_ref_123')
    end

    it 'should skip if no schedule exists' do
      trigger.store.delete('schedule_reference')

      solution = double
      allow(trigger).to receive(:solution).and_return(solution)
      expect(trigger.solution).not_to receive(:soft_delete_schedule)

      trigger.deprovision
    end
  end

  context 'parse request' do
    def validate_triggered_at(triggered_at)
      expect(triggered_at).to be_present
      expect(triggered_at).to be_a(DateTime)
      expect(triggered_at.to_i).to be_within(5).of(Time.current.to_i)
    end

    it 'should return the incoming request body and current timestamp' do
      data = { schedule_id: 'schedule_id_1' }
      request_body = data.to_json

      request = double('request')
      allow(request).to receive(:body).and_return(double('body', read: request_body, rewind: nil))

      output = trigger.parse_request(request)
      validate_triggered_at(output[:triggered_at])
    end

    it 'should handle empty request body' do
      request = double('request')
      allow(request).to receive(:body).and_return(double('body', read: nil, rewind: nil))

      output = trigger.parse_request(request)

      expect(output[:body]).to be_nil
      validate_triggered_at(output[:triggered_at])
    end
  end
end
