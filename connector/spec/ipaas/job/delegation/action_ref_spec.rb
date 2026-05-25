require 'spec_helper'

describe IPaaS::Job::Delegation::ActionRef do
  it 'should self-reference action' do
    action = IPaaS::Connector::Action.new
    expect(action.action).to eq(action)
  end

  it 'should create an example action for an action template' do
    action_template = IPaaS::Connector::ActionTemplate.new('uuid') do
      input_schema do
        field :foo, 'Foo', :string
        field :bar, 'Bar', :integer
      end
    end

    expect(action_template.action.input[:foo]).to eq('Hello World!')
    expect(action_template.action.input[:bar]).to eq(42)
    expect(action_template.action.trigger_output).to be_a(Hash)
    expect(action_template.action.action_output('abc')).to be_nil
    expect(action_template.action.runbook.actions).to eq([action_template.action])
  end
end
