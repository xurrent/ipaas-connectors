module IPaaS
  module Job
    # In-process locker used by the connector test suite, the connector-sdk template,
    # and customer connectors that run outside the platform. Single-process only.
    # Production replaces this with a cross process locker.
    class MemoryLocker
      MUTEX = Monitor.new
      # Keyed by namespaced(key); each entry is { token:, expires_at: }.
      # Mutable by design; do not freeze.
      ENTRIES = {} # rubocop:disable Style/MutableConstant

      def initialize(namespace:)
        @namespace = namespace
      end

      def try_acquire(key, ttl_seconds:)
        full_key = namespaced(key)
        token = SecureRandom.uuid
        MUTEX.synchronize do
          next nil if held?(full_key)
          ENTRIES[full_key] = { token: token, expires_at: Time.current + ttl_seconds }
          token
        end
      end

      def release(key, token)
        full_key = namespaced(key)
        MUTEX.synchronize { ENTRIES.delete(full_key) if owned?(full_key, token) }
        nil
      end

      # rubocop:disable Naming/PredicateMethod -- yields a side-effect block; return signals ownership.
      def compare_and_call(key, token)
        full_key = namespaced(key)
        return false unless MUTEX.synchronize { owned?(full_key, token) }

        yield
        true
      end
      # rubocop:enable Naming/PredicateMethod

      private

      def held?(full_key)
        existing = ENTRIES[full_key]
        existing && existing[:expires_at] > Time.current
      end

      def owned?(full_key, token)
        existing = ENTRIES[full_key]
        existing && existing[:token] == token && existing[:expires_at] > Time.current
      end

      def namespaced(key)
        "#{@namespace}:#{key}"
      end
    end
  end
end
