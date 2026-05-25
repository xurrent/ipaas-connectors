require 'spec_helper'

describe IPaaS::Connector::Types::FloatType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(Float)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  describe 'resolve' do
    it 'should leave nils untouched' do
      expect(subject.resolve(nil)).to be_nil
    end

    it 'should convert integers to float' do
      expect(subject.resolve(42)).to eq(42.0)
    end

    it 'should return floats' do
      expect(subject.resolve(42.3)).to eq(42.3)
    end

    it 'should convert strings to floats' do
      expect(subject.resolve('42.3')).to eq(42.3)
    end

    it 'should convert negative strings to floats' do
      expect(subject.resolve('-42.3')).to eq(-42.3)
    end

    it 'should not convert invalid strings to floats' do
      expect(subject.resolve('42,3')).to eq('42,3')
    end
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :float)
    expect(subject.example(field)).to eq(3.14159265359)
  end
end
