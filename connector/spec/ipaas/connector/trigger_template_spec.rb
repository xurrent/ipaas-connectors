require 'spec_helper'

describe IPaaS::Connector::TriggerTemplate do
  let(:trigger_template) do
    IPaaS::Connector::TriggerTemplate.new('uuid') do
      name 'Test Template'
      # required function
      parse do
      end
    end
  end

  it 'should define by_uuid on the module' do
    expect(IPaaS::Connector::TriggerTemplate.by_uuid('uuid')).to be_nil
    trigger_template
    expect(IPaaS::Connector::TriggerTemplate.by_uuid('uuid').uuid).to eq(trigger_template.uuid)
  end

  describe 'attributes' do
    it 'should define a name' do
      trigger_template.name 'foo'
      expect(trigger_template.name).to eq('foo')
    end

    it 'should define an avatar' do
      trigger_template.avatar 'foo'
      expect(trigger_template.avatar).to eq('foo')
    end

    it 'should define a description' do
      trigger_template.description 'foo'
      expect(trigger_template.description).to eq('foo')
    end

    it 'should define blueprint_filenames' do
      trigger_template.blueprint_filenames = ['other_file.txt']
      expect(trigger_template.blueprint_filenames).to eq(['other_file.txt'])
    end
  end

  describe 'schemas' do
    it 'should define the config_schema with default fields' do
      expect(trigger_template.config_schema).to be_an_instance_of(IPaaS::Connector::Schema)
      expect(trigger_template.config_schema.fields.size).to eq(2)
      url_postfix_field = trigger_template.config_schema.fields.first
      expect(url_postfix_field.id).to eq(:url_postfix)
      expect(url_postfix_field.label).to eq('URL postfix')
      expect(url_postfix_field.type).to eq(:string)
      expect(url_postfix_field.hint).to eq('The given postfix will be added to the end of the endpoint URL.')
      expect(url_postfix_field.visibility).to eq('optional')

      discard_trigger_event_field = trigger_template.config_schema.fields.last
      expect(discard_trigger_event_field.id).to eq(:discard_trigger_event)
      expect(discard_trigger_event_field.label).to eq('Discard trigger event')
      expect(discard_trigger_event_field.type).to eq(:boolean)
      expect(discard_trigger_event_field.hint)
        .to eq('Set to true to discard the trigger event and execute none of the actions of the runbook.')
      expect(discard_trigger_event_field.visibility).to eq('optional')

      trigger_template.config_schema do
        field :foo, 'Foo', :string
      end
      expect(trigger_template.config_schema).to be_an_instance_of(IPaaS::Connector::Schema)
      expect(trigger_template.config_schema.fields.size).to eq(3)
      expect(trigger_template.config_schema.fields.map(&:id)).to eq([:foo, :url_postfix, :discard_trigger_event])
    end

    it 'should define the output_schema' do
      expect(trigger_template.output_schema).to be_an_instance_of(IPaaS::Connector::Schema)
      expect(trigger_template.output_schema.fields.size).to eq(1)
      deduplication_id_field = trigger_template.output_schema.fields.first
      expect(deduplication_id_field.id).to eq(:deduplication_id)
      expect(deduplication_id_field.label).to eq('Deduplication ID')
      expect(deduplication_id_field.type).to eq(:string)
      expect(deduplication_id_field.hint).to eq('ID used to deduplicate events.')

      trigger_template.output_schema do
        field :foo, 'Foo', :string
      end
      expect(trigger_template.output_schema).to be_an_instance_of(IPaaS::Connector::Schema)
      expect(trigger_template.output_schema.fields.size).to eq(2)
      expect(trigger_template.output_schema.fields.map(&:id)).to eq([:foo, :deduplication_id])
    end
  end

  describe 'functions' do
    [:extract_blueprint, :provision, :deprovision, :parse, :respond_with].each do |function_name|
      it "should define the #{function_name} function" do
        trigger_template = IPaaS::Connector::TriggerTemplate.new('uuid')
        expect(trigger_template.send(function_name)).to be_nil
        trigger_template.send(function_name) do
          'Hello World!'
        end
        expect(trigger_template.send(function_name).call).to eq('Hello World!')
      end
    end
  end

  describe 'validations' do
    it 'should be valid' do
      expect(trigger_template).to be_valid
    end

    it 'should validate the name is present' do
      trigger_template.name = ''
      expect(trigger_template).not_to be_valid
      expect(trigger_template.errors[:name]).to eq(["can't be blank."])
    end

    it 'should validate the avatar' do
      trigger_template.avatar 'foo'
      expect(trigger_template).not_to be_valid

      trigger_template.avatar 'https://foo.com/avatar/4?z=bar'
      expect(trigger_template).to be_valid

      trigger_template.avatar '/assets/icons/pencil.svg'
      expect(trigger_template).to be_valid

      trigger_template.avatar '/assets/icons/../../../pencil.svg'
      expect(trigger_template).not_to be_valid
    end

    it 'should require the parse function' do
      trigger_template = IPaaS::Connector::TriggerTemplate.new('foo')
      expect(trigger_template).not_to be_valid
      expect(trigger_template.errors[:parse]).to eq(["function is required, define 'parse do ... end'."])
    end

    it 'should require the extract_blueprint function when blueprint_filenames are defined' do
      trigger_template.blueprint_filenames = ['foo']
      expect(trigger_template).not_to be_valid
      expect(trigger_template.errors[:extract_blueprint]).to eq(["function is required, define 'extract do ... end'."])
    end

    it 'should require the provision function when blueprint_filenames are defined' do
      trigger_template.blueprint_filenames = ['foo']
      expect(trigger_template).not_to be_valid
      expect(trigger_template.errors[:provision]).to eq(["function is required, define 'provision do ... end'."])
    end

    it 'should require outbound traffic when blueprint_filenames are defined' do
      trigger_template.blueprint_filenames = ['foo']
      expect(trigger_template).not_to be_valid
      expect(trigger_template.errors[:blueprint_filenames]).to eq(['requires outbound traffic.'])
    end

    it 'should validate the blueprint filenames for valid characters' do
      trigger_template.outbound_traffic = true
      trigger_template.blueprint_filenames = ['valid.txt', 'with spaces.foo', 'also-_good.foo', 'and&.txt', '../pwd']
      expect(trigger_template).not_to be_valid
      expect(trigger_template.errors[:blueprint_filenames]).to eq(
        ["contains invalid characters: '../pwd', 'and&.txt', 'with spaces.foo'."]
      )
    end

    it 'should limit the number of blueprint files' do
      trigger_template.outbound_traffic = true
      trigger_template.blueprint_filenames = (0..51).map { |nr| "file#{nr}" }
      expect(trigger_template).not_to be_valid
      expect(trigger_template.errors[:blueprint_filenames]).to eq(['Too many files 52, allowed: 50.'])
    end
  end

  it 'should define to_h_ref' do
    expect(trigger_template.to_h_ref).to eq({ uuid: 'uuid' })
  end

  describe 'function context' do
    it 'should reference the connector' do
      load_minimal_fixture
      expect(@trigger.connector.uuid).to eq(@connector.uuid)
    end

    it 'should create a example trigger' do
      load_minimal_fixture
      expect(@trigger.trigger.config.keys.sort).to eq(%w[discard_trigger_event foo url_postfix])
      expect(@trigger.trigger.config[:foo]).to eq('Hello World!')
    end

    it 'should reference the inbound connection' do
      load_minimal_fixture
      expect(@trigger.inbound_connection.validators).to eq([:api_key])
    end

    it 'should reference the outbound connection' do
      load_minimal_fixture
      expect(@trigger.outbound_connection.authenticators).to eq([:oauth2])
    end
  end

  describe 'helpers' do
    before do
      trigger_template.helper(:hello_world) do |message = nil|
        message || 'Hello World!'
      end
    end

    it "has connector's helpers as parent_helpers" do
      load_minimal_fixture
      @connector.helper(:hello_world) { 'Hello World!' }
      @connector.helper(:local_hello_world) { 'Hello World!' }
      @trigger.helper(:local_hello_world) { 'Hallo Wereld!' }
      expect(@trigger.helpers.hello_world).to eq('Hello World!')
      expect(@trigger.helpers.local_hello_world).to eq('Hallo Wereld!')
    end

    it 'should execute the helper' do
      expect(trigger_template.helpers.hello_world).to eq('Hello World!')
    end

    it 'should accept parameters' do
      expect(trigger_template.helpers.hello_world('Hello Moon!')).to eq('Hello Moon!')
    end

    it 'should respond to the helper method' do
      expect(trigger_template.helpers.respond_to?(:hello_world)).to be_truthy
    end

    it 'should validate helpers with the connector' do
      trigger_template.helper(:foo) { invalid_method }
      expect(trigger_template).not_to be_valid

      expect(trigger_template.errors[:helpers].size).to eq(1)
      expect(trigger_template.errors[:helpers].first)
        .to eq(%(Helpers have errors: [["foo", ["Method 'invalid_method' not allowed."]]]))
    end
  end

  describe 'job context identifier' do
    it 'can set job context identifier during parse' do
      trigger_template = IPaaS::Connector::TriggerTemplate.new('uuid') do
        name 'Test Template'
        parse do
          self.job_context_identifier = 'boo'
          'Hello World!'
        end
      end
      expect(trigger_template.parse.call).to eq('Hello World!')
      expect(trigger_template.job_context_identifier).to eq('boo')
    end

    it 'can overwrite job context identifier during respond_with' do
      trigger_template = IPaaS::Connector::TriggerTemplate.new('uuid') do
        name 'Test Template'
        parse do
          self.job_context_identifier = 'boo'
          'Hello World!'
        end
        respond_with do
          result = "Hi #{job_context_identifier}"
          self.job_context_identifier = 'bar'
          result
        end
      end
      expect(trigger_template.parse.call).to eq('Hello World!')
      expect(trigger_template.respond_with.call).to eq('Hi boo')
      expect(trigger_template.job_context_identifier).to eq('bar')
    end
  end
end
