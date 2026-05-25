require 'spec_helper'

describe 'Log Message', :action do
  let(:action_template_id) { '0192229d-fb7a-78d2-91c8-341915eb9e87' }

  context 'input_schema' do
    it 'should require message' do
      expect(action.input_schema.field(:message).required).to be_truthy
    end
  end

  context 'run' do
    it 'logs the message' do
      message = 'Foo Bar Baz'
      output = run_action({ message: message })
      expect(output).to be_empty

      lines = tail_log('log/test.log', 5)
      expect(lines).to include('Foo Bar Baz')
    end
  end
end
