require 'spec_helper'

describe 'Flow Try-Catch Action', :action do
  let(:action_template_id) { '322bb36b-863f-4b31-a677-bb9c927c9202' }

  context 'iteration_state_schema' do
    it 'should have condition as boolean type' do
      expect(action.iteration_state_schema.field(:condition).type).to eq(:boolean)
    end

    it 'should have error_message as string type' do
      expect(action.iteration_state_schema.field(:error_message).type).to eq(:string)
    end
  end

  context 'output_schemas' do
    it 'should have a try output schema' do
      try_schema = action_template.output_schemas.find { |s| s.reference == 'try' }
      expect(try_schema).to be_present
      expect(try_schema.name).to eq('Try')
    end

    it 'should have a catch output schema with error field' do
      catch_schema = action_template.output_schemas.find { |s| s.reference == 'catch' }
      expect(catch_schema).to be_present
      expect(catch_schema.name).to eq('Catch')
      expect(catch_schema.field(:error).type).to eq(:string)
      expect(catch_schema.field(:error).required).to be_truthy
    end
  end

  context 'run' do
    it 'should trigger the try schema when condition is nil' do
      output = run_action({}, schema_reference: 'try')
      expect(output).to eq({})
    end

    it 'should not trigger the catch schema when condition is nil' do
      output = run_action({}, schema_reference: 'catch')
      expect(output).to be_nil
    end

    it 'should trigger the try schema when condition is string false' do
      a = action({})
      runbook.store_action_iteration_state(a.reference, { value: { condition: 'false' } })
      results = a.run
      output = results.detect { |result| result[:schema_reference] == 'try' }&.[](:output)
      expect(output).to eq({})
    end

    it 'should trigger the catch schema when condition is string true' do
      error_message = 'Something went wrong'
      a = action({})
      runbook.store_action_iteration_state(a.reference, { value: { condition: 'true', error_message: error_message } })
      results = a.run
      output = results.detect { |result| result[:schema_reference] == 'catch' }&.[](:output)
      expect(output[:error]).to eq(error_message)
    end

    it 'should not trigger the try schema when condition is string true' do
      a = action({})
      runbook.store_action_iteration_state(a.reference, { value: { condition: 'true', error_message: 'test' } })
      results = a.run
      output = results.detect { |result| result[:schema_reference] == 'try' }&.[](:output)
      expect(output).to be_nil
    end
  end
end
