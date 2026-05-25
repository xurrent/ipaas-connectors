require 'spec_helper'

describe IPaaS::Job::BlueprintStore do
  FILENAME_A = 'test.txt'.freeze
  FILENAME_B = 'app_offering.json'.freeze

  class BlueprintTestContext
    include IPaaS::Job::BlueprintStore
    include RSpec::Mocks::ExampleMethods

    def initialize(connection_uuid: 'connection-uuid', filenames: [FILENAME_A, FILENAME_B])
      @connection_uuid = connection_uuid
      @filenames = filenames
    end

    def trigger
      double(
        outbound_connection: double(uuid: @connection_uuid),
        trigger_template: double(blueprint_filenames: @filenames)
      )
    end
  end

  let(:context) { BlueprintTestContext.new }

  describe 'blueprint_store' do
    it 'should add a default store' do
      context.blueprint_store.write(FILENAME_A, 'bar')
      expect(context.blueprint_store.read(FILENAME_A)).to eq('bar')
    end

    it 'should isolate stores by outbound connection' do
      context2 = BlueprintTestContext.new(connection_uuid: 'other-id')
      context.blueprint_store.write(FILENAME_A, 'bar')
      context2.blueprint_store.write(FILENAME_A, 'baz')
      expect(context.blueprint_store.read(FILENAME_A)).to eq('bar')
      expect(context2.blueprint_store.read(FILENAME_A)).to eq('baz')
    end

    it 'should be possible to override blueprint_store_for' do
      memory_store = ActiveSupport::Cache::MemoryStore.new
      allow(BlueprintTestContext)
        .to receive(:blueprint_store_for)
        .and_return(memory_store)

      context2 = BlueprintTestContext.new
      context.blueprint_store.write(FILENAME_A, 'bar')
      expect(context.blueprint_store.read(FILENAME_A)).to eq('bar')
      expect(context2.blueprint_store.read(FILENAME_A)).to eq('bar')
    end
  end

  it 'should perform the basic operations' do
    expect(context.blueprint_store.read(FILENAME_A)).to be_nil

    context.blueprint_store.write(FILENAME_A, 'my contents')
    expect(context.blueprint_store.read(FILENAME_A)).to eq('my contents')

    context.blueprint_store.write(FILENAME_A, 'my updated contents')
    expect(context.blueprint_store.read(FILENAME_A)).to eq('my updated contents')

    context.blueprint_store.delete(FILENAME_A)
    expect(context.blueprint_store.read(FILENAME_A)).to be_nil
  end

  context 'key validation' do
    it 'should fail on read' do
      expect do
        context.blueprint_store.read('unknown')
      end.to raise_error(ArgumentError, "Invalid filename: 'unknown', allowed: 'app_offering.json', 'test.txt'.")
    end

    it 'should fail on write' do
      expect do
        context.blueprint_store.write('unknown', 'contents')
      end.to raise_error(ArgumentError, "Invalid filename: 'unknown', allowed: 'app_offering.json', 'test.txt'.")
    end

    it 'should fail on delete' do
      expect do
        context.blueprint_store.delete('unknown')
      end.to raise_error(ArgumentError, "Invalid filename: 'unknown', allowed: 'app_offering.json', 'test.txt'.")
    end
  end

  context 'size validation' do
    it 'should fail on write' do
      expect do
        context.blueprint_store.write(FILENAME_A, 'a' * 257.kilobytes)
      end.to raise_error(ArgumentError, "File 'test.txt' too large, allowed: 256 KB.")
    end
  end

  describe 'checksum' do
    it 'should return nil when no blueprint files are present' do
      expect(context.blueprint_store.checksum).to be_nil
    end

    it 'should be consistent' do
      context.blueprint_store.write(FILENAME_A, 'my contents')
      checksum = context.blueprint_store.checksum
      expect(checksum).not_to be_nil

      context.blueprint_store.delete(FILENAME_A)
      expect(context.blueprint_store.checksum).to be_nil

      context.blueprint_store.write(FILENAME_A, 'my contents')
      expect(context.blueprint_store.checksum).to eq(checksum)
    end

    it 'should depend on the file content' do
      context.blueprint_store.write(FILENAME_A, 'my contents')
      checksum = context.blueprint_store.checksum

      context.blueprint_store.write(FILENAME_A, 'my updated contents')
      expect(context.blueprint_store.checksum).not_to eq(checksum)
    end

    it 'should depend on the filename' do
      context.blueprint_store.write(FILENAME_A, 'my contents')
      checksum = context.blueprint_store.checksum

      context.blueprint_store.delete(FILENAME_A)
      context.blueprint_store.write(FILENAME_B, 'my contents')
      expect(context.blueprint_store.checksum).not_to eq(checksum)
    end

    it 'should depend on all files' do
      context.blueprint_store.write(FILENAME_A, 'my contents')
      checksum = context.blueprint_store.checksum

      context.blueprint_store.write(FILENAME_B, 'my other contents')
      expect(context.blueprint_store.checksum).not_to eq(checksum)
    end
  end

  describe 'clear!' do
    it 'should clear all files' do
      context.blueprint_store.write(FILENAME_A, 'my contents')
      context.blueprint_store.write(FILENAME_B, 'my other contents')
      expect(context.blueprint_store.read(FILENAME_A)).not_to be_nil
      expect(context.blueprint_store.read(FILENAME_B)).not_to be_nil

      context.blueprint_store.clear!
      expect(context.blueprint_store.read(FILENAME_A)).to be_nil
      expect(context.blueprint_store.read(FILENAME_B)).to be_nil
    end
  end

  describe 'blank?' do
    it 'should return true when no files are present' do
      expect(context.blueprint_store.blank?).to be_truthy
      context.blueprint_store.write(FILENAME_A, 'my contents')
      expect(context.blueprint_store.blank?).to be_falsey
      context.blueprint_store.clear!
      expect(context.blueprint_store.blank?).to be_truthy
    end
  end

  describe 'present?' do
    it 'should return true when files are present' do
      expect(context.blueprint_store.present?).to be_falsey
      context.blueprint_store.write(FILENAME_A, 'my contents')
      expect(context.blueprint_store.present?).to be_truthy
      context.blueprint_store.clear!
      expect(context.blueprint_store.present?).to be_falsey
    end
  end
end
