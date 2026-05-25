require 'spec_helper'

describe IPaaS::Connector::Dsl::AttrAccessorMixin do
  it 'allows single attribute' do
    foo_tester = Class.new(DslTester) do
      attr_accessor :foo
    end.new
    foo_tester.foo 'bar'
    expect(foo_tester.foo).to eq('bar')
  end

  it 'allows multiple attributes' do
    foo_tester = Class.new(DslTester) do
      attr_accessor :foo, :bar
    end.new
    foo_tester.foo 'baz1'
    foo_tester.bar 'baz2'
    expect(foo_tester.foo).to eq('baz1')
    expect(foo_tester.bar).to eq('baz2')
  end

  it 'allows default values' do
    foo_tester = Class.new(DslTester) do
      attr_accessor :foo do
        :default
      end
    end.new
    expect(foo_tester.foo).to eq(:default)
    foo_tester.foo :custom
    expect(foo_tester.foo).to eq(:custom)

    # explicit nil, so no default
    foo_tester.foo nil
    expect(foo_tester.foo).to be_nil
  end

  it 'different default value per instance' do
    TesterClass = Class.new(DslTester) do
      attr_accessor :foo do
        []
      end
    end
    foo_tester_a = TesterClass.new
    foo_tester_b = TesterClass.new

    foo_tester_a.foo << :a
    foo_tester_b.foo << :b

    expect(foo_tester_a.foo).to eq([:a])
    expect(foo_tester_b.foo).to eq([:b])
  end

  it 'resolves the default based on the current instance' do
    DefaultTesterClass = Class.new(DslTester) do
      attr_accessor :car
      attr_accessor :cars do
        car ? [car] : []
      end
    end
    foo_tester_a = DefaultTesterClass.new
    foo_tester_b = DefaultTesterClass.new

    foo_tester_b.car = 'Kit'

    expect(foo_tester_a.cars).to eq([])
    expect(foo_tester_b.cars).to eq(['Kit'])
  end

  it 'respects nil values' do
    foo_tester = Class.new(DslTester) do
      attr_accessor :foo
    end.new
    foo_tester.foo 'bar'
    expect(foo_tester.foo).to eq('bar')
    foo_tester.foo nil
    expect(foo_tester.foo).to be_nil
  end
end
