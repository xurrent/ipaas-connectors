require 'spec_helper'

describe 'Flow Loop Action', :action do
  let(:action_template_id) { 'a9e30a7c-3caf-4d71-b629-140e68a20748' }

  context 'input_schema' do
    it 'should require items' do
      expect(action.input_schema.field(:items).required).to be_falsey
    end
  end

  context 'run' do
    it 'should trigger the output schema once for each item' do
      results = action({ items: (1..5).to_a }).run

      expect(results.size).to eq(5)
      expect(results.pluck(:schema_reference).uniq.size).to eq(1)
      expect(results.pluck(:output).pluck(:item)).to eq([1, 2, 3, 4, 5])
      expect(results.pluck(:output).pluck(:index)).to eq([0, 1, 2, 3, 4])
    end

    it 'should work with other types as well' do
      results = action({ items: %w[foo bar baz] }).run

      expect(results.size).to eq(3)
      expect(results.pluck(:schema_reference).uniq.size).to eq(1)
      expect(results.pluck(:output).pluck(:item)).to eq(%w[foo bar baz])
      expect(results.pluck(:output).pluck(:index)).to eq([0, 1, 2])
    end
  end
end
