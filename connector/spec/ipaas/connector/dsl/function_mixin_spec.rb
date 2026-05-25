require 'spec_helper'

describe IPaaS::Connector::Dsl::FunctionMixin do
  it 'allows function' do
    function_tester = Class.new(DslTester) do
      function :foo
    end.new
    function_tester.foo do
      'Hello World!'
    end
    expect(function_tester.foo.call).to eq('Hello World!')
  end

  context 'validation' do
    it 'validates presence if required' do
      test = Class.new(DslTester) do
        function :parse, required: true
      end.new
      expect(test).not_to be_valid
      expect(test.errors[:parse].first).to eq("function is required, define 'parse do ... end'.")

      test.parse do
        'bar'
      end
      expect(test).to be_valid
      expect(test.parse.call).to eq('bar')
    end

    it 'validates the function itself' do
      test = Class.new(DslTester) do
        function :parse
      end.new
      test.parse do
        instance_eval('"Hello World!"', __FILE__, __LINE__)
      end
      test.parse.call # for 100% coverage
      expect(test).not_to be_valid
      expect(test.errors[:parse].first).to eq("invalid: Method 'instance_eval' not allowed.")
    end
  end

  describe 'call_function' do
    it 'calls the function' do
      test = Class.new(DslTester) do
        function :parse
      end.new
      called = nil
      test.parse do
        called = name
      end
      test.call_function(:parse, double(name: :bar))
      expect(called).to eq(:bar)
    end

    it 'accepts parameters' do
      test = Class.new(DslTester) do
        function :parse
      end.new
      called = nil
      test.parse do |param|
        called = param
      end
      test.call_function(:parse, Object.new, :bar)
      expect(called).to eq(:bar)
    end

    it 'does not fail when the function is not present' do
      test = Class.new(DslTester) do
        function :parse
      end.new
      test.call_function(:parse, Object.new, :bar)
    end

    it 'raises an error when the function is invalid' do
      test = Class.new(DslTester) do
        function :parse
        function :foo
      end.new
      test.parse do
        send(:present?)
      end
      expect do
        test.call_function(:parse, nil)
      end.to raise_error(IPaaS::Error, "Function 'parse' invalid: invalid: Method 'send' not allowed.")
      test.parse.call # 100% test coverage
    end
  end
end
