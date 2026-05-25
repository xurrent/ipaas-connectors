module IPaaS
  module Job
    module Outbound
      module Scheduler
        extend ActiveSupport::Concern
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :update_schedule, :create_schedule!, :soft_delete_schedule

        included do
          def update_schedule(reference, attributes)
            solution.update_schedule(reference, attributes.to_hash)
          end

          def create_schedule!(runbook_uuid, attributes)
            solution.create_schedule!(runbook_uuid, attributes.to_hash)
          end

          def soft_delete_schedule(reference)
            solution.soft_delete_schedule(reference)
          end
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Outbound::Scheduler)
