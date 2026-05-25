module IPaaS
  module Job
    module Delegation
      module InboundConnectionRef
        extend ActiveSupport::Concern

        included do
          unless method_defined?(:inbound_connection)
            def inbound_connection
              return self if self.is_a?(IPaaS::Connector::Connection) && self.inbound?
              return connector.inbound_connection if self.is_a?(IPaaS::Connector::TriggerTemplate)

              nil
            end
          end
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Delegation::InboundConnectionRef)
