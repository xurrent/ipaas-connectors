require 'spec_helper'

describe IPaaS::Connector do
  let(:connector) { IPaaS::Connector::Connector.new('uuid') }

  it 'should define by_uuid on the module' do
    expect(IPaaS::Connector.by_uuid('uuid')).to be_nil
    connector
    expect(IPaaS::Connector.by_uuid('uuid').uuid).to eq(connector.uuid)
  end

  describe 'update_available?' do
    it 'no update available for a connector not present in default scope' do
      connector_uuid = 'unique_uuid'
      expect(IPaaS::Connector.by_uuid(connector_uuid)).to be_nil

      IPaaS::Connector::Connector.uuid_scope('unique-solution') do
        expect(IPaaS::Connector.by_uuid(connector_uuid)).to be_nil

        outdated_connector = IPaaS::Connector::Connector.new(connector_uuid)
        outdated_connector.version = '1'
        expect(outdated_connector.uuid).to eq(connector_uuid)
        expect(outdated_connector.update_available?).to eq(false)
      end
      expect(IPaaS::Connector.by_uuid(connector_uuid)).to be_nil
    end

    it 'should detect when a newer version is available' do
      default_connector = connector
      default_connector.version = '2'
      connector_uuid = default_connector.uuid
      expect(IPaaS::Connector.by_uuid(connector_uuid)).to be(default_connector)
      expect(default_connector.update_available?).to eq(false)

      IPaaS::Connector::Connector.uuid_scope('outdated_solution') do
        expect(IPaaS::Connector.by_uuid(connector_uuid)).to be_nil

        outdated_connector = IPaaS::Connector::Connector.new(connector_uuid)
        outdated_connector.version = '1'
        expect(outdated_connector).not_to be(default_connector)
        expect(outdated_connector.uuid).to eq(connector_uuid)
        expect(outdated_connector.update_available?).to eq(true)
      end
    end

    it 'should detect when a connector is the latest value' do
      default_connector = connector
      default_connector.version = '2'
      connector_uuid = default_connector.uuid
      expect(IPaaS::Connector.by_uuid(connector_uuid)).to be(default_connector)
      expect(default_connector.update_available?).to eq(false)

      IPaaS::Connector::Connector.uuid_scope('outdated_solution') do
        expect(IPaaS::Connector.by_uuid(connector_uuid)).to be_nil

        outdated_connector = IPaaS::Connector::Connector.new(connector_uuid)
        outdated_connector.version = default_connector.version
        expect(outdated_connector).not_to be(default_connector)
        expect(outdated_connector.uuid).to eq(connector_uuid)
        expect(outdated_connector.update_available?).to eq(false)
      end
    end
  end

  describe 'attributes' do
    it 'should define a name' do
      connector.name 'foo'
      expect(connector.name).to eq('foo')
    end

    it 'should define an avatar' do
      connector.avatar 'foo'
      expect(connector.avatar).to eq('foo')
    end

    it 'should define a description' do
      connector.description 'foo'
      expect(connector.description).to eq('foo')
    end
  end

  describe 'validations' do
    it 'should validate the name is present' do
      expect(connector).not_to be_valid
      expect(connector.errors[:name]).to eq(["can't be blank."])

      connector.name = 'my connector'
      expect(connector).to be_valid
    end

    it 'should validate the avatar' do
      connector.name = 'my connector'
      connector.avatar 'foo'
      expect(connector).not_to be_valid

      connector.avatar 'https://foo.com/avatar/4?z=bar'
      expect(connector).to be_valid

      connector.avatar '/assets/icons/pencil.svg'
      expect(connector).to be_valid

      connector.avatar '/assets/icons/../../../pencil.svg'
      expect(connector).not_to be_valid
    end
  end

  it 'should define to_h_ref' do
    expect(connector.to_h_ref).to eq({ uuid: 'uuid' })
  end

  describe 'inbound connection' do
    before do
      connector.inbound_connection do
        api_key_validator
        config_schema do
          field :foo, 'Foo', :string
        end
        validate do
          'Hello world!'
        end
      end
    end

    it 'should retrieve details of the inbound connection' do
      inbound_connection = connector.inbound_connection
      expect(inbound_connection.validators).to eq([:api_key])
      expect(inbound_connection.config_schema.fields.first.label).to eq('Foo')
      expect(inbound_connection.validate.call).to eq('Hello world!')
    end

    it 'should reference back to the connector' do
      expect(connector.inbound_connection.connector).to eq(connector)
    end

    it 'should reference back to the connector from the schema' do
      expect(connector.inbound_connection.config_schema.connector).to eq(connector)
    end

    it 'should fail immediately when multiple inbound_connections are defined' do
      expect do
        connector.inbound_connection do
        end
      end.to raise_error('Duplicate inbound connection.')
    end

    it 'should validate the inbound connection' do
      connector.inbound_connection.validators << :bar

      expect(connector).not_to be_valid

      expect(connector.errors[:inbound_connection].size).to eq(1)
      fields_message = 'Validators unknown: bar.'
      expect(connector.errors[:inbound_connection].first).to eq("Inbound connection has errors: #{fields_message}")
    end
  end

  describe 'outbound connection' do
    before do
      connector.outbound_connection do
        api_key_authenticator
        config_schema do
          field :foo, 'Foo', :string
        end
        authenticate do
          'Hello world!'
        end
      end
    end

    it 'should retrieve details of the outbound connection' do
      outbound_connection = connector.outbound_connection
      expect(outbound_connection.authenticators).to eq([:api_key])
      expect(outbound_connection.config_schema.fields.first.label).to eq('Foo')
      expect(outbound_connection.authenticate.call).to eq('Hello world!')
    end

    it 'should reference back to the connector' do
      expect(connector.outbound_connection.connector).to eq(connector)
    end

    it 'should reference back to the connector from the schema' do
      expect(connector.outbound_connection.config_schema.connector).to eq(connector)
    end

    it 'should fail immediately when multiple outbound_connections are defined' do
      expect do
        connector.outbound_connection do
        end
      end.to raise_error('Duplicate outbound connection.')
    end

    it 'should validate the outbound connection' do
      connector.outbound_connection.authenticators << :bar

      expect(connector).not_to be_valid

      expect(connector.errors[:outbound_connection].size).to eq(1)
      fields_message = 'Authenticators unknown: bar.'
      expect(connector.errors[:outbound_connection].first).to eq("Outbound connection has errors: #{fields_message}")
    end
  end

  describe 'trigger templates' do
    before do
      connector.trigger('uuid') do
        name 'foo trigger'
        description 'foo trigger description'
        avatar 'foo'

        config_schema do
          field :foo, 'Foo', :string
        end
      end
    end

    it 'should retrieve details of the trigger' do
      expect(connector.triggers.size).to eq(1)
      trigger = connector.trigger('uuid')
      expect(trigger.name).to eq('foo trigger')
      expect(trigger.description).to eq('foo trigger description')
      expect(trigger.avatar).to eq('foo')
    end

    it 'should retrieve the first trigger when UUID is blank' do
      expect(connector.trigger.uuid).to eq('uuid')
    end

    it 'should register the trigger' do
      expect(IPaaS::Connector::TriggerTemplate.by_uuid('uuid').name).to eq('foo trigger')
    end

    it 'should reference back to the connector' do
      expect(connector.trigger('uuid').connector).to eq(connector)
    end

    it 'should reference back to the connector from the schema' do
      expect(connector.trigger.config_schema.connector).to eq(connector)
    end

    it 'should fail immediately when an trigger UUID is duplicated' do
      expect do
        connector.trigger('uuid') do
        end
      end.to raise_error('Duplicate Trigger Template UUID: uuid, in default scope.')
    end

    it 'should validate triggers with the connector' do
      expect(connector).not_to be_valid

      expect(connector.errors[:triggers].size).to eq(1)
      fields_message = "Avatar is invalid. Parse function is required, define 'parse do ... end'."
      expect(connector.errors[:triggers].first).to eq("Trigger uuid has errors: #{fields_message}")
    end
  end

  describe 'action templates' do
    before do
      connector.action('uuid') do
        name 'foo action'
        description 'foo action description'
        avatar 'foo'

        input_schema do
          field :foo, 'Foo', :string
        end
      end
    end

    it 'should retrieve details of action' do
      expect(connector.actions.size).to eq(1)
      action = connector.action('uuid')
      expect(action.name).to eq('foo action')
      expect(action.description).to eq('foo action description')
      expect(action.avatar).to eq('foo')
    end

    it 'should register the action' do
      expect(IPaaS::Connector::ActionTemplate.by_uuid('uuid').name).to eq('foo action')
    end

    it 'should reference back to the connector' do
      expect(connector.action('uuid').connector).to eq(connector)
    end

    it 'should reference back to the connector from the schema' do
      expect(connector.action('uuid').input_schema.connector).to eq(connector)
    end

    it 'should fail immediately when an action UUID is duplicated' do
      expect do
        connector.action('uuid') do
        end
      end.to raise_error('Duplicate Action Template UUID: uuid, in default scope.')
    end

    it 'should validate actions with the connector' do
      expect(connector).not_to be_valid

      expect(connector.errors[:actions].size).to eq(1)
      fields_message = "Avatar is invalid. Run function is required, define 'run do ... end'."
      expect(connector.errors[:actions].first).to eq("Action uuid has errors: #{fields_message}")
    end
  end

  describe 'helpers' do
    before do
      connector.helper(:hello_world) do |message = nil|
        message || 'Hello World!'
      end
    end

    it 'should execute the helper' do
      expect(connector.helpers.hello_world).to eq('Hello World!')
    end

    it 'should accept parameters' do
      expect(connector.helpers.hello_world('Hello Moon!')).to eq('Hello Moon!')
    end

    it 'should respond to the helper method' do
      expect(connector.helpers.respond_to?(:hello_world)).to be_truthy
    end

    it 'should validate helpers with the connector' do
      connector.helper(:foo) { invalid_method }
      expect(connector).not_to be_valid

      expect(connector.errors[:helpers].size).to eq(1)
      expect(connector.errors[:helpers].first)
        .to eq(%(Helpers have errors: [["foo", ["Method 'invalid_method' not allowed."]]]))
    end
  end
end
