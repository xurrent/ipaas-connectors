require 'spec_helper'

describe IPaaS::Job::JWT do
  class TestContext
    include IPaaS::Job::JWT
  end

  let(:context) { TestContext.new }

  es256_pem =
    {
      private: <<~PEM,
        -----BEGIN EC PRIVATE KEY-----
        MHcCAQEEIC3e4UdeURm/xjcTTR0Y1poOYLHk286Vww/Mb76/rn2AoAoGCCqGSM49
        AwEHoUQDQgAEtG7reYmvMm5Wt5zcIuDNqZkZMnbvWO3OBRDR1w+psk4AAGAp3zYs
        p2ylkDqdLMcKXgMBSxAWCoX6LiC3dmHj4A==
        -----END EC PRIVATE KEY-----
      PEM
      public: <<~PEM,
        -----BEGIN PUBLIC KEY-----
        MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEtG7reYmvMm5Wt5zcIuDNqZkZMnbv
        WO3OBRDR1w+psk4AAGAp3zYsp2ylkDqdLMcKXgMBSxAWCoX6LiC3dmHj4A==
        -----END PUBLIC KEY-----
      PEM
    }

  rs256_pem =
    {
      private: <<~PEM,
        -----BEGIN RSA PRIVATE KEY-----
        MIIEogIBAAKCAQEAhc5ADYY1C9sRJfTvkmC3XHuBorC+Du+giNLIm9vQ7sX+B1GF
        qXd73FUImNE5yF54EBm0JLs6XePaeGQSQ3x4KQOaVrDR4ELRGOxdyczjHm9Vu7rg
        7GJg1gZgDIDsKoHIQ46/gbTUFpk8IquAMMQj9ASgC4t/fSpP7eqIUw0o6LvbLd0l
        AgiLmRhheeNG4AIFcF02TxfZRgzuUl711dIDfdQqLDpzAeD9fX88D105BSP780/6
        WXnqquszKl3Na2rePpPkZVN5JbvJQ/8IxmN9NqZBb2UjsbhrPo77qT/8NLOQg23R
        17L5v8WdcfQyC0M8TJ+S7kRP+OZ6PxUn3zHmgwIDAQABAoIBAD9mOQJPd139OBRY
        iJU+X1MiMAvym7M/Bj0eRrBWyJoCVTmJfoAMHbOJ1O93n13ZqSDT1P/ceKzZFACc
        Re0VEmg4jU4LLP6KGkIpaMz/2BNpJGG1i/JlMMXoMmVqRrxjTwz3m7TtBdsJUy2I
        Pk6c+P4bnOurdsZLIKE10c8sOph/Dtd+hz4EvCXibHvZsVpRqHjbUwhnAbnc4OoX
        SSVIJNKltyYvejmSy7vuKiNMs6FWTURRlnvcp3Jlmh2Zr6I/uj7eTrMippbUpRO9
        5bOxMtHXMaFD+hU9S0ZVzZO/lqcUeMP88S4uC758j9P9K52cXELmMOcyif6Zy/im
        zftJLUkCgYEAuolnA9McPx3rWrX3D373+BSIIMOAQWpLyZd1rOuZOXo7PJhr54Mf
        VEdD6UYtsmR/7Dko20Ct6jhhgAcBTdnmd0UUjnjFS+mdP5lI2zweXIlz2iwhDPVW
        DXXCLzlql3jgN4hPt8nopKHtFnu7Sn4JWx4UV9zJyZW+5NaCKuREbosCgYEAt6H7
        JXHyogqlvNeiBqXoAoesC8H2MXavXe2OqNna2t3hWqoGDI9uFXeoY1+RUWlYF1bv
        rWk93/+KXg+6yMB6DDXaH43+HP+MRYrqEiPd4e0eD7CrH/afIR+KKHk9HQVexN0U
        F5AqNCsz7lviazt+h4EjR0IS7p3J1MK+8uN/HukCgYBzZwg9XIEQJ1Fw2DyV8KY2
        a3VgV7LkRX/HoxVhOoyb+5vkPCQdoYhjWoeQLSOeRwDBQwecxWITEnh3fV34LQOg
        7DLwhZUCBvCK5SkmwQXDmCH9aumzm6B2SVEuaCYiudx1XrZ67MYp/Ceyji/rwRfG
        sFBDn0uTlDn6Vx9Gq9wOSwKBgBReFgIYOmY4shtY+3KrUil9rNp8//aKiHbtk2Yt
        C7Y85/LratJX0kj1RasH/ZE/EvM7xEfCpYdDy7AVJI2Bs8fI7VGUqTvEKGXKO54Z
        dlHJwAzTdpeL/ihpXCSTFfEzGEjTkJfweI3iwNbOQDXOmoEjFKuhq4Hl5G4Bz7YW
        /5GJAoGAe/QYzBap7gvfMRpskvTObSfXy0TVRWNgwoNpRVoIQFTjO2VIXtwgy93s
        oZMorBiU3Cv0ibGBKLXbYhSTvz9CuUqlFcTr7n0DHaliyQ4FEkLvgO4OLXolyuXt
        t8HNLl5A89KHrOlCbJDRLKdC4yRoVeFUI5ONay2QFb5c4Nnqz4U=
        -----END RSA PRIVATE KEY-----
      PEM
      public: <<~PEM,
        -----BEGIN PUBLIC KEY-----
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAhc5ADYY1C9sRJfTvkmC3
        XHuBorC+Du+giNLIm9vQ7sX+B1GFqXd73FUImNE5yF54EBm0JLs6XePaeGQSQ3x4
        KQOaVrDR4ELRGOxdyczjHm9Vu7rg7GJg1gZgDIDsKoHIQ46/gbTUFpk8IquAMMQj
        9ASgC4t/fSpP7eqIUw0o6LvbLd0lAgiLmRhheeNG4AIFcF02TxfZRgzuUl711dID
        fdQqLDpzAeD9fX88D105BSP780/6WXnqquszKl3Na2rePpPkZVN5JbvJQ/8IxmN9
        NqZBb2UjsbhrPo77qT/8NLOQg23R17L5v8WdcfQyC0M8TJ+S7kRP+OZ6PxUn3zHm
        gwIDAQAB
        -----END PUBLIC KEY-----
      PEM
    }

  describe 'jwk_to_pem' do
    it 'returns a PEM for a well-formed EC JWK' do
      jwk = JWT::JWK.new(OpenSSL::PKey::EC.new(es256_pem[:public]), { kid: 'k' }).export
      expect(IPaaS::Job::JWT.jwk_to_pem(jwk)).to include('BEGIN PUBLIC KEY')
    end

    context 'when the JWK is malformed (JWT::JWKError)' do
      it 'raises IPaaS::Error when kty is missing' do
        expect { IPaaS::Job::JWT.jwk_to_pem({}) }
          .to raise_error(IPaaS::Error, /Invalid JWK: Key type \(kty\) not provided/)
      end

      it 'raises IPaaS::Error when kty is unsupported' do
        expect { IPaaS::Job::JWT.jwk_to_pem({ 'kty' => 'unknown' }) }
          .to raise_error(IPaaS::Error, /Invalid JWK: Key type unknown not supported/)
      end

      it 'raises IPaaS::Error when an EC JWK is missing crv/x/y' do
        expect { IPaaS::Job::JWT.jwk_to_pem({ 'kty' => 'EC' }) }
          .to raise_error(IPaaS::Error, /Invalid JWK: Key format is invalid for EC/)
      end
    end

    context 'when the JWK params are cryptographically invalid (OpenSSL::OpenSSLError)' do
      it 'raises IPaaS::Error for an EC JWK whose x/y do not form a valid point' do
        expect do
          IPaaS::Job::JWT.jwk_to_pem({ 'kty' => 'EC', 'crv' => 'P-256', 'x' => 'AAAA', 'y' => 'AAAA' })
        end.to raise_error(IPaaS::Error, /Invalid JWK:/)
      end
    end
  end

  describe 'pem_valid?' do
    it 'detects bad rsa256' do
      expect(IPaaS::Job::JWT.pem_valid?('RSA256', 'abc')).to eq(false)
    end

    it 'allows good rsa256' do
      expect(IPaaS::Job::JWT.pem_valid?('RSA256', rs256_pem[:private])).to eq(true)
      expect(IPaaS::Job::JWT.pem_valid?('RSA256', rs256_pem[:public])).to eq(true)
    end

    it 'detects bad es256' do
      expect(IPaaS::Job::JWT.pem_valid?('ES256', 'abc')).to eq(false)
    end

    it 'allows good es256' do
      expect(IPaaS::Job::JWT.pem_valid?('ES256', es256_pem[:private])).to eq(true)
      expect(IPaaS::Job::JWT.pem_valid?('ES256', es256_pem[:public])).to eq(true)
    end
  end

  describe 'make_jwt_payload' do
    it 'makes a payload without additional claims' do
      expect(SecureRandom).to receive(:hex).with(32).and_return('random')

      payload = context.make_jwt_payload(issuer_claim: 'abc', subject_claim: 'foo')
      expect(payload.keys).to contain_exactly(:iss, :iat, :jti, :nbf, :sub)
      expect(payload[:iss]).to eq('abc')
      expect(payload[:sub]).to eq('foo')
      expect(payload[:jti]).to eq('random')
      nbf = payload[:nbf]
      expect(payload[:iat]).to eq(nbf)
    end

    it 'makes a payload with audience claim' do
      expect(SecureRandom).to receive(:hex).with(32).and_return('random2')

      payload = context.make_jwt_payload(issuer_claim: 'abc', subject_claim: 'foo', audience_claim: 'my peeps')
      expect(payload.keys).to contain_exactly(:iss, :iat, :jti, :nbf, :sub, :aud)
      expect(payload[:iss]).to eq('abc')
      expect(payload[:sub]).to eq('foo')
      expect(payload[:jti]).to eq('random2')
      expect(payload[:aud]).to eq('my peeps')
      nbf = payload[:nbf]
      expect(payload[:iat]).to eq(nbf)
    end

    it 'makes a payload with expiry claim' do
      expect(SecureRandom).to receive(:hex).with(32).and_return('random3')

      payload = context.make_jwt_payload(issuer_claim: 'abc', subject_claim: 'foo', expiration_time_claim: 10.minutes)
      expect(payload.keys).to contain_exactly(:iss, :iat, :jti, :nbf, :sub, :exp)
      expect(payload[:iss]).to eq('abc')
      expect(payload[:sub]).to eq('foo')
      expect(payload[:jti]).to eq('random3')
      nbf = payload[:nbf]
      expect(payload[:iat]).to eq(nbf)
      expect(payload[:exp]).to eq(nbf + 600)
    end

    it 'makes a payload with extra claims' do
      expect(SecureRandom).to receive(:hex).with(32).and_return('random4')

      payload = context.make_jwt_payload(issuer_claim: 'abc', subject_claim: 'foo', data: { foo: :bar }, baz: 2)
      expect(payload.keys).to contain_exactly(:iss, :iat, :jti, :nbf, :sub, :data, :baz)
      expect(payload[:iss]).to eq('abc')
      expect(payload[:sub]).to eq('foo')
      expect(payload[:jti]).to eq('random4')
      nbf = payload[:nbf]
      expect(payload[:iat]).to eq(nbf)
      expect(payload[:baz]).to eq(2)
      expect(payload[:data]).to eq({ foo: :bar })
    end
  end

  describe 'encode/decode jwt' do
    {
      'ES256' => es256_pem,
      'RS256' => rs256_pem,
    }.each do |algorithm, pem|
      it "can encode and decode #{algorithm}" do
        payload = context.make_jwt_payload(issuer_claim: 'abc',
                                           subject_claim: 'a',
                                           audience_claim: 'foo',
                                           data: { foo: :bar },)

        jwt = context.encode_jwt(payload, pem: pem[:private], algorithm: algorithm)
        decoded = context.decode_jwt!(jwt, pem: pem[:public], algorithm: algorithm, issuer: 'abc', audience: 'foo')
        expect(decoded[:payload]).to eq(JSON.parse(payload.to_json))
        expect(decoded[:header]).to eq({ 'alg' => algorithm, 'typ' => 'JWT' })
      end
    end

    it 'detects incorrect audience' do
      payload = context.make_jwt_payload(issuer_claim: 'abc',
                                         subject_claim: 'a',
                                         audience_claim: 'foo',
                                         data: { foo: :bar },)

      jwt = context.encode_jwt(payload, pem: rs256_pem[:private], algorithm: 'RS256')
      expect do
        context.decode_jwt!(jwt, pem: rs256_pem[:public], algorithm: 'RS256', issuer: 'abc', audience: 'foo2')
      end.to raise_error(IPaaS::Error, 'Unable to decode JWT: Invalid audience. Expected foo2, received foo')
    end

    it 'detects incorrect issuer' do
      payload = context.make_jwt_payload(issuer_claim: 'abc1',
                                         subject_claim: 'a',
                                         audience_claim: 'foo',
                                         data: { foo: :bar },)

      jwt = context.encode_jwt(payload, pem: rs256_pem[:private], algorithm: 'RS256')
      expect do
        context.decode_jwt!(jwt, pem: rs256_pem[:public], algorithm: 'RS256', issuer: 'abc', audience: 'foo')
      end.to raise_error(IPaaS::Error, 'Unable to decode JWT: Invalid issuer. Expected ["abc"], received abc1')
    end

    it 'detects incorrect signature' do
      payload = context.make_jwt_payload(issuer_claim: 'abc',
                                         subject_claim: 'a',
                                         audience_claim: 'foo',
                                         data: { foo: :bar },)

      jwt = context.encode_jwt(payload, pem: rs256_pem[:private], algorithm: 'RS256')
      expect do
        context.decode_jwt!(jwt, pem: rs256_pem[:public].sub('QAB', 'BAQ'), algorithm: 'RS256', issuer: 'abc',
                                 audience: 'foo')
      end.to raise_error(IPaaS::Error, 'Unable to decode JWT: Signature verification failed')
    end

    it 'detects incorrect RSA public key' do
      payload = context.make_jwt_payload(issuer_claim: 'abc',
                                         subject_claim: 'a')

      jwt = context.encode_jwt(payload, pem: rs256_pem[:private], algorithm: 'RS256')
      expect do
        context.decode_jwt!(jwt, pem: rs256_pem[:public].delete("\n"), algorithm: 'RS256', issuer: 'abc')
      end.to raise_error(IPaaS::Error, 'Invalid PEM')
    end

    it 'detects incorrect ES public key' do
      payload = context.make_jwt_payload(issuer_claim: 'abc',
                                         subject_claim: 'a')

      jwt = context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
      expect do
        context.decode_jwt!(jwt, pem: es256_pem[:public].delete("\n"), algorithm: 'ES256', issuer: 'abc')
      end.to raise_error(IPaaS::Error, 'Invalid PEM')
    end

    it 'detects incorrect RSA private key' do
      payload = context.make_jwt_payload(issuer_claim: 'abc',
                                         subject_claim: 'a')

      expect do
        context.encode_jwt(payload, pem: rs256_pem[:private].delete("\n"), algorithm: 'RS256')
      end.to raise_error(IPaaS::Error, 'Invalid PEM')
    end

    it 'detects incorrect ES private key' do
      payload = context.make_jwt_payload(issuer_claim: 'abc',
                                         subject_claim: 'a')

      expect do
        context.encode_jwt(payload, pem: es256_pem[:private].delete("\n"), algorithm: 'ES256')
      end.to raise_error(IPaaS::Error, 'Invalid PEM')
    end

    it 'detects Issued At Claim drift' do
      Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 +01:00'))
      [2.minutes.ago, 2.minutes.from_now].each do |time|
        payload = context.make_jwt_payload(issuer_claim: 'abc',
                                           subject_claim: 'a',
                                           audience_claim: 'foo',
                                           iat: time.to_i,
                                           data: { foo: :bar },)

        jwt = context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
        expect do
          context.decode_jwt!(jwt, pem: es256_pem[:public], algorithm: 'ES256', issuer: 'abc', audience: 'foo')
        end.to raise_error(IPaaS::Error, 'Issued At claim too far from current time 1445412000')
      end
    end

    it 'detects missing Issued At Claim' do
      payload = context.make_jwt_payload(issuer_claim: 'abc',
                                         subject_claim: 'a',
                                         audience_claim: 'foo',
                                         data: { foo: :bar },)
      payload.delete(:iat)

      jwt = context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
      decoded = context.decode_jwt!(jwt, pem: es256_pem[:public], algorithm: 'ES256', issuer: 'abc', audience: 'foo',)
      expect(decoded[:payload]).to eq(JSON.parse(payload.to_json))

      expect do
        context.decode_jwt!(jwt, pem: es256_pem[:public], algorithm: 'ES256', issuer: 'abc', audience: 'foo',
                                 validate_iat: :always)
      end.to raise_error(IPaaS::Error, 'Issued At claim not present in token')
    end

    it 'detects missing JWT ID claim' do
      payload = context.make_jwt_payload(issuer_claim: 'abc',
                                         subject_claim: 'a',
                                         audience_claim: 'foo',
                                         data: { foo: :bar },)
      payload.delete(:jti)

      jwt = context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
      decoded = context.decode_jwt!(jwt, pem: es256_pem[:public], algorithm: 'ES256', issuer: 'abc', audience: 'foo',)
      expect(decoded[:payload]).to eq(JSON.parse(payload.to_json))

      expect do
        context.decode_jwt!(jwt, pem: es256_pem[:public], algorithm: 'ES256', issuer: 'abc', audience: 'foo',
                                 validate_jti: :always)
      end.to raise_error(IPaaS::Error, 'JWT ID claim not present in token')
    end

    it 'detects JWT ID claim that is too long' do
      payload = context.make_jwt_payload(issuer_claim: 'abc',
                                         subject_claim: 'a',
                                         audience_claim: 'foo',
                                         jti: 'a' * 300,
                                         data: { foo: :bar },)

      jwt = context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
      expect do
        context.decode_jwt!(jwt, pem: es256_pem[:public], algorithm: 'ES256', issuer: 'abc', audience: 'foo')
      end.to raise_error(IPaaS::Error, 'JWT ID claim too long')
    end

    it 'detects JWT ID claim reuse' do
      payload = context.make_jwt_payload(issuer_claim: 'abc',
                                         subject_claim: 'a',
                                         audience_claim: 'foo',
                                         data: { foo: :bar },)

      jwt = context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
      decoded = context.decode_jwt!(jwt, pem: es256_pem[:public], algorithm: 'ES256', issuer: 'abc', audience: 'foo')
      expect(decoded[:payload]).to eq(JSON.parse(payload.to_json))

      expect do
        context.decode_jwt!(jwt, pem: es256_pem[:public], algorithm: 'ES256', issuer: 'abc', audience: 'foo')
      end.to raise_error(IPaaS::Error, 'JWT ID claim invalid')
    end

    it 'uses the given cache when validating JWT ID claim' do
      payload = context.make_jwt_payload(issuer_claim: 'abc',
                                         subject_claim: 'a',
                                         audience_claim: 'foo',
                                         data: { foo: :bar },)

      cache1 = ActiveSupport::Cache::MemoryStore.new
      cache2 = ActiveSupport::Cache::MemoryStore.new

      jwt = context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
      decoded = context.decode_jwt!(jwt, pem: es256_pem[:public], algorithm: 'ES256', issuer: 'abc', audience: 'foo',
                                         jti_cache: cache1)
      expect(decoded[:payload]).to eq(JSON.parse(payload.to_json))

      # Same cache: reused JWT ID claim can be detected
      expect do
        context.decode_jwt!(jwt, pem: es256_pem[:public], algorithm: 'ES256', issuer: 'abc', audience: 'foo',
                                 jti_cache: cache1)
      end.to raise_error(IPaaS::Error, 'JWT ID claim invalid')

      # Different cache: reused JWT ID claim cannot be detected
      decoded = context.decode_jwt!(jwt, pem: es256_pem[:public], algorithm: 'ES256', issuer: 'abc', audience: 'foo',
                                         jti_cache: cache2)
      expect(decoded[:payload]).to eq(JSON.parse(payload.to_json))
    end
  end

  describe 'decode_jwt! OIDC extensions' do
    let(:default_iss) { 'https://wdc.test.host/policy' }
    let(:default_prefix) { 'https://wdc.test.host' }
    let(:default_payload) do
      context.make_jwt_payload(issuer_claim: default_iss, subject_claim: 'sub')
    end
    let(:default_jwt) do
      context.encode_jwt(default_payload, pem: es256_pem[:private], algorithm: 'ES256')
    end

    describe 'algorithm_allowlist' do
      it 'decodes when header alg is in allowlist' do
        decoded = context.decode_jwt!(default_jwt,
                                      algorithm_allowlist: %w[ES256 RS256],
                                      pem: es256_pem[:public], issuer: default_iss)
        expect(decoded[:header]['alg']).to eq('ES256')
        expect(decoded[:payload]['sub']).to eq('sub')
      end

      it 'rejects header alg not in allowlist' do
        expect do
          context.decode_jwt!(default_jwt,
                              algorithm_allowlist: %w[RS256],
                              pem: es256_pem[:public], issuer: default_iss)
        end.to raise_error(IPaaS::Error, "Unsupported JWT algorithm 'ES256'")
      end

      it 'lets explicit algorithm override allowlist' do
        decoded = context.decode_jwt!(default_jwt,
                                      algorithm: 'ES256',
                                      algorithm_allowlist: %w[RS256],
                                      pem: es256_pem[:public], issuer: default_iss)
        expect(decoded[:header]['alg']).to eq('ES256')
      end

      it 'allows the no-verify path when neither algorithm nor key is given' do
        decoded = context.decode_jwt!(default_jwt)
        expect(decoded[:payload]['iss']).to eq(default_iss)
      end

      it 'raises ArgumentError when pem is given without algorithm or allowlist' do
        expect do
          context.decode_jwt!(default_jwt, pem: es256_pem[:public])
        end.to raise_error(ArgumentError, /algorithm or algorithm_allowlist/)
      end

      it 'raises ArgumentError when key_resolver is given without algorithm or allowlist' do
        expect do
          context.decode_jwt!(default_jwt, key_resolver: ->(_h, _p) { es256_pem[:public] })
        end.to raise_error(ArgumentError, /algorithm or algorithm_allowlist/)
      end
    end

    describe 'issuer_prefix' do
      let(:sign_with_iss) do
        ->(iss) do
          payload = context.make_jwt_payload(issuer_claim: iss, subject_claim: 'sub')
          context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
        end
      end

      it 'decodes when iss matches prefix on scheme/host/port and path extends' do
        jwt = sign_with_iss.call("#{default_prefix}/policy/sub-path")
        decoded = context.decode_jwt!(jwt,
                                      algorithm: 'ES256', pem: es256_pem[:public],
                                      issuer_prefix: default_prefix)
        expect(decoded[:payload]['iss']).to eq("#{default_prefix}/policy/sub-path")
      end

      it 'rejects iss whose host extends the prefix host with a suffix' do
        jwt = sign_with_iss.call('https://wdc.test.host.evil.com/policy')
        expect do
          context.decode_jwt!(jwt, algorithm: 'ES256', pem: es256_pem[:public],
                                   issuer_prefix: default_prefix)
        end.to raise_error(IPaaS::Error, /Invalid issuer/)
      end

      it 'rejects iss with userinfo' do
        jwt = sign_with_iss.call('https://wdc.test.host@evil.com/policy')
        expect do
          context.decode_jwt!(jwt, algorithm: 'ES256', pem: es256_pem[:public],
                                   issuer_prefix: default_prefix)
        end.to raise_error(IPaaS::Error, /Invalid issuer/)
      end

      it 'rejects iss with http scheme when prefix is https' do
        jwt = sign_with_iss.call('http://wdc.test.host/policy')
        expect do
          context.decode_jwt!(jwt, algorithm: 'ES256', pem: es256_pem[:public],
                                   issuer_prefix: default_prefix)
        end.to raise_error(IPaaS::Error, /Invalid issuer/)
      end

      it 'rejects iss with a different port' do
        jwt = sign_with_iss.call('https://wdc.test.host:8443/policy')
        expect do
          context.decode_jwt!(jwt, algorithm: 'ES256', pem: es256_pem[:public],
                                   issuer_prefix: default_prefix)
        end.to raise_error(IPaaS::Error, /Invalid issuer/)
      end

      it 'rejects iss whose path does not extend the prefix path' do
        jwt = sign_with_iss.call('https://wdc.test.host/other')
        expect do
          context.decode_jwt!(jwt, algorithm: 'ES256', pem: es256_pem[:public],
                                   issuer_prefix: 'https://wdc.test.host/policy')
        end.to raise_error(IPaaS::Error, /Invalid issuer/)
      end

      it 'raises ArgumentError when both issuer and issuer_prefix are set' do
        expect do
          context.decode_jwt!(default_jwt,
                              algorithm: 'ES256', pem: es256_pem[:public],
                              issuer: default_iss, issuer_prefix: default_prefix)
        end.to raise_error(ArgumentError, /issuer or issuer_prefix/)
      end
    end

    describe 'key_resolver' do
      it 'decodes when resolver returns a valid PEM' do
        resolver = ->(_h, _p) { es256_pem[:public] }
        decoded = context.decode_jwt!(default_jwt,
                                      algorithm: 'ES256', key_resolver: resolver,
                                      issuer: default_iss)
        expect(decoded[:payload]['sub']).to eq('sub')
      end

      it 'is not invoked when pem: is provided' do
        resolver = double('resolver')
        expect(resolver).not_to receive(:call)
        context.decode_jwt!(default_jwt,
                            algorithm: 'ES256',
                            pem: es256_pem[:public], key_resolver: resolver,
                            issuer: default_iss)
      end

      it 'receives the unverified header and payload' do
        captured = nil
        resolver = ->(header, payload) do
          captured = [header, payload]
          es256_pem[:public]
        end
        context.decode_jwt!(default_jwt,
                            algorithm: 'ES256', key_resolver: resolver,
                            issuer: default_iss)
        expect(captured[0]).to include('alg' => 'ES256', 'typ' => 'JWT')
        expect(captured[1]['iss']).to eq(default_iss)
        expect(captured[1]['sub']).to eq('sub')
      end

      it 'is not invoked when issuer pre-check fails' do
        resolver = double('resolver')
        expect(resolver).not_to receive(:call)
        expect do
          context.decode_jwt!(default_jwt,
                              algorithm: 'ES256', key_resolver: resolver,
                              issuer_prefix: 'https://other.host')
        end.to raise_error(IPaaS::Error, /Invalid issuer/)
      end

      it 'is not invoked when timestamp pre-check fails' do
        Timecop.freeze(Time.parse('2026-01-01T00:00:00Z')) do
          payload = context.make_jwt_payload(issuer_claim: default_iss,
                                             subject_claim: 'sub',
                                             iat: 1.hour.from_now.to_i)
          jwt = context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
          resolver = double('resolver')
          expect(resolver).not_to receive(:call)
          expect do
            context.decode_jwt!(jwt,
                                algorithm: 'ES256', key_resolver: resolver,
                                issuer: default_iss)
          end.to raise_error(IPaaS::Error, /Issued At claim too far/)
        end
      end
    end

    describe 'pre-verify timestamps' do
      around do |example|
        Timecop.freeze(Time.parse('2026-01-01T00:00:00Z')) { example.run }
      end

      it 'rejects exp in the past before resolver runs' do
        payload = context.make_jwt_payload(issuer_claim: default_iss, subject_claim: 'sub',
                                           exp: 1.hour.ago.to_i)
        jwt = context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
        resolver = double('resolver')
        expect(resolver).not_to receive(:call)
        expect do
          context.decode_jwt!(jwt, algorithm: 'ES256', key_resolver: resolver, issuer: default_iss)
        end.to raise_error(IPaaS::Error, 'JWT has expired')
      end

      it 'rejects nbf in the future before resolver runs' do
        payload = context.make_jwt_payload(issuer_claim: default_iss, subject_claim: 'sub',
                                           nbf: 1.hour.from_now.to_i)
        jwt = context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
        resolver = double('resolver')
        expect(resolver).not_to receive(:call)
        expect do
          context.decode_jwt!(jwt, algorithm: 'ES256', key_resolver: resolver, issuer: default_iss)
        end.to raise_error(IPaaS::Error, 'JWT not yet valid')
      end

      it 'rejects iat far in the future before resolver runs' do
        payload = context.make_jwt_payload(issuer_claim: default_iss, subject_claim: 'sub',
                                           iat: 1.hour.from_now.to_i)
        jwt = context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
        resolver = double('resolver')
        expect(resolver).not_to receive(:call)
        expect do
          context.decode_jwt!(jwt, algorithm: 'ES256', key_resolver: resolver, issuer: default_iss)
        end.to raise_error(IPaaS::Error, /Issued At claim too far/)
      end

      it 'permits timestamps within MAX_IAT_DRIFT' do
        # Slight past iat/nbf within half the drift window — within the
        # pre-check skew AND already reached for ruby-jwt's strict nbf.
        # Tracks the constant rather than hard-coding 30 seconds.
        offset = (IPaaS::Job::JWT::MAX_IAT_DRIFT.to_i / 2).seconds.ago.to_i
        payload = context.make_jwt_payload(issuer_claim: default_iss, subject_claim: 'sub',
                                           iat: offset,
                                           nbf: offset)
        jwt = context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
        decoded = context.decode_jwt!(jwt, algorithm: 'ES256',
                                           pem: es256_pem[:public], issuer: default_iss)
        expect(decoded[:payload]['sub']).to eq('sub')
      end

      it 'rejects nbf one second past the MAX_IAT_DRIFT boundary' do
        # Boundary contrast: drift+1 in the future must fail pre-check.
        offset = (IPaaS::Job::JWT::MAX_IAT_DRIFT.to_i + 1).seconds.from_now.to_i
        payload = context.make_jwt_payload(issuer_claim: default_iss, subject_claim: 'sub',
                                           nbf: offset)
        jwt = context.encode_jwt(payload, pem: es256_pem[:private], algorithm: 'ES256')
        expect do
          context.decode_jwt!(jwt, algorithm: 'ES256',
                                   pem: es256_pem[:public], issuer: default_iss)
        end.to raise_error(IPaaS::Error, 'JWT not yet valid')
      end
    end

    describe 'JWK round-trip (curve coverage)' do
      it 'decodes ES256 when the PEM was derived from a JWK import' do
        jwk = JWT::JWK.new(OpenSSL::PKey::EC.new(es256_pem[:private]), { kid: 'k' })
        derived_pem = jwk.verify_key.to_pem
        decoded = context.decode_jwt!(default_jwt,
                                      algorithm: 'ES256', pem: derived_pem, issuer: default_iss)
        expect(decoded[:payload]['sub']).to eq('sub')
      end

      it 'decodes RS256 when the PEM was derived from a JWK import' do
        payload = context.make_jwt_payload(issuer_claim: default_iss, subject_claim: 'sub')
        jwt = context.encode_jwt(payload, pem: rs256_pem[:private], algorithm: 'RS256')
        jwk = JWT::JWK.new(OpenSSL::PKey::RSA.new(rs256_pem[:private]), { kid: 'k' })
        derived_pem = jwk.verify_key.to_pem
        decoded = context.decode_jwt!(jwt, algorithm: 'RS256', pem: derived_pem, issuer: default_iss)
        expect(decoded[:payload]['sub']).to eq('sub')
      end
    end
  end
end
