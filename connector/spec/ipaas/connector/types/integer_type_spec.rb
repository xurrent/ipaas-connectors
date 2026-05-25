require 'spec_helper'

describe IPaaS::Connector::Types::IntegerType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(Integer)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  describe 'resolve' do
    it 'should leave nils untouched' do
      expect(subject.resolve(nil)).to be_nil
    end

    it 'should convert floats to integers' do
      expect(subject.resolve(42.3)).to eq(42)
    end

    it 'should return integers' do
      expect(subject.resolve(42)).to eq(42)
    end

    it 'should convert strings to integers' do
      expect(subject.resolve('42')).to eq(42)
    end

    it 'should convert float strings to integers' do
      expect(subject.resolve('42.3')).to eq(42)
    end

    it 'should convert negative float strings to integers' do
      expect(subject.resolve('-42.3')).to eq(-42)
    end

    it 'should convert negative strings to integers' do
      expect(subject.resolve('-42')).to eq(-42)
    end

    it 'should not convert invalid strings to integers' do
      expect(subject.resolve('42,3')).to eq('42,3')
    end
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :integer)
    expect(subject.example(field)).to eq(42)
  end
end
