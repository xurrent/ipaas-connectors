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

  describe 'field options consistency' do
    before(:each) do
      skip_function_capture_validation
    end

    def define_schema_with_list(schema, &options)
      schema.field :space_id, 'Space', :string
      schema.field :list_id, 'List', :string do
        options(&options)
      end
    end

    def define_connector(trigger_options, action_options)
      connector.trigger('trigger-uuid') do
        config_schema { |schema| }
      end
      define_schema_with_list(connector.trigger('trigger-uuid').config_schema, &trigger_options)
      connector.action('action-uuid') do
        input_schema { |schema| }
      end
      define_schema_with_list(connector.action('action-uuid').input_schema, &action_options)
      connector.validate
    end

    # Each block on its own line: the check compares proc source text, which is read per line.
    def lists_options = proc { |space_id:| helpers.lists(space_id) }
    def folders_options = proc { |space_id:| helpers.folders(space_id) }

    it 'accepts the same field id carrying the same options code in a trigger and an action' do
      define_connector(lists_options, lists_options)

      expect(connector.errors[:base]).to be_empty
    end

    it 'rejects the same field id carrying different options code in two schemas' do
      define_connector(lists_options, folders_options)

      expect(connector.errors[:base]).to include('Field (list_id) has different options code in different schemas')
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

  describe 'proc_validations' do
    it 'is one store per connector instance, kept between calls, built by the factory' do
      store = connector.proc_validations

      expect(store).to be_a(Set)
      expect(connector.proc_validations).to be(store)
      expect(IPaaS::Connector::Connector.new('other').proc_validations).not_to be(store)
    end

    it 'builds the store with whatever factory the host installs' do
      installed = Set.new
      original = IPaaS::Connector::Connector.proc_validations_factory
      IPaaS::Connector::Connector.proc_validations_factory = -> { installed }
      begin
        expect(IPaaS::Connector::Connector.new('hosted').proc_validations).to be(installed)
      ensure
        IPaaS::Connector::Connector.proc_validations_factory = original
      end
      expect(connector.proc_validations).not_to be(installed)
    end

    it 'receives the verdict of a helper defined at connector level inside the definition block' do
      defined = IPaaS::Connector::Connector.new('with-helper') do
        name 'With helper'
        helper(:greet) { 'hi' }
      end
      IPaaS::Connector::Common::ProcHelper.validated_before.clear

      expect(defined.helpers_definition.connector).to be(defined)
      expect(defined).to be_valid
      expect(defined.proc_validations.size).to eq(1)
      expect(IPaaS::Connector::Common::ProcHelper.validated_before).to be_empty
    end
  end

  describe 'connector on the objects it builds' do
    it 'is read-only on every template and schema, so nothing can move their verdicts' do
      skip_function_capture_validation
      built = IPaaS::Connector::Connector.new('owner') do
        name 'Owner'
        inbound_connection { api_key_validator }
        outbound_connection { api_key_authenticator }
        trigger('t') do
          name 'Trigger one'
          parse { {} }
        end
        action('a') do
          name 'Action one'
          run { 1 }
        end
      end
      owners = [built.inbound_connection, built.outbound_connection, built.trigger('t'), built.action('a'),
                built.trigger('t').config_schema,]

      aggregate_failures do
        owners.each do |owner|
          expect(owner.connector).to be(built)
          expect(owner).not_to respond_to(:connector=)
          expect { owner.connector(built) }.to raise_error(ArgumentError)
        end
      end
    end
  end

  describe 'seal_helpers!' do
    let(:built) do
      skip_function_capture_validation
      IPaaS::Connector::Connector.new('sealed-owner') do
        name 'Owner'
        inbound_connection { api_key_validator }
        outbound_connection { api_key_authenticator }
        trigger('t') do
          name 'Trigger one'
          parse { {} }
        end
        action('a') do
          name 'Action one'
          run { 1 }
        end
      end
    end

    let(:registries) do
      [built, built.inbound_connection, built.outbound_connection, built.trigger('t'), built.action('a')]
        .map(&:helpers_definition)
    end

    it 'seals every registry in the graph, and the hash inside each one' do
      built.seal_helpers!

      aggregate_failures do
        registries.each do |registry|
          expect(registry).to be_frozen
          expect(registry.proc_helpers_by_name).to be_frozen
        end
      end
    end

    # Contrast case for the above: without the call the same registries are writable, so the spec
    # proves the seal rather than a property they had anyway.
    it 'leaves every registry writable until it is called' do
      aggregate_failures do
        registries.each do |registry|
          expect(registry).not_to be_frozen
          expect(registry.proc_helpers_by_name).not_to be_frozen
        end
      end
    end

    # The one registry the seal creates rather than finds, so freezing the ivar in place would
    # leave it writable.
    it 'seals the registry of a connector that declared nothing' do
      bare = IPaaS::Connector::Connector.new('bare-owner') { name 'Bare' }

      bare.seal_helpers!

      expect(bare.helpers_definition).to be_frozen
      expect { bare.helper(:planted) { 'planted' } }.to raise_error(FrozenError, /sealed/)
    end

    it 'refuses a helper planted on any template in the sealed graph' do
      built.seal_helpers!

      owners = [built, built.inbound_connection, built.outbound_connection, built.trigger('t'),
                built.action('a'),]

      aggregate_failures do
        owners.each do |owner|
          expect { owner.helper(:planted) { 'planted' } }.to raise_error(FrozenError, /sealed/)
        end
      end
    end
  end
end
