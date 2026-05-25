module IPaaS
  module Encryption
    class DataRowRecord
      attr_accessor :key, :data

      class << self
        def deserialize(serialized_data)
          json = JSON.parse(serialized_data.to_s)
          new(key: CryptoKey.deserialize(json['key']), data: json['data'])
        rescue JSON::ParserError => e
          raise Errors::Decryption, "Decryption failed: #{e.class.name} #{e.message}"
        end
      end

      def initialize(key:, data:)
        @key = key
        @data = data
      end

      def serialize
        JSON.dump({ key: key.serialize, data: data })
      end
    end
  end
end
