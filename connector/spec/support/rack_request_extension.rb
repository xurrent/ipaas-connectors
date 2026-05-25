module IPaaS
  module Connector
    module RackRequestExtension
      extend ActiveSupport::Concern

      included do
        def headers
          @headers ||= ActionDispatch::Http::Headers.new(self)
        end
      end
    end
  end
end

Rack::Request.include(IPaaS::Connector::RackRequestExtension)
