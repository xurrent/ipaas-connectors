module IPaaS
  module Job
    class LockerUnavailable < IPaaS::Error; end

    # Cross-process single-flight primitive used by Outbound::OAuth2 to ensure only
    # one worker performs an OAuth refresh at a time (see docs/oauth2-singleflight-plan.md).
    # The connector/ package defines the interface and an in-process default
    # (MemoryLocker); platform/ injects RedisLocker per Solution.
    module Lock
      extend ActiveSupport::Concern
      extend IPaaS::Connector::Common::ProcRules::ProcSafe
      include Store

      proc_safe :with_lock, :release_lock, :write_if_lock_held

      # TTL must remain below the maximum allowed time for a single action (90 s)
      # so a holder killed by an action timeout cannot orphan a lock past its own
      # action. Faraday refresh timeout (20 s) gives a 3x safety margin.
      DEFAULT_TTL_SECONDS = 60

      # When contention or locker outage forces a reschedule, these are the base
      # delays passed to backoff. Contention is short (the holder's refresh
      # typically completes well under 1 s); locker outages need a longer
      # interval to give Redis time to recover before the platform job-retry
      # caps kick in. Random jitter desynchronises waves of contenders that
      # would otherwise reschedule at the same wait_until boundary.
      RETRY_AFTER_CONTENTION        = 2.seconds
      RETRY_AFTER_CONTENTION_JITTER = 1.0
      RETRY_AFTER_OUTAGE            = 30.seconds
      RETRY_AFTER_OUTAGE_JITTER     = 5.0

      included do
        def self.locker_for(_, namespace: nil)
          IPaaS::Job::MemoryLocker.new(namespace: namespace)
        end

        def locker
          @locker ||= self.class.locker_for(self, namespace: lock_namespace)
        end
      end

      def with_lock(key, ttl: DEFAULT_TTL_SECONDS)
        token = acquire_or_reschedule(key, ttl)
        begin
          yield token
        ensure
          release_lock(key, token)
        end
      end

      def release_lock(key, token)
        locker.release(key, token)
      end

      # Compare-and-write: writes only if our token still owns the lock at the
      # start of the write. Not atomic across the two systems — there is a very
      # short window between the lock check and the cache write where ownership
      # can be lost (TTL elapses + peer acquires); callers can observe the
      # rate, the write itself is unaffected.
      def write_if_lock_held(lock_key, token, store_key, value, cache_time)
        locker.compare_and_call(lock_key, token) do
          cache_write(store_key, value, cache_time)
        end
      end

      private

      def acquire_or_reschedule(key, ttl)
        token = locker.try_acquire(key, ttl_seconds: ttl)
        return token unless token.nil?

        reschedule_for_contention(key)
      rescue IPaaS::Job::LockerUnavailable
        reschedule_for_outage(key)
      end

      def reschedule_for_contention(key)
        log("lock.contended lock_key_sha=#{lock_key_sha(key)}")
        backoff('Lock held by another worker; rescheduling.',
                retry_after: RETRY_AFTER_CONTENTION + (rand * RETRY_AFTER_CONTENTION_JITTER).seconds)
      end

      def reschedule_for_outage(key)
        log("lock.unavailable lock_key_sha=#{lock_key_sha(key)}")
        backoff('Lock backend unavailable; rescheduling.',
                retry_after: RETRY_AFTER_OUTAGE + (rand * RETRY_AFTER_OUTAGE_JITTER).seconds)
      end

      def lock_namespace
        respond_to?(:store_namespace, true) ? store_namespace : self.class.name
      end

      # First 8 hex chars of a SHA-256 over the lock key. Used as a correlation
      # id in log lines so the actual lock key is not exposed.
      def lock_key_sha(key)
        Digest::SHA256.hexdigest(key.to_s)[0, 8]
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Lock)
