require 'spec_helper'

# `helpers` is the one position where the method allowlist does not apply
# (`ValidMethodsRule#top_level_helper?`), so the receiver is the control rather than the rule. The
# rules still accept every source below — `valid?` stays true on purpose — which is why each
# rejection is asserted at execute time and paired with an accepted twin.
#
# The context is an explicit axis: each proc-facing resolution reaches `helpers` by a different
# route, and a table that exercises only one of them cannot see the others.
describe IPaaS::Connector::Common::HelpersProxy do
  # Defined at the top level: a captured local parses as a receiverless send, so a helper block
  # written inside an example fails on the enclosing expression rather than on the rule under test.
  PROXY_SPEC_CONNECTOR = IPaaS::Connector::Connector.new('0195fa8b-0000-7000-8000-000000000001') do
    name 'Proxy Spec'
    helper(:from_connector) { 'connector-helper' }
    action('0195fa8b-0000-7000-8000-000000000002') do
      name 'Proxy Spec Action'
      helper(:from_action) { 'action-helper' }
    end
  end

  let(:template) { PROXY_SPEC_CONNECTOR.actions.first }

  let(:action) do
    IPaaS::Connector::Action.new.tap { |a| a.action_template = template }
  end

  let(:auth_binding) do
    Object.new.tap { |object| template.helpers_definition.copy_to(object) }
  end

  before(:each) { IPaaS::Connector::Common::ProcHelper.validated_before.clear }

  def execute(context, source)
    IPaaS::Connector::Common::ProcHelper.new(context, source).execute
  end

  def accepted_by_rules?(source)
    IPaaS::Connector::Common::ProcHelper.new(nil, source).valid?
  end

  # One reflective shape stands in for the class. Refusal keys on the first send name, so the
  # argument string is never reached and a more elaborate one would assert nothing extra.
  REFUSED = {
    'helpers.send(:eval, "1 + 1")' => 'send',
    'helpers.__send__(:eval, "1 + 1")' => '__send__',
    'helpers.instance_eval("1 + 1")' => 'instance_eval',
    'helpers.instance_exec { 1 }' => 'instance_exec',
    'helpers.instance_variable_get(:@context)' => 'instance_variable_get',
    'helpers.proc_helpers_by_name' => 'proc_helpers_by_name',
    'helpers.parent_helpers' => 'parent_helpers',
    'helpers.copy_to(1)' => 'copy_to',
    'helpers.define_helper(:x)' => 'define_helper',
    'helpers.for_proc' => 'for_proc',
    'helpers.registered_helper(:from_action)' => 'registered_helper',
    'helpers.copy_for(1)' => 'copy_for',
    'helpers.valid?' => 'valid?',
    'helpers.errors' => 'errors',
    'helpers.class' => 'class',
    'helpers.singleton_class' => 'singleton_class',
    'helpers.method(:from_action)' => 'method',
    'helpers.freeze' => 'freeze',
    'helpers.to_json' => 'to_json',
    'helpers.tap { 1 }' => 'tap',
    'helpers.not_a_helper' => 'not_a_helper',
  }.freeze

  CONTEXTS = [:template, :action, :auth_binding].freeze

  describe 'refusing everything that is not a registered helper' do
    CONTEXTS.each do |context_name|
      context "with a #{context_name} context" do
        REFUSED.each do |source, refused_name|
          it "refuses #{source}" do
            expect { execute(send(context_name), source) }
              .to raise_error(NoMethodError, "Missing helper method '#{refused_name}'.")
          end
        end
      end
    end
  end

  describe 'still accepting registered helpers' do
    it 'resolves a helper defined on the action, from every context' do
      expect(execute(template, 'helpers.from_action')).to eq('action-helper')
      expect(execute(action, 'helpers.from_action')).to eq('action-helper')
      expect(execute(auth_binding, 'helpers.from_action')).to eq('action-helper')
    end

    it 'resolves a helper defined on the connector through the parent chain' do
      expect(execute(template, 'helpers.from_connector')).to eq('connector-helper')
      expect(execute(action, 'helpers.from_connector')).to eq('connector-helper')
    end

    it 'answers respond_to? from the registry rather than from an inherited method table' do
      proxy = template.helpers

      expect(proxy.respond_to?(:from_action)).to be(true)
      expect(proxy.respond_to?(:from_connector)).to be(true)
      expect(proxy.respond_to?(:to_h)).to be(false)
      expect(proxy.respond_to?(:send)).to be(false)
    end
  end

  # The rules are deliberately untouched, so a source that is refused at execute time is still
  # accepted by them. Without this the table above could pass because some rule started rejecting
  # the source, which would prove nothing about the proxy.
  describe 'the rules themselves' do
    REFUSED.each_key do |source|
      it "still accepts #{source}" do
        expect(accepted_by_rules?(source)).to be(true)
      end
    end
  end

  describe 'a schema block, which runs while the connector is still being defined' do
    it 'refuses a reflective call at definition time' do
      expect do
        IPaaS::Connector::Connector.new('0195fa8b-0000-7000-8000-000000000003') do
          name 'Schema Refused'
          action('0195fa8b-0000-7000-8000-000000000004') do
            name 'Schema Refused Action'
            input_schema do
              field :a, 'A', :string, hint: helpers.send(:eval, '1 + 1')
            end
          end
        end
      end.to raise_error(NoMethodError, "Missing helper method 'send'.")
    end

    it 'resolves a registered helper at definition time' do
      connector = IPaaS::Connector::Connector.new('0195fa8b-0000-7000-8000-000000000005') do
        name 'Schema Accepted'
        helper(:hint_text) { 'from-helper' }
        action('0195fa8b-0000-7000-8000-000000000006') do
          name 'Schema Accepted Action'
          input_schema do
            field :a, 'A', :string, hint: helpers.hint_text
          end
        end
      end

      expect(connector.actions.first.input_schema.fields.first.hint).to eq('from-helper')
    end
  end

  # A context with no helpers of its own must still answer with a proxy rather than nil.
  # A nil `helpers` would not raise here, so the raise is itself the assertion that these
  # contexts answer with a proxy.
  describe 'a context that has no helpers at all' do
    {
      'a schema with no context' => -> { IPaaS::Connector::Schema.new('no-context') },
      'a connection with no connector' => -> { IPaaS::Connector::Connection.new(SecureRandom.uuid) },
      'a test-case action' => -> { IPaaS::TestCase::Action.new },
    }.each do |description, build_context|
      it "refuses a reflective call from #{description}" do
        expect { execute(build_context.call, 'helpers.send(:eval, "1 + 1")') }
          .to raise_error(NoMethodError, "Missing helper method 'send'.")
      end
    end
  end

  describe 'a raw Helpers, if one is ever reached' do
    it 'resolves an unregistered name through the registry rather than sending to the parent' do
      parent = IPaaS::Connector::Common::Helpers.new
      child = IPaaS::Connector::Common::Helpers.new(nil, parent_helpers: parent)

      expect { child.eval('1 + 1') }
        .to raise_error(NoMethodError, "Missing helper method 'eval'.")
    end
  end

  describe 'a copied Helpers' do
    it 'gets its own proxy, so helpers added to the copy resolve' do
      original = IPaaS::Connector::Common::Helpers.new
      original.proc_helpers_by_name[:a] = IPaaS::Connector::Common::ProcHelper.new(nil, "'a'")
      original.for_proc

      copy = original.dup
      copy.proc_helpers_by_name = original.proc_helpers_by_name.dup
      copy.proc_helpers_by_name[:b] = IPaaS::Connector::Common::ProcHelper.new(nil, "'b'")

      expect(copy.for_proc.b).to eq('b')
    end
  end

  describe 'the chain a proc never reaches' do
    it 'rejects a bare helpers_definition send, so the unmediated object stays unreachable' do
      helper = IPaaS::Connector::Common::ProcHelper.new(nil, 'helpers_definition')
      helper.valid?

      expect(helper.errors).to eq(["Method 'helpers_definition' not allowed."])
    end

    it 'keeps helpers_definition out of the proc-safe registry' do
      registry = IPaaS::Connector::Common::ProcRules::ProcSafe.registry

      expect(registry).to include(:helpers)
      expect(registry).not_to include(:helpers_definition)
    end
  end

  describe 'guarding the objects the chain is built from' do
    it 'refuses a proxy as parent_helpers, which method_missing could not send to' do
      helpers = IPaaS::Connector::Common::Helpers.new

      expect { helpers.parent_helpers = helpers.for_proc }
        .to raise_error(ArgumentError, 'parent_helpers must be nil or a Helpers.')
    end

    it 'accepts nil and a Helpers as parent_helpers' do
      helpers = IPaaS::Connector::Common::Helpers.new
      parent = IPaaS::Connector::Common::Helpers.new

      expect { helpers.parent_helpers = nil }.not_to raise_error
      expect { helpers.parent_helpers = parent }.not_to raise_error
    end

    it 'refuses to wrap anything that is not a Helpers' do
      expect { described_class.new(Object.new) }
        .to raise_error(ArgumentError, 'HelpersProxy target must be a Helpers.')
    end
  end

  # The removal set is derived from `BasicObject` rather than listed, so this is what goes red if
  # anyone replaces it with a list that misses a name. It compares against the snapshot the proxy
  # took, so methods injected into `BasicObject` later (rspec-mocks adds several) do not confuse it.
  describe 'the methods it inherited' do
    it 'removed every one it does not define itself' do
      redefined = described_class::OWN_METHODS + [:method_missing, :initialize]
      exposed = described_class.instance_methods(true) +
                described_class.private_instance_methods(true)

      expect((described_class::INHERITED_METHODS - redefined) & exposed).to eq([])
    end

    it 'took a snapshot that actually contained the reflective methods' do
      expect(described_class::INHERITED_METHODS)
        .to include(:__send__, :__id__, :instance_eval, :instance_exec)
    end

    it 'defines every name it claims to answer itself' do
      expect(described_class.instance_methods(false)).to include(*described_class::OWN_METHODS)
    end
  end

  describe 'a helper named after a method the proxy answers itself' do
    it 'is refused, because dispatch would never reach it' do
      helpers = IPaaS::Connector::Common::Helpers.new

      expect { helpers.define_helper(:inspect) { 1 } }
        .to raise_error(ArgumentError, "Helper 'inspect' is reserved; choose another name.")
    end

    it 'is refused under a name a proc may hand a class to, whatever the proxy is called by' do
      helpers = IPaaS::Connector::Common::Helpers.new
      reserved = IPaaS::Connector::Common::ProcRules::ValidConstantsRule::READ_METHODS

      expect(reserved).not_to be_empty
      reserved.each do |name|
        expect { helpers.define_helper(name) { |klass| klass } }
          .to raise_error(ArgumentError, "Helper '#{name}' is reserved; choose another name.")
      end
      expect { helpers.for_proc.raise(Time) }.to raise_error(NoMethodError, "Missing helper method 'raise'.")
    end

    it 'allows a name the proxy does not answer' do
      helpers = IPaaS::Connector::Common::Helpers.new

      expect { helpers.define_helper(:send) { 1 } }.not_to raise_error
    end
  end

  describe 'inspecting an object that holds a proxy' do
    it 'does not raise, which it would if the proxy answered nothing' do
      template.helpers

      expect { template.inspect }.not_to raise_error
      expect { [template].inspect }.not_to raise_error
    end
  end

  # Pinned rather than desired: `ProcHelper#execute` declares no block parameter, so the block
  # never reaches the helper. Changing that is a separate concern.
  describe 'a block passed to a helper' do
    it 'is dropped' do
      helpers = IPaaS::Connector::Common::Helpers.new
      helpers.proc_helpers_by_name[:with_block] =
        IPaaS::Connector::Common::ProcHelper.new(nil, "->(a, &blk) { blk ? 'BLOCK' : 'NOBLOCK' }")

      expect(helpers.for_proc.with_block(1) { 'ignored' }).to eq('NOBLOCK')
    end
  end
end
