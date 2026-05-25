require 'spec_helper'

describe IPaaS::Job::Store do
  class TestContext
    include IPaaS::Job::Store

    def uuid
      'text-context-id'
    end
  end

  let(:context) { TestContext.new }

  describe 'store' do
    it 'should add a default store' do
      context.store.write('foo', 'bar')
      expect(context.store.read('foo')).to eq('bar')
    end

    it 'should isolate stores' do
      context2 = TestContext.new
      context.store.write('foo', 'bar')
      context2.store.write('foo', 'baz')
      expect(context.store.read('foo')).to eq('bar')
      expect(context2.store.read('foo')).to eq('baz')
    end

    it 'should be possible to override store_for' do
      memory_store = ActiveSupport::Cache::MemoryStore.new
      allow(TestContext)
        .to receive(:store_for)
        .with(an_instance_of(TestContext),
              namespace: 'TestContext:text-context-id')
        .and_return(memory_store)

      context2 = TestContext.new
      context.store.write('foo', 'bar')
      expect(context.store.read('foo')).to eq('bar')
      expect(context2.store.read('foo')).to eq('bar')
    end
  end

  describe 'namespace' do
    it 'creates namespace for connections based on their uuid' do
      action1 = IPaaS::Connector::Connection.new('abc')
      action2 = IPaaS::Connector::Connection.new('xyz')

      expect(action1.store.store.namespace).to eq('IPaaS::Connector::Connection:abc')
      expect(action2.store.store.namespace).to eq('IPaaS::Connector::Connection:xyz')
    end

    it "creates namespace for tiggers based on their runbook's uuid" do
      runbook1 = IPaaS::Connector::Runbook.new('abc')
      runbook2 = IPaaS::Connector::Runbook.new('xyz')
      action1 = IPaaS::Connector::Trigger.new({ runbook: runbook1 })
      action2 = IPaaS::Connector::Trigger.new({ runbook: runbook2 })

      expect(action1.store.store.namespace).to eq('IPaaS::Connector::Trigger:abc')
      expect(action2.store.store.namespace).to eq('IPaaS::Connector::Trigger:xyz')
    end

    it 'creates namespace for actions based on their runbook and reference' do
      runbook1 = IPaaS::Connector::Runbook.new('foo')
      runbook2 = IPaaS::Connector::Runbook.new('baz')

      action1 = IPaaS::Connector::Action.new('abc').tap do |action|
        action.runbook = runbook1
      end
      action2 = IPaaS::Connector::Action.new('xyz').tap do |action|
        action.runbook = runbook1
      end
      action3 = IPaaS::Connector::Action.new('abc').tap do |action|
        action.runbook = runbook1
      end
      action4 = IPaaS::Connector::Action.new('abc').tap do |action|
        action.runbook = runbook2
      end

      expect(action1.store.store.namespace).to eq('IPaaS::Connector::Action:foo:abc')
      expect(action2.store.store.namespace).to eq('IPaaS::Connector::Action:foo:xyz')
      expect(action3.store.store.namespace).to eq(action1.store.store.namespace)
      expect(action4.store.store.namespace).not_to eq(action1.store.store.namespace)
    end
  end
end
