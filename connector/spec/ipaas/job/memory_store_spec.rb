require 'spec_helper'

describe IPaaS::Job::MemoryStore do
  let(:store) { described_class.new }

  describe 'delete' do
    it 'removes an existing key and returns true, not the deleted value' do
      store.write('foo', 'bar')

      expect(store.delete('foo')).to be(true)
      expect(store.read('foo')).to be_nil
    end

    it 'returns false, not nil, when there is no such key' do
      store.write('other', 'kept')

      expect(store.delete('foo')).to be(false)
      expect(store.read('other')).to eq('kept')
    end
  end
end
