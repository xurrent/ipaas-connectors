module IPaaS
  module Encryption
    class SecretString
      attr_accessor :encrypted, :encryptor

      delegate :as_json, to: :encrypted, allow_nil: true

      def initialize(encrypted, encryptor = nil)
        self.encrypted = encrypted
        self.encryptor = encryptor
      end

      def self.encrypt(encryptor, value)
        return value if value.is_a?(SecretString)
        self.new(encryptor.encrypt(value), encryptor)
      end

      def to_s
        encrypted
      end

      def blank?
        encrypted.blank?
      end

      def inspect
        return if encrypted.nil?

        '"[SecretString]"'
      end

      def decrypt
        raise 'No encryptor known' unless self.encryptor

        self.encryptor.decrypt(self.encrypted)
      end

      def ==(other)
        return true if other.equal?(self)
        return false unless self.class.equal?(other.class)

        if self.encryptor && other.encryptor
          self.decrypt == other.decrypt
        else
          self.encrypted == other.encrypted
        end
      end

      alias eql? ==

      def hash
        return @hash if @hash

        @hash = [self.class, encryptor ? self.decrypt : encrypted].hash
      end
    end
  end
end
