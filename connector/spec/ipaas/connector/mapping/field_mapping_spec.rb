require 'spec_helper'

describe IPaaS::Connector::Mapping::FieldMapping do
  describe 'parse' do
    context 'single field' do
      let(:field) do
        {
          field_id: :foo,
          fixed: 'Foo',
        }
      end
      it 'should parse a single fixed field mapping from JSON' do
        field_mapping = IPaaS::Connector::Mapping::FieldMapping.parse(field.to_json)
        expect(field_mapping.field_id).to eq(:foo)
        expect(field_mapping.fixed).to eq('Foo')
      end

      it 'should parse a single fixed field mapping from hash' do
        field_mapping = IPaaS::Connector::Mapping::FieldMapping.parse(field)
        expect(field_mapping.field_id).to eq(:foo)
        expect(field_mapping.fixed).to eq('Foo')
      end

      it 'should raise an error when field is not a hash' do
        expect do
          IPaaS::Connector::Mapping::FieldMapping.parse([1].to_yaml)
        end.to raise_error('Field mapping must be a hash.')
      end

      it 'should define to_h_ref' do
        field_mapping = IPaaS::Connector::Mapping::FieldMapping.parse(field)
        expect(field_mapping.to_h_ref).to eq(field)
      end
    end

    context 'multiple fields' do
      let(:fields) do
        [
          {
            field_id: :foo,
            fixed: 'Foo',
          },
          {
            field_id: :bar,
            fixed: 'Bar',
          },
        ]
      end

      it 'should parse a multiple field mappings from JSON' do
        field_mappings = IPaaS::Connector::Mapping::FieldMapping.parse(fields.to_json)
        expect(field_mappings.size).to eq(2)
        expect(field_mappings.first.field_id).to eq(:foo)
        expect(field_mappings.first.fixed).to eq('Foo')
        expect(field_mappings.last.field_id).to eq(:bar)
        expect(field_mappings.last.fixed).to eq('Bar')
      end

      it 'should parse a multiple field mappings from hash' do
        field_mappings = IPaaS::Connector::Mapping::FieldMapping.parse(fields)
        expect(field_mappings.size).to eq(2)
        expect(field_mappings.first.field_id).to eq(:foo)
        expect(field_mappings.first.fixed).to eq('Foo')
        expect(field_mappings.last.field_id).to eq(:bar)
        expect(field_mappings.last.fixed).to eq('Bar')
      end

      it 'should raise an error when field is not valid YAML' do
        expect do
          IPaaS::Connector::Mapping::FieldMapping.parse('&*%^*')
        end.to raise_error('Field mapping must be a YAML hash. Found: "&*%^*".')
      end
    end

    it 'should copy proc to field mapping' do
      field_mapping = IPaaS::Connector::Mapping::FieldMapping.parse(
        {
          field_id: :foo,
          proc: '"Hello World!"',
        }.to_yaml
      )
      expect(field_mapping.field_id).to eq(:foo)
      expect(field_mapping.proc).to eq('"Hello World!"')
    end

    it 'should allow the same field twice to support arrays' do
      field_mappings = IPaaS::Connector::Mapping::FieldMapping.parse(
        [
          {
            field_id: :foo,
            proc: '"Hello World!"',
          },
          {
            field_id: :foo,
            proc: '"Hello Moon!"',
          },
        ]
      )
      expect(field_mappings.first.field_id).to eq(:foo)
      expect(field_mappings.first.proc).to eq('"Hello World!"')
      expect(field_mappings.last.field_id).to eq(:foo)
      expect(field_mappings.last.proc).to eq('"Hello Moon!"')
    end

    it 'should copy nested fields as sub-field mapping' do
      hash = {
        field_id: :foo,
        nested: [
          {
            field_id: :foo,
            fixed: 'Hello World!',
          }.with_indifferent_access,
          {
            field_id: :bar,
            fixed: 'Cheers World!',
          },
        ],
      }
      field_mapping = IPaaS::Connector::Mapping::FieldMapping.parse(hash)
      expect(field_mapping.field_id).to eq(:foo)
      expect(field_mapping.nested.first.field_id).to eq(:foo)
      expect(field_mapping.nested.first.fixed).to eq('Hello World!')
      expect(field_mapping.nested.last.field_id).to eq(:bar)
      expect(field_mapping.nested.last.fixed).to eq('Cheers World!')
      expect(field_mapping.to_h_ref.with_indifferent_access).to eq(hash.with_indifferent_access)
    end

    it 'should validate nested field procs' do
      hash = {
        field_id: :foo,
        nested: [
          {
            field_id: :foo,
            proc: 'unknown(3)',
          },
          {
            field_id: :bar,
            fixed: 'Cheers World!',
          },
        ],
      }
      field_mapping = IPaaS::Connector::Mapping::FieldMapping.parse(hash)
      expect(field_mapping).not_to be_valid
      expect(field_mapping.errors[:nested]).to include("(foo) invalid: Proc invalid: Method 'unknown' not allowed.")
    end

    it 'should copy variable to field mapping' do
      field_mapping = IPaaS::Connector::Mapping::FieldMapping.parse(
        {
          field_id: :foo,
          variable: :foo,
        }
      )
      expect(field_mapping.field_id).to eq(:foo)
      expect(field_mapping.variable).to eq(:foo)
    end

    it 'should copy runbook variable to field mapping' do
      field_mapping = IPaaS::Connector::Mapping::FieldMapping.parse(
        {
          field_id: :foo,
          runbook_variable: :foo,
        }
      )
      expect(field_mapping.field_id).to eq(:foo)
      expect(field_mapping.runbook_variable).to eq(:foo)
    end
  end

  describe 'fixed_mapping' do
    it 'should create fixed fields' do
      field_mappings = IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(
        {
          foo: 'bar',
          nested: {
            bar: 'bie',
          },
          cars: [
            { name: 'MV', nr: 33 },
            { name: 'LH', nr: 44 },
            { name: 'CL', nr: 16 },
          ],
        }
      )
      expect(field_mappings.size).to eq(3)
      expect(field_mappings.pluck(:field_id)).to eq([:foo, :nested, :cars])
      expect(field_mappings.first[:fixed]).to eq('bar')
      expect(field_mappings.second[:fixed]).to eq({ bar: 'bie' })
      expect(field_mappings.last[:fixed].size).to eq(3)
    end

    it 'should validate given values are a hash' do
      expect do
        IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(:foo)
      end.to raise_error('Values must be a hash.')
    end

    it 'should accept nil values' do
      expect(IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(nil)).to eq([])
    end
  end

  describe '#update_runbook_variable' do
    let(:runbook_variable_field_def) do
      double('FieldDefinition', type: :runbook_variable)
    end

    let(:string_field_def) do
      double('FieldDefinition', type: :string)
    end

    it 'updates runbook_variable attribute when it matches' do
      mapping = IPaaS::Connector::Mapping::FieldMapping.parse(
        { field_id: :foo, runbook_variable: 'old-id' }
      )
      updated = mapping.update_runbook_variable('old-id', 'new-id')

      expect(updated).to be_truthy
      expect(mapping.runbook_variable).to eq('new-id')
    end

    it 'updates fixed attribute when it matches and field_definition type is runbook_variable' do
      mapping = IPaaS::Connector::Mapping::FieldMapping.parse(
        { field_id: :foo, fixed: 'old-id' }
      )
      mapping.field_definition = runbook_variable_field_def
      updated = mapping.update_runbook_variable('old-id', 'new-id')

      expect(updated).to be_truthy
      expect(mapping.fixed).to eq('new-id')
    end

    it 'does not update fixed attribute when field_definition type is not runbook_variable' do
      mapping = IPaaS::Connector::Mapping::FieldMapping.parse(
        { field_id: :foo, fixed: 'old-id' }
      )
      mapping.field_definition = string_field_def
      updated = mapping.update_runbook_variable('old-id', 'new-id')

      expect(updated).to be_falsey
      expect(mapping.fixed).to eq('old-id')
    end

    it 'updates procs with all runbook variable methods, quote styles, and safe navigation' do
      proc_str = 'runbook.read_variable("old-id") + runbook&.write_variable(\'old-id\', x) + ' \
                 'runbook.variable_field("old-id")'
      mapping = IPaaS::Connector::Mapping::FieldMapping.parse(
        { field_id: :foo, proc: proc_str }
      )
      updated = mapping.update_runbook_variable('old-id', 'new-id')

      expect(updated).to be_truthy
      expected = 'runbook.read_variable("new-id") + runbook&.write_variable(\'new-id\', x) + ' \
                 'runbook.variable_field("new-id")'
      expect(mapping.proc).to eq(expected)
    end

    it 'updates nested mappings recursively' do
      mapping = IPaaS::Connector::Mapping::FieldMapping.parse(
        {
          field_id: :foo,
          nested: [
            { field_id: :bar, runbook_variable: 'old-id' },
            { field_id: :baz, proc: 'runbook.read_variable("old-id")' },
          ],
        }
      )
      updated = mapping.update_runbook_variable('old-id', 'new-id')

      expect(updated).to be_truthy
      expect(mapping.nested.first.runbook_variable).to eq('new-id')
      expect(mapping.nested.last.proc).to eq('runbook.read_variable("new-id")')
    end

    it 'returns false when nothing is updated' do
      mapping = IPaaS::Connector::Mapping::FieldMapping.parse(
        { field_id: :foo, fixed: 'other-value' }
      )
      updated = mapping.update_runbook_variable('old-id', 'new-id')

      expect(updated).to be_falsey
    end

    it 'handles nil values and non-string fixed values' do
      mapping1 = IPaaS::Connector::Mapping::FieldMapping.parse({ field_id: :foo })
      expect(mapping1.update_runbook_variable('old-id', 'new-id')).to be_falsey

      mapping2 = IPaaS::Connector::Mapping::FieldMapping.parse({ field_id: :foo, fixed: 123 })
      mapping2.field_definition = runbook_variable_field_def
      updated = mapping2.update_runbook_variable('123', 'new-id')
      expect(updated).to be_truthy
      expect(mapping2.fixed).to eq('new-id')

      mapping3 = IPaaS::Connector::Mapping::FieldMapping.parse({ field_id: :foo, fixed: 'old-id' })
      mapping3.field_definition = nil
      expect(mapping3.update_runbook_variable('old-id', 'new-id')).to be_falsey
    end
  end

  describe '#uses_runbook_variables?' do
    let(:runbook_variable_field_def) do
      double('FieldDefinition', type: :runbook_variable)
    end

    let(:string_field_def) do
      double('FieldDefinition', type: :string)
    end

    it 'detects the runbook_variable attribute' do
      mapping = IPaaS::Connector::Mapping::FieldMapping.parse(
        { field_id: :foo, runbook_variable: 'my-variable' }
      )
      expect(mapping.uses_runbook_variables?).to be true
    end

    it 'detects a fixed value on a runbook_variable typed field' do
      mapping = IPaaS::Connector::Mapping::FieldMapping.parse(
        { field_id: :foo, fixed: 'my-variable' }
      )
      mapping.field_definition = runbook_variable_field_def
      expect(mapping.uses_runbook_variables?).to be true
    end

    it 'detects procs for all runbook variable methods and safe navigation' do
      ['runbook.read_variable("x")', "runbook&.write_variable('x', 1)", 'runbook.variable_field("x")']
        .each do |proc_str|
        mapping = IPaaS::Connector::Mapping::FieldMapping.parse({ field_id: :foo, proc: proc_str })
        expect(mapping.uses_runbook_variables?).to be(true), proc_str
      end
    end

    it 'detects runbook variables in nested mappings' do
      mapping = IPaaS::Connector::Mapping::FieldMapping.parse(
        { field_id: :foo, nested: [{ field_id: :bar, runbook_variable: 'my-variable' }] }
      )
      expect(mapping.uses_runbook_variables?).to be true
    end

    it 'is false for mappings without runbook variable references' do
      # Contrast for each detected shape: plain fixed, environment variable,
      # unrelated proc, and nested without references.
      [
        { field_id: :foo, fixed: 'plain' },
        { field_id: :foo, variable: 'environment-variable' },
        { field_id: :foo, proc: 'environment[:foo]' },
        { field_id: :foo, nested: [{ field_id: :bar, fixed: 'x' }] },
      ].each do |hash|
        mapping = IPaaS::Connector::Mapping::FieldMapping.parse(hash)
        expect(mapping.uses_runbook_variables?).to be(false), hash.inspect
      end
    end

    it 'is false for a fixed value on a field that is not runbook_variable typed' do
      # Contrast with 'detects a fixed value on a runbook_variable typed field'.
      mapping = IPaaS::Connector::Mapping::FieldMapping.parse(
        { field_id: :foo, fixed: 'my-variable' }
      )
      mapping.field_definition = string_field_def
      expect(mapping.uses_runbook_variables?).to be false
    end
  end
end
