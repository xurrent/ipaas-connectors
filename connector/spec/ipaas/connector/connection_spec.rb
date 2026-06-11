require 'spec_helper'

describe IPaaS::Connector::Connection do
  let(:connector) do
    IPaaS::Connector::Connector.new('unique-connector-id') do
      helper :my_object_id do
        object_id
      end
      inbound_connection do
        config_schema do
          field :foo, 'Foo', :string,
                required: true,
                pattern: /\A[a-z]*\z/
        end
        validate do |request|
          unless request.params[:foo] == config[:foo]
            discard_trigger_event!("Request param 'foo' should equal '#{config[:foo]}'")
          end
        end
      end
      outbound_connection do
        config_schema do
          field :bar, 'Bar', :string,
                required: true
        end
        provision do
          log("Bar set to #{config[:bar]}")
        end
        deprovision do
          log("Bar removed for #{helpers.my_object_id}")
        end
        authenticate do |request|
          request.headers[:secret_key] = 'dangerously shared key'
        end
      end
    end
  end

  context 'inbound connection' do
    let(:connection_hash) do
      {
        uuid: 'connection_uuid',
        direction: :inbound,
        name: 'test inbound connection',
        description: 'Test description',
        connector: {
          uuid: connector.uuid,
        },
        config_mapping: [
          { field_id: :foo, fixed: 'barbie' },
        ],
      }
    end
    let(:connection) do
      IPaaS::Connector::Connection.parse(connection_hash)
    end

    it 'should define inbound?' do
      expect(connection.inbound?).to be_truthy
      expect(connection.outbound?).to be_falsey
    end

    it 'should define to_h' do
      expect(connection.to_h).to eq(connection_hash)
    end

    it 'should define to_h_ref' do
      expect(connection.to_h_ref).to eq({ uuid: 'connection_uuid' })
    end

    context 'validation' do
      it 'should be valid' do
        expect(connection).to be_valid
      end

      it 'should validate the given value is a hash' do
        expect do
          IPaaS::Connector::Connection.parse([1, 2])
        end.to raise_error('Connection must be a hash.')
      end

      it 'should validate name is required' do
        expect(connection.name).to eq('test inbound connection')
        connection.name = nil
        expect(connection).not_to be_valid
        expect(connection.errors[:name]).to eq(["can't be blank."])
      end

      it 'should validate direction is required' do
        expect(connection.direction).to eq(:inbound)
        connection.direction = nil
        expect(connection).not_to be_valid
        expect(connection.errors[:direction]).to include("can't be blank.")
      end

      it 'should validate direction is correct' do
        connection.direction = :foo
        expect(connection).not_to be_valid
        expect(connection.errors[:direction]).to include('must be one of "inbound", "outbound".')
      end

      it 'should validate the config' do
        invalid_connection = IPaaS::Connector::Connection.parse(
          {
            direction: 'inbound',
            name: 'test inbound connection',
            connector: {
              uuid: connector.uuid,
            },
          }.to_yaml
        )
        expect(invalid_connection).not_to be_valid
        expect(invalid_connection.errors[:config_mapping]).to include("invalid: Field 'foo' is required.")
      end

      it 'should validate the config mapping' do
        invalid_connection = IPaaS::Connector::Connection.parse(
          {
            direction: 'inbound',
            name: 'test inbound connection',
            connector: {
              uuid: connector.uuid,
            },
            config_mapping: [
              { field_id: 'foo', proc: 'unknown(3)' },
            ],
          }.to_yaml
        )
        expect(invalid_connection).not_to be_valid
        message = "(foo) invalid: Proc invalid: Method 'unknown' not allowed."
        expect(invalid_connection.errors[:config_mapping]).to include(message)
      end

      it 'should not accept call to provision when config is invalid' do
        invalid_connection = IPaaS::Connector::Connection.parse(
          {
            direction: 'inbound',
            name: 'test inbound connection',
            connector: {
              uuid: connector.uuid,
            },
          }.to_yaml
        )
        expect do
          invalid_connection.provision
        end.to raise_error('Cannot provision connection when the config is invalid.')
        expect(invalid_connection.errors[:config_mapping]).to include("invalid: Field 'foo' is required.")
      end
    end

    context 'uuid' do
      it 'should take the given UUID' do
        expect(connection.uuid).to eq('connection_uuid')
      end

      it 'should generate a UUID when none is provided' do
        allow(SecureRandom).to receive(:uuid_v7) { 'foo-uuid' }
        uuid_connection = IPaaS::Connector::Connection.parse({ direction: 'inbound', name: 'foo' })
        expect(uuid_connection.uuid).to eq('foo-uuid')
      end
    end

    context 'validate_request' do
      it 'should discard the trigger event' do
        request = double
        expect(request).to receive(:params) { { foo: 'not barbie' } }
        expect do
          connection.validate_request(request)
        end.to raise_error(IPaaS::Job::DiscardTriggerEvent, "Request param 'foo' should equal 'barbie'")
      end

      it 'should accept the job' do
        request = double
        expect(request).to receive(:params) { { foo: 'barbie' } }
        expect do
          connection.validate_request(request)
        end.not_to raise_error
      end
    end

    it 'should define a self reference' do
      expect(connection.inbound_connection).to eq(connection)
      expect(connection.outbound_connection).to be_nil
    end
  end

  context 'outbound connection' do
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
            { field_id: 'bar', proc: '"hi" + "gh"' },
            { field_id: 'proxy_server', proc: '{ host: "https://127.0.0.1:8080", username: "foo" }' },
          ],
        },
      )
    end

    it 'should define outbound?' do
      expect(connection.inbound?).to be_falsey
      expect(connection.outbound?).to be_truthy
    end

    context 'validation' do
      it 'should be valid' do
        expect(connection).to be_valid
      end

      it 'should validate the given value is a hash' do
        expect do
          IPaaS::Connector::Connection.parse([1, 2])
        end.to raise_error('Connection must be a hash.')
      end

      it 'should validate name is required' do
        expect(connection.name).to eq('test outbound connection')
        connection.name = nil
        expect(connection).not_to be_valid
        expect(connection.errors[:name]).to eq(["can't be blank."])
      end

      it 'should validate direction is required' do
        expect(connection.direction).to eq(:outbound)
        connection.direction = nil
        expect(connection).not_to be_valid
        expect(connection.errors[:direction]).to include("can't be blank.")
      end

      it 'should validate direction is correct' do
        connection.direction = :foo
        expect(connection).not_to be_valid
        expect(connection.errors[:direction]).to include('must be one of "inbound", "outbound".')
      end

      it 'should validate the config' do
        invalid_connection = IPaaS::Connector::Connection.parse(
          {
            direction: 'outbound',
            name: 'test outbound connection',
            connector: {
              uuid: connector.uuid,
            },
          }.to_yaml
        )
        expect(invalid_connection).not_to be_valid
        expect(invalid_connection.errors[:config_mapping]).to include("invalid: Field 'bar' is required.")
      end

      it 'should not accept call to provision when config is invalid' do
        invalid_connection = IPaaS::Connector::Connection.parse(
          {
            direction: 'outbound',
            name: 'test outbound connection',
            connector: {
              uuid: connector.uuid,
            },
          }.to_yaml
        )
        expect do
          invalid_connection.provision
        end.to raise_error('Cannot provision connection when the config is invalid.')
        expect(invalid_connection.errors[:config_mapping]).to include("invalid: Field 'bar' is required.")
      end
    end

    context 'runbook variables' do
      let(:runbook_variable_connection) do
        IPaaS::Connector::Connection.parse(
          {
            direction: 'outbound',
            name: 'test outbound connection',
            connector: {
              uuid: connector.uuid,
            },
            config_mapping: [
              { field_id: 'bar', runbook_variable: 'my-variable' },
            ],
          }.to_yaml
        )
      end

      it 'should not validate required fields when they are based on a runbook variable' do
        expect(runbook_variable_connection).to be_valid
      end

      it 'should resolve runbook variables when runbook is present' do
        runbook = double
        expect(runbook).to receive(:read_variable).with('my-variable') { 'myvalue' }
        runbook_variable_connection.runbook = runbook
        runbook_variable_connection.config.resolve # NOTE: that `action.run` refreshes the outbound connection config
        expect(runbook_variable_connection.config[:bar]).to eq('myvalue')
      end
    end

    describe '#update_runbook_variable' do
      it 'updates runbook variables in config_mapping' do
        connection = IPaaS::Connector::Connection.parse(
          {
            direction: 'outbound',
            name: 'test outbound connection',
            connector: {
              uuid: connector.uuid,
            },
            config_mapping: [
              { field_id: 'bar', runbook_variable: 'old-id' },
              { field_id: 'baz', proc: 'runbook.read_variable("old-id")' },
              {
                field_id: 'qux',
                nested: [
                  { field_id: 'qux1', runbook_variable: 'old-id' },
                ],
              },
            ],
          }.to_yaml
        )

        updated = connection.update_runbook_variable('old-id', 'new-id')

        expect(updated).to be_truthy
        expect(connection.config_mapping[0].runbook_variable).to eq('new-id')
        expect(connection.config_mapping[1].proc).to eq('runbook.read_variable("new-id")')
        expect(connection.config_mapping[2].nested[0].runbook_variable).to eq('new-id')
      end

      it 'returns false when nothing is updated' do
        connection = IPaaS::Connector::Connection.parse(
          {
            direction: 'outbound',
            name: 'test outbound connection',
            connector: {
              uuid: connector.uuid,
            },
            config_mapping: [
              { field_id: 'bar', fixed: 'other-value' },
            ],
          }.to_yaml
        )

        expect(connection.update_runbook_variable('old-id', 'new-id')).to be_falsey
      end
    end

    describe '#uses_runbook_variables?' do
      it 'is true when a mapping references a runbook variable' do
        runbook_variable_connection = IPaaS::Connector::Connection.parse(
          {
            direction: 'outbound',
            name: 'test outbound connection',
            connector: { uuid: connector.uuid },
            config_mapping: [
              { field_id: 'bar', runbook_variable: 'my-variable' },
            ],
          }.to_yaml
        )
        expect(runbook_variable_connection.uses_runbook_variables?).to be true
      end

      it 'is false when no mapping references a runbook variable' do
        # Contrast: the shared connection maps fields via fixed values and procs only.
        expect(connection.uses_runbook_variables?).to be false
      end
    end

    context 'uuid' do
      it 'should take the given UUID' do
        expect(connection.uuid).to eq('connection_uuid')
      end

      it 'should generate a UUID when none is provided' do
        allow(SecureRandom).to receive(:uuid_v7) { 'foo-uuid' }
        uuid_connection = IPaaS::Connector::Connection.parse({ direction: 'outbound', name: 'foo' })
        expect(uuid_connection.uuid).to eq('foo-uuid')
      end
    end

    context 'authenticate' do
      it 'should update the header when authenticate request is called' do
        request = double(headers: {})
        connection.authenticate_request(request)
        expect(request.headers[:secret_key]).to eq('dangerously shared key')
      end
    end

    context 'provision' do
      it 'should log some data' do
        logs = []
        allow(connection).to receive(:log) { |msg| logs << msg }
        connection.provision
        expect(logs.first).to eq('Bar set to high')
      end
    end

    context 'deprovision' do
      it 'should log some data' do
        logs = []
        allow(connection).to receive(:log) { |msg| logs << msg }
        connection.deprovision
        expect(logs.first).to eq("Bar removed for #{connection.object_id}")
      end
    end

    # The block dispatches on the resolved config value so a single connector
    # covers all result shapes.
    let(:tester_connector) do
      IPaaS::Connector::Connector.new('config-tester-connector-id') do
        outbound_connection do
          config_schema do
            field :bar, 'Bar', :string, required: true
          end
          config_tester do
            log('config_tester invoked')
            case config[:bar]
            when 'success' then { status: :success, message: 'ok' }
            when 'failed' then { status: :failed, message: 'wrong credentials' }
            when 'error' then { status: :error, message: 'cannot reach' }
            when 'string-status' then { status: 'failed', message: 'wrong credentials' }
            when 'string-keys' then { 'status' => 'success', 'message' => 'ok' }
            when 'invalid-status' then { status: :weird, message: 'x' }
            when 'not-a-hash' then 'nope'
            when 'ipaas-error' then raise IPaaS::Error, 'boom'
            when 'read-timeout' then raise Faraday::TimeoutError, 'execution expired'
            when 'open-timeout'
              # Mirror faraday-net_http: an open timeout is re-raised as ConnectionFailed.
              begin
                raise Net::OpenTimeout, 'execution expired'
              rescue Net::OpenTimeout => e
                raise Faraday::ConnectionFailed, e
              end
            when 'dns-failure'
              begin
                raise SocketError, 'getaddrinfo: name unknown'
              rescue SocketError => e
                raise Faraday::ConnectionFailed, e
              end
            else raise 'kaboom'
            end
          end
        end
      end
    end

    def tester_connection(bar_value)
      IPaaS::Connector::Connection.parse(
        {
          direction: 'outbound',
          name: 'config tester connection',
          connector: { uuid: tester_connector.uuid },
          config_mapping: [{ field_id: 'bar', fixed: bar_value }],
        },
      )
    end

    describe '#config_tester' do
      it 'returns the success result unchanged' do
        expect(tester_connection('success').config_tester).to eq({ status: :success, message: 'ok' })
      end

      it 'returns the failed result unchanged' do
        expect(tester_connection('failed').config_tester).to eq({ status: :failed, message: 'wrong credentials' })
      end

      it 'returns the error result unchanged' do
        expect(tester_connection('error').config_tester).to eq({ status: :error, message: 'cannot reach' })
      end

      it 'coerces a string status to a symbol' do
        # Contrast with 'returns the failed result unchanged' which uses a symbol status.
        expect(tester_connection('string-status').config_tester)
          .to eq({ status: :failed, message: 'wrong credentials' })
      end

      it 'accepts a result hash with string keys' do
        # Connectors may build the result from parsed JSON, which has string keys.
        expect(tester_connection('string-keys').config_tester)
          .to eq({ status: :success, message: 'ok' })
      end

      it 'normalizes an unknown status to an error result' do
        expect(tester_connection('invalid-status').config_tester)
          .to eq({ status: :error, message: 'Test returned an invalid result.' })
      end

      it 'normalizes a non-hash return value to an error result' do
        expect(tester_connection('not-a-hash').config_tester)
          .to eq({ status: :error, message: 'Test returned an invalid result.' })
      end

      it 'converts an IPaaS::Error raised by the function into an error result' do
        expect(tester_connection('ipaas-error').config_tester).to eq({ status: :error, message: 'boom' })
      end

      it 'converts a StandardError raised by the function into an error result' do
        expect(tester_connection('anything-else').config_tester).to eq({ status: :error, message: 'kaboom' })
      end

      it 'converts a read timeout into a timed-out error result' do
        expect(tester_connection('read-timeout').config_tester)
          .to eq({ status: :error, message: 'The connection test timed out.' })
      end

      it 'converts an open timeout wrapped in a connection failure into a timed-out error result' do
        # faraday-net_http delivers Net::OpenTimeout as Faraday::ConnectionFailed.
        expect(tester_connection('open-timeout').config_tester)
          .to eq({ status: :error, message: 'The connection test timed out.' })
      end

      it 'keeps the message of a connection failure that is not a timeout' do
        # Contrast with the open-timeout case: Faraday::ConnectionFailed also
        # covers DNS and refused connections, which must not read as timeouts.
        expect(tester_connection('dns-failure').config_tester)
          .to eq({ status: :error, message: 'getaddrinfo: name unknown' })
      end

      it 'returns an error result without invoking the function when the config is invalid' do
        invalid_connection = IPaaS::Connector::Connection.parse(
          {
            direction: 'outbound',
            name: 'config tester connection',
            connector: { uuid: tester_connector.uuid },
          },
        )
        logs = []
        allow(invalid_connection).to receive(:log) { |msg| logs << msg }
        expect(invalid_connection.config_tester)
          .to eq({ status: :error, message: 'Connection configuration is invalid.' })
        # The config_tester block logs on entry; no log proves it did not run.
        expect(logs).to be_empty
      end

      it 'returns an error result when the connector does not provide a config tester' do
        expect(connection.config_tester)
          .to eq({ status: :error, message: 'Connector does not provide a config tester.' })
      end

      it 'returns an error result for an inbound connection' do
        inbound_connection = IPaaS::Connector::Connection.parse(
          {
            direction: 'inbound',
            name: 'test inbound connection',
            connector: { uuid: connector.uuid },
            config_mapping: [{ field_id: :foo, fixed: 'barbie' }],
          },
        )
        expect(inbound_connection.config_tester)
          .to eq({ status: :error, message: 'Connector does not provide a config tester.' })
      end
    end

    describe '#config_tester?' do
      it 'is true when the connector defines a config_tester on an outbound connection' do
        expect(tester_connection('success').config_tester?).to be true
      end

      it 'is false when the connector does not define a config_tester' do
        # Contrast with 'is true when the connector defines a config_tester'.
        expect(connection.config_tester?).to be false
      end

      it 'is false for an inbound connection' do
        inbound_connection = IPaaS::Connector::Connection.parse(
          {
            direction: 'inbound',
            name: 'test inbound connection',
            connector: { uuid: connector.uuid },
            config_mapping: [{ field_id: :foo, fixed: 'barbie' }],
          },
        )
        expect(inbound_connection.config_tester?).to be false
      end
    end

    it 'should define a self reference' do
      expect(connection.outbound_connection).to eq(connection)
      expect(connection.inbound_connection).to be_nil
    end
  end

  context 'connection template helpers' do
    let(:helpers_connector) do
      IPaaS::Connector::Connector.new('connection-helpers-connector-id') do
        helper :shared_suffix do
          'connector'
        end
        inbound_connection do
          config_schema do
            field :foo, 'Foo', :string
          end
          helper :inbound_greeting do
            "inbound #{helpers.shared_suffix}"
          end
          validate do |_request|
            discard_trigger_event!(helpers.inbound_greeting)
          end
        end
        outbound_connection do
          config_schema do
            field :bar, 'Bar', :string, required: true
          end
          helper :local_message do
            "local #{helpers.shared_suffix}"
          end
          config_tester do
            { status: :success, message: helpers.local_message }
          end
        end
      end
    end

    def parse_connection(direction, config_mapping)
      IPaaS::Connector::Connection.parse(
        {
          direction: direction,
          name: "test #{direction} connection",
          connector: { uuid: helpers_connector.uuid },
          config_mapping: config_mapping,
        },
      )
    end

    it 'resolves outbound connection helpers and falls back to connector helpers' do
      connection = parse_connection('outbound', [{ field_id: 'bar', fixed: 'high' }])
      # 'local connector' proves both the connection-local helper and its
      # parent fallback to the connector-level helper resolved.
      expect(connection.config_tester).to eq({ status: :success, message: 'local connector' })
    end

    it 'resolves inbound connection helpers and falls back to connector helpers' do
      connection = parse_connection('inbound', [{ field_id: 'foo', fixed: 'barbie' }])
      # 'inbound connector' proves both the connection-local helper (inbound_greeting)
      # and its parent fallback to the connector-level helper (shared_suffix) resolved.
      expect { connection.validate_request(double) }
        .to raise_error(IPaaS::Job::DiscardTriggerEvent, 'inbound connector')
    end

    it 'reaches a connector-level helper through the connection helpers' do
      connection = parse_connection('outbound', [{ field_id: 'bar', fixed: 'high' }])
      # shared_suffix is defined only on the connector, proving the parent chain
      # is walked for a helper missing on the connection template.
      expect(connection.helpers.shared_suffix).to eq('connector')
    end

    it 'raises NoMethodError for a helper not defined anywhere in the chain' do
      connection = parse_connection('outbound', [{ field_id: 'bar', fixed: 'high' }])
      # Contrast with 'reaches a connector-level helper through the connection helpers'.
      expect { connection.helpers.unknown_helper }
        .to raise_error(NoMethodError, "Missing helper method 'unknown_helper'.")
    end

    it 'has no helpers when the connection has no connector' do
      expect(IPaaS::Connector::Connection.new('no-connector-uuid').helpers).to be_nil
    end
  end
end
