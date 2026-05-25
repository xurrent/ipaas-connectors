module IPaaS
  module Job
    # For testing purposes - do not use in production!
    class MemoryStore
      attr_accessor :store

      def initialize(options = {})
        self.store = ActiveSupport::Cache::MemoryStore.new(options)
      end

      def read(key)
        value = store.read(key)
        value = value.present? ? JSON.parse(value) : nil
        value = value.with_indifferent_access if value.is_a?(Hash)
        value
      end

      def write(key, value)
        value = value.nil? ? nil : JSON.generate(value)
        store.write(key, value)
        nil
      end

      def delete(key)
        store.delete(key)
      end
    end
  end
end
