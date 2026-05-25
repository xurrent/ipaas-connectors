module IPaaS
  module Job
    module Outbound
      class CustomerCredentialsError < IPaaS::Job::FailJob
        attr_reader :host, :reason

        def initialize(host:, reason:)
          @host = host
          @reason = reason
          super("Authentication to #{host} failed: #{reason}")
        end
      end
    end
  end
end
