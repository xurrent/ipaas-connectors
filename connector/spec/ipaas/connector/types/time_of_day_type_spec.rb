require 'spec_helper'

describe IPaaS::Connector::Types::TimeOfDayType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(String)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :time_of_day)
    expect(subject.example(field)).to eq('14:23:50')
  end

  describe 'resolve' do
    it 'should resolve Time to string' do
      expect(subject.resolve(Time.parse('04:04:21'))).to eq('04:04:21')
    end

    it 'should leave given string in tact' do
      expect(subject.resolve('4:24')).to eq('4:24')
    end
  end

  describe 'valid?' do
    %w[0:0 4:04 04:04 23:59 23:59:0 23:59:59 23:59:59.1234].each do |valid_value|
      it "should accept '#{valid_value}' as valid" do
        expect(subject.valid?(valid_value)).to be_truthy
      end
    end

    %w[:0 0: 4:60 25:04 00:04:60 23:59:59.].each do |valid_value|
      it "should reject '#{valid_value}' as invalid" do
        expect(subject.valid?(valid_value)).to be_falsey
      end
    end
  end
end
