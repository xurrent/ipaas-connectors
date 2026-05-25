require 'spec_helper'

describe 'N-Central Unregister PSA User Action', :action do
  let(:action_template_id) { '019710fb-804f-7532-8f3f-b97c9cbc189a' }

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
