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

      it 'should validate the URI' do
        expect do
          connection.send(:"http_#{method}", 'foo/bar')
        end.to raise_error(IPaaS::Error, 'URI foo/bar is invalid.')
      end

      it 'should validate the params' do
        expect do
          connection.send(:"http_#{method}", EXAMPLE_SERVER, 'foo')
        end.to raise_error(IPaaS::Error, 'Params must be a hash with symbols or strings, found "foo".')
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
