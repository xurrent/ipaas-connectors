require 'spec_helper'

describe 'Flow Retry Action', :action do
  let(:action_template_id) { '0075802a-b2da-7e8a-98e0-f235b0962e8c' }

  context 'input_schema' do
    it 'should have no input fields' do
      expect(action.input_schema.fields).to be_empty
    end
  end

  context 'output_schema' do
    it 'should have an output schema with no fields' do
      expect(action_template.output_schemas.first).to be_present
      expect(action_template.output_schemas.first.fields).to be_empty
    end
  end

  context 'run' do
    it 'should return empty output' do
      output = run_action({})
      expect(output).to eq({})
    end

    it 'should always return the same output regardless of input' do
      output1 = run_action({})
      output2 = run_action({})
      expect(output1).to eq(output2)
      expect(output1).to eq({})
    end

    it 'should return output in the correct format' do
      result = action.run
      expect(result).to be_an(Array)
      expect(result.first).to have_key(:output)
      expect(result.first[:output]).to eq({})
    end
  end
end
