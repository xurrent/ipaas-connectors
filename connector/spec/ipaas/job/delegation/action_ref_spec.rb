require 'spec_helper'

describe IPaaS::Job::Delegation::ActionRef do
  it 'should self-reference action' do
    action = IPaaS::Connector::Action.new
    expect(action.action).to eq(action)
  end

  it 'should create an example action for an action template' do
    action_template = spec_connector.action('uuid') do
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

  it 'gives the example action the connector of its template, so its blocks and helpers have an owner' do
    skip_function_capture_validation
    action_template = spec_connector.action('uuid') do
      helper(:greeting) { 'hello' }
      input_schema do
        field :foo, 'Foo', :string
        after_update { |fields, _values| fields }
      end
    end
    example = action_template.action

    expect(example.connector).to be(spec_connector)
    expect(example.helpers.greeting).to eq('hello')
    expect(example.input[:foo]).to eq('Hello World!')
    after_update = IPaaS::Connector::Common::ProcHelper.new(example, example.input_schema.after_update,
                                                            connector: spec_connector)
    key = after_update.send(:validation_cache_key)
    expect(spec_connector.proc_validations.include?(key)).to be(true)
    expect(IPaaS::Connector::Common::ProcHelper.validated_before).not_to include(key)
  end
end
