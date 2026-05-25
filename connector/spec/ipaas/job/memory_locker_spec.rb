require 'spec_helper'

describe IPaaS::Job::MemoryLocker do
  before { described_class.const_get(:ENTRIES).clear }

  subject(:locker) { described_class.new(namespace: 'spec') }

  describe '#try_acquire' do
    it 'returns a token on first acquisition and nil on a contended second call' do
      first = locker.try_acquire('k', ttl_seconds: 5)
      expect(first).to be_a(String)
      expect(locker.try_acquire('k', ttl_seconds: 5)).to be_nil
    end

    it 'returns a new token after TTL expiry' do
      Timecop.freeze do
        locker.try_acquire('k', ttl_seconds: 1)
        Timecop.travel(2.seconds.from_now) do
          expect(locker.try_acquire('k', ttl_seconds: 5)).to be_present
        end
      end
    end

    it 'isolates by namespace' do
      a = described_class.new(namespace: 'a')
      b = described_class.new(namespace: 'b')
      expect(a.try_acquire('k', ttl_seconds: 5)).to be_present
      expect(b.try_acquire('k', ttl_seconds: 5)).to be_present
    end
  end

  describe '#release' do
    it 'allows re-acquisition after release with matching token' do
      token = locker.try_acquire('k', ttl_seconds: 5)
      locker.release('k', token)
      expect(locker.try_acquire('k', ttl_seconds: 5)).to be_present
    end

    it 'is a no-op when token does not match the holder' do
      token = locker.try_acquire('k', ttl_seconds: 5)
      locker.release('k', 'wrong-token')
      expect(locker.try_acquire('k', ttl_seconds: 5)).to be_nil
      locker.release('k', token)
      expect(locker.try_acquire('k', ttl_seconds: 5)).to be_present
    end

    it 'is a no-op for a stale token from a previous holder whose TTL elapsed' do
      Timecop.freeze do
        stale = locker.try_acquire('k', ttl_seconds: 1)
        Timecop.travel(2.seconds.from_now) do
          new_token = locker.try_acquire('k', ttl_seconds: 5)
          locker.release('k', stale)
          expect(locker.try_acquire('k', ttl_seconds: 5)).to be_nil
          locker.release('k', new_token)
        end
      end
    end
  end

  describe '#compare_and_call' do
    it 'yields when the token still matches' do
      token = locker.try_acquire('k', ttl_seconds: 5)
      ran = 0
      result = locker.compare_and_call('k', token) { ran += 1 }
      expect(ran).to eq(1)
      expect(result).to be_truthy
    end

    it 'does not yield when the token does not match (TTL elapsed mid-write)' do
      Timecop.freeze do
        stale = locker.try_acquire('k', ttl_seconds: 1)
        Timecop.travel(2.seconds.from_now) { locker.try_acquire('k', ttl_seconds: 5) }
        ran = 0
        result = locker.compare_and_call('k', stale) { ran += 1 }
        expect(ran).to eq(0)
        expect(result).to be_falsey
      end
    end
  end
end
