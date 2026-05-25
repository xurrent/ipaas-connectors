require 'spec_helper'

describe IPaaS::Connector::Types::AnyType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(Object)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  describe 'resolve' do
    it 'should leave nils untouched' do
      expect(subject.resolve(nil)).to be_nil
    end

    it 'should return anything' do
      anything = Object.new
      expect(subject.resolve(anything).object_id).to eq(anything.object_id)
    end
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :any_item_type)
    expect(subject.example(field)).to eq('anything')
  end
end
