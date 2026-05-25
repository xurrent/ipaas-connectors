require 'spec_helper'

describe IPaaS::Job::Environment do
  class TestContext
    attr_accessor :solution

    include IPaaS::Job::Environment
  end

  let(:context) { TestContext.new }

  it 'should return an empty environment if the solution has not been injected' do
    expect(context.environment).to eq({})
  end

  it 'should get the environment from the injected solution' do
    solution_double = double
    environment = { foo: 'bar' }
    allow(solution_double).to receive(:environment).and_return(environment)

    context = TestContext.new
    context.solution = solution_double
    expect(context.environment).to eq(environment)
  end

  it 'access to environment is allowed' do
    rule = IPaaS::Connector::Common::ProcRules::ValidMethodsRule.new(
      ->(msg) { raise "Unexpected error: #{msg}" }
    )
    expect { rule.validate_method(:environment) }.not_to raise_error
  end
end
