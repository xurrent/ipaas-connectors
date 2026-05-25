require 'spec_helper'

describe 'Logic Monitor Unregister LM User Action', :action do
  let(:action_template_id) { '0199a9a7-3ca2-7ab0-9bd2-8fca8ad3f7da' }

  context 'input_schema' do
    it 'requires user_name' do
      expect(action.input_schema.field(:user_name).required).to be_truthy
    end
  end

  context 'output_schema' do
    it 'requires user_name' do
      expect(action.output_schemas.first.field(:user_name).required).to be_truthy
    end
  end

  context 'run' do
    let(:user_name) { 'customer1' }

    let(:action_input) do
      {
        user_name: user_name,
      }
    end

    it 'deletes stored credentials' do
      expect(action.outbound_connection.store).to receive(:delete).with("secret##{user_name}")

      output = run_action
      expect(output[:user_name]).to eq(user_name)
    end
  end
end
