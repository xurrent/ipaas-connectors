require 'spec_helper'

describe 'Log Message', :action do
  let(:action_template_id) { '0198371d-7927-792f-84fa-5b60337cb7e0' }

  context 'input_schema' do
    it 'should not require message' do
      expect(action.input_schema.field(:message).required).to be_falsey
    end

    it 'should have a default message value' do
      expect(action.input_schema.field(:message).default).to eq('Stopped')
    end
  end

  context 'run' do
    it 'uses the message in FailedJob exception' do
      message = 'Foo Bar Baz'
      expect { run_action({ message: message }) }.to raise_error(IPaaS::Job::FailJob, message)
    end

    it 'no error if no message is provided' do
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob)
    end
  end
end
