module IPaaS
  module Job
    module Delegation
      module TriggerRef
        extend ActiveSupport::Concern

        included do
          def trigger
            return self if self.is_a?(IPaaS::Connector::Trigger)
            return self.trigger if self.is_a?(IPaaS::Connector::Runbook)
            return example_trigger if self.is_a?(IPaaS::Connector::TriggerTemplate)

            nil
          end

          private

          def example_trigger
            @example_trigger ||= IPaaS::Connector::Trigger.new.tap do |trigger|
              trigger.copy_schema_blocks_from(self, :config_schema)
              fixed_mapping = IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(config_schema.example)
              trigger.config_mapping = fixed_mapping
            end
          end
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Delegation::TriggerRef)
