require 'spec_helper'

describe IPaaS::Connector::RunbookVariable do
  let(:runbook_variable) do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo label', type: :string, max_length: 10)
    IPaaS::Connector::RunbookVariable.new('my-variable', field, 'foo')
  end

  let(:integer_field) do
    IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo label', type: :integer, min: 1, max: 42)
  end

  context 'validation' do
    it 'should be valid' do
      expect(runbook_variable).to be_valid
    end

    it 'should validate the length of the ID' do
      runbook_variable.id = 'a' * 258
      expect(runbook_variable).not_to be_valid
      expect(runbook_variable.errors[:id]).to include('is too long (maximum is 256 characters)')
    end

    it 'should validate the ID is required' do
      runbook_variable.id = nil
      expect(runbook_variable).not_to be_valid
      expect(runbook_variable.errors[:id]).to include("can't be blank.")
    end

    it 'should raise an exception when the value mapping fails' do
      runbook_variable.field = integer_field
      message = "Type of field 'foo' invalid, expected Integer found String."
      expect(runbook_variable).not_to be_valid
      expect(runbook_variable.errors[:value]).to include(message)
    end

    it 'should accept any value when field definition is not present' do
      runbook_variable.field = nil
      expect(runbook_variable).to be_valid
    end

    it 'should not error when there is no value yet' do
      runbook_variable = IPaaS::Connector::RunbookVariable.new('my-variable', integer_field)
      expect(runbook_variable).to be_valid
    end

    context 'array values' do
      let(:array_of_hashes) do
        field = IPaaS::Connector::Schema::Field.new(id: :foo,
                                                    label: 'Foo label',
                                                    type: :hash,
                                                    array: true,
                                                    max_length: 5)
        IPaaS::Connector::RunbookVariable.new('my-variable', field, [{ one: 1 }, { two: 2 }])
      end

      it 'should be valid' do
        expect(array_of_hashes).to be_valid
      end

      it 'should accept empty array' do
        array_of_hashes.value = []
        expect(array_of_hashes).to be_valid
      end

      it 'should accept nil' do
        array_of_hashes.value = nil
        expect(array_of_hashes).to be_valid
      end

      it 'should validate the length of the array' do
        array_of_hashes.value = [{ one: 1 }, { two: 2 }, { three: 3 }, { four: 4 }, { five: 5 }, { six: 6 }]
        message = "Length of field 'foo' should be at most 5."
        expect(array_of_hashes).not_to be_valid
        expect(array_of_hashes.errors[:value]).to include(message)
      end

      it 'should check the type of the values in the array' do
        array_of_hashes.value = %w[one two]
        message = "Type of field 'foo[1]' invalid, expected Hash found String."
        expect(array_of_hashes).not_to be_valid
        expect(array_of_hashes.errors[:value].join).to include(message)
      end
    end
  end
end
