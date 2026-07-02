require 'spec_helper'

describe IPaaS::Job::Outbound::OAuth2 do
  before { IPaaS::Job::MemoryLocker.const_get(:ENTRIES).clear }

  let(:context_class) do
    Class.new do
      include IPaaS::Job::Context

      def uuid
        'oauth-spec'
      end
    end
  end
  let(:context) { context_class.new }
  let(:url)     { 'https://idp.example.com/token' }
  let(:body)    { { client_id: 'a', client_secret: 'b', grant_type: 'client_credentials' } }
  let(:fresh_response) do
    instance_double(
      Faraday::Response,
      status: 200,
      body: { access_token: 'AT-1', expires_in: 3600, token_type: 'bearer' }.to_json,
      headers: {},
    )
  end

  before { allow(context).to receive(:http_post).and_return(fresh_response) }

  def with_env(key, value)
    saved = ENV.fetch(key, :__unset)
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    saved == :__unset ? ENV.delete(key) : ENV[key] = saved
  end

  def suppress_reschedule
    yield
  rescue IPaaS::Job::RescheduleJob
    nil
  end

  describe '#oauth2_authorization_header' do
    it 'returns a cached header without calling the token endpoint' do
      context.oauth2_authorization_header(url, body)
      allow(context).to receive(:http_post).and_raise('should not be called')
      expect(context.oauth2_authorization_header(url, body)).to eq('Bearer AT-1')
    end

    it 'wraps the refresh in with_lock with a connection-scoped key and TTL' do
      lock_calls = []
      allow(context).to receive(:with_lock).and_wrap_original do |orig, key, **opts, &blk|
        lock_calls << [key, opts]
        orig.call(key, **opts, &blk)
      end
      context.oauth2_authorization_header(url, body)
      expect(lock_calls.size).to eq(1)
      key, opts = lock_calls.first
      expect(key).to start_with('oauth2:').and end_with(':refresh')
      expect(opts).to include(ttl: IPaaS::Job::Lock::DEFAULT_TTL_SECONDS)
    end

    it 'uses a lock key distinct from the cache key' do
      cache_key = context.send(:create_cache_key, url, body)
      lock_key  = context.send(:oauth2_lock_key, url, body)
      expect(lock_key).not_to eq(cache_key)
    end

    it 'derives distinct lock keys per connection (different body hashes to different keys)' do
      lock_key_a = context.send(:oauth2_lock_key, url, body)
      lock_key_b = context.send(:oauth2_lock_key, url, body.merge(client_id: 'different'))
      expect(lock_key_a).not_to eq(lock_key_b)
    end

    it 'returns the peer-written cached header on retry without calling http_post' do
      cache_key = context.send(:create_cache_key, url, body)
      context.cache_write(cache_key, 'Bearer AT-peer', 60)
      expect(context).not_to receive(:http_post)
      expect(context.oauth2_authorization_header(url, body)).to eq('Bearer AT-peer')
    end

    it 'does not write to the cache when http_post raises' do
      allow(context).to receive(:http_post).and_raise(IPaaS::Error, 'idp down')
      expect(context).not_to receive(:cache_write)
      expect { context.oauth2_authorization_header(url, body) }.to raise_error(IPaaS::Error, /idp down/)
    end

    it 'releases the lock on failure so the next caller can refresh' do
      allow(context).to receive(:http_post).and_raise(IPaaS::Error, 'idp down')
      expect { context.oauth2_authorization_header(url, body) }.to raise_error(IPaaS::Error)
      allow(context).to receive(:http_post).and_return(fresh_response)
      expect(context.oauth2_authorization_header(url, body)).to eq('Bearer AT-1')
    end

    it 'caches with expires_in minus REFRESH_OPEN_TIMEOUT' do
      Timecop.freeze do
        context.oauth2_authorization_header(url, body)
        within = (3600 - IPaaS::Job::Outbound::OAuth2::REFRESH_OPEN_TIMEOUT - 1).seconds
        beyond = (3600 - IPaaS::Job::Outbound::OAuth2::REFRESH_OPEN_TIMEOUT + 1).seconds
        Timecop.travel(within.from_now) do
          allow(context).to receive(:http_post).and_raise('should not be called')
          expect(context.oauth2_authorization_header(url, body)).to eq('Bearer AT-1')
        end
        Timecop.travel(beyond.from_now) do
          allow(context).to receive(:http_post).and_return(fresh_response)
          context.oauth2_authorization_header(url, body)
        end
      end
    end

    it 'returns the inner double-checked cached header without calling http_post when a peer wrote during the wait' do
      allow(context.locker).to receive(:try_acquire) do |*|
        context.cache_write(context.send(:create_cache_key, url, body), 'Bearer AT-peer', 60)
        SecureRandom.uuid
      end
      expect(context).not_to receive(:http_post)
      expect(context.oauth2_authorization_header(url, body)).to eq('Bearer AT-peer')
    end

    it 'releases the lock even when the inner double-check finds a peer-written cache' do
      release_spy = 0
      allow(context.locker).to receive(:release).and_wrap_original { |orig, *a|
        release_spy += 1
        orig.call(*a)
      }
      context.oauth2_authorization_header(url, body)
      expect(release_spy).to eq(1)
    end

    shared_examples 'fails closed by rescheduling without side effects' do |expected_retry_after:, expected_jitter:|
      it 'raises RescheduleJob with delay in [base, base+jitter]' do
        expect { context.oauth2_authorization_header(url, body) }
          .to raise_error(IPaaS::Job::RescheduleJob) do |e|
            expect(e.reschedule_after - Time.current)
              .to be_between(expected_retry_after - 0.5, expected_retry_after + expected_jitter + 0.5)
          end
      end

      it 'does not call http_post' do
        expect(context).not_to receive(:http_post)
        suppress_reschedule { context.oauth2_authorization_header(url, body) }
      end

      it 'does not write to the cache' do
        expect(context).not_to receive(:cache_write)
        suppress_reschedule { context.oauth2_authorization_header(url, body) }
      end
    end

    context 'when the lock is contended (peer holds it)' do
      before { allow(context.locker).to receive(:try_acquire).and_return(nil) }
      include_examples 'fails closed by rescheduling without side effects',
                       expected_retry_after: IPaaS::Job::Lock::RETRY_AFTER_CONTENTION.to_f,
                       expected_jitter: IPaaS::Job::Lock::RETRY_AFTER_CONTENTION_JITTER.to_f
    end

    context 'when the locker is unavailable (Redis outage simulated)' do
      before do
        allow(context.locker).to receive(:try_acquire)
          .and_raise(IPaaS::Job::LockerUnavailable, 'redis down')
      end
      include_examples 'fails closed by rescheduling without side effects',
                       expected_retry_after: IPaaS::Job::Lock::RETRY_AFTER_OUTAGE.to_f,
                       expected_jitter: IPaaS::Job::Lock::RETRY_AFTER_OUTAGE_JITTER.to_f
    end

    it 'does not clobber a peer-written cache after our lock TTL elapsed (compare-and-write)' do
      peer_value = 'Bearer AT-peer'
      allow(context).to receive(:write_if_lock_held).and_wrap_original do |_orig, *args|
        store_key = args[2]
        context.cache_write(store_key, peer_value, 60)
        false
      end
      context.oauth2_authorization_header(url, body)
      cache_key = context.send(:create_cache_key, url, body)
      expect(context.cache_read(cache_key)).to eq(peer_value)
    end
  end

  describe 'kill-switch path' do
    it 'bypasses with_lock entirely when OAUTH2_SINGLEFLIGHT_DISABLED=1' do
      with_env('OAUTH2_SINGLEFLIGHT_DISABLED', '1') do
        expect(context).not_to receive(:with_lock)
        expect(context).not_to receive(:write_if_lock_held)
        expect(context).to receive(:cache_write).with(an_instance_of(String), 'Bearer AT-1', anything)
        context.oauth2_authorization_header(url, body)
      end
    end

    it 'returns the cached header on the second call without hitting the IdP again' do
      with_env('OAUTH2_SINGLEFLIGHT_DISABLED', '1') do
        context.oauth2_authorization_header(url, body)
        allow(context).to receive(:http_post).and_raise('should not be called')
        expect(context.oauth2_authorization_header(url, body)).to eq('Bearer AT-1')
      end
    end

    it 'uses with_lock normally when the env var is unset' do
      with_env('OAUTH2_SINGLEFLIGHT_DISABLED', nil) do
        expect(context).to receive(:with_lock).and_call_original
        context.oauth2_authorization_header(url, body)
      end
    end
  end

  describe 'observability for residual TOCTOU' do
    it 'logs oauth2.lock.compare_and_write_lost when ownership was lost before write' do
      allow(context).to receive(:write_if_lock_held).and_return(false)
      expect(context).to receive(:log).with(/\Aoauth2\.lock\.compare_and_write_lost/).and_call_original
      expect(context).not_to receive(:log).with(/\Aoauth2\.lock\.lost_after_write/)
      context.oauth2_authorization_header(url, body)
    end

    it 'logs oauth2.lock.lost_after_write when ownership was lost during the cache write' do
      allow(context).to receive(:write_if_lock_held).and_return(true)
      allow(context.locker).to receive(:compare_and_call).and_return(false)
      expect(context).to receive(:log).with(/\Aoauth2\.lock\.lost_after_write/).and_call_original
      context.oauth2_authorization_header(url, body)
    end

    it 'logs neither line on the happy path' do
      allow(context).to receive(:write_if_lock_held).and_return(true)
      allow(context.locker).to receive(:compare_and_call).and_return(true)
      expect(context).not_to receive(:log).with(/oauth2\.lock\.(?:compare_and_write_lost|lost_after_write)/)
      context.oauth2_authorization_header(url, body)
    end

    it 'emits only the lock_key_sha prefix when ownership is lost — never URL, body, or secret fields' do
      allow(context).to receive(:write_if_lock_held).and_return(false)
      sensitive_body = body.merge(client_secret: 'SHOULD-NOT-LEAK', refresh_token: 'SHOULD-NOT-LEAK-RT')
      received = nil
      allow(context).to receive(:log) { |line| received = line }
      context.oauth2_authorization_header(url, sensitive_body)
      expect(received).not_to include('SHOULD-NOT-LEAK')
      expect(received).not_to include('SHOULD-NOT-LEAK-RT')
      expect(received).not_to include(url)
      expect(received).to match(/lock_key_sha=[0-9a-f]{8}/)
    end
  end

  describe 'action-time budget guard' do
    it 'keeps REFRESH_TIMEOUT < LOCK_TTL_SECONDS so the holder cannot outlive its lock' do
      expect(IPaaS::Job::Outbound::OAuth2::REFRESH_TIMEOUT)
        .to be < IPaaS::Job::Outbound::OAuth2::LOCK_TTL_SECONDS
    end
  end

  describe 'request body must not appear in error path' do
    it 'never includes client_secret or refresh_token from the request body in the error message' do
      bad_response = instance_double(Faraday::Response, status: 401, headers: {}, body: 'nope')
      allow(context).to receive(:http_post).and_return(bad_response)
      sensitive_body = body.merge(
        client_secret: 'SHOULD-NOT-LEAK-SECRET',
        refresh_token: 'SHOULD-NOT-LEAK-REFRESH-TOKEN',
      )
      expect { context.oauth2_authorization_header(url, sensitive_body) }
        .to raise_error(IPaaS::Error) do |e|
          expect(e.message).not_to include('SHOULD-NOT-LEAK-SECRET')
          expect(e.message).not_to include('SHOULD-NOT-LEAK-REFRESH-TOKEN')
        end
    end
  end

  describe 'token-endpoint HTTP status classification' do
    def stub_token_response(status:, body:, headers: {})
      response = instance_double(Faraday::Response, status: status, headers: headers, body: body)
      allow(context).to receive(:http_post).and_return(response)
    end

    shared_examples 'raises CustomerCredentialsError' do |expected_reason_match|
      it 'raises CustomerCredentialsError with the IdP host' do
        expect { context.oauth2_authorization_header(url, body) }
          .to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError) { |e| expect(e.host).to eq('idp.example.com') }
      end

      it 'sets the reason from the OAuth2 error fields' do
        expect { context.oauth2_authorization_header(url, body) }
          .to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError) { |e| expect(e.reason).to match(expected_reason_match) }
      end
    end

    shared_examples 'raises plain IPaaS::Error' do
      it 'raises a non-CustomerCredentialsError IPaaS::Error' do
        expect { context.oauth2_authorization_header(url, body) }
          .to raise_error(IPaaS::Error) { |e| expect(e).not_to be_a(IPaaS::Job::Outbound::CustomerCredentialsError) }
      end
    end

    context 'when the IdP returns 400 with invalid_grant' do
      before do
        stub_token_response(
          status: 400,
          body: { error: 'invalid_grant', error_description: 'Invalid client credentials' }.to_json,
        )
      end

      include_examples 'raises CustomerCredentialsError', /invalid_grant.*Invalid client credentials/
    end

    context 'when the IdP returns 400 with invalid_client' do
      before { stub_token_response(status: 400, body: { error: 'invalid_client' }.to_json) }
      include_examples 'raises CustomerCredentialsError', /\Ainvalid_client\z/
    end

    context 'when the IdP returns 400 with unauthorized_client' do
      before { stub_token_response(status: 400, body: { error: 'unauthorized_client' }.to_json) }
      include_examples 'raises CustomerCredentialsError', /unauthorized_client/
    end

    context 'when the IdP returns 400 with invalid_scope' do
      before do
        stub_token_response(
          status: 400,
          body: { error: 'invalid_scope', error_description: 'AADSTS70011: The provided scope is not valid' }.to_json,
        )
      end

      include_examples 'raises CustomerCredentialsError', /invalid_scope.*AADSTS70011/
    end

    context 'when the IdP returns 400 with invalid_request (generic, not a credentials error)' do
      before do
        stub_token_response(
          status: 400,
          body: { error: 'invalid_request', error_description: "AADSTS900144: missing 'scope'" }.to_json,
        )
      end

      include_examples 'raises plain IPaaS::Error'
    end

    context 'when the IdP returns 400 with unsupported_grant_type (not a credentials error)' do
      before { stub_token_response(status: 400, body: { error: 'unsupported_grant_type' }.to_json) }
      include_examples 'raises plain IPaaS::Error'
    end

    context 'when the IdP returns 400 with a non-JSON body' do
      before { stub_token_response(status: 400, body: '<html>oops</html>') }
      include_examples 'raises plain IPaaS::Error'
    end

    context 'when the IdP returns 401 with no parseable error fields' do
      before { stub_token_response(status: 401, body: 'authentication failed: token expired') }

      it 'logs minimal information as this should not happen according to spec' do
        expect { context.oauth2_authorization_header(url, body) }
          .to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError) do |e|
            expect(e.host).to eq('idp.example.com')
            expect(e.reason).to eq('HTTP 401')
          end
      end
    end

    context 'when the IdP returns 403' do
      before { stub_token_response(status: 403, body: { error: 'forbidden' }.to_json) }
      include_examples 'raises CustomerCredentialsError', /forbidden/
    end

    context 'when the IdP returns 403 with no parseable error fields' do
      before { stub_token_response(status: 403, body: 'authentication failed: token expired') }

      it 'logs minimal information as this should not happen according to spec' do
        expect { context.oauth2_authorization_header(url, body) }
          .to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError) do |e|
          expect(e.host).to eq('idp.example.com')
          expect(e.reason).to eq('HTTP 403')
        end
      end
    end

    context 'when the IdP returns 500' do
      before { stub_token_response(status: 500, body: 'boom') }
      include_examples 'raises plain IPaaS::Error'
    end

    context 'message sanitization' do
      let(:noisy_headers) do
        { 'set-cookie' => 'SHOULD-NOT-APPEAR=1', 'content-security-policy' => 'SHOULD-NOT-APPEAR-CSP' }
      end
      let(:noisy_body) do
        { error: 'invalid_grant', error_description: 'bad creds', extra: 'SHOULD-NOT-APPEAR-EXTRA' }.to_json
      end

      before { stub_token_response(status: 400, body: noisy_body, headers: noisy_headers) }

      it 'omits response headers from the error message' do
        expect { context.oauth2_authorization_header(url, body) }
          .to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError) { |e| expect(e.message).not_to include('SHOULD-NOT-APPEAR') }
      end

      it 'omits unrelated response body fields from the error message' do
        expect { context.oauth2_authorization_header(url, body) }
          .to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError) { |e| expect(e.message).not_to include('SHOULD-NOT-APPEAR-EXTRA') }
      end
    end
  end

  describe 'token-response body classification (HTTP 200)' do
    def stub_token_response(body)
      response = instance_double(Faraday::Response, status: 200, headers: {}, body: body)
      allow(context).to receive(:http_post).and_return(response)
    end

    context 'when the response is missing access_token (server protocol violation)' do
      before { stub_token_response({ token_type: 'bearer' }.to_json) }

      it 'raises a plain IPaaS::Error so the malformed response stays loud' do
        expect { context.oauth2_authorization_header(url, body) }
          .to raise_error(IPaaS::Error, 'Unable to authenticate, no access_token found') do |e|
            expect(e).not_to be_a(IPaaS::Job::Outbound::CustomerCredentialsError)
          end
      end
    end

    context 'when the response uses an unsupported token_type' do
      before { stub_token_response({ token_type: 'mac', access_token: 'AT' }.to_json) }

      it 'raises a plain IPaaS::Error (not a CustomerCredentialsError)' do
        expect { context.oauth2_authorization_header(url, body) }
          .to raise_error(IPaaS::Error) { |e| expect(e).not_to be_a(IPaaS::Job::Outbound::CustomerCredentialsError) }
      end
    end

    context 'when the response carries a valid bearer token (contrast)' do
      before { stub_token_response({ access_token: 'AT-OK', token_type: 'bearer', expires_in: 3600 }.to_json) }

      it 'returns the Bearer header without raising' do
        expect(context.oauth2_authorization_header(url, body)).to eq('Bearer AT-OK')
      end
    end
  end
end
