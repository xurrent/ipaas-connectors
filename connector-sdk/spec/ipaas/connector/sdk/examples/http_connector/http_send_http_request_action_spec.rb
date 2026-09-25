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
      pattern = action.input_schema.field(:query_parameters).field(:name).pattern
      expect(pattern).to eq(/\A[A-Za-z0-9$\-_\[\]]+\z/)
      expect('$filter').to match(pattern)
      expect('$skiptoken').to match(pattern)
      expect('$top').to match(pattern)
      expect('%24filter').not_to match(pattern)
      expect('$fil ter').not_to match(pattern)
    end

    it 'should keep body optional' do
      expect(action.input_schema.field(:body).required).to be_falsey
    end
  end

  context 'output_schema' do
    let(:response_headers) { action.output_schemas.first.field(:response).field(:headers) }

    it 'should require a response header name' do
      expect(response_headers.field(:name).required).to be_truthy
    end

    it 'should keep the response header value optional so an empty value validates' do
      expect(response_headers.field(:value).required).to be_falsey
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

      it 'should percent-encode an OData $-prefixed parameter name on the wire' do
        stub = stub_request(:get, "#{example_server}?%24top=5")
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', query_parameters: [
          { name: '$top', value: '5' },
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
      # WebMock sorts query keys on both sides before matching, so a stub URL proves which bytes
      # each value carries but never the order the keys went out in. Capture what the encoder
      # emits instead: that string is verbatim the query Faraday puts on the wire.
      def captured_queries
        queries = []
        allow(IPaaS::Job::Outbound::SelectiveParamsEncoder).to receive(:encode).and_wrap_original do |original, params|
          original.call(params).tap { |query| queries << query }
        end
        queries
      end

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

      it 'should escape an already-encoded value again when already_encoded is not set' do
        # Contrast case for the specs below: this is the pre-existing behaviour that
        # breaks signed URLs, and it must stay put for every caller that does not opt out.
        stub = stub_request(:get, "#{example_server}?d=attachment%253B%2Bfile.csv")
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', query_parameters: [
          { name: 'd', value: 'attachment%3B+file.csv' },
        ], })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end

      it 'should send an already-encoded value byte-for-byte when already_encoded is set' do
        stub = stub_request(:get, "#{example_server}?d=attachment%3B+file.csv")
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', query_parameters: [
          { name: 'd', value: 'attachment%3B+file.csv', already_encoded: true },
        ], })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end

      it 'should still escape an unflagged value sitting alongside a raw one' do
        stub = stub_request(:get, "#{example_server}?d=a%3Bb&note=x+y")
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', query_parameters: [
          { name: 'd', value: 'a%3Bb', already_encoded: true },
          { name: 'note', value: 'x y' },
        ], })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end

      it 'should escape the value when already_encoded is explicitly false' do
        stub = stub_request(:get, "#{example_server}?d=a%253Bb")
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', query_parameters: [
          { name: 'd', value: 'a%3Bb', already_encoded: false },
        ], })
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end

      it 'should pass the value through when a proc supplies the flag as a string' do
        # A whole-array `proc:`/`fixed:` mapping is not type-cast (NestedType falls back to a plain
        # hash), so the flag arrives as a String here where the designer's nested path arrives cast.
        # Both shapes must agree, or the same value 403s depending on how the mapping was authored.
        stub = stub_request(:get, "#{example_server}?d=a%3Bb").to_return(body: 'Hello World!')
        run_action({ method: 'GET', query_parameters: [
          { name: 'd', value: 'a%3Bb', already_encoded: 'true' },
        ], })
        expect(stub).to have_been_requested.once
      end

      it 'should escape the value when a proc supplies a false-ish flag as a string' do
        queries = captured_queries
        stub = stub_request(:get, "#{example_server}?d=a%253Bb").to_return(body: 'Hello World!')

        output = run_action({ method: 'GET', query_parameters: [
          { name: 'd', value: 'a%3Bb', already_encoded: '0' },
        ], })

        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(queries.last).to eq('d=a%253Bb')
        expect(stub).to have_been_requested.once
      end

      # The spellings ActiveModel would read as true and the toggle deliberately does not. Each one
      # has to stay escaped, or a condition that readmitted any of them would pass this suite unseen.
      %w[1 t on yes].each do |flag|
        it "should not treat #{flag.inspect} as enabling already_encoded" do
          queries = captured_queries
          stub = stub_request(:get, "#{example_server}?d=a%253Bb").to_return(body: 'Hello World!')

          output = run_action({ method: 'GET', query_parameters: [
            { name: 'd', value: 'a%3Bb', already_encoded: flag },
          ], })

          expect(output.dig(:response, :body)).to eq('Hello World!')
          expect(queries.last).to eq('d=a%253Bb')
          expect(stub).to have_been_requested.once
        end
      end

      it 'should send a signed URL query string in the given order, byte for byte' do
        # CloudFront signs the literal query string, so both the escaping and the key order
        # have to survive. Faraday's default encoder would sort these alphabetically.
        signed = 'response-content-disposition=attachment%3B+filename%2A%3DUTF-8%27%27p.csv' \
                 '&Expires=1786611447&Signature=321Khx-zhb8Uv5x~ONRVnpn__&Key-Pair-Id=K1B11OUIVHWE4B'
        queries = captured_queries
        stub = stub_request(:get, "#{example_server}?#{signed}").to_return(body: 'csv,data')
        output = run_action({ method: 'GET', query_parameters: [
          { name: 'response-content-disposition',
            value: 'attachment%3B+filename%2A%3DUTF-8%27%27p.csv', already_encoded: true, },
          { name: 'Expires', value: '1786611447', already_encoded: true },
          { name: 'Signature', value: '321Khx-zhb8Uv5x~ONRVnpn__', already_encoded: true },
          { name: 'Key-Pair-Id', value: 'K1B11OUIVHWE4B', already_encoded: true },
        ], })
        expect(output.dig(:response, :body)).to eq('csv,data')
        expect(queries.last).to eq(signed)
        expect(stub).to have_been_requested.once
      end

      context 'with an API key placed in the query string' do
        let(:outbound_connection_config) do
          {
            # The space matters: it makes the escaped form differ visibly from the raw one, so
            # the assertion below can tell "escaped" from "passed through".
            api_key: { key: 'secret', value: make_secret_string('k 1'), placement: 'Query params' },
            base_url: example_server,
          }
        end

        it 'should still escape the injected key and lead the query string with it' do
          # The key is injected when the connection is built, before the action's params are
          # set, so it leads the query string rather than landing inside the signed portion.
          queries = captured_queries
          stub = stub_request(:get, "#{example_server}?secret=k+1&d=a%3Bb&zz=x+y")
                 .to_return(body: 'Hello World!')
          output = run_action({ method: 'GET', query_parameters: [
            { name: 'd', value: 'a%3Bb', already_encoded: true },
            { name: 'zz', value: 'x y' },
          ], })
          expect(output.dig(:response, :body)).to eq('Hello World!')
          expect(queries.last).to eq('secret=k+1&d=a%3Bb&zz=x+y')
          expect(stub).to have_been_requested.once
        end
      end

      it 'should keep a name-only parameter bare whichever way the toggle is set' do
        # `value` is not required, so an entry can be name-only. Flipping encoding must not turn a
        # bare `flag` into `flag=`; that is a different request to APIs that distinguish the two.
        stub = stub_request(:get, "#{example_server}?flag").to_return(body: 'Hello World!')
        run_action({ method: 'GET', query_parameters: [{ name: 'flag', already_encoded: true }] })
        run_action({ method: 'GET', query_parameters: [{ name: 'flag' }] })
        expect(stub).to have_been_requested.twice
      end

      it 'should read a toggle that carries surrounding whitespace, as a data pill can' do
        # The uncast whole-array path hands the toggle over as a raw string; without the strip this
        # silently escapes the value a second time and the signed URL 403s with no error.
        stub = stub_request(:get, "#{example_server}?d=a%3Bb").to_return(body: 'Hello World!')
        run_action({ method: 'GET', query_parameters: [
          { name: 'd', value: 'a%3Bb', already_encoded: ' True ' },
        ], })
        expect(stub).to have_been_requested.once
      end

      it 'should refuse an unencoded value that would inject a second query parameter' do
        # The value beside the toggle routinely carries a data pill from a webhook payload, so a
        # bare & would let a third party append parameters to an authenticated outbound request.
        expect do
          run_action({ method: 'GET', query_parameters: [
            { name: 'filter', value: 'sig&api_key=EVIL', already_encoded: true },
          ], })
        end.to raise_error(IPaaS::Error, /must not contain '&', a tab/)
      end

      it 'should send a bare semicolon inside an already-encoded value as part of that one value' do
        # A CloudFront signed URL carries response-content-type=text/plain;charset=utf-8 as one value.
        # WebMock normalises `;` and `=` alike on both sides, so only the captured query proves the bytes.
        queries = captured_queries
        stub = stub_request(:get, "#{example_server}?filter=sig%3Bapi_key=EVIL").to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', query_parameters: [
          { name: 'filter', value: 'sig;api_key=EVIL', already_encoded: true },
        ], })
        expect(queries.last).to eq('filter=sig;api_key=EVIL')
        expect(output.dig(:response, :body)).to eq('Hello World!')
        expect(stub).to have_been_requested.once
      end

      context 'configured the way the designer stores it' do
        # run_action builds one `fixed:` blob holding the whole array with a native Ruby false.
        # The designer instead writes a nested mapping per array entry, and BooleanFieldEditor
        # stores the toggle as String(value), so what actually reaches the connector is the
        # STRING "true", cast back to a boolean by BooleanType. Nothing else covers that path.
        def designer_input_mapping(flag_fixed)
          nested = [{ field_id: 'name', fixed: 'd' }, { field_id: 'value', fixed: 'a%3Bb' }]
          nested << { field_id: 'already_encoded', fixed: flag_fixed } if flag_fixed
          [{ field_id: 'method', fixed: 'GET' }, { field_id: 'query_parameters', nested: nested }]
        end

        def run_designer_action(flag_fixed)
          built = IPaaS::Connector::Action.parse(
            runbook,
            { reference: SecureRandom.uuid,
              outbound_connection: { uuid: outbound_connection&.uuid },
              action_template: { uuid: action_template.uuid },
              input_mapping: designer_input_mapping(flag_fixed), },
          )
          raise IPaaS::Error, "Action invalid: #{built.full_error_messages}" unless built.valid?

          built.run
        end

        it 'should pass the value through when the toggle stored the string "true"' do
          stub = stub_request(:get, "#{example_server}?d=a%3Bb").to_return(body: 'Hello World!')
          run_designer_action('true')
          expect(stub).to have_been_requested.once
        end

        it 'should escape the value when the toggle stored the string "false"' do
          stub = stub_request(:get, "#{example_server}?d=a%253Bb").to_return(body: 'Hello World!')
          run_designer_action('false')
          expect(stub).to have_been_requested.once
        end

        it 'should escape the value when the entry predates the toggle' do
          # No already_encoded child at all, which is every parameter stored before this change.
          stub = stub_request(:get, "#{example_server}?d=a%253Bb").to_return(body: 'Hello World!')
          run_designer_action(nil)
          expect(stub).to have_been_requested.once
        end
      end

      it 'should send repeated raw names bare instead of appending []' do
        stub = stub_request(:get, "#{example_server}?q=A&q=B")
               .to_return(body: 'Hello World!')
        output = run_action({ method: 'GET', query_parameters: [
          { name: 'q', value: 'A', already_encoded: true },
          { name: 'q', value: 'B', already_encoded: true },
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

      it 'should return a header the server sent with an empty value' do
        # An empty field value is valid HTTP, so a 200 carrying one must not fail
        # output validation. The entry is kept so the runbook still sees the header.
        stub_request(:get, example_server)
          .to_return(body: 'Hello World!', headers: { 'x-ratelimit-limit' => '' })
        output = run_action({ method: 'GET' })
        expect(output.dig(:response, :headers)).to include({ name: 'x-ratelimit-limit', value: '' })
      end

      it 'should return the Request#81284669 response whose three rate-limit headers are all empty' do
        stub_request(:get, example_server).to_return(
          status: 200,
          body: '{"count":1}',
          headers: {
            'content-type' => 'application/json',
            'x-ratelimit-limit' => '',
            'x-ratelimit-remaining' => '',
            'x-ratelimit-period' => '',
          },
        )
        output = run_action({ method: 'GET' })
        expect(output.dig(:response, :status)).to eq(200)
        expect(output.dig(:response, :body)).to eq('{"count":1}')
        expect(output.dig(:response, :headers)).to include(
          { name: 'x-ratelimit-limit', value: '' },
          { name: 'x-ratelimit-remaining', value: '' },
          { name: 'x-ratelimit-period', value: '' },
        )
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
