require 'spec_helper'

describe 'Assign Runbook Variable', :action do
  let(:action_template_id) { '01956bca-86a6-7996-8d96-606af5237024' }
  let(:outbound_connection_config) { nil }

  before(:each) do
    # stub runbook variables mapped in other runbook connections/actions
    IPaaS::Connector::Runbook.parse_runbook_variables(
      runbook,
      [
        { id: 'my-int-var', label: 'My Int', type: :integer, min: 1, max: 42 },
        { id: 'my-string-var', label: 'My String', type: :string, required: true },
        { id: 'my-array-of-hash-var', label: 'My Array of Hash', type: :hash, array: true },
        {
          id: 'my-nested-var', label: 'My Nested', type: :nested,
          fields: [{ id: 'foo', label: 'My Sub Var', type: :string }],
        },
        {
          id: 'my-nested-array-var', label: 'My Nested Array', type: :nested, array: true,
          fields: [{ id: 'foo', label: 'My Sub Var', type: :string }],
        },
      ]
    )
  end

  context 'input_schema' do
    it 'should require ID' do
      expect(action.input_schema.field(:id).required).to be_truthy
    end

    it 'should not require value' do
      expect(action.input_schema.field(:value).required).to be_falsey
    end

    context 'after_update' do
      it 'should use the declared integer type' do
        input = { id: 'my-int-var', value: 42 }
        result = action(input)
        expect(result.errors).to be_empty
        expect(result.input_schema.fields.length).to eq(2)
        expect(result.output_schema.length).to eq(1)
        id_field, value_field = result.input_schema.fields

        expect(id_field.id).to eq(:id)
        expect(id_field.label).to eq('ID')
        expect(value_field.id).to eq(:value)
        expect(value_field.label).to eq('Value')
        expect(value_field.type).to eq(:integer)
        expect(value_field.required).to be_falsey
        expect(value_field.min).to eq(1)
        expect(value_field.max).to eq(42)

        output_value_field = result.output_schema.first.fields.first
        expect(output_value_field.id).to eq(:value)
        expect(output_value_field.label).to eq('Value')
        expect(output_value_field.type).to eq(:integer)
      end

      it 'should use the declared string type' do
        input = { id: 'my-string-var', value: 'foobar' }
        result = action(input)
        expect(result.errors).to be_empty
        expect(result.input_schema.fields.length).to eq(2)
        id_field, value_field = result.input_schema.fields

        expect(id_field.id).to eq(:id)
        expect(id_field.label).to eq('ID')
        expect(value_field.id).to eq(:value)
        expect(value_field.label).to eq('Value')
        expect(value_field.type).to eq(:string)
        expect(value_field.required).to be_truthy
        expect(value_field.min).to be_nil
        expect(value_field.max).to be_nil

        output_value_field = result.output_schema.first.fields.first
        expect(output_value_field.id).to eq(:value)
        expect(output_value_field.label).to eq('Value')
        expect(output_value_field.type).to eq(:string)
      end

      it 'should fall back to the any_value_type when the runbook variable is not declared' do
        input = { id: 'my-unused-var', value: 'foo' }
        result = action(input)
        expect(result.errors[:input_mapping]).to include("invalid: Field 'id' is required.")
        expect(result.input_schema.fields.length).to eq(2)
        id_field, value_field = result.input_schema.fields

        expect(id_field.id).to eq(:id)
        expect(id_field.label).to eq('ID')
        expect(value_field.id).to eq(:value)
        expect(value_field.label).to eq('Value')
        expect(value_field.type).to eq(:any_value_type)
        expect(value_field.required).to be_falsey
        expect(value_field.min).to be_nil
        expect(value_field.max).to be_nil

        output_value_field = result.output_schema.first.fields.first
        expect(output_value_field.id).to eq(:value)
        expect(output_value_field.label).to eq('Value')
        expect(output_value_field.type).to eq(:any_value_type)
      end
    end
  end

  context 'run' do
    it 'assign the runbook variable' do
      expect(runbook.read_variable('my-int-var')).to be_nil

      output = run_action({ id: 'my-int-var', value: 42 })
      expect(output).to eq({ 'value' => 42 })

      expect(runbook.read_variable('my-int-var')).to eq(42)
    end

    it 'should be possible to clear a runbook variable' do
      runbook.write_variable('my-int-var', 33)
      expect(runbook.read_variable('my-int-var')).to eq(33)

      output = run_action({ id: 'my-int-var', value: nil })
      expect(output).to eq({ 'value' => nil })

      expect(runbook.read_variable('my-int-var')).to be_nil
    end

    it 'raises an error when the runbook variable is not declared' do
      expect do
        run_action({ id: 'my-unknown-var', value: 'foo' })
      end.to raise_error(IPaaS::Error, "Action invalid: Input mapping invalid: Field 'id' is required.")
    end

    it 'raises an error when the type is incorrect' do
      type_invalid_message = "Type of field 'value' invalid, expected Integer found String."
      expect do
        run_action({ id: 'my-int-var', value: 'foo' })
      end.to raise_error(IPaaS::Error, "Action invalid: Input mapping invalid: #{type_invalid_message}")

      expect(runbook.read_variable('my-int-var')).to be_nil
    end

    context 'array values' do
      it 'should allow array values' do
        one_two = [{ one: 1 }, { two: 2 }].map(&:with_indifferent_access)
        output = run_action({ id: 'my-array-of-hash-var', value: [{ one: 1 }, { two: 2 }] })
        expect(output).to eq({ 'value' => one_two })
        expect(runbook.read_variable('my-array-of-hash-var')).to eq(one_two)
      end

      it 'should allow empty array values' do
        output = run_action({ id: 'my-array-of-hash-var', value: [] })
        expect(output).to eq({ 'value' => [] })
        expect(runbook.read_variable('my-array-of-hash-var')).to eq([])
      end

      it 'should convert to array' do
        one = { one: 1 }.with_indifferent_access
        output = run_action({ id: 'my-array-of-hash-var', value: one })
        expect(output).to eq({ 'value' => [one] })
        expect(runbook.read_variable('my-array-of-hash-var')).to eq([one])
      end
    end

    context 'nested values' do
      it 'should allow nested values' do
        output = run_action({ id: 'my-nested-var', value: { foo: 'bar' } })
        expect(output).to eq({ 'value' => { 'foo' => 'bar' } })
      end

      it 'should allow array of nested values' do
        output = run_action({ id: 'my-nested-array-var', value: [{ foo: 'bar' }, { foo: 'baz' }] })
        expect(output).to eq({ 'value' => [{ 'foo' => 'bar' }, { 'foo' => 'baz' }] })
      end
    end

    context 'default value' do
      it 'should use the default value' do
        IPaaS::Connector::Runbook.parse_runbook_variables(
          runbook,
          [{ id: 'my-int-var', label: 'My Int', type: :integer, default: 42 }]
        )

        output = run_action({ id: 'my-int-var' })
        expect(output).to eq({ 'value' => 42 })
      end
    end
  end
end
