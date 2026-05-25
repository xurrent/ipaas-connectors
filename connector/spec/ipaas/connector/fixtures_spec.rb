require 'spec_helper'

describe 'fixtures' do
  it 'should validate the HTTP connector' do
    require_relative '../../fixtures/connectors/http_connector'
    connector = IPaaS::Connector::Connector.by_uuid('6a8f5f03-bf6b-40d6-9ae3-ae3a7d4734c1')
    expect(connector).to be_valid
  end

  it 'should validate the JSON endpoint connector' do
    require_relative '../../fixtures/connectors/json_endpoint_connector'
    connector = IPaaS::Connector::Connector.by_uuid('ef6a3a61-cdd1-4ec6-9d27-cb2aa5f8427d')
    expect(connector).to be_valid
  end

  it 'should validate the Flow connector' do
    require_relative '../../fixtures/connectors/flow_connector'
    connector = IPaaS::Connector::Connector.by_uuid('60f87e74-8f76-4d9e-b2ca-ac976f1c4359')
    expect(connector).to be_valid
  end

  it 'should validate the Scheduler connector' do
    require_relative '../../fixtures/connectors/scheduler_connector'
    connector = IPaaS::Connector::Connector.by_uuid('05901261-4073-4e5b-91b2-5f533935ddae')
    expect(connector).to be_valid
  end

  it 'should validate the Xurrent GraphQL connector' do
    require_relative '../../fixtures/connectors/xurrent_graphql_connector'
    connector = IPaaS::Connector::Connector.by_uuid('01962529-c8eb-7a89-a682-73d6f09541d6')
    expect(connector).to be_valid, -> { connector.errors.full_messages.join(', ') }
  end

  it 'should validate the Xurrent connector' do
    require_relative '../../fixtures/connectors/xurrent_connector'
    connector = IPaaS::Connector::Connector.by_uuid('01930641-94f0-7d88-941f-cd0f542b75b9')
    expect(connector).to be_valid, -> { connector.errors.full_messages.join(', ') }
  end
end
