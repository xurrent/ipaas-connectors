require 'sinatra/base'

module TriggerServer
  TRIGGER_SERVER_PORT = 2998

  # Middleware to make the request body rewindable, needed because WEBrick's
  # input wrapper does not support rewind.
  class RewindableInput
    def initialize(app)
      @app = app
    end

    def call(env)
      if env['rack.input']
        body = env['rack.input'].read
        env['rack.input'] = StringIO.new(body)
      end
      @app.call(env)
    end
  end

  HANDLER = Sinatra.new do
    use RewindableInput

    post '/inbound/:uuid' do
      content_type :json
      begin
        IPaaS::Connector::Runbook.by_uuid(params[:uuid]).trigger.parse_request(request).to_json
      rescue IPaaS::Job::FailJob => e
        status 400
        { error: e.message }.to_json
      end
    end
  end

  class << self
    def start
      return if @server

      Thread.new do
        WEBrick::Config::HTTP[:AccessLog] = []
        HANDLER.run!(port: TRIGGER_SERVER_PORT, host: 'localhost', quiet: true,
                     server_settings: { Logger: WEBrick::Log.new(File::NULL) }) do
          @server = true
        end
      end
      sleep 0.0001 until @server
    end

    def stop
      HANDLER.quit!
      @server = false
    end

    def running?
      @server
    end
  end
end
