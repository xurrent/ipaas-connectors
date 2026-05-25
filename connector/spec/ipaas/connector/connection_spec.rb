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

    it 'should define a self reference' do
      expect(connection.outbound_connection).to eq(connection)
      expect(connection.inbound_connection).to be_nil
    end
  end
end
