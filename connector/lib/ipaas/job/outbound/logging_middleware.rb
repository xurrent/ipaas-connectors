require 'faraday'

module IPaaS
  module Job
    module Outbound
      class LoggingMiddleware < Faraday::Middleware
        SENSITIVE_KEY_PATTERN = /token|secret|api[_-]?key|access[_-]?token|password|auth/i
        REDACTED_HEADERS = %w[
          Authorization
          Proxy-Authorization
          Cookie
          Set-Cookie
          X-Api-Key
        ].freeze

        def on_request(env)
          env.request.instance_variable_set(:@ipaas_start, monotonic_now)
        end

        def on_complete(env)
          emit(env, error: nil)
        end

        def call(env)
          on_request(env)
          @app.call(env).on_complete { |response_env| on_complete(response_env) }
        rescue StandardError => e
          emit(env, error: e)
          raise
        end

        private

        def emit(env, error:)
          logger.info(build_payload(env, error).to_json)
        rescue StandardError
          nil
        end

        # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        def build_payload(env, error)
          started = env.request.instance_variable_get(:@ipaas_start)
          url = env.url
          payload = {
            event: 'outbound_http',
            method: env.method.to_s.upcase,
            host: url.host,
            path: url.path,
            query: redacted_query(url.query),
            duration_ms: started ? ((monotonic_now - started) * 1000).round(1) : nil,
            req_bytes: byte_size(env.request_body),
            req_headers: redact_headers(env.request_headers),
            error_class: error&.class&.name,
            error_message: error&.message&.truncate(300),
          }
          if error.nil?
            payload[:status] = env.status
            payload[:res_bytes] = byte_size(env.response_body)
          end
          payload.compact
        end
        # rubocop:enable Metrics/AbcSize,Metrics/MethodLength

        def logger
          @logger ||=
            if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
              Rails.logger
            else
              ::Logger.new($stdout)
            end
        end

        def redact_headers(headers)
          return {} unless headers.respond_to?(:each_pair)

          headers.each_with_object({}) do |(k, v), acc|
            acc[k] = sensitive_header?(k) ? "[REDACTED len=#{v.to_s.bytesize}]" : v
          end
        end

        def redacted_query(query_string)
          return nil if query_string.blank?

          parts = query_string.split('&').map do |kv|
            key, = kv.split('=', 2)
            if key && sensitive_key?(key)
              "#{key}=[REDACTED]"
            else
              kv
            end
          end
          parts.join('&')
        end

        def sensitive_header?(name)
          REDACTED_HEADERS.any? { |h| h.casecmp?(name.to_s) } || sensitive_key?(name)
        end

        def sensitive_key?(key)
          SENSITIVE_KEY_PATTERN.match?(key.to_s)
        end

        def byte_size(body)
          case body
          when nil then 0
          when String then body.bytesize
          else body.to_s.bytesize
          end
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
