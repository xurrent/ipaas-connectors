module IPaaS
  module Job
    module Outbound
      module Backoff
        extend ActiveSupport::Concern
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :backoff_if_needed

        # Checks the HTTP response status and triggers a backoff if rate-limited (429)
        # or a server error is detected. Parses the Retry-After header to determine
        # how long to wait before retrying.
        #
        # @param response [Object] HTTP response with #status, #headers, #body
        # @param api_name [String] name of the API for error messages (e.g. 'Lansweeper')
        # @param header_name [String] retry-after header name (default: 'Retry-After')
        # @param default_retry_after [Integer] fallback seconds when header is missing/invalid
        # @param server_error_statuses [Array<Integer>] status codes treated as server errors
        def backoff_if_needed(response, api_name:, header_name: 'Retry-After',
                              default_retry_after: 60, server_error_statuses: [503])
          return unless response.status == 429 || server_error_statuses.include?(response.status)

          retry_after, retry_after_msg = parse_retry_after(response.headers[header_name], default_retry_after)

          if response.status == 429
            backoff("#{api_name} API rate limit hit#{retry_after_msg}. '#{response.body}'", retry_after: retry_after)
          else
            backoff("#{api_name} API not available#{retry_after_msg}. '#{response.body}'", retry_after: retry_after)
          end
        end

        private

        def parse_retry_after(header_value, default)
          return [default, ''] if header_value.blank?

          msg = " (retry after: #{header_value})"
          seconds = parse_retry_after_value(header_value, default)
          [seconds, msg]
        rescue StandardError
          [default, msg]
        end

        def parse_retry_after_value(header_value, default)
          return header_value.to_i if /^\d+$/.match(header_value) && header_value.to_i > 0

          parsed = Time.parse(header_value)
          parsed > Time.current ? (parsed - Time.current) : default
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Outbound::Backoff)
