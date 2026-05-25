require 'spec_helper'

describe 'Flow If-Then-Else Action', :action do
  let(:action_template_id) { '3a8bb36b-863f-4b31-a677-bb9c927c9202' }

  context 'input_schema' do
    it 'should require a condition' do
      expect(action.input_schema.field(:condition).required).to be_truthy
    end

    it 'has output schemas for true and false' do
      expect(action.output_schema.map(&:reference)).to eq(%w[true false])
    end

    it 'has an optional field to hide the false path that defaults to true' do
      field = action.input_schema.field(:include_false_path)
      expect(field.visibility).to eq('optional')
      expect(field.default).to eq(true)
    end

    context 'include_false_path set to false' do
      let(:action_input) do
        [
          { field_id: :include_false_path, fixed: false },
        ]
      end

      it 'hides the false output schema' do
        expect(action.output_schema.map(&:reference)).to eq(%w[true])
      end
    end
  end

  context 'run' do
    it 'should trigger the condition not met schema when condition is false' do
      output = run_action({ condition: false }, schema_reference: 'false')
      expect(output[:result]).to eq(false)
    end

    it 'should not trigger the condition not met schema when condition is false but false is excluded' do
      output = run_action({ condition: false, include_false_path: false }, schema_reference: 'false')
      expect(output).to be_nil
    end

    it 'should not trigger the condition met schema when condition is false' do
      output = run_action({ condition: false }, schema_reference: 'true')
      expect(output).to be_nil
    end

    it 'should trigger the condition met schema when condition is true' do
      output = run_action({ condition: true }, schema_reference: 'true')
      expect(output[:result]).to eq(true)
    end

    it 'should not trigger the condition is not met schema when condition is true' do
      output = run_action({ condition: true }, schema_reference: 'false')
      expect(output).to be_nil
    end

    it 'should accept string values like True as well' do
      output = run_action({ condition: 'True' }, schema_reference: 'true')
      expect(output[:result]).to eq(true)
    end

    it 'should accept string values like F as well' do
      output = run_action({ condition: 'F' }, schema_reference: 'false')
      expect(output[:result]).to eq(false)
    end
  end
end
