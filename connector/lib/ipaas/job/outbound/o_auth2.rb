module IPaaS
  module Job
    module Outbound
      module OAuth2
        extend ActiveSupport::Concern
        extend IPaaS::Connector::Common::ProcRules::ProcSafe
        include HTTP
        include IPaaS::Job::Lock

        proc_safe :oauth2_client_credentials_body, :oauth2_refresh_body, :oauth2_authorization_header,
                  :clear_oauth2_header_cache

        AUTHENTICATION_HEADER_CACHE_KEY = 'oauth2_authentication_header'.freeze
        CUSTOMER_OAUTH2_ERROR_CODES = %w[invalid_client invalid_grant unauthorized_client invalid_scope].freeze

        LOCK_TTL_SECONDS     = IPaaS::Job::Lock::DEFAULT_TTL_SECONDS
        REFRESH_OPEN_TIMEOUT = 5
        REFRESH_TIMEOUT      = 20

        def oauth2_client_credentials_body(client_id, client_secret)
          {
            client_id: client_id,
            client_secret: client_secret,
            grant_type: 'client_credentials',
          }
        end

        def oauth2_refresh_body(client_id, client_secret, refresh_token)
          {
            client_id: client_id,
            client_secret: client_secret,
            refresh_token: refresh_token,
            grant_type: 'refresh_token',
          }
        end

        def oauth2_authorization_header(url, body, **extra_params)
          cache_key = create_cache_key(url, body, **extra_params)
          cached = cache_read(cache_key)
          return cached if cached.present?

          lock_key = oauth2_lock_key(url, body, **extra_params)
          refresh_oauth2_token(url, body, cache_key, lock_key)
        end

        private

        # Operational kill-switch (OAUTH2_SINGLEFLIGHT_DISABLED=1): bypass the
        # cross-process lock and revert to the pre-singleflight code path.
        # Token=nil signals the persist branch to write the cache directly.
        def refresh_oauth2_token(url, body, cache_key, lock_key)
          if ENV['OAUTH2_SINGLEFLIGHT_DISABLED'] == '1'
            refresh_under_lock(url, body, cache_key, lock_key, nil)
          else
            with_lock(lock_key, ttl: LOCK_TTL_SECONDS) do |token|
              refresh_under_lock(url, body, cache_key, lock_key, token)
            end
          end
        end

        def refresh_under_lock(url, body, cache_key, lock_key, token)
          cached = cache_read(cache_key)
          return cached if cached.present?

          result = request_authorization_header(url, body)
          cache_time = result[:response_body]['expires_in'].to_i - REFRESH_OPEN_TIMEOUT
          persist_refreshed_token(lock_key, token, cache_key, result[:header], cache_time)
          result[:header]
        end

        def persist_refreshed_token(lock_key, token, cache_key, value, cache_time)
          if token.nil?
            cache_write(cache_key, value, cache_time)
          elsif write_if_lock_held(lock_key, token, cache_key, value, cache_time)
            # Diagnostic only. write_if_lock_held verifies ownership at the START
            # of the cache_write but not throughout. The MySQL write takes ~ms;
            # if the lock TTL elapses during that window and a peer acquires, we
            # need to know — this probe re-checks ownership after the write
            # completed. No corrective action is taken (the write already
            # happened); the log line surfaces the cross-system TOCTOU rate.
            still_held = locker.compare_and_call(lock_key, token) { true }
            log("oauth2.lock.lost_after_write lock_key_sha=#{lock_key_sha(lock_key)}") unless still_held
          else
            log("oauth2.lock.compare_and_write_lost lock_key_sha=#{lock_key_sha(lock_key)}")
          end
        end

        def oauth2_lock_key(url, body, **extra_params)
          "oauth2:#{create_cache_key(url, body, **extra_params)}:refresh"
        end

        def request_authorization_header(url, body)
          response = call_oauth2_endpoint(url, body)
          response_body = JSON.parse(response.body)
          access_token = extract_bearer_token(response_body)

          { header: "Bearer #{access_token}", response_body: response_body }
        end

        def call_oauth2_endpoint(url, body)
          headers = { content_type: 'application/x-www-form-urlencoded', accept: 'application/json' }
          response = http_post(url, URI.encode_www_form(body), headers,
                               skip_authentication: true,
                               open_timeout: REFRESH_OPEN_TIMEOUT,
                               timeout: REFRESH_TIMEOUT)
          return response if response.status == 200

          host = URI(url).host
          oauth2_error = oauth2_error_reason(response.status, response.body)
          raise CustomerCredentialsError.new(host: host, reason: oauth2_error) if oauth2_error.present?

          raise IPaaS::Error, "Unable to authenticate to #{host} (HTTP #{response.status})"
        end

        def oauth2_error_reason(status, body)
          parsed_body = safe_parse_json(body)
          return unless customer_credentials_error?(status, parsed_body)

          code = parsed_body['error'].presence
          description = parsed_body['error_description'].presence
          return "#{code}: #{description}" if code && description
          return code if code
          return description if description
          "HTTP #{status}"
        end

        def customer_credentials_error?(status, parsed_body)
          return true if [401, 403].include?(status)
          return false unless status == 400
          CUSTOMER_OAUTH2_ERROR_CODES.include?(parsed_body['error'])
        end

        def safe_parse_json(body)
          parsed = JSON.parse(body.to_s)
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          {}
        end

        def extract_bearer_token(response_body)
          if response_body.key?('token_type') && response_body['token_type'].downcase != 'bearer'
            raise IPaaS::Error, "Unable to authenticate, unsupported token_type: '#{response_body['token_type']}'"
          end
          access_token = response_body['access_token']
          raise IPaaS::Error, 'Unable to authenticate, no access_token found' if access_token.blank?
          access_token
        end

        def create_cache_key(url, body, **extra_params)
          key_state = {
            url: url,
            body: body,
          }
          key_state[:extra_params] = extra_params if extra_params.present?
          hash = Digest::SHA256.hexdigest(key_state.to_json)
          "#{AUTHENTICATION_HEADER_CACHE_KEY}_#{hash}"
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Outbound::OAuth2)
