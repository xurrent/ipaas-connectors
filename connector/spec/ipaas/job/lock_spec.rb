require 'spec_helper'

describe IPaaS::Job::Lock do
  before { IPaaS::Job::MemoryLocker.const_get(:ENTRIES).clear }

  let(:context_class) do
    Class.new do
      include IPaaS::Job::Context

      def uuid
        'ctx-1'
      end
    end
  end
  let(:context) { context_class.new }

  def suppress_reschedule
    yield
  rescue IPaaS::Job::RescheduleJob
    nil
  end

  describe '#with_lock' do
    it 'yields once with a token and returns the block value' do
      token_seen = nil
      result = context.with_lock('k') do |t|
        token_seen = t
        :v
      end
      expect(token_seen).to be_a(String)
      expect(result).to eq(:v)
    end

    it 'releases the lock after a successful run' do
      release_spy = 0
      allow(context.locker).to receive(:release).and_wrap_original do |orig, *args|
        release_spy += 1
        orig.call(*args)
      end
      context.with_lock('k') { |_| :ok }
      expect(release_spy).to eq(1)
    end

    it 'releases the lock when the block raises' do
      release_spy = 0
      allow(context.locker).to receive(:release).and_wrap_original do |orig, *args|
        release_spy += 1
        orig.call(*args)
      end
      expect { context.with_lock('k') { |_| raise 'boom' } }.to raise_error('boom')
      expect(release_spy).to eq(1)
    end

    it 'raises RescheduleJob with RETRY_AFTER_CONTENTION (plus jitter) when the lock is held by a peer' do
      allow(context.locker).to receive(:try_acquire).and_return(nil)
      expect(context).not_to receive(:sleep)
      expect { context.with_lock('k') { |_| raise 'inner block must not run' } }
        .to raise_error(IPaaS::Job::RescheduleJob) do |e|
          base   = IPaaS::Job::Lock::RETRY_AFTER_CONTENTION.to_f
          jitter = IPaaS::Job::Lock::RETRY_AFTER_CONTENTION_JITTER.to_f
          expect(e.reschedule_after - Time.current).to be_between(base - 0.5, base + jitter + 0.5)
          expect(e.message).to match(/Lock held by another worker/)
        end
    end

    it 'raises RescheduleJob with RETRY_AFTER_OUTAGE (plus jitter) when the locker is unavailable' do
      allow(context.locker).to receive(:try_acquire).and_raise(IPaaS::Job::LockerUnavailable, 'redis down')
      expect { context.with_lock('k') { |_| raise 'inner block must not run' } }
        .to raise_error(IPaaS::Job::RescheduleJob) do |e|
          base   = IPaaS::Job::Lock::RETRY_AFTER_OUTAGE.to_f
          jitter = IPaaS::Job::Lock::RETRY_AFTER_OUTAGE_JITTER.to_f
          expect(e.reschedule_after - Time.current).to be_between(base - 0.5, base + jitter + 0.5)
          expect(e.message).to match(/Lock backend unavailable/)
        end
    end

    it 'does not call release when the lock was never acquired' do
      allow(context.locker).to receive(:try_acquire).and_return(nil)
      expect(context.locker).not_to receive(:release)
      suppress_reschedule { context.with_lock('k') { :ok } }
    end
  end

  describe 'pluggable locker_for' do
    it 'uses MemoryLocker by default' do
      expect(context.locker).to be_a(IPaaS::Job::MemoryLocker)
    end

    it 'uses the platform-supplied locker when overridden' do
      injected = instance_double(IPaaS::Job::MemoryLocker, try_acquire: 'tok', release: nil)
      allow(context_class).to receive(:locker_for).and_return(injected)
      fresh = context_class.new
      fresh.with_lock('k') { |_| :ok }
      expect(injected).to have_received(:try_acquire).with('k', ttl_seconds: IPaaS::Job::Lock::DEFAULT_TTL_SECONDS)
      expect(injected).to have_received(:release).with('k', 'tok')
    end
  end

  describe 'observability for reschedule paths' do
    it 'logs lock.contended when a peer holds the lock' do
      allow(context.locker).to receive(:try_acquire).and_return(nil)
      expect(context).to receive(:log).with(/\Alock\.contended/).and_call_original
      suppress_reschedule { context.with_lock('k') { :ok } }
    end

    it 'logs lock.unavailable when the locker raises LockerUnavailable' do
      allow(context.locker).to receive(:try_acquire).and_raise(IPaaS::Job::LockerUnavailable, 'down')
      expect(context).to receive(:log).with(/\Alock\.unavailable/).and_call_original
      suppress_reschedule { context.with_lock('k') { :ok } }
    end

    it 'never logs raw lock keys in either reschedule line' do
      allow(context.locker).to receive(:try_acquire).and_return(nil)
      received = nil
      allow(context).to receive(:log) { |line| received = line }
      suppress_reschedule { context.with_lock('SHOULD-NOT-LEAK-KEY') { :ok } }
      expect(received).not_to include('SHOULD-NOT-LEAK-KEY')
      expect(received).to match(/lock_key_sha=[0-9a-f]{8}/)
    end
  end

  describe 'reschedule jitter' do
    it 'adds rand x RETRY_AFTER_CONTENTION_JITTER on top of the base contention delay' do
      allow(context.locker).to receive(:try_acquire).and_return(nil)
      expect(context).to receive(:rand).with(no_args).and_return(0.5)
      expected = IPaaS::Job::Lock::RETRY_AFTER_CONTENTION.to_f +
                 (0.5 * IPaaS::Job::Lock::RETRY_AFTER_CONTENTION_JITTER)
      expect { context.with_lock('k') { |_| :ok } }
        .to raise_error(IPaaS::Job::RescheduleJob) do |e|
          expect(e.reschedule_after - Time.current).to be_within(0.1).of(expected)
        end
    end

    it 'adds rand x RETRY_AFTER_OUTAGE_JITTER on top of the base outage delay' do
      allow(context.locker).to receive(:try_acquire).and_raise(IPaaS::Job::LockerUnavailable, 'down')
      expect(context).to receive(:rand).with(no_args).and_return(0.6)
      expected = IPaaS::Job::Lock::RETRY_AFTER_OUTAGE.to_f +
                 (0.6 * IPaaS::Job::Lock::RETRY_AFTER_OUTAGE_JITTER)
      expect { context.with_lock('k') { |_| :ok } }
        .to raise_error(IPaaS::Job::RescheduleJob) do |e|
          expect(e.reschedule_after - Time.current).to be_within(0.5).of(expected)
        end
    end

    it 'produces a non-zero jitter draw across multiple reschedules (anti-herd guard)' do
      allow(context.locker).to receive(:try_acquire).and_return(nil)
      delays = Array.new(20) do
        Timecop.freeze do
          context.with_lock('k') { |_| :ok }
        rescue IPaaS::Job::RescheduleJob => e
          e.reschedule_after - Time.current
        end
      end
      base = IPaaS::Job::Lock::RETRY_AFTER_CONTENTION.to_f
      expect(delays.uniq.size).to be > 1, "all 20 reschedule delays equal #{base}s — jitter is broken"
    end
  end
end
