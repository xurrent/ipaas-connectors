require 'spec_helper'

describe IPaaS::Connector::Common::UuidMixin do
  class UuidTesterA
    include IPaaS::Connector::Common::Model
    include IPaaS::Connector::Common::UuidMixin
  end

  class UuidTesterB
    include IPaaS::Connector::Common::Model
    include IPaaS::Connector::Common::UuidMixin
  end

  before(:each) do
    UuidTesterA.records_by_uuid = {}
    UuidTesterB.records_by_uuid = {}
  end

  describe 'initializer' do
    it 'disallows similar UUIDs in a single class' do
      expect do
        UuidTesterA.new('foo')
        UuidTesterA.new('foo')
      end.to raise_exception('Duplicate Uuid Tester A UUID: foo, in default scope.')
    end

    it 'allows similar UUIDs in different classes' do
      foo_a = UuidTesterA.new('foo')
      foo_b = UuidTesterB.new('foo')
      expect(UuidTesterA.by_uuid('foo').uuid).to eq(foo_a.uuid)
      expect(UuidTesterB.by_uuid('foo').uuid).to eq(foo_b.uuid)
    end

    it 'allows for a block that is evaluated on the newly created instance' do
      foo_a = UuidTesterA.new('foo') do
        instance_variable_set(:@local, 'foo')
      end
      expect(foo_a.instance_variable_get(:@local)).to eq('foo')
    end

    context 'scoping' do
      it 'returns current scope without block' do
        expect(IPaaS::Connector::Common::UuidMixin::DEFAULT_SCOPE).not_to eq('a')
        expect(UuidTesterA.uuid_scope).to eq(IPaaS::Connector::Common::UuidMixin::DEFAULT_SCOPE)
        UuidTesterA.uuid_scope('a') do
          expect(UuidTesterA.uuid_scope).to eq('a')
        end
        expect(UuidTesterA.uuid_scope).to eq(IPaaS::Connector::Common::UuidMixin::DEFAULT_SCOPE)
      end

      it 'current scope is thread specific' do
        ActiveSupport::IsolatedExecutionState.isolation_level = :thread
        expect(IPaaS::Connector::Common::UuidMixin::DEFAULT_SCOPE).not_to eq('a')
        expect(UuidTesterA.uuid_scope).to eq(IPaaS::Connector::Common::UuidMixin::DEFAULT_SCOPE)
        thread1_scope = nil
        thread2_scope = nil
        thread1 = Thread.new do
          UuidTesterA.uuid_scope('a') do
            expect(UuidTesterA.uuid_scope).to eq('a')
            sleep(0.1)
            thread1_scope = UuidTesterA.uuid_scope
          end
        end
        thread2 = Thread.new do
          UuidTesterA.uuid_scope('b') do
            expect(UuidTesterA.uuid_scope).to eq('b')
            thread2_scope = UuidTesterA.uuid_scope
          end
        end
        thread1.join
        thread2.join
        expect(UuidTesterA.uuid_scope).to eq(IPaaS::Connector::Common::UuidMixin::DEFAULT_SCOPE)
        expect(thread1_scope).to eq('a')
        expect(thread2_scope).to eq('b')
      end

      it 'current scope is fiber specific' do
        ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
        expect(IPaaS::Connector::Common::UuidMixin::DEFAULT_SCOPE).not_to eq('a')
        expect(UuidTesterA.uuid_scope).to eq(IPaaS::Connector::Common::UuidMixin::DEFAULT_SCOPE)
        fiber1 = Fiber.new do
          UuidTesterA.uuid_scope('a') do
            Fiber.yield UuidTesterA.uuid_scope
            Fiber.yield UuidTesterA.uuid_scope
            UuidTesterA.uuid_scope
          end
        end
        fiber2 = Fiber.new do
          UuidTesterA.uuid_scope('b') do
            Fiber.yield UuidTesterA.uuid_scope
            Fiber.yield UuidTesterA.uuid_scope
            UuidTesterA.uuid_scope
          end
        end
        expect(fiber1.resume).to eq('a')
        expect(fiber2.resume).to eq('b')
        expect(UuidTesterA.uuid_scope).to eq(IPaaS::Connector::Common::UuidMixin::DEFAULT_SCOPE)
        expect(fiber1.resume).to eq('a')
        expect(fiber2.resume).to eq('b')
        expect(UuidTesterA.uuid_scope).to eq(IPaaS::Connector::Common::UuidMixin::DEFAULT_SCOPE)
        expect(fiber1.resume).to eq('a')
        expect(fiber2.resume).to eq('b')
        expect(UuidTesterA.uuid_scope).to eq(IPaaS::Connector::Common::UuidMixin::DEFAULT_SCOPE)
      end

      context 'uuid scope as hash' do
        it 'stores uuids in the context of the class' do
          UuidTesterA.uuid_scope({}) do
            foo1a = UuidTesterA.new('foo')
            expect(UuidTesterA.by_uuid('foo')).to eq(foo1a)

            foo1b = UuidTesterB.new('foo')
            expect(UuidTesterB.by_uuid('foo')).to eq(foo1b)

            expect(UuidTesterA.by_uuid('foo')).to eq(foo1a)
          end
        end

        it 'differentiates different scopes' do
          scope1 = {}
          scope2 = {}
          foo1 = UuidTesterA.uuid_scope(scope1) do
            UuidTesterA.new('foo')
          end

          foo2 = UuidTesterA.uuid_scope(scope2) do
            UuidTesterA.new('foo')
          end

          expect(foo1).not_to eq(foo2)

          expect(UuidTesterA.uuid_scope(scope1) { UuidTesterA.by_uuid('foo') }).to eq(foo1)
          expect(UuidTesterA.uuid_scope(scope2) { UuidTesterA.by_uuid('foo') }).to eq(foo2)
          expect(UuidTesterA.uuid_scope { UuidTesterA.by_uuid('foo') }).to be_nil # nothing in default scope
        end
      end

      it 'disallows similar UUIDs in a single class and scope' do
        expect do
          UuidTesterA.uuid_scope({ UuidTesterB => { 'bar' => { baz: 3 } }, UuidTesterA => {} }) do
            UuidTesterA.new('foo')
            UuidTesterA.new('foo')
          end
        end.to raise_exception('Duplicate Uuid Tester A UUID: foo, ' \
                               'in scope: {"UuidTesterB" => ["bar"], "UuidTesterA" => ["foo"]}.')
      end

      it 'allows similar UUIDs in a single class and different scope' do
        tester1 = UuidTesterA.new('foo')
        UuidTesterA.uuid_scope('solution1') do
          UuidTesterA.new('foo')
        end
        UuidTesterA.uuid_scope('solution2') do
          UuidTesterA.new('foo')
        end
        expect(UuidTesterA.by_uuid('foo')).to eq(tester1)
      end

      it 'disallows similar UUIDs in different threads in a single class and scope' do
        ActiveSupport::IsolatedExecutionState.isolation_level = :thread
        tester1 = UuidTesterA.new('foo')
        thread1 = Thread.new do
          UuidTesterA.uuid_scope('solution1') do
            UuidTesterA.new('foo')
          end
        end
        thread1.join
        thread2 = Thread.new do
          expect do
            UuidTesterA.uuid_scope('solution1') do
              UuidTesterA.new('foo')
            end
          end.to raise_exception('Duplicate Uuid Tester A UUID: foo, in scope: solution1.')
        end
        thread2.join
        expect(UuidTesterA.by_uuid('foo')).to eq(tester1)
      end
    end

    it 'disallows similar UUIDs in different fibers in a single class and scope' do
      ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
      tester1 = UuidTesterA.new('foo')
      fiber1 = Fiber.new do
        UuidTesterA.uuid_scope('solution1') do
          UuidTesterA.new('foo')
        end
        'fiber 1 completed'
      end
      fiber2 = Fiber.new do
        expect do
          UuidTesterA.uuid_scope('solution1') do
            UuidTesterA.new('foo')
          end
        end.to raise_exception('Duplicate Uuid Tester A UUID: foo, in scope: solution1.')
        'fiber 2 completed'
      end
      expect(fiber1.resume).to eq('fiber 1 completed')
      expect(fiber2.resume).to eq('fiber 2 completed')
      expect(UuidTesterA.by_uuid('foo')).to eq(tester1)
    end
  end

  describe 'by_uuid' do
    it 'should return the instances by UUID' do
      foo_a = UuidTesterA.new('foo')
      bar_b = UuidTesterA.new('bar')
      expect(UuidTesterA.by_uuid('foo').uuid).to eq(foo_a.uuid)
      expect(UuidTesterA.by_uuid('bar').uuid).to eq(bar_b.uuid)
    end

    it 'allows similar UUIDs in a single class and different scope' do
      tester1 = UuidTesterA.new('foo')
      tester2 = UuidTesterA.uuid_scope('solution1') do
        UuidTesterA.new('foo')
      end

      expect(UuidTesterA.by_uuid('foo')).to eq(tester1)
      UuidTesterA.uuid_scope('solution1') do
        expect(UuidTesterA.by_uuid('foo')).to eq(tester2)
      end
    end

    it 'shares objects across threads 1' do
      tester1 = UuidTesterA.new('foo')
      tester2 = UuidTesterA.uuid_scope('solution1') do
        UuidTesterA.new('foo')
      end

      Thread.new do
        expect(UuidTesterA.by_uuid('foo')).to eq(tester1)
        UuidTesterA.uuid_scope('solution1') do
          expect(UuidTesterA.by_uuid('foo')).to eq(tester2)
        end
      end.join
    end

    it 'shares objects across threads 2' do
      tester1 = nil
      tester2 = nil
      Thread.new do
        tester1 = UuidTesterA.new('foo')
        tester2 = UuidTesterA.uuid_scope('solution1') do
          UuidTesterA.new('foo')
        end
      end.join
      expect(tester1).not_to be_nil
      expect(tester2).not_to be_nil

      expect(UuidTesterA.by_uuid('foo')).to eq(tester1)
      UuidTesterA.uuid_scope('solution1') do
        expect(UuidTesterA.by_uuid('foo')).to eq(tester2)
      end
    end
  end

  describe 'all' do
    it 'should return all instances' do
      UuidTesterA.new('foo')
      UuidTesterA.new('bar')
      expect(UuidTesterA.all.map(&:uuid).sort).to eq(%w[bar foo])
    end

    it 'allows return all instances in different scopes' do
      UuidTesterA.new('foo')
      UuidTesterA.new('bar')
      UuidTesterA.uuid_scope('solution1') do
        UuidTesterA.new('baz')
        UuidTesterA.new('boo')
      end
      expect(UuidTesterA.all.map(&:uuid).sort).to eq(%w[bar foo])
      UuidTesterA.uuid_scope('solution1') do
        expect(UuidTesterA.all.map(&:uuid).sort).to eq(%w[baz boo])
      end
    end
  end

  describe 'first' do
    it 'returns the first instance' do
      UuidTesterA.new('foo')
      UuidTesterA.new('bar')
      expect(UuidTesterA.first.uuid).to eq('foo')
    end
  end

  describe 'find_each' do
    it 'applies the block to all instances' do
      results = Set.new
      UuidTesterA.new('foo')
      UuidTesterA.new('bar')
      UuidTesterA.find_each { |model| results << model.uuid }
      expect(results).to contain_exactly('foo', 'bar')
    end
  end

  describe 'find' do
    it 'finds the instance with the given uuid' do
      obj1 = UuidTesterA.new('foo')
      obj2 = UuidTesterA.new('bar')
      expect(UuidTesterA.find('foo')).to eq(obj1)
      expect(UuidTesterA.find('bar')).to eq(obj2)
      expect(UuidTesterA.find('baz')).to be_nil
    end
  end

  describe 'purge' do
    it 'should purge' do
      UuidTesterA.new('foo')
      UuidTesterB.new('foo')
      expect(UuidTesterA.by_uuid('foo')).not_to be_nil
      expect(UuidTesterB.by_uuid('foo')).not_to be_nil

      IPaaS::Connector::Common::UuidMixin.purge
      expect(UuidTesterA.by_uuid('foo')).to be_nil
      expect(UuidTesterB.by_uuid('foo')).to be_nil
    end

    it 'should purge except a specific class' do
      UuidTesterA.new('foo')
      UuidTesterB.new('foo')
      expect(UuidTesterA.by_uuid('foo')).not_to be_nil
      expect(UuidTesterB.by_uuid('foo')).not_to be_nil

      IPaaS::Connector::Common::UuidMixin.purge(except: [UuidTesterA])
      expect(UuidTesterA.by_uuid('foo')).not_to be_nil
      expect(UuidTesterB.by_uuid('foo')).to be_nil
    end
  end
end
