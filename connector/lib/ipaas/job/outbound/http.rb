module IPaaS
  module Job
    module Outbound
      module HTTP
        OPEN_TIMEOUT = 5 # 5 seconds
        TIMEOUT = 300 # 5 minutes
        VALID_METHODS = Faraday::Connection::METHODS

        extend ActiveSupport::Concern
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :http_connection, :http_send,
                  :get, :post, :put, :delete, :head, :patch, :options, :trace,
                  :http_get, :http_post, :http_put, :http_delete, :http_head, :http_patch, :http_options, :http_trace,
                  :multipart_post, :create_text_part, :create_binary_part

        included do
          def http_connection(uri, skip_authentication: false, open_timeout: nil, timeout: nil)
            IPaaS::Job::Outbound::HTTP.validate_uri!(uri)
            IPaaS::Job::Outbound::HTTP.validate_timeouts!(open_timeout, timeout)
            faraday_for(uri, skip_authentication: skip_authentication,
                             request_options: request_options(open_timeout: open_timeout, timeout: timeout))
          end

          def faraday_for(uri, skip_authentication:, request_options:)
            conn = outbound_connection
            Faraday.new(url: uri, request: request_options, ssl: no_verification_in_development) do |request_builder|
              request_builder.request :multipart
              conn.authenticate_request(request_builder) unless skip_authentication
              request_builder.headers['User-Agent'] = 'Xurrent iPaaS'
              request_builder.use IPaaS::Job::Outbound::LoggingMiddleware
            end
          end

          def http_send(method, url, path = nil, &block)
            IPaaS::Job::Outbound::HTTP.validate_method!(method)

            http_connection(url).send(method, path, &block)
          end

          [:get, :head, :delete, :trace, :options].each do |method|
            define_method :"http_#{method}" do |url, params = nil, headers = nil,
                                                skip_authentication: false, open_timeout: nil, timeout: nil, &block|
              IPaaS::Job::Outbound::HTTP.validate_headers!(headers)
              IPaaS::Job::Outbound::HTTP.validate_params!(params)

              http_connection(url, skip_authentication: skip_authentication,
                                   open_timeout: open_timeout, timeout: timeout)
                .run_request(method, nil, nil, nil) do |request|
                request.params = params if params
                request.headers.merge!(headers) if headers
                block&.call(request)
              end
            end
          end

          [:post, :put, :patch].each do |method|
            define_method :"http_#{method}" do |url, body = nil, headers = nil,
                                                skip_authentication: false, open_timeout: nil, timeout: nil, &block|
              http_connection(url, skip_authentication: skip_authentication,
                                   open_timeout: open_timeout, timeout: timeout)
                .run_request(method, nil, nil, nil) do |request|
                IPaaS::Job::Outbound::HTTP.validate_headers!(headers)
                IPaaS::Job::Outbound::HTTP.validate_body!(body)

                request.body = body if body
                request.headers.merge!(headers) if headers
                block&.call(request)
              end
            end
          end

          def multipart_post(url, params, headers = nil, skip_authentication: false, &block)
            http_connection(url, skip_authentication: skip_authentication)
              .run_request(:post, nil, nil, nil) do |request|
              IPaaS::Job::Outbound::HTTP.validate_headers!(headers)
              IPaaS::Job::Outbound::HTTP.validate_multipart_params!(params)

              request.headers.merge!(headers) if headers
              request.body = params
              block&.call(request)
            end
          end

          private

          def request_options(open_timeout: nil, timeout: nil)
            {
              open_timeout: open_timeout || OPEN_TIMEOUT,
              timeout: timeout || TIMEOUT,
              proxy: proxy_config,
            }
          end

          def proxy_config
            config = outbound_connection&.config&.[](:proxy_server)
            return unless config

            {
              uri: config[:host],
              user: config[:username],
              password: decrypt_secret_string(config[:password]),
            }
          end

          def no_verification_in_development
            return nil unless defined?(Rails) && Rails.env.development?

            { verify: false }
          end
        end

        class << self
          def validate_method!(method)
            return if VALID_METHODS.include?(method.to_sym)

            raise IPaaS::Error, "Invalid http method, expected one of #{VALID_METHODS.join(', ')}."
          end

          def validate_uri!(uri)
            return if IPaaS::Connector::Types::UriType.valid?(uri)

            raise IPaaS::Error, "URI #{uri} is invalid."
          end

          def validate_timeouts!(open_timeout, timeout)
            if timeout && timeout > TIMEOUT
              raise IPaaS::Error, "timeout #{timeout}s must not exceed module maximum #{TIMEOUT}s."
            end
            return unless open_timeout && timeout && open_timeout >= timeout

            raise IPaaS::Error, "open_timeout #{open_timeout}s must be less than timeout #{timeout}s."
          end

          def validate_headers!(headers)
            return if headers.nil?
            return if hash_with_symbols_or_keys?(headers)

            raise IPaaS::Error, "Headers must be a hash with symbols or strings, found #{headers.inspect}."
          end

          def validate_params!(params)
            return if params.nil?
            return if hash_with_symbols_or_keys?(params)

            raise IPaaS::Error, "Params must be a hash with symbols or strings, found #{params.inspect}."
          end

          def validate_body!(body)
            return if body.nil?
            return if body.is_a?(String)

            raise IPaaS::Error, "Body must be a string, found #{body.inspect}. Consider adding `.to_s`."
          end

          def create_binary_part(filename, content_type, data)
            Faraday::Multipart::FilePart.new(StringIO.new(data, 'rb'), content_type, filename)
          end

          def create_text_part(content_type, text)
            Faraday::Multipart::ParamPart.new(text, content_type)
          end

          def validate_multipart_params!(parts)
            if parts.is_a?(Hash) &&
               parts.present? &&
               all_symbols_or_keys?(parts.keys)
              bad_parts = parts.reject { |_k, v| symbol_or_key?(v) || valid_part?(v) }
              return if bad_parts.empty?

              raise IPaaS::Error, "Unsupported parts found: #{bad_parts.keys}."
            end
            raise IPaaS::Error, "Parts must be a hash with simple keys, found #{parts.inspect}."
          end

          def valid_part?(value)
            value.is_a?(Faraday::Multipart::FilePart) || value.is_a?(Faraday::Multipart::ParamPart)
          end

          private

          def hash_with_symbols_or_keys?(hash)
            return false unless hash.is_a?(Hash)
            return false unless all_symbols_or_keys?(hash.keys)
            return false unless all_symbols_or_keys?(hash.values)

            true
          end

          def all_symbols_or_keys?(values)
            values.all? { |value| symbol_or_key?(value) }
          end

          def symbol_or_key?(value)
            value.is_a?(String) || value.is_a?(Symbol)
          end
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Outbound::HTTP)
