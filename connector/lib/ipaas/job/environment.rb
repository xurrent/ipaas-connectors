module IPaaS
  module Job
    module Environment
      extend ActiveSupport::Concern
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :environment

      included do
        def environment
          solution&.environment || {}
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Environment)
