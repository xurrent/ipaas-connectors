require 'sinatra/base'

module TriggerServer
  TRIGGER_SERVER_PORT = 2999
  VERBOSE = false

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

    get '/inbound/:uuid' do
      content_type :json
      begin
        runbook = IPaaS::Connector::Runbook.by_uuid(params[:uuid])
        raise "Runbook invalid: #{runbook.full_error_messages}" unless runbook.valid?
        runbook.trigger.parse_request(request).to_json
      rescue IPaaS::Job::FailJob => e
        status 400
        { error: e.message }.to_json
      end
    end
    post '/inbound/:uuid' do
      content_type :json
      begin
        runbook = IPaaS::Connector::Runbook.by_uuid(params[:uuid])
        raise "Runbook invalid: #{runbook.full_error_messages}" unless runbook.valid?
        runbook.trigger.parse_request(request).to_json
      rescue IPaaS::Job::DiscardTriggerEvent
        status 200
        { result: 'Discarded' }.to_json
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
        WEBrick::Config::HTTP[:AccessLog] = [] unless VERBOSE
        HANDLER.run!(port: TRIGGER_SERVER_PORT, host: 'localhost', quiet: true,
                     server_settings: VERBOSE ? {} : { Logger: WEBrick::Log.new(File::NULL) }) do
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

def post_trigger(data, params: {}, headers: {}, basic_auth: nil)
  send_trigger(:post, data, params: params, headers: headers, basic_auth: basic_auth)
end

def get_trigger(params: {}, headers: {}, basic_auth: nil)
  send_trigger(:get, nil, params: params, headers: headers, basic_auth: basic_auth)
end

def send_trigger(method, data, params: {}, headers: {}, basic_auth: nil)
  uri = build_trigger_uri(params)
  response = Faraday.send(method, uri) { |req| configure_trigger_request(req, data, headers, basic_auth) }
  JSON.parse(response.body).deep_symbolize_keys
end

def build_trigger_uri(params)
  endpoint = "/inbound/#{trigger.runbook.uuid}"
  URI.parse("http://127.0.0.1:#{TriggerServer::TRIGGER_SERVER_PORT}#{endpoint}?#{build_query_params(params)}")
end

def configure_trigger_request(request, data, headers, basic_auth)
  request.body = data.is_a?(Hash) ? data.to_json : data
  request.headers['Content-Type'] = 'application/json'
  headers.each { |key, value| request.headers[key.to_s] = value }
  return unless basic_auth

  request.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{basic_auth.first}:#{basic_auth.second}")}"
end

def build_query_params(params)
  params.map do |name, values|
    Array(values).map do |value|
      "#{CGI.escape(name.to_s)}=#{CGI.escape(value.to_s)}"
    end
  end.flatten.join('&')
end
