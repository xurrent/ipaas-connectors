module IPaaS
  module TestCase
    class ExpectationResult
      include IPaaS::Connector::Common::Model

      attribute :errors, type: [String], default: []

      def passed?
        errors.blank?
      end

      def failed?
        !passed?
      end

      def to_h
        IPaaS::Connector::Common::Serializer.to_h(self, :errors)
      end
    end
  end
end
