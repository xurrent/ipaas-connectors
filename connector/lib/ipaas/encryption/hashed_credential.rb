require 'openssl'
require 'base64'
require 'securerandom'
require 'active_support/security_utils'

module IPaaS
  module Encryption
    # Non-reversible representation of a plaintext secret: a random salt plus a
    # PBKDF2-derived hash. Holds ONLY derived material — never plaintext, never an
    # encryptor. Verified by recomputation, never by decryption.
    class HashedCredential
      # Pinned KDF parameters — the source of truth the browser TS constant mirrors,
      # used for derivation/verify, NOT persisted per-record (single algorithm/count today).
      DERIVE_ITERATIONS = 600_000
      SALT_BYTES = 16
      KEY_BYTES = 32
      DIGEST = 'sha256'.freeze
      # Server-side entropy floor for `derive` (~128 bits when randomly generated).
      MIN_PLAINTEXT_LENGTH = 22

      # Stored records carry only {salt, hash} — no per-record iteration count —
      # so `verify` recomputes at this pinned count. It exists as its own
      # constant so DERIVE_ITERATIONS can only be raised as a deliberate
      # two-step migration: new records must first store their count
      # per-record; existing records cannot be re-derived (their plaintext is
      # gone) and keep verifying at this count forever.
      LEGACY_ITERATIONS = 600_000

      HASH_READERS = [:[], :dig, :fetch, :fetch_values, :values_at, :key?, :has_key?].freeze

      attr_reader :salt, :hash_value

      class << self
        # SERVER derivation path (API/import/YAML/tests). The browser derives the
        # same {salt,hash} record for the primary UI path.
        def derive(plaintext)
          plaintext = plaintext.to_s
          if plaintext.length < MIN_PLAINTEXT_LENGTH
            raise IPaaS::Encryption::Errors::InvalidHashedCredential,
                  "Secret must be at least #{MIN_PLAINTEXT_LENGTH} characters."
          end

          raw_salt = SecureRandom.random_bytes(SALT_BYTES)
          raw_hash = OpenSSL::KDF.pbkdf2_hmac(
            plaintext, salt: raw_salt, iterations: DERIVE_ITERATIONS, length: KEY_BYTES, hash: DIGEST
          )
          new(salt: Base64.strict_encode64(raw_salt), hash: Base64.strict_encode64(raw_hash))
        end

        # Tolerant reader for the TRUSTED env-var read path (record already validated
        # at its write boundary). Untrusted input must use from_h! instead.
        def from_h(hash)
          record = (hash || {}).with_indifferent_access
          new(salt: record[:salt], hash: record[:hash])
        rescue StandardError
          new(salt: nil, hash: nil)
        end

        # The single strict gate shared by every untrusted path (apply_value, resolve, valid?).
        def from_h!(hash)
          raise IPaaS::Encryption::Errors::InvalidHashedCredential, 'Expected a Hash.' unless hash.is_a?(Hash)

          record = hash.with_indifferent_access
          salt = record[:salt]
          hash_value = record[:hash]
          if salt.blank? || hash_value.blank?
            raise IPaaS::Encryption::Errors::InvalidHashedCredential, 'Missing salt or hash.'
          end

          validate_byte_length!(salt, SALT_BYTES, 'salt')
          validate_byte_length!(hash_value, KEY_BYTES, 'hash')
          new(salt: salt, hash: hash_value)
        end

        private

        def validate_byte_length!(encoded, expected_bytes, field)
          # Reject a non-String before decoding: Base64.strict_decode64 raises
          # NoMethodError on a numeric/boolean/array, which would escape as a 500.
          raise IPaaS::Encryption::Errors::InvalidHashedCredential, "Invalid #{field}." unless encoded.is_a?(String)

          decoded = begin
            Base64.strict_decode64(encoded)
          rescue ArgumentError
            raise IPaaS::Encryption::Errors::InvalidHashedCredential, "Invalid #{field}." # non-strict-Base64
          end
          return if decoded.bytesize == expected_bytes

          raise IPaaS::Encryption::Errors::InvalidHashedCredential, "Unexpected #{field} length."
        end
      end

      def initialize(salt:, hash:)
        @salt = salt
        @hash_value = hash
      end

      HASH_READERS.each do |reader|
        define_method(reader) do |*|
          raise IPaaS::Encryption::Errors::InvalidHashedCredential,
                "Reading a hashed credential with '#{reader}' is not allowed."
        end
      end

      # Constant-work for ANY candidate (nil/blank treated as "") so timing does not
      # distinguish a blank candidate from a wrong one.
      def verify(candidate_plaintext)
        return false if blank?

        raw_salt = Base64.strict_decode64(salt)
        computed = OpenSSL::KDF.pbkdf2_hmac(
          candidate_plaintext.to_s, salt: raw_salt, iterations: effective_iterations,
                                    length: KEY_BYTES, hash: effective_digest
        )
        ActiveSupport::SecurityUtils.secure_compare(Base64.strict_encode64(computed), hash_value.to_s)
      rescue StandardError
        false
      end

      def to_h
        { 'salt' => salt, 'hash' => hash_value }
      end

      def encode_with(coder)
        coder.represent_object(nil, to_h)
      end

      def as_json(*)
        to_h
      end

      def to_json(*)
        to_h.to_json(*)
      end

      def blank?
        salt.blank? || hash_value.blank?
      end

      # Never expose salt/hash in logs/inspect.
      def inspect
        '"[HashedCredential]"'
      end

      def ==(other)
        return true if other.equal?(self)
        return false unless self.class.equal?(other.class)

        salt == other.salt && hash_value == other.hash_value
      end

      alias eql? ==

      def hash
        [self.class, salt, hash_value].hash
      end

      private

      def effective_iterations
        LEGACY_ITERATIONS
      end

      def effective_digest
        DIGEST
      end
    end
  end
end
