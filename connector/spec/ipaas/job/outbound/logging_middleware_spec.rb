require 'spec_helper'
require 'json'
require 'faraday'
require 'stringio'

describe IPaaS::Job::Outbound::LoggingMiddleware do
  let(:io) { StringIO.new }
  let(:logger) { Logger.new(io) }
  let(:waiting) { Queue.new }
  let(:release) { Queue.new }

  let(:app) do
    app_logger = logger
    Faraday.new do |conn|
      conn.use described_class do |m|
        m.instance_variable_set(:@logger, app_logger)
      end
      conn.adapter :test do |stub|
        stub.get('/ok') { [200, { 'Content-Type' => 'application/json' }, 'hello'] }
        stub.get('/boom') { raise Faraday::ConnectionFailed, 'dns down' }
        stub.get('/peer') do
          described_class.record_peer('203.0.113.7', :public)
          [200, {}, 'ok']
        end
        stub.get('/peer-refused') do
          described_class.record_peer('192.0.2.10', :example_class)
          raise IPaaS::Error, 'refused'
        end
        stub.get('/planted') do |env|
          env[:peer_address] = '198.51.100.9'
          env[:peer_class] = :public
          [200, {}, 'ok']
        end
        stub.get('/outer') do
          app.get('/peer')
          described_class.record_peer('192.0.2.20', :example_class)
          [200, {}, 'ok']
        end
        stub.get('/interrupted') do
          described_class.record_peer('192.0.2.30', :example_class)
          raise Timeout::ExitException
        end
        stub.get('/binary-error') { raise IPaaS::Error, "refused \xFF".b }
        stub.get('/slow') do
          described_class.record_peer('192.0.2.50', :example_class)
          waiting << true
          release.pop(timeout: 5)
          [200, {}, 'late']
        end
        stub.get('/dummy-encoding-error') { raise IPaaS::Error, 'refused'.dup.force_encoding(Encoding::UTF_7) }
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

    it 'still logs a request whose header value is not valid UTF-8' do
      app.get('/ok', nil, { 'X-Signature' => "\xFF".b })
      expect(io.string.lines.size).to eq(1)
      expect(last_payload).to include('status' => 200)
      expect(last_payload['req_headers']['X-Signature']).to eq("\uFFFD")
    end

    it 'still logs a request whose header name is not valid UTF-8' do
      app.get('/ok', nil, { "X-\xFF".b => 'value' })
      expect(io.string.lines.size).to eq(1)
      expect(last_payload['req_headers']).to include("X-\uFFFD" => 'value')
    end

    it 'keeps the text of a header value in another encoding' do
      app.get('/ok', nil, { 'X-Name' => 'café'.encode(Encoding::ISO_8859_1) })
      expect(last_payload['req_headers']['X-Name']).to eq('café')
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

  describe 'peer address' do
    it 'logs the peer address and class the connection recorded' do
      app.get('/peer')
      expect(last_payload).to include('peer_address' => '203.0.113.7', 'peer_class' => 'public')
    end

    it 'logs the recorded peer on a request that fails after connecting' do
      expect { app.get('/peer-refused') }.to raise_error(IPaaS::Error, 'refused')
      expect(io.string.lines.size).to eq(1)
      expect(last_payload).to include('peer_address' => '192.0.2.10', 'peer_class' => 'example_class',
                                      'error_class' => 'IPaaS::Error')
    end

    it 'omits the peer when no connection recorded one' do
      app.get('/ok')
      expect(last_payload.keys).not_to include('peer_address', 'peer_class')
    end

    it 'ignores a peer written into the request env' do
      app.get('/planted')
      expect(last_payload).to include('status' => 200)
      expect(last_payload.keys).not_to include('peer_address', 'peer_class')
    end

    it 'keeps the peer of each request when one request is made inside another' do
      app.get('/outer')
      payloads = io.string.lines.map { |line| JSON.parse(line.split(' -- : ', 2).last) }
      expect(payloads.map { |payload| payload.values_at('path', 'peer_address') })
        .to eq([['/peer', '203.0.113.7'], ['/outer', '192.0.2.20']])
    end

    it 'ignores a peer recorded outside a request' do
      described_class.record_peer('192.0.2.40', :example_class)
      expect(Thread.current[described_class::PEER_SLOT]).to be_nil
      app.get('/ok')
      expect(last_payload.keys).not_to include('peer_address', 'peer_class')
    end
  end

  describe 'a request interrupted by an exception outside StandardError' do
    it 'still logs the request with its peer and lets the exception through' do
      expect { app.get('/interrupted') }.to raise_error(Timeout::ExitException)
      expect(io.string.lines.size).to eq(1)
      expect(last_payload).to include('peer_address' => '192.0.2.30', 'error_class' => 'Timeout::ExitException')
    end
  end

  describe 'a request killed while it waits' do
    it 'does not log an exception the caller had already handled' do
      thread = Thread.new do
        raise IPaaS::Error, 'earlier step failed'
      rescue IPaaS::Error
        app.get('/slow')
      end
      expect(waiting.pop(timeout: 5)).to be(true)
      thread.kill.join(5)
      expect(io.string.lines.size).to eq(1)
      expect(last_payload).to include('path' => '/slow', 'peer_address' => '192.0.2.50')
      expect(last_payload.keys).not_to include('status', 'error_class', 'error_message')
    ensure
      thread&.kill
    end

    it 'still logs the request when it is killed while its line is written' do
      writes = 0
      allow(logger).to receive(:info).and_wrap_original do |original, *args|
        writes += 1
        Thread.current.kill if writes == 1
        original.call(*args)
      end
      thread = Thread.new { app.get('/peer') }
      thread.join(5)
      expect(writes).to eq(2)
      expect(thread.value).to be_nil
      expect(io.string.lines.size).to eq(1)
      expect(last_payload).to include('path' => '/peer', 'peer_address' => '203.0.113.7')
    end
  end

  describe 'a response completed later' do
    let(:deferred) { {} }
    let(:deferred_app) do
      holder = deferred
      Faraday.new(url: 'http://example.test') do |conn|
        conn.use described_class
        conn.use(Class.new(Faraday::Middleware) do
          define_method(:call) do |env|
            holder[:env] = env
            holder[:response] = Faraday::Response.new
          end
        end)
      end
    end

    it 'logs the request once, when it completes' do
      deferred_app.get('/later')
      expect(io.string.lines.size).to eq(0)
      deferred[:env].status = 200
      deferred[:response].finish(deferred[:env])
      expect(io.string.lines.size).to eq(1)
      expect(last_payload).to include('path' => '/later', 'status' => 200)
    end
  end

  describe 'a line that cannot be built' do
    around do |example|
      original = described_class.context_provider
      described_class.context_provider = -> { { account_id: 7 } }
      example.run
    ensure
      described_class.context_provider = original
    end

    it 'still logs the event with the sender and the recorded peer' do
      allow_any_instance_of(described_class).to receive(:build_payload).and_raise(ArgumentError)
      app.get('/peer')
      expect(last_payload).to eq('account_id' => 7, 'event' => 'outbound_http', 'peer_address' => '203.0.113.7',
                                 'peer_class' => 'public', 'log_error_class' => 'ArgumentError')
    end

    it 'still logs a request whose header refers to itself' do
      cyclic = {}
      cyclic['a'] = cyclic
      expect { app.get('/peer') { |request| request.headers['X-Cyclic'] = cyclic } }.not_to raise_error
      expect(io.string.lines.size).to eq(1)
      expect(last_payload).to include('peer_address' => '203.0.113.7', 'log_error_class' => 'JSON::NestingError')
    end
  end

  describe 'a logger that fails' do
    before { allow(logger).to receive(:info).and_raise(IOError) }

    it 'does not fail the request' do
      expect(app.get('/ok').status).to eq(200)
    end

    it "does not replace the request's own error" do
      expect { app.get('/boom') }.to raise_error(Faraday::ConnectionFailed)
    end
  end

  describe 'connector uuid' do
    it 'omits the connector uuid when built without one' do
      app.get('/ok')
      expect(last_payload.keys).not_to include('connector_uuid')
    end

    context 'when built with a connector uuid' do
      let(:app) do
        Faraday.new do |conn|
          conn.use described_class, connector_uuid: 'connector-uuid'
          conn.adapter(:test) { |stub| stub.get('/ok') { [200, {}, 'ok'] } }
        end
      end

      it 'logs the connector uuid it was built with' do
        app.get('/ok')
        expect(last_payload).to include('connector_uuid' => 'connector-uuid', 'status' => 200)
      end
    end
  end

  describe 'context provider' do
    around do |example|
      original = described_class.context_provider
      example.run
    ensure
      described_class.context_provider = original
    end

    it 'merges the fields the host provides' do
      described_class.context_provider = -> { { account_id: 7, job_uuid: 'job-uuid' } }
      app.get('/ok')
      expect(last_payload).to include('account_id' => 7, 'job_uuid' => 'job-uuid', 'status' => 200)
    end

    it 'keeps its own fields when the provider names the same keys' do
      described_class.context_provider = -> { { event: 'other', status: 500, account_id: 7 } }
      app.get('/ok')
      expect(last_payload).to include('event' => 'outbound_http', 'status' => 200, 'account_id' => 7)
    end

    it 'still logs the request without sender fields when the provider raises' do
      described_class.context_provider = -> { raise 'provider down' }
      app.get('/ok')
      expect(last_payload).to include('event' => 'outbound_http', 'status' => 200)
      expect(last_payload.keys).not_to include('account_id', 'job_uuid')
    end

    it 'logs no sender fields when no provider is installed' do
      described_class.context_provider = nil
      app.get('/ok')
      expect(last_payload.keys).not_to include('account_id', 'job_uuid')
    end
  end

  describe 'error path' do
    it 'still logs a request whose error message has no UTF-8 conversion' do
      expect { app.get('/dummy-encoding-error') }.to raise_error(IPaaS::Error)
      expect(io.string.lines.size).to eq(1)
      expect(last_payload).to include('path' => '/dummy-encoding-error', 'error_class' => 'IPaaS::Error')
    end

    it 'still logs a request whose error message is not valid UTF-8' do
      expect { app.get('/binary-error') }.to raise_error(IPaaS::Error)
      expect(io.string.lines.size).to eq(1)
      expect(last_payload['error_message']).to eq("refused \uFFFD")
    end

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
