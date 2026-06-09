require 'spec_helper'

describe IPaaS::Connector::ActionTemplate do
  let(:action_template) do
    IPaaS::Connector::ActionTemplate.new('uuid') do
      # required function
      run do
        'foo'
      end
    end
  end

  it 'should define by_uuid on the module' do
    expect(IPaaS::Connector::ActionTemplate.by_uuid('uuid')).to be_nil
    action_template.call_function(:run, nil) # code coverage 100%
    expect(IPaaS::Connector::ActionTemplate.by_uuid('uuid').uuid).to eq('uuid')
    expect(IPaaS::Connector::ActionTemplate.by_uuid('uuid').run).to eq(action_template.run)
  end

  describe 'attributes' do
    it 'should define a name' do
      action_template.name 'foo'
      expect(action_template.name).to eq('foo')
    end

    it 'should define an avatar' do
      action_template.avatar 'foo'
      expect(action_template.avatar).to eq('foo')
    end

    it 'should define a description' do
      action_template.description 'foo'
      expect(action_template.description).to eq('foo')
    end

    it 'should define disable_output_schema_name_mapping with default false' do
      expect(action_template.disable_output_schema_name_mapping).to eq(false)
    end

    it 'should allow setting disable_output_schema_name_mapping to true' do
      action_template.disable_output_schema_name_mapping = true
      expect(action_template.disable_output_schema_name_mapping).to eq(true)
    end

    it 'should allow setting disable_output_schema_name_mapping to false' do
      action_template.disable_output_schema_name_mapping = false
      expect(action_template.disable_output_schema_name_mapping).to eq(false)
    end
  end

  it 'should define to_h_ref' do
    expect(action_template.to_h_ref).to eq({ uuid: 'uuid' })
  end

  describe 'schemas' do
    it 'should define the input_schema without default fields' do
      expect(action_template.input_schema).to be_an_instance_of(IPaaS::Connector::Schema)
      expect(action_template.input_schema.fields.size).to eq(0)

      action_template.input_schema do
        field :foo, 'Foo', :string
      end
      expect(action_template.input_schema).to be_an_instance_of(IPaaS::Connector::Schema)
      expect(action_template.input_schema.fields.size).to eq(1)
      expect(action_template.input_schema.fields.map(&:id)).to eq([:foo])
    end

    it 'should define the output_schema and output_schemas' do
      expect(action_template.output_schemas).to eq([])
      action_template.output_schema('ref 1') do
      end
      expect(action_template.output_schemas.size).to eq(1)
      expect(action_template.output_schemas.first).to be_an_instance_of(IPaaS::Connector::Schema)

      action_template.output_schema('ref 2') do
      end
      expect(action_template.output_schemas.size).to eq(2)
      expect(action_template.output_schemas.second.reference).to eq('ref 2')
    end
  end

  describe 'functions' do
    before(:each) do
      skip_function_capture_validation
    end

    [:run].each do |function_name|
      it "should define the #{function_name} function" do
        action_template = IPaaS::Connector::ActionTemplate.new('uuid')
        expect(action_template.send(function_name)).to be_nil
        action_template.send(function_name) do
          'Hello World!'
        end
        expect(action_template.send(function_name).call).to eq('Hello World!')
      end
    end
  end

  describe 'validations' do
    it 'should validate the name is present' do
      expect(action_template).not_to be_valid
      expect(action_template.errors[:name]).to eq(["can't be blank."])

      action_template.name = 'my action_template'
      expect(action_template).to be_valid
    end

    it 'should validate the avatar' do
      action_template.name = 'my action_template'
      action_template.avatar 'foo'
      expect(action_template).not_to be_valid

      action_template.avatar 'https://foo.com/avatar/4?z=bar'
      expect(action_template).to be_valid

      action_template.avatar '/assets/icons/pencil.svg'
      expect(action_template).to be_valid

      action_template.avatar '/assets/icons/../../../pencil.svg'
      expect(action_template).not_to be_valid
    end

    it 'should validate uniqueness of output schema references' do
      action_template.output_schema('ref 1') do
      end
      expect do
        action_template.output_schema('ref 1') do
        end
      end.to raise_error('Duplicate schema reference: ref 1.')
    end

    it 'should require the run function' do
      action_template = IPaaS::Connector::ActionTemplate.new('foo')
      expect(action_template).not_to be_valid
      expect(action_template.errors[:run]).to eq(["function is required, define 'run do ... end'."])
    end
  end

  describe 'function context' do
    it 'should reference the connector' do
      load_minimal_fixture
      expect(@action.connector.uuid).to eq(@connector.uuid)
    end

    it 'should create a example action' do
      load_minimal_fixture
      expect(@action.action.input.keys.sort).to eq(%w[foo])
      expect(@action.action.input[:foo]).to eq('Hello World!')
    end

    it 'should reference the outbound connection' do
      load_minimal_fixture
      expect(@action.outbound_connection.authenticators).to eq([:oauth2])
    end
  end

  describe 'helpers' do
    before do
      action_template.helper(:hello_world) do |message = nil|
        message || 'Hello World!'
      end
    end

    it "has connector's helpers as parent_helpers" do
      load_minimal_fixture
      @connector.helper(:hello_world) { 'Hello World!' }
      @connector.helper(:local_hello_world) { 'Hello World!' }
      @action.helper(:local_hello_world) { 'Hallo Wereld!' }
      expect(@action.helpers.hello_world).to eq('Hello World!')
      expect(@action.helpers.local_hello_world).to eq('Hallo Wereld!')
    end

    it 'should execute the helper' do
      expect(action_template.helpers.hello_world).to eq('Hello World!')
    end

    it 'should accept parameters' do
      expect(action_template.helpers.hello_world('Hello Moon!')).to eq('Hello Moon!')
    end

    it 'should respond to the helper method' do
      expect(action_template.helpers.respond_to?(:hello_world)).to be_truthy
    end

    it 'should validate helpers with the connector' do
      action_template.helper(:foo) { invalid_method }
      expect(action_template).not_to be_valid

      expect(action_template.errors[:helpers].size).to eq(1)
      expect(action_template.errors[:helpers].first)
        .to eq(%(Helpers have errors: [["foo", ["Method 'invalid_method' not allowed."]]]))
    end
  end

  describe 'job context identifier' do
    before(:each) do
      skip_function_capture_validation
    end

    it 'can set job context identifier during run' do
      action_template = IPaaS::Connector::ActionTemplate.new('uuid') do
        run do
          self.job_context_identifier = 'boo'
          'foo'
        end
      end
      expect(action_template.run.call).to eq('foo')
      expect(action_template.job_context_identifier).to eq('boo')
    end

    it 'can retrieve job context identifier during run' do
      action_template = IPaaS::Connector::ActionTemplate.new('uuid') do
        run do
          self.job_context_identifier
        end
      end
      action_template.job_context_identifier = 'bar'
      expect(action_template.run.call).to eq('bar')
    end
  end
end
