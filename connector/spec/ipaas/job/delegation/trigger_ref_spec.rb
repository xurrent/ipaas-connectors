require 'spec_helper'

describe IPaaS::Job::Delegation::TriggerRef do
  it 'should self-reference trigger' do
    trigger = IPaaS::Connector::Trigger.new
    expect(trigger.trigger).to eq(trigger)
  end

  it 'should create an example trigger for an trigger template' do
    trigger_template = IPaaS::Connector::TriggerTemplate.new('uuid') do
      config_schema do
        field :foo, 'Foo', :string
        field :bar, 'Bar', :integer
      end
    end

    expect(trigger_template.trigger.config[:foo]).to eq('Hello World!')
    expect(trigger_template.trigger.config[:bar]).to eq(42)
  end
end
