module IPaaS
  module Job
    module Delegation
      module HelpersRef
        extend ActiveSupport::Concern

        included do
          def helpers
            return action_template.helpers if self.is_a?(IPaaS::Connector::Action)
            return trigger_template.helpers if self.is_a?(IPaaS::Connector::Trigger)
            return connection_definition.helpers if self.is_a?(IPaaS::Connector::Connection) && connection_definition

            try(:connector)&.helpers
          end
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Delegation::HelpersRef)
