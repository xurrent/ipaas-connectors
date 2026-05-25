module IPaaS
  module Job
    module BasicAuth
      extend ActiveSupport::Concern
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :basic_auth_credentials

      BASIC_AUTH_PREFIX = /\ABasic\s+/

      def basic_auth_credentials(headers, **)
        fail_job!('Missing basic authentication header.') unless IPaaS::Job::BasicAuth.basic_auth_present?(headers)

        IPaaS::Job::BasicAuth.basic_auth_credentials(headers, **)
      end

      class << self
        def basic_auth_present?(headers)
          authorization_header(headers).present?
        end

        def basic_auth_credentials(headers, strict: true)
          header_value = authorization_header(headers)
          return [nil, nil] unless header_value

          decode_credentials(header_value, strict).presence || [nil, nil]
        end

        private

        def authorization_header(headers)
          header = headers['Authorization']
          return nil unless header&.match?(BASIC_AUTH_PREFIX)

          header
        end

        def decode_credentials(header_value, strict)
          encoded = header_value.gsub(BASIC_AUTH_PREFIX, '')
          decoded = strict ? Base64.strict_decode64(encoded) : Base64.decode64(encoded)
          decoded.split(':', 2)
        rescue StandardError
          [nil, nil]
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::BasicAuth)
