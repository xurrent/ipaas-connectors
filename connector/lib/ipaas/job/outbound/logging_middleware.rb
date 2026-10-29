require 'faraday'

module IPaaS
  module Job
    module Outbound
      class LoggingMiddleware < Faraday::Middleware
        SENSITIVE_KEY_PATTERN = /token|secret|api[_-]?key|access[_-]?token|password|auth/i
        REDACTED_HEADERS = IPaaS.make_shareable(%w[
          Authorization
          Proxy-Authorization
          Cookie
          Set-Cookie
          X-Api-Key
        ])

        PEER_SLOT = :ipaas_outbound_http_peer

        cattr_accessor :context_provider, instance_accessor: false

        class << self
          def record_peer(address, address_class)
            Thread.current[PEER_SLOT]&.replace(peer_address: address, peer_class: address_class)
          end
        end

        def initialize(app, connector_uuid: nil)
          super(app)
          @connector_uuid = connector_uuid
        end

        def on_request(env)
          env.request.instance_variable_set(:@ipaas_start, monotonic_now)
        end

        def call(env)
          with_peer_slot { |peer| logged_call(env, peer) }
        end

        private

        def with_peer_slot
          outer_peer = Thread.current[PEER_SLOT]
          peer = {}
          begin
            Thread.current[PEER_SLOT] = peer
            yield peer
          ensure
            Thread.current[PEER_SLOT] = outer_peer
          end
        end

        def logged_call(env, peer)
          logged = false
          on_request(env)
          response = @app.call(env)
          logged = log_response(response, peer)
          response
        rescue Exception => e # rubocop:disable Lint/RescueException
          logged ||= emit(env, peer, error: e)
          raise
        ensure
          emit(env, peer, error: nil) unless logged
        end

        def log_response(response, peer)
          return emit(response.env, peer, error: nil) if response.finished?

          response.on_complete { |response_env| emit(response_env, peer, error: nil) }
          :deferred
        end

        def emit(env, peer, error:)
          logger.info(build_payload(env, peer, error).to_json)
          true
        rescue StandardError => e
          emit_fallback(peer, e)
          true
        end

        def emit_fallback(peer, error)
          payload = { **sender_fields, event: 'outbound_http', **peer }
          logger.info(payload.merge(connector_uuid: @connector_uuid, log_error_class: error.class.name).compact.to_json)
        rescue StandardError
          nil
        end

        # rubocop:disable-next Metrics/AbcSize,Metrics/MethodLength
        def build_payload(env, peer, error)
          started = env.request.instance_variable_get(:@ipaas_start)
          url = env.url
          payload = {
            **sender_fields,
            event: 'outbound_http',
            method: env.method.to_s.upcase,
            host: url.host,
            path: url.path,
            query: redacted_query(url.query),
            duration_ms: started ? ((monotonic_now - started) * 1000).round(1) : nil,
            req_bytes: byte_size(env.request_body),
            req_headers: redact_headers(env.request_headers),
            error_class: error&.class&.name,
            error_message: loggable(error&.message)&.truncate(300),
            **peer,
            connector_uuid: @connector_uuid,
          }
          if error.nil?
            payload[:status] = env.status
            payload[:res_bytes] = byte_size(env.response_body)
          end
          payload.compact
        end

        def sender_fields
          self.class.context_provider&.call.to_h
        rescue StandardError
          {}
        end

        def logger
          IPaaS.default_logger
        end

        def redact_headers(headers)
          return {} unless headers.respond_to?(:each_pair)

          headers.each_with_object({}) do |(k, v), acc|
            key = loggable(k)
            acc[key] = sensitive_header?(key) ? "[REDACTED len=#{v.to_s.bytesize}]" : loggable(v)
          end
        end

        def loggable(value)
          return value unless value.is_a?(String)
          return value if value.encoding == Encoding::UTF_8 && value.valid_encoding?
          if [Encoding::BINARY, Encoding::UTF_8].include?(value.encoding)
            return value.dup.force_encoding(Encoding::UTF_8).scrub
          end

          value.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        rescue EncodingError
          value.b.force_encoding(Encoding::UTF_8).scrub
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
