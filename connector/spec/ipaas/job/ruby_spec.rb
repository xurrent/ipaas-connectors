require 'spec_helper'

describe IPaaS::Job::Ruby do
  class TestContext
    include IPaaS::Job::Context
  end

  class TestContextWithInputOutput
    include IPaaS::Job::Context

    def input
      'original input'
    end

    def output(param)
      "original output with param: #{param}"
    end
  end

  let(:context) { TestContext.new }
  let(:context_with_input_output) { TestContextWithInputOutput.new }

  describe 'ruby_eval' do
    it 'should evaluate the proc' do
      expect(context.ruby_eval("log('foo'); i = 45; output[:o] = i * i", {})).to eq({ o: 2025 }.with_indifferent_access)
      expect(context.ruby_eval('output[:o] = input[:i] * input[:i]',
                               { i: 45 })).to eq({ o: 2025 }.with_indifferent_access)
      expect(context.ruby_eval(<<~RUBY, { a: 'hello', b: 'world' })).to eq({ o: 'world' }.with_indifferent_access)
        if input[:a].starts_with?("hello")
          output[:o] = input[:b]
        else#{' '}
          output[:o] = input[:a]
        end
      RUBY
    end

    it 'has indifferent access to input and output' do
      expect(context.ruby_eval(<<~RUBY, { 'a' => 1, b: 2 })).to eq({ o: 3, p: 3 }.with_indifferent_access)
        output[:o] = input[:a] + input[:b]
        output['p'] = input['a'] + input['b']
      RUBY
    end

    it 'should evaluate nested calls to ruby_eval' do
      expect(context.ruby_eval(<<~RUBY, { i: 17 })).to eq({ o: 2025 }.with_indifferent_access)
        nested = "output[:o] = input[:i] * input[:i]; output[:o2] = 42;"
        output[:o] = ruby_eval(nested, { i: 46 })[:o] - 91
      RUBY

      expect(context.respond_to?(:input)).to be_falsey
      expect(context.respond_to?(:output)).to be_falsey
      expect(context.respond_to?(:_ruby_eval_input_stack)).to be_falsey
      expect(context.respond_to?(:_ruby_eval_output_stack)).to be_falsey
    end

    it 'should not evaluate procs using forbidden methods' do
      expect { context.ruby_eval('unknown', {}) }.to raise_error("Ruby code is invalid: Method 'unknown' not allowed.")
    end

    it 'restores original input and output methods in the context' do
      expect(context_with_input_output.ruby_eval('42', {})).to eq({})
      expect(context_with_input_output.input).to eq('original input')
      expect(context_with_input_output.output(3)).to eq('original output with param: 3')
    end
  end
end
