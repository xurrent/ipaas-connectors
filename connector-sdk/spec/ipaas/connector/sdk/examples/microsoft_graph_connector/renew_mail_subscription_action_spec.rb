require 'spec_helper'

describe 'Microsoft Graph Renew Mail Subscription Action', :action, :microsoft_graph do
  let(:action_template_id) { '019ff9e8-8af5-762d-be39-e82b1cbdebb0' }
  let(:target_runbook_uuid) { 'runbook-uuid-1' }

  let(:target_runbook) do
    IPaaS::Connector::Runbook.new(target_runbook_uuid).tap do |r|
      IPaaS::Connector::Runbook.add_record_by_uuid(r)
    end
  end

  before do
    stub_graph_token
    target_runbook
  end

  it 'requires mail_trigger_runbook' do
    expect(action.input_schema.field(:mail_trigger_runbook).required).to be_truthy
  end

  it 'fails when no subscription is stored for the runbook' do
    expect { run_action({ mail_trigger_runbook: target_runbook_uuid }) }
      .to raise_error(IPaaS::Job::FailJob,
                      'No active Microsoft Graph subscription found for that runbook. Has the trigger been enabled?')
  end

  context 'when a subscription is stored' do
    before do
      action({ mail_trigger_runbook: target_runbook_uuid })
      outbound_connection.store.write("graph_mail_subscription_id-#{target_runbook_uuid}", 'sub-1')
    end

    it 'patches the subscription with a new expiration and returns it' do
      stub = stub_request(:patch, 'https://graph.microsoft.com/v1.0/subscriptions/sub-1')
             .to_return(status: 200, body: { id: 'sub-1' }.to_json)

      Timecop.freeze do
        output = run_action({ mail_trigger_runbook: target_runbook_uuid })

        expect(output[:subscription_id]).to eq('sub-1')
        expect(output[:expiration_date_time]).to eq(4230.minutes.from_now)
      end
      expect(stub).to have_been_requested.once
    end

    it 'fails when Microsoft Graph rejects the renewal' do
      stub_request(:patch, 'https://graph.microsoft.com/v1.0/subscriptions/sub-1')
        .to_return(status: 404, body: { error: { code: 'ResourceNotFound', message: 'Subscription expired.' } }.to_json)

      expect { run_action({ mail_trigger_runbook: target_runbook_uuid }) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [ResourceNotFound]: Subscription expired.')
    end
  end
end
