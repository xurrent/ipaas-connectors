module IPaaS
  module Job
    module Outbound
      module JsonResponse
        extend ActiveSupport::Concern
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :parse_json_response

        # Parses a JSON response body string, raising a FailJob error on parse failure.
        #
        # @param body [String] raw JSON response body
        # @param error_message [String, nil] custom error message for parse failures
        # @return [Hash, Array] parsed JSON
        def parse_json_response(body, error_message: nil)
          JSON.parse(body)
        rescue JSON::ParserError
          fail_job!(error_message || "Response was not valid JSON: '#{body}'")
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Outbound::JsonResponse)
