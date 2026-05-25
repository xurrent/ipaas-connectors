require 'spec_helper'

describe 'Flow Batch Action', :action do
  let(:action_template_id) { '7c07f696-e14a-4b18-8f39-39f01908f3f0' }

  context 'input_schema' do
    it 'should require items' do
      expect(action.input_schema.field(:items).required).to be_truthy
    end

    it 'should require batch size' do
      expect(action.input_schema.field(:batch_size).required).to be_truthy
    end

    it 'should accept minimum of 2 for batch size' do
      expect(action.input_schema.field(:batch_size).min).to eq(2)
    end
  end

  context 'run' do
    it 'should trigger the output schema once for each batch of items' do
      results = action({ items: (1..5).to_a, batch_size: 2 }).run

      expect(results.size).to eq(3)
      expect(results.pluck(:schema_reference).uniq.size).to eq(1)
      expect(results.pluck(:output).pluck(:items)).to eq([[1, 2], [3, 4], [5]])
    end

    it 'should work with other types as well' do
      results = action({ items: %w[foo bar baz boo hoo bar bie], batch_size: 4 }).run

      expect(results.size).to eq(2)
      expect(results.pluck(:schema_reference).uniq.size).to eq(1)
      expect(results.pluck(:output).pluck(:items)).to eq([%w[foo bar baz boo], %w[hoo bar bie]])
    end
  end
end
