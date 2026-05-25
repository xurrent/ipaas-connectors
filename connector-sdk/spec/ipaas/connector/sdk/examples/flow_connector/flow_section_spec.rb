require 'spec_helper'

describe 'Section Action', :action do
  let(:action_template_id) { '0195802a-b2da-7e8a-98e0-f235b0962e8c' }

  context 'input_schema' do
    it 'should not have any input values' do
      expect(action.input_schema.fields).to be_blank
    end
  end

  context 'output_schema' do
    it 'should not have a name' do
      expect(action.output_schema.first.name).to be_blank
    end

    it 'should not have any output values' do
      expect(action.output_schema.size).to eq(1)
      expect(action.output_schema.first.fields).to be_blank
    end
  end

  context 'run' do
    it 'should trigger the nested_section' do
      output = run_action({}, schema_reference: 'nested_section')
      expect(output).to eq({})
    end
  end
end
