require 'spec_helper'

describe 'Flow Finish Action', :action do
  let(:action_template_id) { '0198371e-7927-792f-84fa-5b60337cb7e0' }

  context 'input_schema' do
    it 'should require a message' do
      expect(action.input_schema.field(:message).required).to be_truthy
    end

    it 'should have a default message' do
      field = action.input_schema.field(:message)
      expect(field.default).to eq('Runbook execution completed')
    end
  end

  context 'output_schema' do
    it 'should have an output schema with no fields' do
      expect(action_template.output_schemas.first).to be_present
      expect(action_template.output_schemas.first.fields).to be_empty
    end
  end

  context 'run' do
    it 'should raise FinishJob exception with custom message' do
      custom_message = 'Custom completion message'
      expect do
        run_action({ message: custom_message })
      end.to raise_error(IPaaS::Job::FinishJob, custom_message)
    end

    it 'should raise FinishJob exception with default message when message not provided' do
      expect do
        run_action({})
      end.to raise_error(IPaaS::Job::FinishJob, 'Runbook execution completed')
    end

    it 'should log the message before raising exception' do
      custom_message = 'Test completion message'
      expect_any_instance_of(Logger).to receive(:info).with(custom_message)
      expect do
        run_action({ message: custom_message })
      end.to raise_error(IPaaS::Job::FinishJob, custom_message)
    end
  end
end
