require 'spec_helper'

describe 'HTTP Send HTTP Request Action', :action do
  let(:example_server) { 'https://example.com' }
  let(:action_template_id) { '0195fa8b-e402-713c-bf69-cf192637bbe3' }

  context 'outbound connection' do
    context 'config' do
      it 'should allow API key authentication' do
        expect(connector.outbound_connection.authenticators).to include(:api_key)
      end

      it 'should allow basic auth authentication' do
        expect(connector.outbound_connection.authenticators).to include(:basic_auth)
      end

      it 'should allow bearer authentication' do
        expect(connector.outbound_connection.authenticators).to include(:bearer)
      end

      it 'should allow oauth2 authentication' do
        expect(connector.outbound_connection.authenticators).to include(:oauth2)
      end
    end

    context 'api key' do
      let(:secret_value) { make_secret_string('boo') }
      let(:outbound_connection_config) do
        {
          api_key: {
            key: 'secret',
            value: secret_value,
            placement: 'Query params',
          },
          base_url: example_server,
        }
      end

      it 'should add the API key to the outbound request' do
        stub = stub_request(:get, example_server)
               .with(query: { 'secret' => 'boo' })
               .to_return(body: { foo: 'bar' }.to_json)
        output = run_action({ method: 'GET' })
        expect(JSON.parse(output.dig(:response, :body))).to eq({ 'foo' => 'bar' })
        expect(stub).to have_been_requested.once
      end
    end

    context 'basic auth' do
      let(:outbound_connection_config) do
        {
          basic_auth: {
            username: 'admin',
            password: make_secret_string('12345'),
          },
          base_url: example_server,
        }
      end

      it 'should add the authorization header to the outbound request' do
        stub = stub_request(:get, example_server)
               .with(headers: { 'Authorization' => 'Basic YWRtaW46MTIzNDU=' })
               .to_return(body: { foo: 'bar' }.to_json)
        output = run_action({ method: 'GET' })
        expect(JSON.parse(output.dig(:response, :body))).to eq({ 'foo' => 'bar' })
        expect(stub).to have_been_requested.once
      end
    end
  end

  context 'input_schema' do
    it 'should require a method' do
      expect(action.input_schema.field(:method).required).to be_truthy
    end

    it 'should validate the pattern of the path' do
      expect(action.input_schema.field(:path).pattern).to eq(%r{\A[A-Za-z0-9\-._~!$&'()*+,;=:@%/]+\z})
    end

    it 'should keep headers optional' do
      expect(action.input_schema.field(:headers).required).to be_falsey
    end

    it 'should require a header name in case a header is added' do
      expect(action.input_schema.field(:headers).field(:name).required).to be_truthy
    end

    it 'should validate the pattern of the header name' do
      expect(action.input_schema.field(:headers).field(:name).pattern).to eq(/\A[A-Za-z0-9\-_]+\z/)
    end

    it 'should keep query parameters optional' do
      expect(action.input_schema.field(:query_parameters).required).to be_falsey
    end

    it 'should require a query parameter name in case a header is added' do
      expect(action.input_schema.field(:query_parameters).field(:name).required).to be_truthy
    end

    it 'should validate the pattern of the query parameter name' do
      expect(action.input_schema.field(:query_parameters).field(:name).pattern).to eq(/\A[A-Za-z0-9\-_\[\]]+\z/)
    end

    it 'should keep body optional' do
      expect(action.input_schema.field(:body).required).to be_falsey
    end
  end

  context 'run' do
    let(:outbound_connection_config) do
      {
        base_url: example_server,
      }
    end

    context 'methods' do
      %w[HEAD GET POST PUT PATCH DELETE OPTIONS TRACE].each do |method|
        it "should be able to send basic #{method} requests" do
          stub = stub_request(method.downcase.to_sym, example_server)
                 .to_return(body: 'Hello World!')
          output = run_action({ method: method })
          expect(output.dig(:response, :body)).to eq('Hello World!')
          expect(stub).to have_been_requested.once
        end
      end
    end

    context 'path' do
      it 'should add the given path' do
        stub = stub_request(:get, "#{example_server}/my/path")
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', path: '/my/path' })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end

      it 'should accept relative paths' do
        stub = stub_request(:get, "#{example_server}/my/path")
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', path: 'my/path' })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end

      it 'should accept all 79 characters' do
        path = 'aAbBcCdDeEfFgGhH/iIjJkKlLmMnNoOpP/qQrRsStTuUvVwWxXyYzZ/0123456789/-._~!$&\'()*+,;=:@%12/foo'
        stub = stub_request(:get, "#{example_server}/#{path}")
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', path: path })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end

      it 'should ensure path is correct' do
        path = 'a\b /foo'
        pattern = "\\A[A-Za-z0-9\\-._~!$&'()*+,;=:@%\\/]+\\z"
        expect do
          run_action({ method: 'GET', path: path })
        end.to raise_error(
          IPaaS::Error,
          "Action invalid: Input mapping invalid: Field 'path' should confirm to pattern /#{pattern}/."
        )
      end
    end

    context 'headers' do
      it 'should add a header' do
        stub = stub_request(:get, example_server)
               .with(headers: { 'User-Agent' => 'Xurrent iPaaS', 'Foo-Bar' => 'Baz' })
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', headers: [
          { name: 'Foo-Bar', value: 'Baz' },
        ], })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end

      it 'should override the default User-Agent header' do
        stub = stub_request(:get, example_server)
               .with(headers: { 'User-Agent' => 'Ruby' })
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', headers: [
          { name: 'User-Agent', value: 'Ruby' },
        ], })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end

      context 'multi valued' do
        it 'should add an empty header' do
          stub = stub_request(:get, example_server)
                 .with(headers: { 'a' => '' })
                 .to_return(body: 'Hello World!')
          output = run_action({ method: 'GET', headers: [
            { name: 'a', value: nil },
            { name: 'a', value: nil },
          ], })
          expect(output.dig(:response, :body)).to eq('Hello World!')
          expect(stub).to have_been_requested.once
        end

        it 'should add a multi valued header' do
          # TODO: This is incorrect, see https://github.com/lostisland/faraday/issues/1120
          #       it should send the same header twice instead of concatenating the values with a comma
          stub = stub_request(:get, example_server)
                 .with(headers: { 'a' => '1, 2' })
                 .to_return(body: 'Hello World!')
          output = run_action({ method: 'GET', headers: [
            { name: 'a', value: '1' },
            { name: 'a', value: '2' },
          ], })
          expect(output.dig(:response, :body)).to eq('Hello World!')
          expect(stub).to have_been_requested.once
        end

        it 'should combine three or more repeated request headers into a single comma-joined value' do
          # Locks the connector description's claim that repeated request header names
          # are sent as a single comma-joined value (not multiple field lines).
          stub = stub_request(:get, example_server)
                 .with(headers: { 'Accept' => 'text/plain, application/json, text/html' })
                 .to_return(body: 'Hello World!')
          output = run_action({ method: 'GET', headers: [
            { name: 'Accept', value: 'text/plain' },
            { name: 'Accept', value: 'application/json' },
            { name: 'Accept', value: 'text/html' },
          ], })
          expect(output.dig(:response, :body)).to eq('Hello World!')
          expect(stub).to have_been_requested.once
        end
      end
    end

    context 'params' do
      it 'should add query parameters' do
        stub = stub_request(:get, example_server)
               .with(query: { 'q' => 'John', 'page' => '3' })
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', query_parameters: [
          { name: 'q', value: 'John' },
          { name: 'page', value: '3' },
        ], })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end

      context 'multi valued' do
        it 'should add an empty multi valued parameter' do
          # TODO: This is incorrect in Faraday, see https://github.com/lostisland/faraday/issues/182
          #       It should not automagically add the []
          #       Better solution would be to make this configurable for the connector developer
          #       something like http_connection.array_parameter_style = :none, :brackets, :brackets_with_index
          stub = stub_request(:get, "#{example_server}?a%5B%5D=")
                 .to_return(body: 'Hello World!')
          output = run_action({ method: 'GET', query_parameters: [
            { name: 'a', value: '' }, # when changing this to nil, the `=` is not sent?
            { name: 'a', value: nil },
          ], })
          expect(output.dig(:response, :body)).to eq('Hello World!')
          expect(stub).to have_been_requested.once
        end

        it 'should add a multi valued header' do
          # TODO: This is incorrect in Faraday, see https://github.com/lostisland/faraday/issues/182
          #       It should not automagically add the []
          #       Better solution would be to make this configurable for the connector developer
          #       something like http_connection.array_parameter_style = :none, :brackets, :brackets_with_index
          stub = stub_request(:get, "#{example_server}?a%5B%5D=1&a%5B%5D=2")
                 .to_return(body: 'Hello World!')
          output = run_action({ method: 'GET', query_parameters: [
            { name: 'a', value: '1' },
            { name: 'a', value: '2' },
          ], })
          expect(output.dig(:response, :body)).to eq('Hello World!')
          expect(stub).to have_been_requested.once
        end
      end
    end

    context 'body' do
      it 'should send the given body' do
        stub = stub_request(:get, example_server)
               .with(body: 'Foo Bar')
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', body: 'Foo Bar' })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end
    end

    context 'response status' do
      it 'should return a 4xx response to the workflow without raising' do
        stub_request(:get, example_server)
          .to_return(status: 404, body: 'Not Found', headers: { 'Content-Type' => 'text/plain' })
        output = run_action({ method: 'GET' })
        expect(output.dig(:response, :status)).to eq(404)
        expect(output.dig(:response, :body)).to eq('Not Found')
      end

      it 'should return a 5xx response to the workflow without raising' do
        stub_request(:get, example_server)
          .to_return(status: 503, body: 'Service Unavailable')
        output = run_action({ method: 'GET' })
        expect(output.dig(:response, :status)).to eq(503)
        expect(output.dig(:response, :body)).to eq('Service Unavailable')
      end

      it 'should return a 429 response without retrying' do
        # Locks the documented behaviour that the connector never retries on 429,
        # even when the response includes a Retry-After header.
        stub = stub_request(:get, example_server)
               .to_return(status: 429, headers: { 'Retry-After' => '30' })
        output = run_action({ method: 'GET' })
        expect(output.dig(:response, :status)).to eq(429)
        expect(stub).to have_been_requested.once
      end
    end

    context 'network errors' do
      it 'should surface the underlying error when the connection fails' do
        stub_request(:get, example_server)
          .to_raise(Faraday::ConnectionFailed.new('connection refused'))
        expect { run_action({ method: 'GET' }) }.to raise_error(Faraday::Error)
      end

      it 'should surface the underlying error on a request timeout' do
        stub_request(:get, example_server).to_timeout
        expect { run_action({ method: 'GET' }) }.to raise_error(Faraday::Error)
      end
    end

    context 'default headers' do
      it 'should send a User-Agent of Xurrent iPaaS by default' do
        # Locks the documented default that every outbound request carries
        # User-Agent: Xurrent iPaaS unless the runbook overrides it.
        stub = stub_request(:get, example_server)
               .with(headers: { 'User-Agent' => 'Xurrent iPaaS' })
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET' })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end
    end

    context 'query parameter encoding' do
      it 'should append [] to repeated parameter names' do
        # Locks the documented on-the-wire format: two entries with the same
        # name are emitted as `name[]=A&name[]=B`, not `name=A&name=B`.
        stub = stub_request(:get, "#{example_server}?q%5B%5D=A&q%5B%5D=B")
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', query_parameters: [
          { name: 'q', value: 'A' },
          { name: 'q', value: 'B' },
        ], })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end
    end

    context 'response headers' do
      it 'should combine duplicate response headers into a single comma-joined entry' do
        # Per RFC 9110 §5.3, a recipient MAY combine multiple field lines with the
        # same field name into one line separated by commas. Faraday::Utils::Headers
        # does this in `add_parsed` when parsing response headers.
        stub_request(:get, example_server)
          .to_return(body: 'Hello World!', headers: { 'X-Multi' => %w[a b] })
        output = run_action({ method: 'GET' })
        multi = output.dig(:response, :headers).select { |h| h[:name].to_s.downcase == 'x-multi' }
        expect(multi.size).to eq(1)
        expect(multi.first[:value]).to eq('a, b')
      end
    end

    context 'logging' do
      it 'should log the request and response' do
        stub = stub_request(:post, "#{example_server}?page=3")
               .to_return(body: 'Hello World!', headers: { 'Content-Type' => 'text/plain' })

        allow_any_instance_of(IPaaS::Job::Outbound::LoggingMiddleware).to receive(:emit)

        request_message = %(HTTP post request to https://example.com with headers {"User-Agent" => "Ruby"},
                            query parameters {"page" => "3"} and body: Foo Bar).squish
        expect_any_instance_of(Logger).to receive(:info).with(request_message)

        response_message = %(HTTP response 200 with headers {"content-type" => "text/plain"} and body "Hello World!")
        expect_any_instance_of(Logger).to receive(:info).with(response_message)

        output = run_action({
          method: 'POST',
          headers: [{ name: 'User-Agent', value: 'Ruby' }],
          query_parameters: [{ name: 'page', value: '3' }],
          body: 'Foo Bar',
        })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end
    end
  end
end
