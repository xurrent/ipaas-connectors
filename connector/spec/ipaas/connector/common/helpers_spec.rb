require 'spec_helper'

describe IPaaS::Connector::Common::Helpers do
  let(:helpers) do
    IPaaS::Connector::Common::Helpers.new(connector: spec_connector).tap do |h|
      proc = ->(message = nil) { message || 'Hello World!' }
      complex_proc = ->(m, *extra, **options) { "Hi #{m}, #{extra} #{options}" }
      self_proc = -> { self.object_id }
      h.define_helper(:hello_world, &proc)
      h.define_helper(:complex, &complex_proc)
      h.define_helper(:self_proc, &self_proc)
    end
  end

  it 'default context is nil' do
    expect(helpers.self_proc).to eq(nil.object_id)
  end

  it 'should execute the helper' do
    expect(helpers.hello_world).to eq('Hello World!')
  end

  it 'should accept parameters' do
    expect(helpers.hello_world('Hello Moon!')).to eq('Hello Moon!')
  end

  it 'should respond to the helper method' do
    expect(helpers.respond_to?(:hello_world)).to be_truthy
  end

  it 'can raise NoMethodError' do
    expect { helpers.other_method }.to raise_error(NoMethodError)
  end

  it 'allows complex helpers' do
    h = helpers.complex('F', 1, 2, a: :foo, b: :bar)
    expect(h).to eq('Hi F, [1, 2] {a: :foo, b: :bar}')
  end

  it 'can copy helpers to apply to new context' do
    a = Object.new
    copy = helpers.copy_for(a)
    expect(copy.hello_world('Hello Moon!')).to eq('Hello Moon!')
    expect(copy.self_proc).to eq(a.object_id)
  end

  it 'can add helpers to new context' do
    a = Object.new
    helpers.copy_to(a)
    expect(a.helpers.hello_world('Hello Moon!')).to eq('Hello Moon!')
    expect(a.helpers.self_proc).to eq(a.object_id)
  end

  describe 'inspect' do
    it 'lists the helper names without following the connector' do
      expect(helpers.inspect).to eq('Helpers ["hello_world", "complex", "self_proc"]')
      expect(helpers.inspect).not_to include(spec_connector.uuid)
    end
  end

  describe 'validation store' do
    it 'records the verdict of every helper in the connector store, not the process-wide cache' do
      IPaaS::Connector::Common::ProcHelper.validated_before.clear

      expect(helpers.valid?).to be(true)
      expect(spec_connector.proc_validations.size).to eq(3)
      expect(IPaaS::Connector::Common::ProcHelper.validated_before).to be_empty
    end

    it 'raises for a helper block when no connector is reachable' do
      orphan = IPaaS::Connector::Common::Helpers.new
      orphan.define_helper(:hello_world, &-> { 'Hello World!' })
      allow(IPaaS.default_logger).to receive(:warn)

      expect { orphan.valid? }.to raise_error(IPaaS::Connector::Common::ProcHelper::MissingValidationStore)
    end
  end

  describe 'with parent helpers' do
    let(:child_helpers) do
      IPaaS::Connector::Common::Helpers.new(parent_helpers: helpers).tap do |h|
        proc = ->(message = nil) { message || 'Bye World!' }
        h.define_helper(:bye_world, &proc)
      end
    end

    it 'should execute the helper' do
      expect(child_helpers.bye_world).to eq('Bye World!')
    end

    it 'should accept parameters' do
      expect(child_helpers.bye_world('Bye Moon!')).to eq('Bye Moon!')
    end

    it 'should respond to the helper method' do
      expect(child_helpers.respond_to?(:bye_world)).to be_truthy
    end

    it 'allows override of parent helper' do
      proc = -> { 'Hallo Wereld!' }
      child_helpers.define_helper(:hello_world, &proc)
      expect(child_helpers.hello_world).to eq('Hallo Wereld!')
    end

    it 'should execute the parent helper' do
      expect(child_helpers.hello_world).to eq('Hello World!')
    end

    it 'should accept parameters for parent' do
      expect(child_helpers.hello_world('Hello Moon!')).to eq('Hello Moon!')
    end

    it 'should respond to the parent helper method' do
      expect(child_helpers.respond_to?(:hello_world)).to be_truthy
    end

    it 'can raise NoMethodError' do
      expect { child_helpers.other_method }.to raise_error(NoMethodError)
    end

    it 'allows complex helpers of parent to be called' do
      h = child_helpers.complex('F', 1, 2, a: :foo, b: :bar)
      expect(h).to eq('Hi F, [1, 2] {a: :foo, b: :bar}')
    end

    it 'can copy helpers to apply to new context' do
      a = Object.new
      copy = child_helpers.copy_for(a)
      expect(copy.hello_world('Hello Moon!')).to eq('Hello Moon!')
      expect(copy.bye_world).to eq('Bye World!')
      expect(copy.self_proc).to eq(a.object_id)
    end

    it 'can add helpers to new context' do
      a = Object.new
      child_helpers.copy_to(a)
      expect(a.helpers.hello_world('Hello Moon!')).to eq('Hello Moon!')
      expect(a.helpers.self_proc).to eq(a.object_id)
    end

    it 'resolves the connector through the parent chain and keeps it on a copy' do
      expect(child_helpers.connector).to be(spec_connector)
      expect(child_helpers.copy_for(Object.new).connector).to be(spec_connector)
    end

    it 'has no connector of its own when the chain ends without one' do
      expect(IPaaS::Connector::Common::Helpers.new(parent_helpers: IPaaS::Connector::Common::Helpers.new).connector)
        .to be_nil
    end
  end

  describe 'sealed' do
    let(:sealed) { helpers.tap(&:freeze) }

    it 'refuses a helper that would replace one already registered, leaving the original in place' do
      original = sealed.registered_helper(:hello_world)
      allow(IPaaS::Connector::Common::ProcHelper).to receive(:new).and_call_original

      expect { sealed.define_helper(:hello_world) { 'planted' } }.to raise_error(FrozenError, /sealed/)

      expect(sealed.registered_helper(:hello_world)).to be(original)
      expect(sealed.hello_world).to eq('Hello World!')
      expect(IPaaS::Connector::Common::ProcHelper).not_to have_received(:new)
    end

    it 'refuses a helper under a name not yet registered, and registers nothing' do
      expect { sealed.define_helper(:brand_new) { 'planted' } }.to raise_error(FrozenError, /sealed/)

      expect(sealed.registered_helper(:brand_new)).to be_nil
    end

    # Contrast case for the two above: the same calls succeed while unsealed, so the refusal is the
    # seal's doing and not something the name or the block would have caused anyway.
    it 'accepts both of those helpers while unsealed' do
      helpers.define_helper(:hello_world) { 'replaced' }
      helpers.define_helper(:brand_new) { 'added' }

      expect(helpers.hello_world).to eq('replaced')
      expect(helpers.brand_new).to eq('added')
    end

    it 'answers valid? repeatedly without raising, when true' do
      expect([sealed.valid?, sealed.valid?, sealed.valid?]).to eq([true, true, true])
      expect(sealed.errors).to eq([])
    end

    it 'reports an invalid helper through the errors array and allows multiple calls of valid?' do
      helpers.define_helper(:broken) { File.read('/etc/passwd') }
      helpers.freeze

      expect([helpers.valid?, helpers.valid?]).to eq([false, false])
      expect(helpers.errors.map(&:first)).to eq(['broken'])
    end

    it 'hands out a working proxy, which a seal before first use would otherwise refuse to memoize' do
      expect(sealed.for_proc.respond_to?(:hello_world)).to be(true)
      expect(sealed.for_proc.hello_world).to eq('Hello World!')
    end

    it 'freezes the registry itself, not only the object holding it' do
      expect(sealed).to be_frozen
      expect(sealed.proc_helpers_by_name).to be_frozen
    end

    it 'still resolves and executes through a parent chain that is sealed too' do
      own_proc = -> { 'own' }
      child = IPaaS::Connector::Common::Helpers.new(parent_helpers: sealed)
      child.define_helper(:own, &own_proc)
      child.freeze

      expect(child.hello_world).to eq('Hello World!')
      expect(child.own).to eq('own')
    end

    it 'yields an unfrozen, writable copy from copy_for' do
      extra_proc = -> { 'extra' }
      copy = sealed.copy_for(Object.new)
      copy.define_helper(:extra, &extra_proc)

      expect(copy).not_to be_frozen
      expect(copy.extra).to eq('extra')
      expect(copy.hello_world).to eq('Hello World!')
    end
  end
end
