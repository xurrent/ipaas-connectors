module IPaaS
  module Job
    module JWT
      extend ActiveSupport::Concern
      extend IPaaS::Connector::Common::ProcRules::ProcSafe
      include IPaaS::Job::Cache

      proc_safe :decode_jwt!, :encode_jwt, :make_jwt_payload, :pem_valid?, :jwk_to_pem,
                :assert_no_oidc_redirect!

      MAX_JTI_LENGTH = 256
      MAX_IAT_DRIFT = 1.minute
      JTI_CACHE_DURATION = 2 * MAX_IAT_DRIFT

      SUPPORTED_ALGORITHMS = %w[RS256 RS384 RS512 ES256 ES384 ES512].freeze
      ASYMMETRIC_JWK_KTYS = %w[RSA EC].freeze
      MAX_TOKEN_BYTES = 8 * 1024
      MAX_OIDC_RESPONSE_BYTES = 64 * 1024
      OIDC_HTTP_OPTS = { open_timeout: 2, timeout: 5 }.freeze

      def decode_jwt!(*, **)
        IPaaS::Job::JWT.decode_jwt!(*, jti_cache: internal_cache, **)
      rescue ::JWT::DecodeError => e
        raise IPaaS::Error, "Unable to decode JWT: #{e}"
      end

      def encode_jwt(...)
        IPaaS::Job::JWT.encode_jwt(...)
      end

      def make_jwt_payload(...)
        IPaaS::Job::JWT.make_jwt_payload(...)
      end

      class << self
        def pem_valid?(algorithm, pem)
          !!pem_to_key(algorithm, pem)
        rescue StandardError
          false
        end

        # Convert a JWK hash (from a JWKS document) into a PEM string.
        # Wrapped here so callers can stay inside the proc-safe registry
        # without needing direct access to JWT::JWK#import / #verify_key / #to_pem.
        def jwk_to_pem(jwk_hash)
          ::JWT::JWK.import(jwk_hash).verify_key.to_pem
        rescue ::JWT::JWKError, OpenSSL::OpenSSLError => e
          # JWT::JWKError covers shape problems (missing/unsupported kty, missing
          # required key params);
          # OpenSSL::OpenSSLError covers JWKs whose params are well-formed but
          # cryptographically invalid (e.g. EC point not on the curve),
          # which surfaces from verify_key as an OpenSSL::PKey error.
          raise IPaaS::Error, "Invalid JWK: #{e.message}"
        end

        # Belt-and-braces: assert a Faraday response did not arrive via a
        # redirect from the originally-requested URL. `faraday_for` does not
        # currently register `:follow_redirects`, but global middleware
        # registered later could enable it silently — this check fails fast
        # if a future change starts auto-following redirects, since host
        # pinning would otherwise be bypassed.
        def assert_no_oidc_redirect!(response, requested_url)
          effective = response.env&.url&.to_s
          return if effective.nil? || effective == requested_url
          raise IPaaS::Error, "OIDC fetch redirected (#{requested_url} -> #{effective})"
        end

        # Possible values for validate_iat and validate_jti:
        # * :never
        # * :if_present
        # * :always
        def decode_jwt!(token, algorithm: nil, algorithm_allowlist: nil,
                        pem: nil, key_resolver: nil,
                        issuer: nil, issuer_prefix: nil, audience: nil,
                        validate_iat: :if_present, validate_jti: :if_present, jti_cache: nil)
          validate_decode_options!(algorithm: algorithm, algorithm_allowlist: algorithm_allowlist,
                                   pem: pem, key_resolver: key_resolver,
                                   issuer: issuer, issuer_prefix: issuer_prefix)

          public_key, decode_options = pre_verify_and_resolve_key(
            token, algorithm, algorithm_allowlist, pem, key_resolver, issuer, issuer_prefix, audience,
          )
          payload, header = ::JWT.decode(token, public_key, public_key.present?, decode_options)

          self.validate_iat(payload['iat'], validate_iat)
          self.validate_jti(payload['jti'], validate_jti, jti_cache)
          { header: header, payload: payload }
        end

        def validate_iat(iat, validation_type)
          return if validation_type == :never
          return if iat.blank? && validation_type == :if_present

          raise IPaaS::Error, 'Issued At claim not present in token' if validation_type == :always && iat.blank?

          return unless (iat.to_i - Time.current.to_i).abs > MAX_IAT_DRIFT

          raise IPaaS::Error, "Issued At claim too far from current time #{Time.current.to_i}"
        end

        def validate_jti(jti, validation_type, cache)
          return if skip_jti_validation?(jti, validation_type, cache)

          validate_jti_format(jti, validation_type)
          validate_jti_uniqueness(jti, cache)
        end

        def validate_issuer!(jwt_iss, issuer, issuer_prefix)
          if issuer.present?
            return if jwt_iss == issuer
            # Use ruby-jwt's error type + format so the Concern wrapper
            # surfaces the same string an exact-match failure would normally
            # produce — pre-check before key_resolver runs against an
            # unverified iss.
            raise ::JWT::InvalidIssuerError, "Invalid issuer. Expected [\"#{issuer}\"], received #{jwt_iss}"
          end
          return if issuer_prefix.blank?

          prefix_uri = parse_uri_for_issuer_check!(issuer_prefix)
          jwt_uri = parse_uri_for_issuer_check!(jwt_iss)
          raise IPaaS::Error, "Invalid issuer '#{jwt_iss}'" if issuer_uri_mismatch?(prefix_uri, jwt_uri)
        end

        def validate_pre_verify_timestamps!(payload)
          now = Time.current.to_i
          drift = MAX_IAT_DRIFT.to_i
          check_exp_pre_verify!(payload['exp'], now, drift)
          check_nbf_pre_verify!(payload['nbf'], now, drift)
          check_iat_pre_verify!(payload['iat'], now, drift)
        end

        def encode_jwt(payload, algorithm: nil, pem: nil, header_fields: { typ: 'JWT' })
          private_key = (pem_to_key(algorithm, pem) if algorithm.present?)
          ::JWT.encode(payload, private_key, resolve_algorithm(algorithm), header_fields)
        end

        def make_jwt_payload(issuer_claim:, subject_claim:, audience_claim: nil, expiration_time_claim: 0,
                             **extra_claims)
          now = Time.now.to_i
          {
            nbf: now, iat: now, jti: SecureRandom.hex(32),
          }.tap do |h|
            h[:sub] = subject_claim if subject_claim.present?
            h[:iss] = issuer_claim if issuer_claim.present?
            h[:exp] = now + expiration_time_claim if expiration_time_claim > 0
            h[:aud] = audience_claim if audience_claim.present?
            h.merge!(extra_claims) if extra_claims.present?
          end
        end

        private

        def pem_to_key(algorithm, pem)
          if algorithm.start_with?('ES')
            OpenSSL::PKey::EC.new(pem)
          else
            OpenSSL::PKey::RSA.new(pem)
          end
        rescue OpenSSL::PKey::PKeyError
          raise IPaaS::Error, 'Invalid PEM'
        end

        def fill_decode_options(decode_options, algorithm, audience, issuer)
          decode_options[:algorithm] = resolve_algorithm(algorithm)
          if issuer.present?
            decode_options[:iss] = issuer
            decode_options[:verify_iss] = true
          end
          return unless audience.present?
          decode_options[:aud] = audience
          decode_options[:verify_aud] = true
        end

        def resolve_algorithm(algorithm)
          algorithm.presence || 'NONE'
        end

        def validate_decode_options!(algorithm:, algorithm_allowlist:, pem:, key_resolver:, issuer:, issuer_prefix:)
          if issuer.present? && issuer_prefix.present?
            raise ArgumentError, 'decode_jwt!: pass either issuer or issuer_prefix, not both'
          end
          return unless (pem.present? || !key_resolver.nil?) && algorithm.blank? && algorithm_allowlist.blank?
          raise ArgumentError,
                'decode_jwt!: an algorithm or algorithm_allowlist is required when a key is provided'
        end

        def resolve_effective_algorithm(unverified_header, algorithm, allowlist)
          return algorithm if algorithm.present?
          return nil if allowlist.blank?

          header_alg = unverified_header['alg']
          raise IPaaS::Error, "Unsupported JWT algorithm '#{header_alg}'" unless allowlist.include?(header_alg)
          header_alg
        end

        # rubocop:disable Metrics/ParameterLists
        def pre_verify_and_resolve_key(token, algorithm, algorithm_allowlist, pem, key_resolver,
                                       issuer, issuer_prefix, audience)
          unverified_payload, unverified_header = ::JWT.decode(token, nil, false)
          effective_algorithm = resolve_effective_algorithm(unverified_header, algorithm, algorithm_allowlist)
          validate_issuer!(unverified_payload['iss'], issuer, issuer_prefix)
          validate_pre_verify_timestamps!(unverified_payload)
          resolved_pem = pem.presence || key_resolver&.call(unverified_header, unverified_payload)
          build_decode_input(resolved_pem, effective_algorithm, audience, issuer)
        end
        # rubocop:enable Metrics/ParameterLists

        def build_decode_input(resolved_pem, effective_algorithm, audience, issuer)
          decode_options = {}
          public_key = if resolved_pem.present?
                         fill_decode_options(decode_options, effective_algorithm, audience, issuer)
                         pem_to_key(effective_algorithm, resolved_pem)
                       end
          [public_key, decode_options]
        end

        def parse_uri_for_issuer_check!(value)
          URI.parse(value.to_s)
        rescue URI::InvalidURIError
          raise IPaaS::Error, "Invalid issuer: cannot parse '#{value}'"
        end

        def issuer_uri_mismatch?(prefix_uri, jwt_uri)
          return true unless issuer_uri_scheme_ok?(prefix_uri, jwt_uri)
          return true unless issuer_uri_authority_ok?(prefix_uri, jwt_uri)
          !jwt_uri.path.start_with?(prefix_uri.path)
        end

        def issuer_uri_scheme_ok?(prefix_uri, jwt_uri)
          prefix_uri.scheme == 'https' && jwt_uri.scheme == 'https' &&
            prefix_uri.userinfo.nil? && jwt_uri.userinfo.nil?
        end

        def issuer_uri_authority_ok?(prefix_uri, jwt_uri)
          prefix_uri.host == jwt_uri.host && prefix_uri.port == jwt_uri.port
        end

        def check_exp_pre_verify!(exp, now, drift)
          return if exp.blank?
          raise IPaaS::Error, 'JWT has expired' if exp.to_i < now - drift
        end

        def check_nbf_pre_verify!(nbf, now, drift)
          return if nbf.blank?
          raise IPaaS::Error, 'JWT not yet valid' if nbf.to_i > now + drift
        end

        def check_iat_pre_verify!(iat, now, drift)
          return if iat.blank?
          return unless iat.to_i > now + drift
          raise IPaaS::Error, "Issued At claim too far from current time #{now}"
        end

        def skip_jti_validation?(jti, validation_type, cache)
          return true if validation_type == :never
          return true if validation_type == :if_present && (jti.blank? || cache.nil?)
          false
        end

        def validate_jti_format(jti, validation_type)
          raise IPaaS::Error, 'JWT ID claim not present in token' if validation_type == :always && jti.blank?
          raise IPaaS::Error, 'JWT ID claim too long' if jti.length > MAX_JTI_LENGTH
        end

        def validate_jti_uniqueness(jti, cache)
          raise NotImplementedError, 'Cannot validate JWT ID claim without cache' if cache.nil?
          return unless cache.increment("jwt/jti/#{jti}", 1, expires_in: JTI_CACHE_DURATION) > 1
          raise IPaaS::Error, 'JWT ID claim invalid'
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::JWT)
