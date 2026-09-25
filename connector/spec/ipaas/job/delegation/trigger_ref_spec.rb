require 'spec_helper'

describe IPaaS::Job::Delegation::TriggerRef do
  it 'should self-reference trigger' do
    trigger = IPaaS::Connector::Trigger.new
    expect(trigger.trigger).to eq(trigger)
  end

  it 'should create an example trigger for an trigger template' do
    trigger_template = spec_connector.trigger('uuid') do
      config_schema do
        field :foo, 'Foo', :string
        field :bar, 'Bar', :integer
      end
    end

    expect(trigger_template.trigger.config[:foo]).to eq('Hello World!')
    expect(trigger_template.trigger.config[:bar]).to eq(42)
  end

  it 'gives the example trigger the connector of its template, so its blocks and helpers have an owner' do
    skip_function_capture_validation
    trigger_template = spec_connector.trigger('uuid') do
      helper(:greeting) { 'hello' }
      config_schema do
        field :foo, 'Foo', :string
        after_update { |fields, _values| fields }
      end
    end
    example = trigger_template.trigger

    expect(example.connector).to be(spec_connector)
    expect(example.helpers.greeting).to eq('hello')
    expect(example.config[:foo]).to eq('Hello World!')
    after_update = IPaaS::Connector::Common::ProcHelper.new(example, example.config_schema.after_update,
                                                            connector: spec_connector)
    key = after_update.send(:validation_cache_key)
    expect(spec_connector.proc_validations.include?(key)).to be(true)
    expect(IPaaS::Connector::Common::ProcHelper.validated_before).not_to include(key)
  end
end
