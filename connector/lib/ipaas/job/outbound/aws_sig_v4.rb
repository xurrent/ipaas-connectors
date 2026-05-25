module IPaaS
  module Job
    module Outbound
      module AwsSigV4
        extend ActiveSupport::Concern
        extend IPaaS::Connector::Common::ProcRules::ProcSafe
        include HTTP
        include XML

        proc_safe :aws_credentials_for_role, :aws_account_id, :build_aws_signed_headers, :call_aws

        AWS_CREDENTIALS_CACHE_KEY = 'aws_credentials'.freeze
        AWS_ALGORITHM = 'AWS4-HMAC-SHA256'.freeze
        AWS_REQUEST_TYPE = 'aws4_request'.freeze
        AWS_SESSION_DURATION_SECONDS = 3600
        AWS_CACHE_BUFFER_SECONDS = 300
        AWS_MIN_CACHE_SECONDS = 60

        def aws_account_id
          ENV.fetch('AWS_ACCOUNT_ID', 'Not available')
        end

        def aws_credentials_for_role(role_arn, external_id, region, session_name = nil)
          session_name ||= 'XurrentIPaaSSession'
          key_state = { role_arn: role_arn, external_id: external_id, region: region }
          hash = Digest::SHA256.hexdigest(key_state.to_json)
          cache_key = "#{AWS_CREDENTIALS_CACHE_KEY}_#{hash}"
          cached_creds = cache_read(cache_key)
          return cached_creds.symbolize_keys if cached_creds.present?
          credentials = retrieve_role_credentials(role_arn, external_id, region, session_name)
          cache_time = get_cache_time(credentials[:expiration])
          cache_write(cache_key, credentials, cache_time) if cache_time > 0
          credentials
        end

        def build_aws_signed_headers(method:, url:, payload:, credentials:, region:, service:, content_type: nil,
                                     timestamp: Time.now.utc)
          context = build_signing_context(method: method, url: url, payload: payload, credentials: credentials,
                                          region: region, service: service, content_type: content_type,
                                          timestamp: timestamp)
          authorization = "#{AWS_ALGORITHM} " \
                          "Credential=#{credentials[:access_key_id]}/#{context[:credential_scope]}, " \
                          "SignedHeaders=#{context[:signed_headers]}, " \
                          "Signature=#{context[:signature]}"
          result_headers = { 'Authorization' => authorization, 'x-amz-date' => context[:amz_date] }
          result_headers['x-amz-security-token'] = credentials[:session_token] if credentials[:session_token].present?
          result_headers
        end

        def call_aws(service_name = 'AWS')
          response = yield
          handle_aws_backoff_if_needed(response, service_name)
          handle_non_200_response(response, service_name)
          response
        end

        def handle_aws_backoff_if_needed(response, service_name = 'AWS')
          status = response.status
          return unless [429, 503].include?(status)
          error_code = parse_aws_error_code(response.body)
          retry_after = parse_retry_after_header(response.headers) || default_retry_for(error_code) || 30.seconds

          error_msg = if status == 429
                        "AWS #{service_name} rate limit exceeded (#{error_code}). Throttling detected."
                      else
                        "AWS #{service_name} service unavailable (#{error_code}). Service temporarily down."
                      end

          backoff(error_msg, retry_after: retry_after)
        end

        def parse_aws_error_code(body)
          doc = parse_xml_response(body)
          doc.at_xpath('//Error/Code')&.text.presence || 'Unknown'
        rescue StandardError
          'Unknown'
        end

        private

        def get_cache_time(expiration)
          expiration = Time.iso8601(expiration).to_i
          cache_seconds = expiration - Time.now.to_i - AWS_CACHE_BUFFER_SECONDS
          cache_seconds > AWS_MIN_CACHE_SECONDS ? cache_seconds : 0
        rescue StandardError => e
          log("Failed to parse expiration time '#{expiration}': #{e.message}")
          0
        end

        def parse_retry_after_header(headers)
          header = headers['Retry-After'] || headers['retry-after']
          return nil if header.blank?
          return header.to_i.seconds if /^\d+$/.match?(header)
          parsed_time = Time.parse(header)
          delay = parsed_time - Time.current
          delay > 0 ? delay : nil
        rescue StandardError
          nil
        end

        def default_retry_for(error_code)
          case error_code
          when 'Throttling', 'ThrottlingException', 'RequestThrottled'
            30.seconds
          when 'ServiceUnavailable', 'InternalError'
            60.seconds
          end
        end

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def build_signing_context(method:, url:, payload:, credentials:, region:, service:, content_type:, timestamp:)
          uri = URI.parse(url)
          amz_date = timestamp.strftime('%Y%m%dT%H%M%SZ')
          date_stamp = timestamp.strftime('%Y%m%d')

          canonical_query = build_canonical_query(uri)
          headers = build_signing_headers(uri, amz_date, content_type, credentials)
          payload_hash = Digest::SHA256.hexdigest(payload || '')
          canonical_headers = headers.sort.map { |k, v| "#{k.downcase}:#{v.strip}\n" }.join
          signed_headers = headers.keys.sort.map(&:downcase).join(';')

          credential_scope = "#{date_stamp}/#{region}/#{service}/#{AWS_REQUEST_TYPE}"
          canonical_path = if uri.path.empty?
                             '/'
                           else
                             uri.path.split('/', -1).map { |segment| uri_escape(segment) }.join('/')
                           end

          canonical_request = [
            method.upcase,
            canonical_path,
            canonical_query,
            canonical_headers,
            signed_headers,
            payload_hash,
          ].join("\n")

          canonical_hash = Digest::SHA256.hexdigest(canonical_request)
          string_to_sign = [AWS_ALGORITHM, amz_date, credential_scope, canonical_hash].join("\n")
          signature = calculate_signature(credentials[:secret_access_key], date_stamp, region, service,
                                          string_to_sign)

          { credential_scope: credential_scope, signed_headers: signed_headers, signature: signature,
            amz_date: amz_date, }
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        def build_canonical_query(uri)
          return '' unless uri.query

          query_params = CGI.parse(uri.query)
          param_list = query_params.flat_map { |key, values| values.map { |value| [key, value] } }
          param_list.sort.map { |key, value| "#{uri_escape(key)}=#{uri_escape(value)}" }.join('&')
        end

        def build_signing_headers(uri, amz_date, content_type, credentials)
          host_value = uri.host
          host_value = "#{uri.host}:#{uri.port}" if uri.port && !standard_port?(uri)
          headers = {
            'host' => host_value,
            'x-amz-date' => amz_date,
          }
          headers['content-type'] = content_type if content_type.present?
          headers['x-amz-security-token'] = credentials[:session_token] if credentials[:session_token].present?
          headers
        end

        def retrieve_role_credentials(role_arn, external_id, region, session_name)
          platform_creds = validate_aws_credential_present!

          response = call_aws('STS') do
            send_sts_assume_role(role_arn, external_id, region, session_name, platform_creds)
          end
          parse_assume_role_response(response)
        rescue IPaaS::Error
          raise
        rescue StandardError => e
          raise IPaaS::Error, "Unable to assume AWS role: #{e.message}"
        end

        def send_sts_assume_role(role_arn, external_id, region, session_name, platform_creds)
          full_url = sts_url(external_id, region, role_arn, session_name)
          signed_headers = build_aws_signed_headers(
            method: 'GET',
            url: full_url,
            payload: '',
            credentials: platform_creds,
            region: region,
            service: 'sts'
          )
          http_get(full_url, nil, signed_headers, skip_authentication: true)
        end

        def validate_aws_credential_present!
          platform_creds = platform_aws_credentials
          unless platform_creds[:access_key_id].present? && platform_creds[:secret_access_key].present?
            raise IPaaS::Error,
                  'Platform AWS credentials not configured. Please set AWS_ACCESS_KEY_ID and ' \
                  'AWS_SECRET_ACCESS_KEY environment variables, or ensure the ECS task has an IAM task role attached.'
          end
          platform_creds
        end

        def sts_url(external_id, region, role_arn, session_name)
          sts_endpoint = "https://sts.#{region}.amazonaws.com/"
          params = {
            'Action' => 'AssumeRole',
            'RoleArn' => role_arn,
            'RoleSessionName' => session_name,
            'ExternalId' => external_id,
            'Version' => '2011-06-15',
            'DurationSeconds' => AWS_SESSION_DURATION_SECONDS.to_s,
          }
          "#{sts_endpoint}?#{URI.encode_www_form(params)}"
        end

        def extract_aws_error_details(xml_body)
          doc = parse_xml_response(xml_body)
          error = doc.at_xpath('//Error')
          code = error&.at_xpath('Code')&.text
          message = error&.at_xpath('Message')&.text
          combined = [code, message].compact.join(': ')
          return combined unless combined.empty?
          xml_body.truncate(500)
        rescue StandardError
          xml_body.truncate(500)
        end

        def parse_assume_role_response(response)
          doc = parse_xml_response(response.body)
          credentials_element = doc.at_xpath('//Credentials')
          return extract_credentials_from_xml(credentials_element) if credentials_element
          raise_missing_credentials_error(response, doc)
        rescue IPaaS::Error
          raise
        rescue StandardError => e
          raise IPaaS::Error, "Failed to parse AWS STS response: #{e.message}"
        end

        def handle_non_200_response(response, service_name)
          return if response.status == 200

          error_details = extract_aws_error_details(response.body)
          raise IPaaS::Error, "AWS #{service_name} call failed (HTTP #{response.status}): #{error_details}"
        end

        def raise_missing_credentials_error(response, doc)
          error_element = doc.at_xpath('//Error')
          error_msg = if error_element
                        extract_aws_error_details(response.body)
                      else
                        'Unknown error - no credentials or error information in response'
                      end
          raise IPaaS::Error, "AWS STS did not return credentials: #{error_msg}"
        end

        def extract_credentials_from_xml(credentials_element)
          get_text = ->(name) { credentials_element.at_xpath(name)&.text }

          credentials_hash = {
            access_key_id: get_text.call('AccessKeyId'), secret_access_key: get_text.call('SecretAccessKey'),
            session_token: get_text.call('SessionToken'), expiration: get_text.call('Expiration'),
          }

          validate_credentials(credentials_hash)
          credentials_hash
        rescue StandardError => e
          raise IPaaS::Error, "Failed to extract credentials from STS response: #{e.message}"
        end

        def validate_credentials(credentials)
          missing = credentials.select { |_, v| v.to_s.strip.empty? }.keys
          return if missing.empty?

          formatted = missing.map { |f| f.to_s.split('_').map(&:capitalize).join }
          raise IPaaS::Error, "Incomplete credentials in AWS STS response. Missing fields: #{formatted.join(', ')}"
        end

        def calculate_signature(secret_key, date_stamp, region, service, string_to_sign)
          k_date = hmac("AWS4#{secret_key}", date_stamp)
          k_region = hmac(k_date, region)
          k_service = hmac(k_region, service)
          k_signing = hmac(k_service, AWS_REQUEST_TYPE)

          OpenSSL::HMAC.hexdigest('SHA256', k_signing, string_to_sign)
        end

        def hmac(key, data)
          OpenSSL::HMAC.digest('SHA256', key, data)
        end

        def uri_escape(string)
          URI.encode_www_form_component(string.to_s).gsub('+', '%20')
        end

        def standard_port?(uri)
          (uri.scheme == 'https' && uri.port == 443) || (uri.scheme == 'http' && uri.port == 80)
        end

        def platform_aws_credentials
          env_creds = {
            access_key_id: ENV.fetch('AWS_ACCESS_KEY_ID', nil),
            secret_access_key: ENV.fetch('AWS_SECRET_ACCESS_KEY', nil),
            session_token: ENV.fetch('AWS_SESSION_TOKEN', nil),
          }

          return env_creds if env_creds[:access_key_id].present? && env_creds[:secret_access_key].present?

          fetch_credentials_from_aws_sdk
        end

        def fetch_credentials_from_aws_sdk
          creds = ::Aws::ECSCredentials.new.credentials

          return {} unless creds

          {
            access_key_id: creds.access_key_id,
            secret_access_key: creds.secret_access_key,
            session_token: creds.session_token,
          }
        rescue StandardError => e
          log("Failed to fetch credentials via AWS SDK: #{e.message}")
          {}
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Outbound::AwsSigV4)
