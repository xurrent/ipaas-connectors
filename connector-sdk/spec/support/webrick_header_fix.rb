module SinatraRequestExtension
  extend ActiveSupport::Concern
  included do
    def headers
      @headers ||= ActionDispatch::Http::Headers.new(self)
    end
  end
end

Sinatra::Request.include(SinatraRequestExtension)
