require 'spec_helper'

describe IPaaS::Connector::Common::Helpers do
  let(:helpers) do
    IPaaS::Connector::Common::Helpers.new.tap do |h|
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
  end
end
