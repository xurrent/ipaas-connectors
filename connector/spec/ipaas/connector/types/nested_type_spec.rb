require 'spec_helper'

describe IPaaS::Connector::Types::NestedType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(Hash)
  end

  it 'should return true for nested?' do
    expect(subject.nested?).to be_truthy
  end

  describe 'example' do
    it 'should return a hash of field examples' do
      field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :nested)
      field.field :name, 'Name', :string
      field.field :age, 'Age', :integer
      expect(subject.example(field)).to eq({ name: 'Hello World!', age: 42 })
    end

    it 'should skip nil entries in fields' do
      field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :nested)
      sub_field = IPaaS::Connector::Schema::Field.new(id: :name, label: 'Name', type: :string)
      field.fields = [nil, sub_field]
      expect(subject.example(field)).to eq({ name: 'Hello World!' })
    end
  end
end
