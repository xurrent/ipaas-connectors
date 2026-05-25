module IPaaS
  module Encryption
    class CryptoKey
      attr_accessor :secret, :encrypted_key,
                    :kms_key_arn, :parent_key_identifier # reference to parent

      class << self
        def generate
          CryptoKey.new.tap do |key|
            key.secret = Cipher.generate_random_key
          end
        end

        def deserialize(serialized_data)
          CryptoKey.new.tap { |key| key.deserialize(serialized_data) }
        end
      end

      def serialize
        JSON.dump({
          k: ::Base64.strict_encode64(encrypted_key),
        }.tap do |json|
          json[:a] = kms_key_arn if kms_key_arn
          json[:p] = parent_key_identifier if parent_key_identifier
        end)
      end

      def deserialize(serialized_data)
        json = JSON.parse(serialized_data)
        self.encrypted_key = ::Base64.strict_decode64(json['k'])
        self.kms_key_arn = json['a']
        self.parent_key_identifier = json['p']
      end

      def inspect # :nodoc:
        "#<#{self.class.name}:#{format('%#016x', object_id << 1)}>"
      end
    end
  end
end
