require 'spec_helper'

describe IPaaS::Connector::Types::DateType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(Date)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  describe 'resolve' do
    it 'should leave nils untouched' do
      expect(subject.resolve(nil)).to be_nil
    end

    it 'should resolve date' do
      resolved = subject.resolve('Tue, 11 Jun 2024 16:55:50 +0200')
      {
        year: 2024,
        month: 6,
        day: 11,
      }.each do |attribute, expected|
        expect(resolved.send(attribute)).to eq(expected)
      end
    end

    it 'should convert date time to date' do
      resolved = subject.resolve(DateTime.parse('Tue, 11 Jun 2024 16:55:50 +0200'))
      {
        year: 2024,
        month: 6,
        day: 11,
      }.each do |attribute, expected|
        expect(resolved.send(attribute)).to eq(expected)
      end
    end

    it 'should not convert time to date' do
      time = Time.now
      expect(subject.resolve(time)).to eq(time)
    end

    it 'should not convert integers' do
      expect(subject.resolve(42)).to eq(42)
    end

    it 'should not error on invalid strings' do
      expect(subject.resolve('foo')).to eq('foo')
    end
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :integer)
    expect(subject.example(field)).to eq(Date.current)
  end
end
