require 'spec_helper'

describe IPaaS::Connector::Types::NestedType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(Hash)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_truthy
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :nested)
    field.field :bar, 'Bar', :string
    expect(subject.example(field)).to eq({ bar: 'Hello World!' })
  end
end
