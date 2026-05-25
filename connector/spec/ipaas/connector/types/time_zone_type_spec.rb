require 'spec_helper'

describe IPaaS::Connector::Types::TimeZoneType do
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

    it 'should return name' do
      expect(subject.resolve('amsterdam')).to eq('Amsterdam')
    end

    it 'should resolve name from identifier' do
      expect(subject.resolve('cape_verde_is')).to eq('Cape Verde Is.')
    end

    it 'should not convert when value is unknown' do
      expect(subject.resolve('foo')).to eq('foo')
    end

    it 'should not convert when value is another type' do
      expect(subject.resolve(42)).to eq(42)
    end
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :time_zone)
    expect(subject.example(field)).to eq('central_time')
  end

  describe 'valid?' do
    it 'should validate known type by id as valid' do
      expect(subject.valid?('amsterdam')).to be_truthy
    end

    it 'should validate known type by name as valid' do
      expect(subject.valid?('Amsterdam')).to be_truthy
    end

    it 'should invalidate unknown types as valid' do
      expect(subject.valid?('utrecht')).to be_falsey
    end
  end

  describe 'time_zone' do
    it 'should retrieve the time_zone by id' do
      expect(subject.time_zone('amsterdam')).to eq('Amsterdam')
    end

    it 'should retrieve the time_zone by name' do
      expect(subject.time_zone('Amsterdam')).to eq('Amsterdam')
    end

    it 'should return UTC for unknown types' do
      expect(subject.time_zone('utrecht')).to eq('UTC')
    end
  end
end
