require 'spec_helper'

describe IPaaS::Connector::Types::DateTimeType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(DateTime)
  end

  it 'should return true for nested?' do
    expect(subject.nested?).to be_truthy
  end

  it 'should return true for variable_resolvable?' do
    expect(subject.variable_resolvable?).to be_truthy
  end

  describe 'resolve' do
    it 'should leave nils untouched' do
      expect(subject.resolve(nil)).to be_nil
    end

    it 'should resolve date time with timezone' do
      resolved = subject.resolve('Tue, 11 Jun 2024 16:55:50 +0200')
      {
        year: 2024,
        month: 6,
        day: 11,
        hour: 16,
        utc_offset: 7200,
        minute: 55,
      }.each do |attribute, expected|
        expect(resolved.send(attribute)).to eq(expected)
      end
    end

    it 'should convert date to date time at start of day' do
      resolved = subject.resolve(Date.parse('Tue, 11 Jun 2024'))
      {
        year: 2024,
        month: 6,
        day: 11,
        hour: 0,
        utc_offset: 0,
        minute: 0,
      }.each do |attribute, expected|
        expect(resolved.send(attribute)).to eq(expected)
      end
    end

    it 'should resolve from resolved field mapping' do
      resolved = subject.resolve(
        {
          date: Date.parse('Tue, 11 Jun 2024'),
          time: Time.parse('2021-01-01 09:49:29.21267 +0200'),
          time_zone: 'America/New_York',
        }
      )
      {
        year: 2024,
        month: 6,
        day: 11,
        hour: 9,
        min: 49,
        sec: 29,
        utc_offset: -14_400,
      }.each do |attribute, expected|
        expect(resolved.send(attribute)).to eq(expected)
      end
    end

    it 'should return the hash when an error occurs' do
      resolved = subject.resolve(
        {
          date: Date.parse('Tue, 11 Jun 2024'),
          time: 'foo',
          time_zone: 'America/New_York',
        }
      )
      expect(resolved[:date]).to eq(Date.parse('Tue, 11 Jun 2024'))
      expect(resolved[:time]).to eq('foo')
      expect(resolved[:time_zone]).to eq('America/New_York')
    end

    it 'should not convert time to date time' do
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
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :date_time)
    date_time = IPaaS.use_time_zone('central_time') { DateTime.now.in_time_zone.change(hour: 12, min: 0) }
    expect(subject.example(field)).to eq(date_time)
  end

  describe 'schema' do
    let(:schema) { subject.schema }

    [:date, :time, :time_zone]
      .each do |field_id|
      it "should mark #{field_id} as required" do
        expect(schema.field(field_id).required).to be_truthy
      end
    end
  end
end
