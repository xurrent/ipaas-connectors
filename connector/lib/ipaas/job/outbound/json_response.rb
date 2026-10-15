module IPaaS
  module Job
    module Outbound
      module JsonResponse
        extend ActiveSupport::Concern
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :parse_json_response, :parse_json_object_or_empty

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

        # Parses a body that is read for its error details only, so a body that is not a JSON object
        # answers an empty hash instead of failing the job.
        #
        # @param body [String, nil] raw response body
        # @return [Hash] the parsed object, or an empty hash
        def parse_json_object_or_empty(body)
          parsed = JSON.parse(body.to_s)
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          {}
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Outbound::JsonResponse)
