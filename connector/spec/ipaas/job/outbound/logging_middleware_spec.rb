require 'spec_helper'
require 'json'
require 'faraday'
require 'stringio'

describe IPaaS::Job::Outbound::LoggingMiddleware do
  let(:io) { StringIO.new }
  let(:logger) { Logger.new(io) }

  let(:app) do
    app_logger = logger
    Faraday.new do |conn|
      conn.use described_class do |m|
        m.instance_variable_set(:@logger, app_logger)
      end
      conn.adapter :test do |stub|
        stub.get('/ok') { [200, { 'Content-Type' => 'application/json' }, 'hello'] }
        stub.get('/boom') { raise Faraday::ConnectionFailed, 'dns down' }
      end
    end
  end

  # Inject our logger by reopening the instance after build.
  before do
    allow_any_instance_of(described_class).to receive(:logger).and_return(logger)
  end

  def last_payload
    line = io.string.lines.last
    JSON.parse(line.split(' -- : ', 2).last)
  end

  describe 'successful request' do
    it 'logs method, host, path, status, and byte counts' do
      app.get('/ok', nil, { 'Authorization' => 'Bearer secret', 'X-Normal' => 'ok' })
      payload = last_payload
      expect(payload).to include(
        'event' => 'outbound_http',
        'method' => 'GET',
        'path' => '/ok',
        'status' => 200,
      )
      expect(payload['res_bytes']).to eq('hello'.bytesize)
      expect(payload['duration_ms']).to be_a(Numeric)
    end

    it 'redacts sensitive headers' do
      app.get('/ok', nil, { 'Authorization' => 'Bearer sekret', 'Cookie' => 'abc', 'X-Api-Key' => 'k' })
      headers = last_payload['req_headers']
      expect(headers['Authorization']).to match(/\A\[REDACTED len=\d+\]\z/)
      expect(headers['Cookie']).to match(/\A\[REDACTED len=\d+\]\z/)
      expect(headers['X-Api-Key']).to match(/\A\[REDACTED len=\d+\]\z/)
    end

    it 'preserves non-sensitive headers' do
      app.get('/ok', nil, { 'Accept' => 'application/json' })
      expect(last_payload['req_headers']['Accept']).to eq('application/json')
    end

    it 'redacts sensitive query params and keeps others' do
      app.get('/ok?token=abc&page=2&api_key=z&name=foo')
      expect(last_payload['query']).to include('token=[REDACTED]', 'page=2', 'api_key=[REDACTED]', 'name=foo')
    end
  end

  describe 'error path' do
    it 'logs error_class/error_message and omits status/res_bytes' do
      expect { app.get('/boom') }.to raise_error(Faraday::ConnectionFailed)
      payload = last_payload
      expect(payload['error_class']).to eq('Faraday::ConnectionFailed')
      expect(payload['error_message']).to include('dns down')
      expect(payload).not_to have_key('status')
      expect(payload).not_to have_key('res_bytes')
    end
  end
end
