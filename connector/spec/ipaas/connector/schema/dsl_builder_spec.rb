require 'spec_helper'

RSpec.describe IPaaS::Connector::Schema::DslBuilder do
  describe 'rendering fields' do
    it 'renders a simple string field with sample and hint' do
      structure = {
        type: :nested,
        fields: {
          'name' => { type: :string, values: { 'John' => 1 } },
        },
      }
      output = described_class.build(structure)
      expect(output).to eq(<<~DSL)
        field :name, 'Name', :string,
              sample: 'John',
              hint: 'For example: John'
      DSL
    end

    it 'renders an integer field' do
      structure = {
        type: :nested,
        fields: {
          'count' => { type: :integer, values: { 42 => 1 } },
        },
      }
      output = described_class.build(structure)
      expect(output).to include('field :count,')
      expect(output).to include(':integer')
      expect(output).to include('sample: 42')
    end

    it 'renders a nested field with sub-fields' do
      structure = {
        type: :nested,
        fields: {
          'user' => {
            type: :nested,
            fields: {
              'name' => { type: :string, values: { 'John' => 1 } },
            },
          },
        },
      }
      output = described_class.build(structure)
      expect(output).to include("field :user, 'User', :nested do")
      expect(output).to include("field :name, 'Name', :string")
      expect(output).to include('end')
    end

    it 'renders an array field' do
      structure = {
        type: :nested,
        fields: {
          'tags' => { type: :string, array: true, values: { 'a' => 1, 'b' => 1 } },
        },
      }
      output = described_class.build(structure)
      expect(output).to include('array: true')
      expect(output).to include("sample: ['a', 'b']")
    end

    it 'renders null type as string' do
      structure = {
        type: :nested,
        fields: {
          'missing' => { type: :null },
        },
      }
      output = described_class.build(structure)
      expect(output).to include("field :missing, 'Missing', :string")
    end

    it 'uses quoted symbol for digit-leading keys' do
      structure = {
        type: :nested,
        fields: {
          '3d_view' => { type: :string, values: { 'val' => 1 } },
        },
      }
      output = described_class.build(structure)
      expect(output).to include('field :"3d_view",')
    end

    it 'handles deeply nested structures with proper indentation' do
      structure = {
        type: :nested,
        fields: {
          'a' => {
            type: :nested,
            fields: {
              'b' => {
                type: :nested,
                fields: {
                  'c' => { type: :string, values: { 'deep' => 1 } },
                },
              },
            },
          },
        },
      }
      output = described_class.build(structure)
      expect(output).to eq(<<~DSL)
        field :a, 'A', :nested do
          field :b, 'B', :nested do
            field :c, 'C', :string,
                  sample: 'deep',
                  hint: 'For example: deep'
          end
        end
      DSL
    end
  end

  describe 'max_hint_values' do
    it 'limits the number of hint values' do
      values = { 'a' => 5, 'b' => 4, 'c' => 3, 'd' => 2, 'e' => 1 }
      structure = {
        type: :nested,
        fields: {
          'code' => { type: :string, values: values },
        },
      }
      output = described_class.build(structure, max_hint_values: 3)
      expect(output).to include("hint: 'For example: a, b, c'")
    end
  end

  describe 'max_sample_values' do
    it 'limits array sample values' do
      values = { 'a' => 5, 'b' => 4, 'c' => 3, 'd' => 2, 'e' => 1 }
      structure = {
        type: :nested,
        fields: {
          'tags' => { type: :string, array: true, values: values },
        },
      }
      output = described_class.build(structure, max_sample_values: 2)
      expect(output).to include("sample: ['a', 'b']")
    end
  end

  describe '.escape_single_quotes' do
    it 'escapes single quotes' do
      expect(described_class.escape_single_quotes("O'Brien")).to eq("O\\'Brien")
    end

    it 'handles strings without single quotes' do
      expect(described_class.escape_single_quotes('hello')).to eq('hello')
    end
  end
end
