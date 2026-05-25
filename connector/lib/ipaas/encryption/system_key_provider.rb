module IPaaS
  module Encryption
    class SystemKeyProvider
      MEMSTORE_SIZE = 1.megabyte
      REVOKED_CHECK_INTERVAL = 60.minutes
      EXPIRE_AFTER = 90.days

      attr_accessor :store, :kms, :system_id, :kms_key_arn

      @memcache = nil

      def self.memcache
        @memcache ||= ActiveSupport::Cache::MemoryStore.new(size: MEMSTORE_SIZE)
      end

      def initialize(store, kms, system_id, kms_key_arn)
        self.store = store
        self.kms = kms
        self.system_id = system_id
        self.kms_key_arn = kms_key_arn
      end

      def encryption_key
        self.class.memcache.fetch(partition, expires_in: REVOKED_CHECK_INTERVAL) do
          key = StoredCryptoKey.load_latest(store, partition)

          # Not that in race conditions, this may generate multiple keys at (almost) the same time.
          # The last one becomes the "winner", and the other ones will be used only once
          key = create_new_system_key(partition) if key.nil? || key.expired?(EXPIRE_AFTER)

          key.secret ||= kms.decrypt(key.encrypted_key, kms_key_arn)
          key
        end
      end

      def decryption_key(id)
        self.class.memcache.fetch(id, expires_in: REVOKED_CHECK_INTERVAL) do
          key = StoredCryptoKey.load(store, id)

          raise Errors::Decryption, 'Key permanently revoked' if key.nil?
          raise Errors::Decryption, 'Key temporarily revoked' if key.revoked?

          key.secret = kms.decrypt(key.encrypted_key, key.kms_key_arn)
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

      def partition
        "partition_#{system_id}_#{kms_key_arn}"
      end

      private

      def create_new_system_key(partition)
        secret = Cipher.generate_random_key
        encrypted_key = kms.encrypt(secret, kms_key_arn)

        attributes = { encrypted_key: encrypted_key, kms_key_arn: kms_key_arn }
        key = StoredCryptoKey.create_latest(store, partition, attributes)
        key.secret = secret
        key
      end
    end
  end
end
