require 'spec_helper'

describe 'Microsoft Outlook Get Shared Mailbox Email Action', :action, :microsoft_outlook do
  let(:action_template_id) { 'b7635516-0e3f-4e1c-b447-efb59ace546f' }
  let(:shared_mailbox) { 'helpdesk@contoso.com' }
  let(:inbox_url) { "https://graph.microsoft.com/v1.0/users/#{shared_mailbox}/mailFolders/inbox" }
  let(:message_url) { "https://graph.microsoft.com/v1.0/users/#{shared_mailbox}/messages/msg-1" }

  before do
    stub_graph_token
    stub_request(:get, inbox_url).to_return(status: 200, body: { id: 'inbox-id' }.to_json)
  end

  it 'requires shared_mailbox_address and message_id' do
    expect(action.input_schema.field(:shared_mailbox_address).required).to be_truthy
    expect(action.input_schema.field(:message_id).required).to be_truthy
  end

  it 'fetches the message from the shared mailbox after the preflight access check' do
    stub_request(:get, message_url).to_return(status: 200, body: { id: 'msg-1', subject: 'Hello' }.to_json)

    output = run_action({ shared_mailbox_address: shared_mailbox, message_id: 'msg-1' })

    expect(output['message_id']).to eq('msg-1')
    expect(output['subject']).to eq('Hello')
  end

  it 'fails with a clear message when the connection lacks access to the shared mailbox' do
    stub_request(:get, inbox_url).to_return(status: 403, body: '')

    expect { run_action({ shared_mailbox_address: shared_mailbox, message_id: 'msg-1' }) }
      .to raise_error(IPaaS::Job::FailJob, "This connection does not have access to #{shared_mailbox}.")
  end
end
