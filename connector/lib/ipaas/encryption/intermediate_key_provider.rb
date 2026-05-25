module IPaaS
  module Encryption
    class IntermediateKeyProvider
      MEMSTORE_SIZE = 1.megabyte
      REVOKED_CHECK_INTERVAL = 60.minutes
      EXPIRE_AFTER = 1.days

      attr_accessor :store, :system_key_provider

      @memcache = nil

      def self.memcache
        @memcache ||= ActiveSupport::Cache::MemoryStore.new(size: MEMSTORE_SIZE)
      end

      def initialize(store, system_key_provider)
        self.store = store
        self.system_key_provider = system_key_provider
      end

      def encryption_key
        self.class.memcache.fetch(partition, expires_in: REVOKED_CHECK_INTERVAL) do
          key = StoredCryptoKey.load_latest(store, partition)

          # Not that in race conditions, this may generate multiple keys at (almost) the same time.
          # The last one becomes the "winner", and the other ones will be used only once
          key = create_new_intermediate_key(partition) if key.nil? || key.expired?(EXPIRE_AFTER)

          key.secret ||= decrypt_secret(key)
          key
        end
      end

      def decryption_key(id)
        self.class.memcache.fetch(id, expires_in: REVOKED_CHECK_INTERVAL) do
          key = StoredCryptoKey.load(store, id)

          raise Errors::Decryption, 'Key permanently revoked' if key.nil?
          raise Errors::Decryption, 'Key temporarily revoked' if key.revoked?

          key.secret = decrypt_secret(key)
          key
        end
      end

      def revoke(id)
        key = StoredCryptoKey.load(store, id)
        return if key.nil?

        key.revoked_at = Time.now.utc
        StoredCryptoKey.save(store, key)
        self.class.memcache.delete(id)
      end

      private

      def partition
        "#{system_key_provider.partition}_#{Time.now.utc.strftime('%Y%m%d')}"
      end

      def create_new_intermediate_key(partition)
        system_key = system_key_provider.encryption_key
        secret = Cipher.generate_random_key
        encrypted_key = Cipher.new(system_key.secret).encrypt(secret)

        attributes = { encrypted_key: encrypted_key, parent_key_identifier: system_key.identifier }
        key = StoredCryptoKey.create_latest(store, partition, attributes)
        key.secret = secret
        key
      end

      def decrypt_secret(key)
        sk = system_key_provider.decryption_key(key.parent_key_identifier)
        Cipher.new(sk.secret).decrypt(key.encrypted_key)
      end
    end
  end
end
