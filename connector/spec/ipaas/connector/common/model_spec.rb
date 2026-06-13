require 'spec_helper'

describe IPaaS::Connector::Common::Model do
  class BrokenModelTester
    include IPaaS::Connector::Common::Model
    include IPaaS::Connector::Common::UuidMixin

    attribute :name
    validates :name, presence: true
  end

  before(:each) { BrokenModelTester.records_by_uuid = {} }

  describe '#broken?' do
    it 'is false for a freshly built record' do
      expect(BrokenModelTester.new('a').broken?).to be(false)
    end

    it 'is true once a load error is set' do
      record = BrokenModelTester.new('a')
      record.load_error = 'Unable to parse'
      expect(record.broken?).to be(true)
    end
  end

  describe 'validation bridge' do
    it 'surfaces the load error as a base error and marks the record invalid' do
      record = BrokenModelTester.new('a').tap { |r| r.load_error = 'boom' }
      record.name = 'foo'

      expect(record.valid?).to be(false)
      expect(record.errors[:base]).to include('boom')
    end

    it 'leaves a parseable record validating on its own rules' do
      record = BrokenModelTester.new('a')

      expect(record.valid?).to be(false)
      expect(record.errors[:base]).to be_empty
      expect(record.errors[:name]).to be_present

      record.name = 'foo'
      expect(record.valid?).to be(true)
    end
  end

  describe '.broken' do
    it 'builds a quarantined placeholder registered in the scope' do
      record = BrokenModelTester.broken(uuid: 'a', load_error: 'boom')

      expect(record.broken?).to be(true)
      expect(record.load_error).to eq('boom')
      expect(BrokenModelTester.find('a')).to be(record)
      expect(BrokenModelTester.all.size).to eq(1)
    end

    it 'marks an already-registered record instead of raising on a duplicate uuid' do
      first = BrokenModelTester.new('a')

      result = BrokenModelTester.broken(uuid: 'a', load_error: 'boom')

      expect(result).to be(first)
      expect(result.load_error).to eq('boom')
      expect(BrokenModelTester.all.size).to eq(1)
    end
  end
end
