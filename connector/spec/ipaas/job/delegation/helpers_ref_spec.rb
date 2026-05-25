require 'spec_helper'

describe IPaaS::Job::Delegation::HelpersRef do
  it 'should retrieve the helpers from the action template' do
    action = IPaaS::Connector::Action.new
    expect(action).to receive(:action_template) { double(helpers: 'helpers') }
    expect(action.helpers).to eq('helpers')
  end

  it 'should retrieve the helpers from the trigger template' do
    trigger = IPaaS::Connector::Trigger.new
    expect(trigger).to receive(:trigger_template) { double(helpers: 'helpers') }
    expect(trigger.helpers).to eq('helpers')
  end

  it 'should default to calling the connector method' do
    inbound_connection = IPaaS::Connector::Connection.new('connection_uuid').tap do |c|
      c.direction = :inbound
      c.connector = IPaaS::Connector::Connector.new('connector_uuid').tap do |connector|
        connector.helper(:foo) { 'bar' }
      end
    end
    expect(inbound_connection.helpers.foo).to eq('bar')
  end

  class TestContext
    include IPaaS::Job::Context
  end

  it 'should return nil when connector is not known' do
    context = TestContext.new
    expect(context.helpers).to be_nil
  end
end
