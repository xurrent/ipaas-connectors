require 'spec_helper'

describe IPaaS::Job::Delegation::OutboundConnectionRef do
  it 'should self-reference outbound connection' do
    outbound_connection = IPaaS::Connector::Connection.new('connection_uuid').tap do |c|
      c.direction = :outbound
    end
    expect(outbound_connection.outbound_connection).to eq(outbound_connection)
  end

  it 'should return the outbound connection of the trigger template' do
    trigger_template = IPaaS::Connector::TriggerTemplate.new('uuid')
    expect(trigger_template).to receive(:connector) { double(outbound_connection: 'outbound_connection') }
    expect(trigger_template.outbound_connection).to eq('outbound_connection')
  end

  it 'should return the outbound connection of the trigger template' do
    action_template = IPaaS::Connector::ActionTemplate.new('uuid')
    expect(action_template).to receive(:connector) { double(outbound_connection: 'outbound_connection') }
    expect(action_template.outbound_connection).to eq('outbound_connection')
  end
end
