require 'spec_helper'

describe IPaaS::Connector::Types::StringType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(String)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  describe 'resolve' do
    it 'should leave nils untouched' do
      expect(subject.resolve(nil)).to be_nil
    end

    it 'should return strings' do
      expect(subject.resolve('Hello Moon!')).to eq('Hello Moon!')
    end

    it 'should auto-convert integers' do
      expect(subject.resolve(12)).to eq('12')
    end

    it 'should auto-convert floats only using . (dot) as decimal separator' do
      expect(subject.resolve(12_345.67)).to eq('12345.67')
    end
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :string)
    expect(subject.example(field)).to eq('Hello World!')
  end

  it 'should provide an example when the pattern is set' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :string, pattern: /a/)
    expect(subject.example(field)).to eq('no-example-for-pattern')
  end
end
