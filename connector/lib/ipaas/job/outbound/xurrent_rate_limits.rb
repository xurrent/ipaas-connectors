module IPaaS
  module Job
    module Outbound
      # Reads Xurrent-specific rate-limit and cost-limit telemetry from HTTP response headers.
      # The `x-costlimit-*` header family is unique to Xurrent's GraphQL API.
      module XurrentRateLimits
        extend ActiveSupport::Concern
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :xurrent_rate_limit_from_headers, :xurrent_cost_limit_from_headers

        # Reads the `x-ratelimit-*` headers Xurrent emits on every response.
        #
        # @param response [Object] HTTP response with #headers
        # @return [Hash{Symbol => String, nil}] keys :limit, :remaining, :reset
        def xurrent_rate_limit_from_headers(response)
          {
            limit: response.headers['x-ratelimit-limit'],
            remaining: response.headers['x-ratelimit-remaining'],
            reset: response.headers['x-ratelimit-reset'],
          }
        end

        # Reads the `x-costlimit-*` headers Xurrent emits on every GraphQL response.
        #
        # @param response [Object] HTTP response with #headers
        # @return [Hash{Symbol => String, nil}] keys :limit, :cost, :remaining, :reset
        def xurrent_cost_limit_from_headers(response)
          {
            limit: response.headers['x-costlimit-limit'],
            cost: response.headers['x-costlimit-cost'],
            remaining: response.headers['x-costlimit-remaining'],
            reset: response.headers['x-costlimit-reset'],
          }
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Outbound::XurrentRateLimits)
