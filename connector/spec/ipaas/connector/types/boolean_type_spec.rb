require 'spec_helper'

describe IPaaS::Connector::Types::BooleanType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(Boolean)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  describe 'resolve' do
    it 'should leave nils untouched' do
      expect(subject.resolve(nil)).to be_nil
    end

    ['t', 'true', 'True', true, '1', 1, 'Falso'].each do |value|
      it "should resolve #{value.inspect} to true" do
        expect(subject.resolve(value)).to be_truthy
      end
    end

    ['f', 'false', 'False', false, '0', 0].each do |value|
      it "should resolve #{value.inspect} to false" do
        expect(subject.resolve(value)).to be_falsey
      end
    end
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :boolean)
    expect(subject.example(field)).to eq(true)
  end
end
