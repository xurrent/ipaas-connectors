module IPaaS
  module Job
    module Cache
      extend ActiveSupport::Concern
      extend IPaaS::Connector::Common::ProcRules::ProcSafe
      include Store

      proc_safe :cache_write, :cache_read, :cache_clear

      KEY_PREFIX = 'cache_of_'.freeze

      def cache_write(key, value, cache_time)
        if cache_time > 0
          valid_to = (current_time + cache_time.seconds).to_i
          store.write(cache_key(key), { valid_to: valid_to, value: value }.to_json)
        end
        value
      end

      def cache_clear(key)
        store.write(cache_key(key), nil)
      end

      def cache_read(key)
        cache_value = store.read(cache_key(key))
        cache_value = cache_value.present? ? JSON.parse(cache_value) : nil
        if cache_value && cache_value['valid_to'] > current_time.to_i
          cache_value['value']
        else
          nil
        end
      end

      # For internal use. Cache entries are not stored in a SQL database, but in e.g. Memcached or Redis
      def internal_cache
        @internal_cache ||= ActiveSupport::Cache::MemoryStore.new
      end

      private

      def cache_key(key)
        "#{KEY_PREFIX}#{key}"
      end

      def current_time
        Time.now.utc
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Cache)
