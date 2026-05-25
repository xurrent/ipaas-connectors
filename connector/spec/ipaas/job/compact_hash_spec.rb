require 'spec_helper'

describe IPaaS::Job::CompactHash do
  describe '.compact_hash' do
    it 'removes nil values' do
      result = described_class.compact_hash({ a: 1, b: nil })
      expect(result).to eq({ 'a' => 1 })
    end

    it 'removes empty string values' do
      result = described_class.compact_hash({ a: 'hello', b: '' })
      expect(result).to eq({ 'a' => 'hello' })
    end

    it 'removes empty array values' do
      result = described_class.compact_hash({ a: 'hello', b: [] })
      expect(result).to eq({ 'a' => 'hello' })
    end

    it 'removes empty hash values' do
      result = described_class.compact_hash({ a: 'hello', b: {} })
      expect(result).to eq({ 'a' => 'hello' })
    end

    it 'keeps false values' do
      result = described_class.compact_hash({ a: false })
      expect(result).to eq({ 'a' => false })
    end

    it 'keeps zero values' do
      result = described_class.compact_hash({ a: 0 })
      expect(result).to eq({ 'a' => 0 })
    end

    it 'converts keys to strings' do
      result = described_class.compact_hash({ foo: 'bar' })
      expect(result).to eq({ 'foo' => 'bar' })
    end

    it 'returns nil for nil input' do
      expect(described_class.compact_hash(nil)).to be_nil
    end

    it 'returns nil for empty hash' do
      expect(described_class.compact_hash({})).to be_nil
    end

    it 'returns nil when all values are blank' do
      expect(described_class.compact_hash({ a: nil, b: '', c: [] })).to be_nil
    end
  end
end
