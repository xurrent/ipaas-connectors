module IPaaS
  module Encryption
    class TestKeyProvider
      def secret
        'x' * 32
      end

      def encryption_key
        TestKey.new(secret, 1)
      end

      def decryption_key(identifier)
        TestKey.new(secret, identifier)
      end
    end

    class TestKey
      attr_accessor :secret, :identifier

      def initialize(secret, identifier)
        self.secret = secret
        self.identifier = identifier
      end
    end
  end
end
