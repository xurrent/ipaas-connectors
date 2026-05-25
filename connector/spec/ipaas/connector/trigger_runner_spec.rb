require 'spec_helper'

describe 'Trigger Runner' do
  before(:all) do
    TriggerServer.start
  end

  let(:connector) do
    IPaaS::Connector::Connector.new('unique-connector-id') do
      inbound_connection do
        api_key_validator
      end

      trigger 'unique-trigger-id' do
        name 'JSON'

        output_schema 'unique-output-id' do
          field :root, 'Root', :hash
        end

        parse do |request|
          { root: JSON.parse(request.body.read).merge({ bar: 'baz' }) }
        end
      end
    end
  end

  let(:inbound_connection) do
    IPaaS::Connector::Connection.parse(
      {
        uuid: 'inbound_connection_uuid',
        direction: 'inbound',
        name: 'Test runner',
        connector: {
          uuid: connector.uuid,
        },
        config_mapping: [
          { field_id: 'api_key', nested:
            [
              { field_id: 'key', fixed: 'secret' },
              { field_id: 'value', fixed: 'boo' },
              { field_id: 'placement', fixed: 'Query params' },
            ],  },
        ],
      },
    )
  end

  let(:runbook) do
    double.tap do |runbook|
      allow(runbook).to receive(:uuid).and_return('runbook_uuid')
      allow(runbook).to receive(:store_trigger_output)
      IPaaS::Connector::Runbook.add_record_by_uuid(runbook)
    end
  end

  let(:trigger) do
    IPaaS::Connector::Trigger.parse(
      runbook,
      {
        inbound_connection: {
          uuid: inbound_connection.uuid,
        },
        trigger_template: {
          uuid: connector.trigger('unique-trigger-id').uuid,
        },
      },
    )
  end

  before(:each) do
    allow(runbook).to receive(:trigger).and_return(trigger)
  end

  it 'should parse a minimal incoming request' do
    endpoint = "/inbound/#{runbook.uuid}"
    uri = URI.parse("http://127.0.0.1:#{TriggerServer::TRIGGER_SERVER_PORT}#{endpoint}?secret=boo")
    data = { foo: 'bar' }
    response = Faraday.post(uri, data.to_json, 'Content-Type' => 'application/json')
    expect(response.status).to eq(200)
    expect(response.body).to eq({ root: data.merge({ bar: 'baz' }) }.to_json)
  end

  it 'should fail when authentication is missing' do
    endpoint = "/inbound/#{runbook.uuid}"
    uri = URI.parse("http://127.0.0.1:#{TriggerServer::TRIGGER_SERVER_PORT}#{endpoint}?secret=oops")
    data = { foo: 'bar' }
    response = Faraday.post(uri, data.to_json, 'Content-Type' => 'application/json')
    expect(response.status).to eq(400)
    expect(response.body).to eq({ error: 'Invalid or missing API key.' }.to_json)
  end

  context 'when validate and parse both read the request body' do
    let(:connector) do
      IPaaS::Connector::Connector.new('rewind-runner-connector') do
        inbound_connection do
          validate do |request|
            # stash what validate sees in a header so parse (and the test) can read it back
            request.headers['X-Validate-Saw'] = request.body.read
          end
        end

        trigger 'rewind-runner-trigger' do
          name 'Body echo'

          output_schema 'rewind-runner-output' do
            field :body_in_validate, 'Body seen by validate', :string
            field :body_in_parse, 'Body seen by parse', :string
          end

          parse do |request|
            {
              body_in_validate: request.headers['X-Validate-Saw'],
              body_in_parse: request.body.read,
            }
          end
        end
      end
    end

    let(:inbound_connection) do
      IPaaS::Connector::Connection.parse(
        {
          uuid: 'rewind_runner_inbound_uuid',
          direction: 'inbound',
          name: 'Rewind runner',
          connector: { uuid: connector.uuid },
        },
      )
    end

    let(:trigger) do
      IPaaS::Connector::Trigger.parse(
        runbook,
        {
          inbound_connection: { uuid: inbound_connection.uuid },
          trigger_template: { uuid: connector.trigger('rewind-runner-trigger').uuid },
        },
      )
    end

    it 'lets validate and parse both see the full body' do
      endpoint = "/inbound/#{runbook.uuid}"
      uri = URI.parse("http://127.0.0.1:#{TriggerServer::TRIGGER_SERVER_PORT}#{endpoint}")
      data = { hello: 'world' }
      response = Faraday.post(uri, data.to_json, 'Content-Type' => 'application/json')
      expect(response.status).to eq(200)
      body = JSON.parse(response.body)
      expect(body['body_in_validate']).to eq(data.to_json)
      expect(body['body_in_parse']).to eq(data.to_json)
    end
  end
end
