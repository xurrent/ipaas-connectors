module IPaaS
  module Job
    module Delegation
      module ActionRef
        extend ActiveSupport::Concern

        included do
          def action
            return self if self.is_a?(IPaaS::Connector::Action)
            return example_action if self.is_a?(IPaaS::Connector::ActionTemplate)

            nil
          end

          private

          def example_action
            @example_action ||= IPaaS::Connector::Action.new.tap do |action|
              action.copy_schema_blocks_from(self, :input_schema)
              fixed_mapping = IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(input_schema.example)
              action.input_mapping = fixed_mapping
              action.runbook = example_runbook(action)
            end
          end
        end

        def example_runbook(action)
          IPaaS::Connector::Runbook.new(SecureRandom.uuid).tap do |runbook|
            runbook.store_trigger_output(IPaaS::Connector::Types::HashType.example(nil))
            runbook.actions = [action]
          end
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Delegation::ActionRef)
