require 'spec_helper'

describe IPaaS::Job::Outbound::HTTP do
  EXAMPLE_SERVER = 'https://example.com'.freeze

  let(:connector) do
    IPaaS::Connector::Connector.new('unique-connector-id') do
      outbound_connection do
        config_schema do
          field :shared_secret,
                'Shared secret',
                :string,
                required: true
        end

        authenticate do |request|
          request.headers[:secret_key] = config[:shared_secret]
        end
      end
    end
  end

  let(:connection) do
    IPaaS::Connector::Connection.parse(
      {
        uuid: 'connection_uuid',
        direction: 'outbound',
        name: 'test outbound connection',
        description: 'Test description',
        connector: {
          uuid: connector.uuid,
        },
        config_mapping: [
          { field_id: 'shared_secret', fixed: 'dangerously shared key' },
        ],
      },
    )
  end

  describe 'VALID_METHODS' do
    it 'contains all methods Faraday supports' do
      Faraday::Connection::METHODS.each do |method|
        expect(IPaaS::Job::Outbound::HTTP::VALID_METHODS).to include(method), "Faraday supports #{method}"
      end
      IPaaS::Job::Outbound::HTTP::VALID_METHODS.each do |method|
        expect(Faraday::Connection::METHODS).to include(method), "Faraday does not support #{method}"
      end
    end

    it 'did not freeze the Faraday methods set' do
      expect(Faraday::Connection::METHODS).not_to be_frozen
      expect(IPaaS::Job::Outbound::HTTP::VALID_METHODS).not_to equal(Faraday::Connection::METHODS)
    end
  end

  describe 'http_connection' do
    let(:connection) do
      secret = make_secret_string('secret').to_s
      parsed_secret = %(new_secret_string('#{secret}'))

      IPaaS::Connector::Connection.parse(
        {
          uuid: 'connection_uuid',
          direction: 'outbound',
          name: 'test outbound connection',
          description: 'Test description',
          connector: {
            uuid: connector.uuid,
          },
          config_mapping: [
            { field_id: 'shared_secret', fixed: 'dangerously shared key' },
            { field_id: 'proxy_server',
              proc: %({ host: "https://127.0.0.1:8080", username: "foo", password: #{parsed_secret} }), },
          ],
        },
      )
    end

    it 'should add a default User-Agent header' do
      http_connection = connection.http_connection(EXAMPLE_SERVER)
      expect(http_connection.headers[:'User-Agent']).to eq('Xurrent iPaaS')
    end

    it 'should call the authenticate method when creating a new connection' do
      http_connection = connection.http_connection(EXAMPLE_SERVER)
      expect(http_connection.headers[:secret_key]).to eq('dangerously shared key')
    end

    it 'should set the proxy server' do
      http_connection = connection.http_connection(EXAMPLE_SERVER)
      expect(http_connection.options.proxy.uri).to eq(URI.parse('https://127.0.0.1:8080'))
      expect(http_connection.options.proxy.user).to eq('foo')
      expect(http_connection.options.proxy.password).to eq('secret')
    end

    it 'should set the timeouts' do
      http_connection = connection.http_connection(EXAMPLE_SERVER)
      expect(http_connection.options.open_timeout).to eq(5)
      expect(http_connection.options.timeout).to eq(5 * 60)
    end

    it 'should validate the URI' do
      expect do
        connection.http_connection('foo/bar')
      end.to raise_error(IPaaS::Error, 'URI foo/bar is invalid.')
    end

    it 'should perform SSL verification when in Rails production mode' do
      stub_const 'Rails', Class.new
      allow(Rails).to receive(:env).and_return(double('development?' => false))
      http_connection = connection.http_connection(EXAMPLE_SERVER)
      expect(http_connection.ssl.verify).to be_nil # defaults to true
    end

    it 'should skip SSL verification when in Rails development mode' do
      stub_const 'Rails', Class.new
      allow(Rails).to receive(:env).and_return(double('development?' => true))
      http_connection = connection.http_connection(EXAMPLE_SERVER)
      expect(http_connection.ssl.verify).to eq(false)
    end
  end

  describe 'array_params' do
    let(:hostnames) { %w[host1 host2] }

    # Asserted on the raw query string rather than through a stub URL: WebMock matches a stub by
    # parsing both sides into a hash, and `h=host1&h=host2` parses to `{'h' => 'host2'}` there, so a
    # stub URL cannot tell one occurrence of a repeated name from two.
    def query_for(**)
      stub_request(:get, /#{Regexp.escape(EXAMPLE_SERVER)}/o).to_return(body: 'ok')
      response = connection.http_connection(EXAMPLE_SERVER, **)
                           .get { |request| request.params['h'] = hostnames }
      response.env.url.query
    end

    it 'should repeat the parameter name once per element in flat mode' do
      expect(query_for(array_params: :flat)).to eq('h=host1&h=host2')
    end

    it 'should bracket the parameter name once per element in nested mode' do
      expect(query_for(array_params: :nested)).to eq('h%5B%5D=host1&h%5B%5D=host2')
    end

    # The contrast case: without it, a mode that silently did nothing would still pass the above.
    it 'should encode as nested when no mode is given' do
      expect(query_for).to eq('h%5B%5D=host1&h%5B%5D=host2')
      expect(query_for).not_to eq(query_for(array_params: :flat))
    end

    # Documented carve-out: the raw branch fixes the group's wire format, so :nested cannot bracket
    # a group holding a raw value. Pinned here because `array_params:` now names :nested as a mode.
    it 'should send an array holding a raw-marked value exploded even in nested mode' do
      stub_request(:get, /#{Regexp.escape(EXAMPLE_SERVER)}/o).to_return(body: 'ok')
      response = connection.http_connection(EXAMPLE_SERVER, array_params: :nested).get do |request|
        request.params['h'] = [IPaaS::Job::Outbound::HTTP.raw_param_value('host1'), 'host2']
      end
      expect(response.env.url.query).to eq('h=host1&h=host2')
    end

    it 'should keep raw-marked values unescaped in flat mode' do
      stub = stub_request(:get, "#{EXAMPLE_SERVER}?h=a%3Bb").to_return(body: 'ok')
      connection.http_connection(EXAMPLE_SERVER, array_params: :flat).get do |request|
        request.params['h'] = IPaaS::Job::Outbound::HTTP.raw_param_value('a%3Bb')
      end
      expect(stub).to have_been_requested.once
    end

    it 'should leave the timeouts alone when a mode is given' do
      http_connection = connection.http_connection(EXAMPLE_SERVER, array_params: :flat)
      expect(http_connection.options.open_timeout).to eq(5)
      expect(http_connection.options.timeout).to eq(5 * 60)
    end

    it 'should reject a mode that is neither nested nor flat' do
      expect do
        connection.http_connection(EXAMPLE_SERVER, array_params: :exploded)
      end.to raise_error(ArgumentError, 'array_params must be one of :nested, :flat, found :exploded.')
    end

    it 'should reject a string spelling of a supported mode' do
      expect do
        connection.http_connection(EXAMPLE_SERVER, array_params: 'flat')
      end.to raise_error(ArgumentError, 'array_params must be one of :nested, :flat, found "flat".')
    end

    it 'should reject nil rather than fall back to the default' do
      expect do
        connection.http_connection(EXAMPLE_SERVER, array_params: nil)
      end.to raise_error(ArgumentError, 'array_params must be one of :nested, :flat, found nil.')
    end
  end

  describe 'http_send' do
    it 'should call the http_connection method' do
      expect(connection).to receive(:http_connection).with(EXAMPLE_SERVER).and_return(double(get: 'response'))
      expect(connection.http_send(:get, EXAMPLE_SERVER)).to eq('response')
    end

    it 'should fail when an invalid method is passed' do
      failure_message = 'Invalid http method, expected one of get, post, put, delete, head, patch, options, trace.'
      expect do
        connection.http_send(:foo, EXAMPLE_SERVER) {}
      end.to raise_error(IPaaS::Error, failure_message)
    end

    it 'should actually call the endpoint' do
      stub = stub_request(:get, EXAMPLE_SERVER)
             .with(headers: { 'secret_key' => 'dangerously shared key' })
             .to_return(body: { foo: 'bar' }.to_json)
      response = connection.http_send(:get, EXAMPLE_SERVER)
      expect(JSON.parse(response.body)).to eq({ 'foo' => 'bar' })
      expect(response.status).to eq(200)
      expect(stub).to have_been_requested.times(1)
    end

    it 'should be possible to pass a path, body and additional headers' do
      stub = stub_request(:post, "#{EXAMPLE_SERVER}/my/path")
             .with(headers: { 'secret_key' => 'dangerously shared key', 'h2' => 'baz' }, body: 'foo')
             .to_return(body: { foo: 'bar' }.to_json)
      response = connection.http_send(:post, EXAMPLE_SERVER, '/my/path') do |request|
        request.headers['h2'] = 'baz'
        request.body = 'foo'
      end
      expect(JSON.parse(response.body)).to eq({ 'foo' => 'bar' })
      expect(response.status).to eq(200)
      expect(stub).to have_been_requested.times(1)
    end

    it 'should send a raw-marked query parameter without escaping it again' do
      stub = stub_request(:get, "#{EXAMPLE_SERVER}?d=a%3Bb").to_return(body: 'ok')
      connection.http_send(:get, EXAMPLE_SERVER) do |request|
        request.params['d'] = IPaaS::Job::Outbound::HTTP.raw_param_value('a%3Bb')
      end
      expect(stub).to have_been_requested.times(1)
    end

    it 'should escape an unmarked query parameter that is already encoded' do
      # Contrast case: without the marker the pre-existing double-escaping still applies.
      stub = stub_request(:get, "#{EXAMPLE_SERVER}?d=a%253Bb").to_return(body: 'ok')
      connection.http_send(:get, EXAMPLE_SERVER) do |request|
        request.params['d'] = 'a%3Bb'
      end
      expect(stub).to have_been_requested.times(1)
    end

    it 'should be possible to pass query parameters and additional headers' do
      stub = stub_request(:patch, "#{EXAMPLE_SERVER}?foo=bar")
             .with(headers: { 'secret_key' => 'dangerously shared key', 'h2' => 'baz' })
             .to_return(body: { foo: 'bar' }.to_json)
      response = connection.http_send(:patch, EXAMPLE_SERVER) do |request|
        request.headers['h2'] = 'baz'
        request.params['foo'] = 'bar'
      end
      expect(JSON.parse(response.body)).to eq({ 'foo' => 'bar' })
      expect(response.status).to eq(200)
      expect(stub).to have_been_requested.times(1)
    end

    it 'should be possible to do multipart file upload' do
      received_request = nil
      stub = stub_request(:post, EXAMPLE_SERVER)
             .with { |request| received_request = request }
             .to_return(body: { foo: 'baz' }.to_json)

      headers = {}
      headers['h1'] = 'abc'

      params = {}
      params[:avatar_file_name] = 'profile.png'
      data = File.binread('spec/fixtures/icon.png')
      params[:extra] = IPaaS::Job::Outbound::HTTP.create_text_part('application/json', { a: 1 }.to_json)
      params[:avatar] = IPaaS::Job::Outbound::HTTP.create_binary_part('icon.png', 'image/jpeg', data)

      # rubocop:disable Layout/LineLength
      expected_name_part = %(\r\nContent-Disposition: form-data; name="avatar_file_name"\r\n\r\nprofile.png\r\n--)
                           .encode!('ASCII-8BIT')
      expected_extra_part = %(\r\nContent-Disposition: form-data; name="extra"\r\nContent-Type: application/json\r\n\r\n{"a":1}\r\n--)
                            .encode!('ASCII-8BIT')
      expected_avatar_prefix = %(\r\nContent-Disposition: form-data; name="avatar"; filename="icon.png"\r\nContent-Length: 4166\r\nContent-Type: image/jpeg\r\nContent-Transfer-Encoding: binary\r\n)
                               .encode!('ASCII-8BIT')
      # rubocop:enable Layout/LineLength

      response = connection.multipart_post(EXAMPLE_SERVER, params, headers)

      expect(response.status).to eq(200)
      expect(JSON.parse(response.body)).to eq({ 'foo' => 'baz' })
      expect(stub).to have_been_requested.times(1)
      expect(received_request.headers).to include({ 'Secret-Key' => 'dangerously shared key' }, { 'H1' => 'abc' })
      expect(received_request.headers['Content-Type']).to start_with('multipart/form-data; boundary=-')
      boundary = received_request.headers['Content-Type'].sub('multipart/form-data; boundary=', '')
      parts = received_request.body.split(boundary)
      expect(parts.size).to eq(5)
      expect(parts[0]).to eq('--')
      expect(parts[1]).to eq(expected_name_part)
      expect(parts[2]).to eq(expected_extra_part)
      expect(parts[3]).to start_with(expected_avatar_prefix)
      expect(parts[4]).to eq("--\r\n".encode!('ASCII-8BIT'))
    end
  end

  describe 'raw query parameters' do
    let(:raw) { IPaaS::Job::Outbound::HTTP.raw_param_value('a%3Bb') }

    it 'should expose raw_param_value as an instance helper, the form the SDK documents' do
      # It is listed in proc_safe, so a runbook proc calls it bare; without the forwarder that call
      # passes AST validation and then raises NoMethodError at run time.
      expect(connection.raw_param_value('a%3Bb')).to be_a(IPaaS::Job::Outbound::RawParamValue)
    end

    it 'should accept a raw value passed through the params argument' do
      # The marker is not a String, so validate_params! has to allow it explicitly.
      stub = stub_request(:get, "#{EXAMPLE_SERVER}?d=a%3Bb").to_return(body: 'ok')
      connection.http_get(EXAMPLE_SERVER, { 'd' => raw })
      expect(stub).to have_been_requested.times(1)
    end

    it 'should accept a repeated raw value through the params argument, which the encoder emits bare' do
      # The encoder has an Array branch for this; the validator used to reject it before it ran.
      stub = stub_request(:get, "#{EXAMPLE_SERVER}?q=A&q=B").to_return(body: 'ok')
      repeated = %w[A B].map { |value| IPaaS::Job::Outbound::HTTP.raw_param_value(value) }
      connection.http_get(EXAMPLE_SERVER, { 'q' => repeated })
      expect(stub).to have_been_requested.times(1)
    end

    it 'should accept a name-only params entry, which the encoder emits without an equals sign' do
      stub = stub_request(:get, "#{EXAMPLE_SERVER}?flag&d=a%3Bb").to_return(body: 'ok')
      connection.http_get(EXAMPLE_SERVER, { 'flag' => nil, 'd' => raw })
      expect(stub).to have_been_requested.times(1)
    end

    it 'should still reject a params value that is neither a string nor raw-marked' do
      expect do
        connection.http_get(EXAMPLE_SERVER, { 'd' => 42 })
      end.to raise_error(IPaaS::Error, /Params must be a hash with symbols, strings or raw-marked values/)
    end

    it 'should still reject a raw-marked header value' do
      expect do
        connection.http_get(EXAMPLE_SERVER, nil, { 'X-Foo' => raw })
      end.to raise_error(IPaaS::Error, /Headers must be a hash with symbols or strings/)
    end

    it 'should still reject a raw-marked multipart part' do
      expect do
        connection.multipart_post(EXAMPLE_SERVER, { f: raw })
      end.to raise_error(IPaaS::Error, /Unsupported parts found/)
    end

    it 'should send a raw-marked query parameter unescaped from multipart_post' do
      stub = stub_request(:post, "#{EXAMPLE_SERVER}?d=a%3Bb").to_return(body: 'ok')
      parts = { f: IPaaS::Job::Outbound::HTTP.create_text_part('text/plain', 'x') }
      connection.multipart_post(EXAMPLE_SERVER, parts) { |request| request.params['d'] = raw }
      expect(stub).to have_been_requested.times(1)
    end

    [:post, :put, :patch].each do |method|
      it "should send a raw-marked query parameter unescaped for http_#{method}" do
        stub = stub_request(method, "#{EXAMPLE_SERVER}?d=a%3Bb").to_return(body: 'ok')
        connection.send(:"http_#{method}", EXAMPLE_SERVER) { |request| request.params['d'] = raw }
        expect(stub).to have_been_requested.times(1)
      end

      it "should escape an unmarked already-encoded query parameter for http_#{method}" do
        stub = stub_request(method, "#{EXAMPLE_SERVER}?d=a%253Bb").to_return(body: 'ok')
        connection.send(:"http_#{method}", EXAMPLE_SERVER) { |request| request.params['d'] = 'a%3Bb' }
        expect(stub).to have_been_requested.times(1)
      end
    end

    # The bare Faraday verbs are proc_safe too, and a shipped connector reaches one of them
    # directly (checkmk_connector.rb:781). No call-site hook can cover these, which is why the
    # encoder is installed on the connection rather than swapped in per request.
    [:get, :head, :delete, :trace].each do |method|
      it "should send a raw-marked query parameter unescaped for the bare #{method} verb" do
        stub = stub_request(method, "#{EXAMPLE_SERVER}?d=a%3Bb").to_return(body: 'ok')
        connection.http_connection(EXAMPLE_SERVER).send(method) { |request| request.params['d'] = raw }
        expect(stub).to have_been_requested.times(1)
      end

      it "should escape an unmarked already-encoded query parameter for the bare #{method} verb" do
        stub = stub_request(method, "#{EXAMPLE_SERVER}?d=a%253Bb").to_return(body: 'ok')
        connection.http_connection(EXAMPLE_SERVER).send(method) { |request| request.params['d'] = 'a%3Bb' }
        expect(stub).to have_been_requested.times(1)
      end
    end

    it 'should send a raw-marked query parameter unescaped from a direct run_request' do
      stub = stub_request(:get, "#{EXAMPLE_SERVER}?d=a%3Bb").to_return(body: 'ok')
      connection.http_connection(EXAMPLE_SERVER)
                .run_request(:get, nil, nil, nil) { |request| request.params['d'] = raw }
      expect(stub).to have_been_requested.times(1)
    end

    it 'should not carry raw mode into a later request on the same connection' do
      raw_stub = stub_request(:get, "#{EXAMPLE_SERVER}?d=a%3Bb").to_return(body: 'ok')
      escaped_stub = stub_request(:get, "#{EXAMPLE_SERVER}?d=a%253Bb").to_return(body: 'ok')
      reused = connection.http_connection(EXAMPLE_SERVER)
      reused.http_send(:get) { |request| request.params['d'] = raw }
      reused.http_send(:get) { |request| request.params['d'] = 'a%3Bb' }
      expect(raw_stub).to have_been_requested.times(1)
      expect(escaped_stub).to have_been_requested.times(1)
    end

    it 'should leave a connector-chosen encoder in charge, marker or not' do
      # An explicit choice beats the default install, so a connector that assigns its own encoder
      # keeps it and forfeits raw pass-through rather than silently losing its own format.
      # `array_params:` is the supported route; this pins today's behaviour for the connection an
      # author still mutates.
      # Once we use an allowlist for class usage and Faraday::FlatParamsEncoder is not on it this
      # spec can be removed. We don't intend to support this going forward.
      stub = stub_request(:get, "#{EXAMPLE_SERVER}?d=a%253Bb").to_return(body: 'ok')
      conn = connection.http_connection(EXAMPLE_SERVER)
      conn.options[:params_encoder] = Faraday::FlatParamsEncoder
      conn.http_send(:get) { |request| request.params['d'] = raw }
      expect(stub).to have_been_requested.times(1)
    end

    it 'should still let the URL layer escape a raw value that is not already legal' do
      # The encoder emits the value verbatim, then URI::Generic#query= has its say, so
      # "byte-for-byte" holds for existing escapes but not for a literal space or #.
      stub = stub_request(:get, "#{EXAMPLE_SERVER}?d=sp%20ace").to_return(body: 'ok')
      connection.http_send(:get, EXAMPLE_SERVER) do |request|
        request.params['d'] = IPaaS::Job::Outbound::HTTP.raw_param_value('sp ace')
      end
      expect(stub).to have_been_requested.times(1)
    end

    it 'should fail with a connector error when a raw value carries an invalid percent escape' do
      expect do
        connection.http_send(:get, EXAMPLE_SERVER) do |request|
          request.params['d'] = IPaaS::Job::Outbound::HTTP.raw_param_value('100%zz')
        end
      end.to raise_error(IPaaS::Error, /must not contain a '%' that is not followed by two hex digits/)
    end

    it 'should fail on a malformed escape that the URL layer would have shipped verbatim' do
      expect do
        connection.http_send(:get, EXAMPLE_SERVER) do |request|
          request.params['d'] = IPaaS::Job::Outbound::HTTP.raw_param_value('discount%off')
        end
      end.to raise_error(IPaaS::Error, /must not contain a '%' that is not followed by two hex digits/)
    end

    it 'should still send a value whose percent escapes are all well formed' do
      stub = stub_request(:get, "#{EXAMPLE_SERVER}?d=a%3Bb%2Ac").to_return(body: 'ok')
      connection.http_send(:get, EXAMPLE_SERVER) do |request|
        request.params['d'] = IPaaS::Job::Outbound::HTTP.raw_param_value('a%3Bb%2Ac')
      end
      expect(stub).to have_been_requested.times(1)
    end

    it 'should keep Faraday sorting and [] expansion when nothing is marked' do
      # WebMock folds the query into a Hash before matching, so a stub URL proves the set of
      # parameters and never their order. Assert on what the encoder emits for both claims.
      encoder = IPaaS::Job::Outbound::SelectiveParamsEncoder
      stub = stub_request(:get, "#{EXAMPLE_SERVER}?a=2&z=1").to_return(body: 'ok')
      connection.http_send(:get, EXAMPLE_SERVER) do |request|
        request.params['z'] = '1'
        request.params['a'] = '2'
      end
      expect(stub).to have_been_requested.times(1)
      expect(encoder.encode({ 'z' => '1', 'a' => '2' })).to eq('a=2&z=1')
      expect(encoder.encode({ 'q' => %w[A B] })).to eq('q%5B%5D=A&q%5B%5D=B')
    end
  end

  describe 'short hand requests with query params' do
    [:get, :head, :delete, :trace, :options].each do |method|
      it "should be possible to use short hand http_#{method}" do
        stub = stub_request(method, EXAMPLE_SERVER)
               .with(headers: { 'secret_key' => 'dangerously shared key' })
               .to_return(body: { foo: 'bar' }.to_json)
        response = connection.send(:"http_#{method}", EXAMPLE_SERVER)
        expect(response.status).to eq(200)
        expect(JSON.parse(response.body)).to eq({ 'foo' => 'bar' })
        expect(stub).to have_been_requested.times(1)
      end

      it "should be possible to pass query parameters and additional headers for http_#{method}" do
        stub = stub_request(method, EXAMPLE_SERVER)
               .with(headers: { 'secret_key' => 'dangerously shared key', 'h2' => 'baz' }, query: { 'bar' => 'bie' })
               .to_return(body: { foo: 'bar' }.to_json)
        response = connection.send(:"http_#{method}", EXAMPLE_SERVER, { bar: 'bie' }, { h2: 'baz' })
        expect(response.status).to eq(200)
        expect(JSON.parse(response.body)).to eq({ 'foo' => 'bar' })
        expect(stub).to have_been_requested.times(1)
      end

      it "should be possible to pass query parameters and additional headers for http_#{method} using a block" do
        stub = stub_request(method, EXAMPLE_SERVER)
               .with(headers: { 'secret_key' => 'dangerously shared key', 'h2' => 'baz' }, query: { 'bar' => 'bie' })
               .to_return(body: { foo: 'bar' }.to_json)
        response = connection.send(:"http_#{method}", EXAMPLE_SERVER) do |request|
          request.params[:bar] = 'bie'
          request.headers[:h2] = 'baz'
        end
        expect(response.status).to eq(200)
        expect(JSON.parse(response.body)).to eq({ 'foo' => 'bar' })
        expect(stub).to have_been_requested.times(1)
      end

      it "should send a raw-marked query parameter unescaped for http_#{method}" do
        stub = stub_request(method, "#{EXAMPLE_SERVER}?d=a%3Bb").to_return(body: 'ok')
        connection.send(:"http_#{method}", EXAMPLE_SERVER) do |request|
          request.params['d'] = IPaaS::Job::Outbound::HTTP.raw_param_value('a%3Bb')
        end
        expect(stub).to have_been_requested.times(1)
      end

      it "should escape an unmarked already-encoded query parameter for http_#{method}" do
        stub = stub_request(method, "#{EXAMPLE_SERVER}?d=a%253Bb").to_return(body: 'ok')
        connection.send(:"http_#{method}", EXAMPLE_SERVER) do |request|
          request.params['d'] = 'a%3Bb'
        end
        expect(stub).to have_been_requested.times(1)
      end

      it 'should validate the URI' do
        expect do
          connection.send(:"http_#{method}", 'foo/bar')
        end.to raise_error(IPaaS::Error, 'URI foo/bar is invalid.')
      end

      it 'should validate the params' do
        expect do
          connection.send(:"http_#{method}", EXAMPLE_SERVER, 'foo')
        end.to raise_error(IPaaS::Error,
                           'Params must be a hash with symbols, strings or raw-marked values, found "foo".')
      end

      it 'should validate the headers' do
        expect do
          connection.send(:"http_#{method}", EXAMPLE_SERVER, nil, 'foo')
        end.to raise_error(IPaaS::Error, 'Headers must be a hash with symbols or strings, found "foo".')
      end

      it "should pass open_timeout and timeout through to http_connection for http_#{method}" do
        stub_request(method, EXAMPLE_SERVER).to_return(body: '{}')
        expect(connection).to receive(:http_connection)
          .with(EXAMPLE_SERVER, skip_authentication: false, open_timeout: 2, timeout: 5)
          .and_call_original
        connection.send(:"http_#{method}", EXAMPLE_SERVER, nil, nil, open_timeout: 2, timeout: 5)
      end
    end

    describe 'short hand requests with body' do
      [:post, :put, :patch].each do |method|
        it "should be possible to use short hand http_#{method}" do
          stub = stub_request(method, EXAMPLE_SERVER)
                 .with(headers: { 'secret_key' => 'dangerously shared key' })
                 .to_return(body: { foo: 'bar' }.to_json)
          response = connection.send(:"http_#{method}", EXAMPLE_SERVER)
          expect(response.status).to eq(200)
          expect(JSON.parse(response.body)).to eq({ 'foo' => 'bar' })
          expect(stub).to have_been_requested.times(1)
        end

        it "should send a raw-marked query parameter unescaped for http_#{method}" do
          stub = stub_request(method, "#{EXAMPLE_SERVER}?d=a%3Bb").to_return(body: 'ok')
          connection.send(:"http_#{method}", EXAMPLE_SERVER) do |request|
            request.params['d'] = IPaaS::Job::Outbound::HTTP.raw_param_value('a%3Bb')
          end
          expect(stub).to have_been_requested.times(1)
        end

        it "should escape an unmarked already-encoded query parameter for http_#{method}" do
          stub = stub_request(method, "#{EXAMPLE_SERVER}?d=a%253Bb").to_return(body: 'ok')
          connection.send(:"http_#{method}", EXAMPLE_SERVER) do |request|
            request.params['d'] = 'a%3Bb'
          end
          expect(stub).to have_been_requested.times(1)
        end

        it "should be possible to pass body and additional headers for http_#{method}" do
          stub = stub_request(method, EXAMPLE_SERVER)
                 .with(headers: { 'secret_key' => 'dangerously shared key', 'h2' => 'baz' }, body: 'foo')
                 .to_return(body: { foo: 'bar' }.to_json)
          response = connection.send(:"http_#{method}", EXAMPLE_SERVER, 'foo', { h2: 'baz' })
          expect(response.status).to eq(200)
          expect(JSON.parse(response.body)).to eq({ 'foo' => 'bar' })
          expect(stub).to have_been_requested.times(1)
        end

        it "should be possible to pass body and additional headers for http_#{method} using a block" do
          stub = stub_request(method, EXAMPLE_SERVER)
                 .with(headers: { 'secret_key' => 'dangerously shared key', 'h2' => 'baz' }, body: 'foo')
                 .to_return(body: { foo: 'bar' }.to_json)
          response = connection.send(:"http_#{method}", EXAMPLE_SERVER, 'foo') do |request|
            request.headers[:h2] = 'baz'
          end
          expect(response.status).to eq(200)
          expect(JSON.parse(response.body)).to eq({ 'foo' => 'bar' })
          expect(stub).to have_been_requested.times(1)
        end

        it 'should validate the URI' do
          expect do
            connection.send(:"http_#{method}", 'foo/bar')
          end.to raise_error(IPaaS::Error, 'URI foo/bar is invalid.')
        end

        it 'should validate the headers' do
          expect do
            connection.send(:"http_#{method}", EXAMPLE_SERVER, nil, 'foo')
          end.to raise_error(IPaaS::Error, 'Headers must be a hash with symbols or strings, found "foo".')
        end

        it 'should validate the body' do
          expect do
            connection.send(:"http_#{method}", EXAMPLE_SERVER, { bo: 'dy' })
          end.to raise_error(IPaaS::Error, 'Body must be a string, found {bo: "dy"}. Consider adding `.to_s`.')
        end
      end
    end
  end
end
