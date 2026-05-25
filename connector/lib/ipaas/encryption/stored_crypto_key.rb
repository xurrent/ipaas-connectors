module IPaaS
  module Encryption
    class StoredCryptoKey < CryptoKey
      attr_accessor :identifier, :revoked_at, :created_at, :encryption_key_id

      STORABLE_ATTRIBUTES = [:identifier, :revoked_at, :created_at, :encrypted_key, :kms_key_arn,
                             :parent_key_identifier,].freeze

      class << self
        def load(store, identifier)
          json = store.read(identifier)
          return nil if json.nil?

          StoredCryptoKey.new.tap do |key|
            map_from_json(STORABLE_ATTRIBUTES, json, key)
            key.revoked_at = safe_parse_time(key.revoked_at)
            key.created_at = safe_parse_time(key.created_at)
          end
        end

        def save(store, key)
          store.write(key.identifier, key.to_h)
        end

        def load_latest(store, partition)
          identifier = store.read("encryption_keys/latest/#{partition}")
          identifier.present? ? load(store, identifier[:identifier]) : nil
        end

        def create_latest(store, partition, attributes)
          key = StoredCryptoKey.new.tap do |obj|
            map_from_json(attributes.keys, attributes, obj)
            obj.created_at = Time.now.utc
            obj.identifier = SecureRandom.uuid_v7
          end

          save(store, key)
          store_as_latest(store, partition, key.identifier)
          key
        end

        private

        def store_as_latest(store, partition, identifier)
          store.write("encryption_keys/latest/#{partition}", { identifier: identifier })
        end

        def safe_parse_time(value)
          return nil if value.nil?
          Time.parse(value)
        rescue StandardError
          nil
        end

        def map_from_json(attrs, json, obj)
          attrs.each do |attr|
            obj.send(:"#{attr}=", json[attr])
          end
        end
      end

      def expired?(expire_after)
        created_at < (Time.now.utc - expire_after)
      end

      def revoked?
        self.revoked_at.present?
      end

      def to_h
        result = STORABLE_ATTRIBUTES.to_h do |attribute|
          [attribute, send(attribute)]
        end
        result[:revoked_at] = self.revoked_at.to_s if result[:revoked_at]
        result[:created_at] = self.created_at.to_s if result[:created_at]
        result
      end
    end
  end
end
