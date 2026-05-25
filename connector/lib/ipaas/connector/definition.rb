module IPaaS
  module Connector
    class Definition
      def self.connector(uuid, &block)
        return @connector unless block
        raise IPaaS::Error, 'Only one connector per class allowed' if @connector

        @connector = IPaaS::Connector::Connector.new(uuid).tap do |c|
          c.instance_eval(&block)
        end
      end
    end
  end
end
