require 'spec_helper'

describe 'Flow Case Action', :action do
  let(:action_template_id) { 'f93f2f08-c901-4655-8083-9c88e5d40761' }

  context 'input_schema' do
    it 'should require an expression' do
      expect(action.input_schema.field(:expression).required).to be_truthy
    end

    it 'should require a match' do
      expect(action.input_schema.field(:matches).required).to be_truthy
    end

    it 'should accept 50 matches at most' do
      expect(action.input_schema.field(:matches).max_length).to eq(50)
    end

    context 'with foo bar matches' do
      let(:action_input) do
        [
          { field_id: :matches, fixed: %w[foo bar] },
        ]
      end

      it 'adds the else output schema' do
        expect(action.output_schema.map(&:reference)).to eq(%w[foo bar else])
      end

      context 'include_else_path set to false' do
        let(:action_input) do
          [
            { field_id: :matches, fixed: %w[foo bar] },
            { field_id: :include_else_path, fixed: false },
          ]
        end

        it 'hides the else output schema' do
          expect(action.output_schema.map(&:reference)).to eq(%w[foo bar])
        end
      end
    end
  end

  context 'run' do
    let(:action_input) do
      [
        { field_id: :expression, proc: 'action.store.read("selected_value") || "baz"' },
        { field_id: :matches, fixed: %w[foo bar baz boo] },
      ]
    end

    it 'should return the selected match with consistent schema_reference' do
      result = action.run.first
      baz_schema_reference = result[:schema_reference]
      expect(result.dig(:output, :expression)).to eq('baz')

      action.store.write('selected_value', 'boo')
      result = action.run.first
      expect(result.dig(:output, :expression)).to eq('boo')
      expect(result[:schema_reference]).not_to eq(baz_schema_reference)

      action.store.write('selected_value', 'baz')
      result = action.run.first
      expect(result.dig(:output, :expression)).to eq('baz')
      expect(result[:schema_reference]).to eq(baz_schema_reference)
    end

    it 'should trigger the else schema when no match was found' do
      output = run_action({ matches: ['foo'], expression: 'unknown' }, schema_reference: 'else')
      expect(output[:expression]).to eq('unknown')
    end

    it 'should trigger no schema when no match was found and include_else_path is false' do
      output = run_action({ matches: ['foo'], expression: 'unknown', include_else_path: false },
                          schema_reference: 'else')
      expect(output).to be_nil
    end
  end
end
