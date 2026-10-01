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
            IPaaS::Connector::Action.new.tap do |action|
              # Not the writer: it also copies the output schemas, which this placeholder must leave empty.
              action.instance_variable_set(:@action_template, self)
              action.copy_schema_blocks_from(self, :input_schema)
              fixed_mapping = IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(input_schema.example)
              action.input_mapping = fixed_mapping
              action.runbook = example_runbook(action)
            end
          end

          def example_runbook(action)
            unregistered_runbook.tap do |runbook|
              runbook.store_trigger_output(IPaaS::Connector::Types::HashType.example(nil))
              runbook.actions = [action]
            end
          end

          def unregistered_runbook
            IPaaS::Connector::Runbook.uuid_scope({}) { IPaaS::Connector::Runbook.new(SecureRandom.uuid) }
          end
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Delegation::ActionRef)
