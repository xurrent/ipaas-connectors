require 'spec_helper'

describe IPaaS::Connector::Types::TimeType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(Time)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  describe 'resolve' do
    it 'should leave nils untouched' do
      expect(subject.resolve(nil)).to be_nil
    end

    it 'should resolve time' do
      resolved = subject.resolve('16:55:50')
      {
        hour: 16,
        min: 55,
        sec: 50,
      }.each do |attribute, expected|
        expect(resolved.send(attribute)).to eq(expected)
      end
    end

    it 'should convert date time to date' do
      resolved = subject.resolve(DateTime.parse('Tue, 11 Jun 2024 16:55:50 +0200'))
      {
        hour: 16,
        min: 55,
        sec: 50,
      }.each do |attribute, expected|
        expect(resolved.send(attribute)).to eq(expected)
      end
    end

    it 'should not convert date to time' do
      date = Date.current
      expect(subject.resolve(date)).to eq(date)
    end

    it 'should not convert integers' do
      expect(subject.resolve(42)).to eq(42)
    end

    it 'should not error on invalid strings' do
      expect(subject.resolve('foo')).to eq('foo')
    end
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :time)
    time = IPaaS.use_time_zone('central_time') { Time.now.in_time_zone.change(hour: 12, min: 0) }
    expect(subject.example(field)).to eq(time)
  end
end
