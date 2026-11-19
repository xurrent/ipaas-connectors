require 'spec_helper'

describe IPaaS::Encryption::HashedCredential do
  let(:plaintext) { 'correct horse battery staple' }
  let(:credential) { described_class.derive(plaintext) }

  describe '.derive' do
    it 'returns a HashedCredential whose to_h is exactly a Base64 salt/hash pair of the pinned byte lengths' do
      expect(credential).to be_a(described_class)
      expect(credential.to_h.keys).to eq(%w[salt hash])
      expect(Base64.strict_decode64(credential.to_h['salt']).bytesize).to eq(described_class::SALT_BYTES)
      expect(Base64.strict_decode64(credential.to_h['hash']).bytesize).to eq(described_class::KEY_BYTES)
    end

    it 'accepts a plaintext at the minimum length floor' do
      at_floor = 'a' * described_class::MIN_PLAINTEXT_LENGTH
      expect(described_class.derive(at_floor)).to be_a(described_class)
    end

    it 'rejects a plaintext shorter than the minimum length floor' do
      too_short = 'a' * (described_class::MIN_PLAINTEXT_LENGTH - 1)
      expect { described_class.derive(too_short) }
        .to raise_error(IPaaS::Encryption::Errors::InvalidHashedCredential,
                        /at least #{described_class::MIN_PLAINTEXT_LENGTH} characters/o)
    end

    it 'produces different salts and hashes for the same plaintext (random salting)' do
      other = described_class.derive(plaintext)
      expect(other.salt).not_to eq(credential.salt)
      expect(other.hash_value).not_to eq(credential.hash_value)
    end
  end

  describe '#verify' do
    it 'returns true for the correct plaintext and false for a wrong plaintext' do
      expect(credential.verify(plaintext)).to be(true)
      expect(credential.verify('a-different-long-secret')).to be(false)
    end

    it 'returns false when the stored salt is tampered' do
      tampered = described_class.new(salt: Base64.strict_encode64(SecureRandom.random_bytes(16)),
                                     hash: credential.hash_value)
      expect(credential.verify(plaintext)).to be(true)
      expect(tampered.verify(plaintext)).to be(false)
    end

    it 'returns false for a nil or blank candidate' do
      expect(credential.verify(nil)).to be(false)
      expect(credential.verify('')).to be(false)
    end

    it 'verifies a record that stores only salt+hash at the pinned LEGACY_ITERATIONS count' do
      # Records carry no per-record iteration count, so verify recomputes at
      # LEGACY_ITERATIONS; this breaks if that pin ever drifts from the count
      # the record was derived with.
      field_less = described_class.from_h(credential.to_h)
      expect(field_less.to_h.keys).to eq(%w[salt hash])
      expect(field_less.verify(plaintext)).to be(true)
    end
  end

  describe '.from_h' do
    it 'round-trips a serialized record so it verifies the original plaintext' do
      expect(described_class.from_h(credential.to_h).verify(plaintext)).to be(true)
    end

    it 'surfaces a blank record for a malformed Hash without raising' do
      expect(described_class.from_h({ 'salt' => 'only-salt' })).to be_blank
      expect(described_class.from_h(nil)).to be_blank
    end
  end

  describe '.from_h!' do
    it 'accepts a well-formed record and returns a canonical HashedCredential' do
      wrapped = described_class.from_h!(credential.to_h)
      expect(wrapped.to_h).to eq(credential.to_h)
    end

    it 'rejects a record missing salt or hash' do
      expect { described_class.from_h!({ 'hash' => credential.hash_value }) }
        .to raise_error(IPaaS::Encryption::Errors::InvalidHashedCredential)
      expect { described_class.from_h!({ 'salt' => credential.salt }) }
        .to raise_error(IPaaS::Encryption::Errors::InvalidHashedCredential)
    end

    it 'rejects non-strict-Base64 salt or hash' do
      expect { described_class.from_h!({ 'salt' => 'not base64!!', 'hash' => credential.hash_value }) }
        .to raise_error(IPaaS::Encryption::Errors::InvalidHashedCredential)
      expect { described_class.from_h!({ 'salt' => credential.salt, 'hash' => 'not base64!!' }) }
        .to raise_error(IPaaS::Encryption::Errors::InvalidHashedCredential)
    end

    it 'rejects a salt or hash that decodes to the wrong byte length' do
      wrong_salt = Base64.strict_encode64(SecureRandom.random_bytes(8))
      wrong_hash = Base64.strict_encode64(SecureRandom.random_bytes(16))
      expect { described_class.from_h!({ 'salt' => wrong_salt, 'hash' => credential.hash_value }) }
        .to raise_error(IPaaS::Encryption::Errors::InvalidHashedCredential)
      expect { described_class.from_h!({ 'salt' => credential.salt, 'hash' => wrong_hash }) }
        .to raise_error(IPaaS::Encryption::Errors::InvalidHashedCredential)
    end

    it 'rejects a non-Hash argument' do
      expect { described_class.from_h!('not a hash') }.to raise_error(IPaaS::Encryption::Errors::InvalidHashedCredential)
    end

    it 'raises InvalidHashedCredential (not NoMethodError) for a non-String salt or hash' do
      [123, true, false, [credential.salt]].each do |bad|
        expect { described_class.from_h!({ 'salt' => bad, 'hash' => credential.hash_value }) }
          .to raise_error(IPaaS::Encryption::Errors::InvalidHashedCredential)
        expect { described_class.from_h!({ 'salt' => credential.salt, 'hash' => bad }) }
          .to raise_error(IPaaS::Encryption::Errors::InvalidHashedCredential)
      end
    end
  end

  describe '#to_h' do
    it 'has only string keys and string values and never exposes plaintext' do
      hash = credential.to_h
      expect(hash.keys).to eq(%w[salt hash])
      expect(hash.values).to all(be_a(String))
      expect(hash.to_json).not_to include(plaintext)
    end
  end

  describe '#inspect' do
    it 'masks the salt and hash' do
      expect(credential.inspect).to eq('"[HashedCredential]"')
      expect(credential.inspect).not_to include(credential.salt)
    end
  end

  describe '#blank?' do
    it 'is true for an unset instance and false for a derived one' do
      expect(described_class.new(salt: nil, hash: nil)).to be_blank
      expect(credential).not_to be_blank
    end
  end

  describe 'reading it like a Hash' do
    it 'refuses every hash reader with InvalidHashedCredential' do
      [:[], :dig, :fetch, :fetch_values, :values_at, :key?, :has_key?].each do |reader|
        expect { credential.public_send(reader, :account_id) }
          .to raise_error(IPaaS::Encryption::Errors::InvalidHashedCredential,
                          "Reading a hashed credential with '#{reader}' is not allowed.")
      end
    end
  end

  describe 'value equality' do
    it 'is equal for identical salt/hash but not for two derivations of the same plaintext' do
      same = described_class.new(salt: credential.salt, hash: credential.hash_value)
      expect(credential).to eq(same)
      expect(credential.hash).to eq(same.hash)
      expect(credential).not_to eq(described_class.derive(plaintext))
    end
  end

  describe 'JS↔Ruby PBKDF2 parity fixture' do
    # Pinned vector shared with the Vitest test so a parameter/encoding drift breaks
    # a test instead of silently failing all auth. Uses a FIXED salt for determinism.
    let(:parity_secret) { 'correct horse battery staple' }
    let(:parity_salt_b64) { 'MTIzNDU2Nzg5MGFiY2RlZg==' } # "1234567890abcdef"
    let(:parity_expected_hash_b64) { 'Nfo7SGC6ArzcZ+Lr8PQd073OF/B5JhddSOR+iWgGV/s=' }

    it 'derives the pinned expected hash for the fixed salt and iteration count' do
      raw_salt = Base64.strict_decode64(parity_salt_b64)
      computed = OpenSSL::KDF.pbkdf2_hmac(
        parity_secret, salt: raw_salt, iterations: described_class::DERIVE_ITERATIONS,
                       length: described_class::KEY_BYTES, hash: described_class::DIGEST
      )
      expect(Base64.strict_encode64(computed)).to eq(parity_expected_hash_b64)
    end

    it 'verifies a record built from the pinned salt and hash against the pinned secret' do
      record = described_class.new(salt: parity_salt_b64, hash: parity_expected_hash_b64)
      expect(record.verify(parity_secret)).to be(true)
    end
  end

  describe 'writing itself to YAML' do
    let(:record) { described_class.derive('a' * described_class::MIN_PLAINTEXT_LENGTH) }

    it 'writes a plain mapping rather than a native object tag' do
      dumped = IPaaS::Connector::Common::Serializer.dump({ 'v' => record })

      expect(dumped).not_to include('!ruby/object:')
      expect(dumped).to include('salt:', 'hash:')
    end

    it 'reads back through the strict gate it writes for' do
      dumped = IPaaS::Connector::Common::Serializer.dump({ 'v' => record })
      reloaded = described_class.from_h!(IPaaS::Connector::Common::Serializer.parse(dumped)['v'])

      expect(reloaded).to eq(record)
    end
  end
end
