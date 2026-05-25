require 'spec_helper'

describe IPaaS::Job::Delegation::InboundConnectionRef do
  it 'should self-reference inbound connection' do
    inbound_connection = IPaaS::Connector::Connection.new('connection_uuid').tap do |c|
      c.direction = :inbound
    end
    expect(inbound_connection.inbound_connection).to eq(inbound_connection)
  end

  it 'should return the inbound connection of the trigger template' do
    trigger_template = IPaaS::Connector::TriggerTemplate.new('uuid')
    expect(trigger_template).to receive(:connector) { double(inbound_connection: 'inbound_connection') }
    expect(trigger_template.inbound_connection).to eq('inbound_connection')
  end

  it 'should return nil for action templates' do
    action_template = IPaaS::Connector::ActionTemplate.new('uuid')
    expect(action_template.inbound_connection).to be_nil
  end
end
