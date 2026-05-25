require 'spec_helper'
require_relative 'shared/webhook_trigger_specs'

describe 'Xurrent Webhook Trigger OIDC verification', :trigger do
  include WebhookTriggerSpecs

  let(:trigger_config) do
    { payload_schema: [{ id: 'pet', label: 'Pet', type: 'string' }] }
  end

  # The trigger output for a valid webhook delivery: the configured
  # delivery id (from event_headers['x-xurrent-delivery']) plus the body
  # symbolised. Used by every success-path assertion in this file.
  let(:expected_webhook_output) do
    { delivery: '00c7bb4a-b3ba-4744-8126-1e7ef87ef90a' }.merge(webhook_body.deep_symbolize_keys)
  end

  context 'OIDC discovery' do
    let(:oidc_kid) { 'test-kid-1' }
    let(:oidc_iss) { 'https://wdc.test.host/webhook_policies/policy' }
    let(:oidc_jwk_export) do
      JWT::JWK.new(OpenSSL::PKey::EC.new(es256_pem[:public]), { kid: oidc_kid }).export.merge('use' => 'sig')
    end
    let(:well_known_url) { 'https://wdc.test.host/webhook_policies/policy/.well-known/openid-configuration' }
    let(:jwks_url) { 'https://wdc.test.host/webhook_policies/policy/jwks' }
    let(:cache_key) do
      digest = Digest::SHA256.hexdigest('https://wdc.test.host/webhook_policies/policy')
      "oidc_jwks/#{digest}/#{oidc_kid}"
    end

    let(:inbound_connection_config) do
      { policy: { account_url: oidc_iss, audience: nil } }
    end

    def sign_oidc_webhook(body, kid: oidc_kid, iss: oidc_iss, alg: 'ES256', private_pem: es256_pem[:private])
      payload = IPaaS::Job::JWT.make_jwt_payload(issuer_claim: iss,
                                                 subject_claim: 'abc',
                                                 data: body)
      token = IPaaS::Job::JWT.encode_jwt(payload, pem: private_pem, algorithm: alg,
                                                  header_fields: { typ: 'JWT', kid: kid })
      post_webhook(jwt: token)
    end

    def stub_well_known_ok
      stub_request(:get, well_known_url).to_return(
        status: 200, body: { jwks_uri: jwks_url }.to_json,
      )
    end

    def stub_jwks_ok(keys: [oidc_jwk_export])
      stub_request(:get, jwks_url).to_return(status: 200, body: { keys: keys }.to_json)
    end

    # Verifies the prefix/exact-match iss enforcement: a JWT whose iss
    # matches the configured/derived prefix proceeds to OIDC discovery and
    # succeeds, while a JWT with a mismatched iss is rejected before key
    # resolution runs (no .well-known fetch). Used by Mode A (exact match)
    # and Mode B/C (prefix derivation) tests.
    def assert_iss_acceptance_and_mismatch(expected_iss:, mismatched_iss:)
      assert_matching_iss_accepted(expected_iss)
      WebMock.reset_executed_requests!
      assert_mismatched_iss_rejected(mismatched_iss)
    end

    def stub_oidc_for(iss)
      stub_request(:get, "#{iss}/.well-known/openid-configuration")
        .to_return(status: 200, body: { jwks_uri: "#{iss}/jwks" }.to_json)
      stub_request(:get, "#{iss}/jwks")
        .to_return(status: 200, body: { keys: [oidc_jwk_export] }.to_json)
    end

    def assert_matching_iss_accepted(iss)
      stub_oidc_for(iss)
      output = sign_oidc_webhook(webhook_body, iss: iss)
      expect(output).to eq(expected_webhook_output)
      expect(WebMock).to have_requested(:get, "#{iss}/.well-known/openid-configuration").once
    end

    def assert_mismatched_iss_rejected(iss)
      expect_log(/Invalid issuer/)
      output = sign_oidc_webhook(webhook_body, iss: iss)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
      expect(WebMock).not_to have_requested(:get, /\.well-known/)
    end

    # Capture every Logger#info call across all instances into a list,
    # then assert (after the trigger has run) that at least one entry
    # matches the expected pattern. Avoids the
    # `expect_any_instance_of(Logger).to receive(:info)` race with
    # Faraday's LoggingMiddleware (which logs to a different Logger
    # instance and triggers "already received by another instance"
    # errors). Each test calls `expect_log(/regex/)` first; the matcher
    # is checked at end-of-example via the after hook.
    let(:captured_log_lines) { [] }
    let(:expected_log_patterns) { [] }

    before do
      patterns = expected_log_patterns
      lines = captured_log_lines
      allow_any_instance_of(Logger).to receive(:info).and_wrap_original do |original, *args, &block|
        msg = if args.first.is_a?(String)
                args.first
              elsif block
                block.call
              else
                args.first.to_s
              end
        lines << msg if msg.is_a?(String)
        original.call(*args, &block)
      end
      patterns # keep reference (rubocop)
    end

    after do |example|
      next if example.exception
      expected_log_patterns.each do |pattern|
        unless captured_log_lines.any? { |line| line.match?(pattern) }
          raise "Expected log line matching #{pattern.inspect}; captured lines: #{captured_log_lines.inspect}"
        end
      end
    end

    def expect_log(pattern)
      expected_log_patterns << pattern
    end

    it 'fetches well-known and JWKS and writes the resolved PEM to the cache' do
      stub_well_known_ok
      stub_jwks_ok
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq(expected_webhook_output)
      expect(inbound_connection.store.read(cache_key)).to include('BEGIN PUBLIC KEY')
    end

    it 'serves a cached PEM without making any HTTP requests' do
      inbound_connection.store.write(cache_key, es256_pem[:public])
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq(expected_webhook_output)
      expect(WebMock).not_to have_requested(:get, %r{/\.well-known/})
      expect(WebMock).not_to have_requested(:get, jwks_url)
    end

    it 'isolates cache entries per issuer (different iss does not pick up other-iss key)' do
      other_iss_digest = Digest::SHA256.hexdigest('https://other.host/policy')
      inbound_connection.store.write("oidc_jwks/#{other_iss_digest}/#{oidc_kid}", 'garbage-pem')
      stub_well_known_ok
      stub_jwks_ok
      sign_oidc_webhook(webhook_body)
      expect(inbound_connection.store.read("oidc_jwks/#{other_iss_digest}/#{oidc_kid}")).to eq('garbage-pem')
      expect(inbound_connection.store.read(cache_key)).to include('BEGIN PUBLIC KEY')
    end

    it 'rejects a JWT without a kid header' do
      expect_log(/JWT has no kid header/)
      output = sign_oidc_webhook(webhook_body, kid: nil)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects when kid is not in JWKS' do
      stub_well_known_ok
      stub_jwks_ok(keys: [JWT::JWK.new(OpenSSL::PKey::EC.new(es256_pem[:public]),
                                       { kid: 'other-kid' }).export])
      expect_log(/Key '#{oidc_kid}' not found in JWKS/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects symmetric kty (oct) JWKs' do
      stub_well_known_ok
      stub_jwks_ok(keys: [{ 'kty' => 'oct', 'kid' => oidc_kid, 'use' => 'sig', 'k' => 'aaaa' }])
      expect_log(/Key '#{oidc_kid}' not found in JWKS/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects JWKs whose use is not sig' do
      stub_well_known_ok
      enc_jwk = oidc_jwk_export.merge('use' => 'enc')
      stub_jwks_ok(keys: [enc_jwk])
      expect_log(/Key '#{oidc_kid}' not found/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects JWKs whose use is absent' do
      # RFC 7517 §4.2 makes `use` optional, but Xurrent always publishes
      # `use: "sig"` and select_jwk! requires an exact match — a JWK
      # without `use` must be rejected (fail closed).
      stub_well_known_ok
      no_use_jwk = oidc_jwk_export.except('use')
      stub_jwks_ok(keys: [no_use_jwk])
      expect_log(/Key '#{oidc_kid}' not found/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects JWKs whose alg disagrees with the JWT alg' do
      stub_well_known_ok
      mismatched = oidc_jwk_export.merge('alg' => 'RS256')
      stub_jwks_ok(keys: [mismatched])
      expect_log(/Key '#{oidc_kid}' not found/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects when well-known returns non-200' do
      stub_request(:get, well_known_url).to_return(status: 500, body: '')
      expect_log(/OIDC discovery failed: 500/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects when JWKS returns non-200' do
      stub_well_known_ok
      stub_request(:get, jwks_url).to_return(status: 500, body: '')
      expect_log(/JWKS fetch failed: 500/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects when well-known returns an unparseable body' do
      stub_request(:get, well_known_url).to_return(status: 200, body: '{not json')
      expect_log(/OIDC discovery failed: response could not be parsed/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects when JWKS returns an unparseable body' do
      stub_well_known_ok
      stub_request(:get, jwks_url).to_return(status: 200, body: '{not json')
      expect_log(/JWKS fetch failed: response could not be parsed/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects an oversized well-known response (Content-Length header)' do
      stub_request(:get, well_known_url).to_return(
        status: 200, body: '{}',
        headers: { 'Content-Length' => (IPaaS::Job::JWT::MAX_OIDC_RESPONSE_BYTES + 1).to_s },
      )
      expect_log(/OIDC response too large/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects an oversized well-known response when Content-Length is missing' do
      stub_request(:get, well_known_url).to_return(
        status: 200, body: 'x' * (IPaaS::Job::JWT::MAX_OIDC_RESPONSE_BYTES + 1),
      )
      expect_log(/OIDC response too large/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects an oversized JWKS response' do
      stub_well_known_ok
      stub_request(:get, jwks_url).to_return(
        status: 200, body: 'x' * (IPaaS::Job::JWT::MAX_OIDC_RESPONSE_BYTES + 1),
      )
      expect_log(/OIDC response too large/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects a 3xx without follow_redirects (status check)' do
      # `faraday_for` does not enable follow_redirects, so a 302 surfaces
      # as a non-200 status and the discovery fails fast on the status
      # guard. This is the today-default path.
      stub_request(:get, well_known_url).to_return(status: 302)
      expect_log(/OIDC discovery failed: 302/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects a fetch whose effective URL differs from the requested URL' do
      # Belt-and-braces against future global middleware that adds
      # auto-follow: simulate a redirect-following response by stubbing
      # the requested URL to deliver a 200 body but with the response's
      # `env.url` pointing at a different host (what a follow_redirects
      # middleware would produce).
      stub_request(:get, well_known_url).to_return do |_request|
        { status: 200, body: { jwks_uri: jwks_url }.to_json }
      end
      # Override Faraday::Response#env.url for any response from this URL
      allow_any_instance_of(Faraday::Response).to receive(:env).and_wrap_original do |original, *args|
        env = original.call(*args)
        if env&.url&.to_s == well_known_url
          redirected = env.dup
          redirected.url = URI.parse('https://attacker.example/cfg')
          redirected
        else
          env
        end
      end
      expect_log(/OIDC fetch redirected/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'rejects iss that smuggles a host via userinfo' do
      expect_log(/Invalid issuer/)
      output = sign_oidc_webhook(webhook_body, iss: 'https://wdc.test.host@evil.com/policy')
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
      expect(WebMock).not_to have_requested(:get, /evil\.com/)
      expect(WebMock).not_to have_requested(:get, /\.well-known/)
    end

    it 'rejects iss whose host extends the configured account host' do
      inbound_connection_config[:policy][:account_url] = 'https://wdc.test.host'
      expect_log(/Invalid issuer/)
      output = sign_oidc_webhook(webhook_body, iss: 'https://wdc.test.host.evil.com/policy')
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
      expect(WebMock).not_to have_requested(:get, /\.well-known/)
    end

    it 'rejects iss with http scheme if account url uses https' do
      expect_log(/Invalid issuer/)
      inbound_connection_config[:policy][:account_url] = 'https://wdc.test.host/policy'
      output = sign_oidc_webhook(webhook_body, iss: 'http://wdc.test.host/policy')
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
      expect(WebMock).not_to have_requested(:get, /\.well-known/)
    end

    it 'rejects an http account_url before fetching OIDC discovery' do
      expect_log(/OIDC URL must use https/)
      inbound_connection_config[:policy][:account_url] = 'http://wdc.test.host/policy'
      output = sign_oidc_webhook(webhook_body, iss: 'http://wdc.test.host/policy')
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
      expect(WebMock).not_to have_requested(:get, /\.well-known/)
    end

    it 'rejects discovery whose jwks_uri host differs from iss host' do
      stub_request(:get, well_known_url).to_return(
        status: 200, body: { jwks_uri: 'https://attacker.example/keys' }.to_json,
      )
      expect_log(/JWKS URI host mismatch/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
      expect(WebMock).not_to have_requested(:get, %r{attacker\.example/keys})
    end

    it 'rejects a discovered jwks_uri with an http scheme' do
      stub_request(:get, well_known_url).to_return(
        status: 200, body: { jwks_uri: 'http://wdc.test.host/keys' }.to_json,
      )
      expect_log(/OIDC URL must use https/)
      output = sign_oidc_webhook(webhook_body)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
    end

    it 'pins iss to the configured account_url and rejects mismatched issuers' do
      # Mode A: account_url set ⇒ exact match. Discovery proceeds against
      # the pinned host, and a JWT with any other iss must be rejected
      # before key resolution runs.
      assert_iss_acceptance_and_mismatch(expected_iss: oidc_iss,
                                         mismatched_iss: "#{oidc_iss}/other")
    end

    it 'derives the algorithm from the JWT header when none is configured' do
      stub_well_known_ok
      stub_jwks_ok
      output = sign_oidc_webhook(webhook_body, alg: 'ES256')
      expect(output).to eq(expected_webhook_output)
    end

    it 'rejects a JWT whose header alg is not in the supported allowlist' do
      # Manually craft an HS256 token (symmetric, would normally be unverifiable)
      payload = IPaaS::Job::JWT.make_jwt_payload(issuer_claim: oidc_iss,
                                                 subject_claim: 'abc',
                                                 data: webhook_body)
      encoded_header = Base64.urlsafe_encode64({ typ: 'JWT', alg: 'HS256', kid: oidc_kid }.to_json, padding: false)
      encoded_payload = Base64.urlsafe_encode64(payload.to_json, padding: false)
      signature = Base64.urlsafe_encode64('fakesig', padding: false)
      token = "#{encoded_header}.#{encoded_payload}.#{signature}"
      expect_log(/Unsupported JWT algorithm 'HS256'/)
      output = post_webhook(jwt: token)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
      expect(WebMock).not_to have_requested(:get, /\.well-known/)
    end

    it 'rejects an expired JWT before any OIDC fetch' do
      stub_well_known_ok
      stub_jwks_ok
      payload = IPaaS::Job::JWT.make_jwt_payload(issuer_claim: oidc_iss,
                                                 subject_claim: 'abc',
                                                 data: webhook_body,
                                                 exp: 1.hour.ago.to_i)
      token = IPaaS::Job::JWT.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256',
                                                  header_fields: { typ: 'JWT', kid: oidc_kid })
      expect_log(/JWT has expired/)
      output = post_webhook(jwt: token)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
      expect(WebMock).not_to have_requested(:get, /\.well-known/)
    end

    it 'rejects a JWT with iat far in the future before any OIDC fetch' do
      stub_well_known_ok
      stub_jwks_ok
      payload = IPaaS::Job::JWT.make_jwt_payload(issuer_claim: oidc_iss,
                                                 subject_claim: 'abc',
                                                 data: webhook_body,
                                                 iat: 1.hour.from_now.to_i)
      token = IPaaS::Job::JWT.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256',
                                                  header_fields: { typ: 'JWT', kid: oidc_kid })
      expect_log(/Issued At claim too far/)
      output = post_webhook(jwt: token)
      expect(output).to eq({ error: 'Webhook JWT verification failed' })
      expect(WebMock).not_to have_requested(:get, /\.well-known/)
    end

    it 'normalises iss with a trailing slash to the same cache key' do
      stub_well_known_ok
      stub_jwks_ok
      # Pre-populate the canonical cache key so the second delivery (with trailing slash)
      # still hits the cache and skips HTTP.
      inbound_connection.store.write(cache_key, es256_pem[:public])
      inbound_connection_config[:policy][:account_url] = "#{oidc_iss}/"
      sign_oidc_webhook(webhook_body, iss: "#{oidc_iss}/")
      expect(WebMock).not_to have_requested(:get, %r{/\.well-known/})
    end

    context 'when policy account_url is blank' do
      let(:inbound_connection_config) { { policy: { audience: nil } } }

      context 'and no outbound connection exists' do
        let(:system_account_id) { 'sys' }
        let(:system_xurrent_domain) { 'xurrent-test.com' }
        let(:system_iss) { "https://#{system_account_id}.#{system_xurrent_domain}/webhook_policies/policy" }

        before do
          allow(trigger).to receive(:solution).and_return(
            double(environment: { xurrent_ipaas_account_id: system_account_id,
                                  xurrent_ipaas_domain: system_xurrent_domain, }),
          )
        end

        it 'accepts an iss matching the derived prefix and rejects mismatched issuers' do
          # Mode B: account_url blank ⇒ prefix derived from system_account_id +
          # system_xurrent_domain. An iss extending the prefix passes the
          # pre-check and proceeds to OIDC discovery; an iss whose host
          # differs is rejected before key resolution runs.
          assert_iss_acceptance_and_mismatch(
            expected_iss: system_iss,
            mismatched_iss: "https://other.#{system_xurrent_domain}/webhook_policies/policy",
          )
        end
      end

      context 'and outbound configuration overrides the region' do
        let(:hybrid_account_id) { 'sys' }
        let(:hybrid_iss) { "https://#{hybrid_account_id}.au.xurrent.com/webhook_policies/policy" }

        before do
          # system_account_id supplies the account; the domain is taken
          # from xurrent_domain (outbound stage 'Prod' + region 'au' ⇒
          # au.xurrent.com), which overrides system_xurrent_domain because
          # outbound_connection is non-nil.
          allow(trigger).to receive(:solution).and_return(
            double(environment: { xurrent_ipaas_account_id: hybrid_account_id,
                                  xurrent_ipaas_domain: 'xurrent-test.com', }),
          )
          allow(trigger).to receive(:outbound_connection).and_return(
            double('outbound_connection',
                   config: { environment: { stage: 'Prod', region: 'au' } }),
          )
        end

        it 'derives the prefix from system_account_id and the outbound region' do
          # Mode B + outbound override: the iss host extending
          # https://sys.au.xurrent.com is accepted; an iss whose host uses
          # system_xurrent_domain (the value that would apply without the
          # outbound override) is rejected, proving the override took effect.
          assert_iss_acceptance_and_mismatch(
            expected_iss: hybrid_iss,
            mismatched_iss: "https://#{hybrid_account_id}.xurrent-test.com/webhook_policies/policy",
          )
        end
      end

      context 'and outbound credentials provide an account_id' do
        let(:outbound_account_id) { 'outbound-acct' }
        let(:outbound_iss) { "https://#{outbound_account_id}.xurrent-demo.com/webhook_policies/policy" }

        before do
          # outbound takes precedence: even when a system Xurrent account is
          # configured, the outbound credentials.account_id wins. The operator's
          # outbound config is the explicit declaration of which Xurrent account
          # this runbook works with, which can legitimately differ from the iPaaS
          # tenant's own account.
          allow(trigger).to receive(:solution).and_return(
            double(environment: { xurrent_ipaas_account_id: 'system-acct',
                                  xurrent_ipaas_domain: 'xurrent-test.com', }),
          )
          allow(trigger).to receive(:outbound_connection).and_return(
            double('outbound_connection',
                   config: { credentials: { account_id: outbound_account_id },
                             environment: { stage: 'Demo' }, }),
          )
        end

        it 'accepts an iss matching the outbound-derived prefix and rejects the system-derived prefix' do
          # Mode C: account_url blank, outbound credentials present ⇒ prefix
          # derived from outbound credentials.account_id + xurrent_domain. The
          # mismatched iss uses the system-derived prefix to prove outbound
          # wins when both are configured.
          assert_iss_acceptance_and_mismatch(
            expected_iss: outbound_iss,
            mismatched_iss: 'https://system-acct.xurrent-test.com/webhook_policies/policy',
          )
        end
      end
    end
  end

  context 'misconfiguration' do
    # No outbound credentials → expected_issuer_prefix returns nil.
    # No policy account_url → both Mode A and Mode B/C unreachable.
    let(:inbound_connection_config) { { policy: nil } }

    it 'returns a generic error and logs the misconfig when no host can be derived' do
      allow_any_instance_of(Logger).to receive(:info)
      expect_any_instance_of(Logger)
        .to receive(:info)
        .with(/no policy account_url and no system Xurrent account/).at_least(:once)
      payload = IPaaS::Job::JWT.make_jwt_payload(issuer_claim: 'https://wdc.test.host',
                                                 subject_claim: 'abc',
                                                 data: webhook_body)
      token = IPaaS::Job::JWT.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256',
                                                  header_fields: { typ: 'JWT', kid: 'k' })
      output = post_webhook(jwt: token)
      expect(output).to eq({ error: 'Webhook configuration error' })
    end
  end

  context 'body and JWT size caps' do
    let(:inbound_connection_config) { { policy: policy_config.dup } }

    it 'rejects bodies larger than MAX_WEBHOOK_BODY_BYTES' do
      allow_any_instance_of(Logger).to receive(:info)
      expect_any_instance_of(Logger)
        .to receive(:info).with(/Webhook body too large/).at_least(:once)
      big_body = { jwt: 'x' * (XurrentConnector::MAX_WEBHOOK_BODY_BYTES + 1) }
      output = post_webhook(big_body)
      expect(output).to eq({ error: 'Webhook body too large' })
    end

    it 'rejects JWTs larger than MAX_TOKEN_BYTES even when the body fits' do
      allow_any_instance_of(Logger).to receive(:info)
      expect_any_instance_of(Logger)
        .to receive(:info).with(/Webhook JWT too large/).at_least(:once)
      giant_jwt = 'x' * (IPaaS::Job::JWT::MAX_TOKEN_BYTES + 1)
      output = post_webhook(jwt: giant_jwt)
      expect(output).to eq({ error: 'Webhook JWT is too large' })
    end
  end
end
