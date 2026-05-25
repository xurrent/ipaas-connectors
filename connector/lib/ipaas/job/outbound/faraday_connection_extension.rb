module IPaaS
  module Job
    module Outbound
      module FaradayConnectionExtension
        METHODS = Faraday::Connection::METHODS

        extend ActiveSupport::Concern

        included do
          def http_send(method, path = nil, &block)
            IPaaS::Job::Outbound::HTTP.validate_method!(method)

            send(method.to_sym, path, &block)
          end
        end
      end
    end
  end
end

Faraday::Connection.include(IPaaS::Job::Outbound::FaradayConnectionExtension)
