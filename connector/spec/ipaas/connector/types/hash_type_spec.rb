require 'spec_helper'

describe IPaaS::Connector::Types::HashType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(Hash)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  describe 'resolve' do
    it 'should leave nils untouched' do
      expect(subject.resolve(nil)).to be_nil
    end

    it 'should return hash with indifferent access' do
      expect(subject.resolve({ 'a' => 1 })['a']).to eq(1)
      expect(subject.resolve({ 'a' => 1 })[:a]).to eq(1)
    end

    it 'should ignore other types' do
      expect(subject.resolve(42)).to eq(42)
    end
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :hash)
    expect(subject.example(field)).to eq({ foo: 'bar' })
  end
end
