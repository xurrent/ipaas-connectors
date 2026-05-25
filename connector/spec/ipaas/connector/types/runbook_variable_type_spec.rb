require 'spec_helper'

describe IPaaS::Connector::Types::RunbookVariableType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(IPaaS::Connector::Schema::Field)
  end

  it 'should return false for nested?' do
    expect(subject.nested?).to be_falsey
  end

  describe 'resolve' do
    it 'should leave nils untouched' do
      expect(subject.resolve(nil)).to be_nil
    end

    it 'should return runbook variable if it exists in the runbook' do
      foo_var = double(id: :foo)
      bar_var = double(id: :bar)
      variables = [foo_var, bar_var]
      runbook_double = double(runbook_variables: variables)
      context = double(runbook: runbook_double)

      foo_var2 = subject.ruby_class.new.tap { |var| var.id = :foo }

      expect(subject.resolve(:foo, context: context)).to eq(foo_var)
      expect(subject.resolve(foo_var2, context: context)).to eq(foo_var)
      expect(subject.resolve('bar', context: context)).to eq(bar_var)
      expect(subject.resolve(:baz, context: context)).to be_nil
    end

    it 'should return runbook variable based on hash input' do
      baz_var = double(id: :baz)
      foo_var = double(id: :foo)
      bar_var = double(id: :bar)
      variables = [baz_var, foo_var, bar_var]
      runbook_double = double(runbook_variables: variables)
      context = double(runbook: runbook_double)

      expect(subject.resolve({ id: :foo }, context: context)).to eq(foo_var)
      expect(subject.resolve({ id: 'baz' }, context: context)).to eq(baz_var)
      expect(subject.resolve({ 'id' => :baz }, context: context)).to eq(baz_var)
      expect(subject.resolve({ id: 'xyz' }, context: context)).to eq(nil)
      expect(subject.resolve({ foo: 'foo' }, context: context)).to eq(nil)
    end

    it 'handles context that does not respond to runbook' do
      expect(subject.resolve({ id: :foo }, context: nil)).to eq(nil)
      expect(subject.resolve({ id: :foo }, context: double)).to eq(nil)
    end
  end

  it 'should provide an example' do
    expect(subject.example(double)).to eq('id-of-runbook-variable')
  end
end
