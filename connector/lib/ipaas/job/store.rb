module IPaaS
  module Job
    module Store
      extend ActiveSupport::Concern
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :store, :read, :write

      included do
        def self.store_for(_, namespace: nil)
          MemoryStore.new(namespace: namespace)
        end

        def store
          @store ||= store_for
        end

        private

        def store_for
          self.class.store_for(self, namespace: store_namespace)
        end

        def store_namespace
          unique_id = try(:uuid) || try(:id) || object_id
          "#{self.class.name}:#{unique_id}"
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Store)
