module IPaaS
  module Job
    module Delegation
      module OutboundConnectionRef
        extend ActiveSupport::Concern

        included do
          unless method_defined?(:outbound_connection)
            def outbound_connection
              return self if self.is_a?(IPaaS::Connector::Connection) && self.outbound?
              return connector.outbound_connection if self.is_a?(IPaaS::Connector::TriggerTemplate)
              return connector.outbound_connection if self.is_a?(IPaaS::Connector::ActionTemplate)

              nil
            end
          end
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Delegation::OutboundConnectionRef)
