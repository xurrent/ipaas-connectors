require 'spec_helper'

describe 'Microsoft Outlook Send Email From Shared Mailbox Action', :action, :microsoft_outlook do
  let(:action_template_id) { '0e714f55-e685-4c39-b336-8b7c870c40c9' }
  let(:shared_mailbox) { 'helpdesk@contoso.com' }
  let(:inbox_url) { "https://graph.microsoft.com/v1.0/users/#{shared_mailbox}/mailFolders/inbox" }
  let(:send_mail_url) { "https://graph.microsoft.com/v1.0/users/#{shared_mailbox}/sendMail" }
  let(:sent_items_url) { "https://graph.microsoft.com/v1.0/users/#{shared_mailbox}/mailFolders/sentitems/messages" }

  let(:base_input) do
    {
      shared_mailbox_address: shared_mailbox,
      subject: 'Hello',
      body_content: '<p>Hi there</p>',
      to_recipients: [{ address: 'bob@contoso.com' }],
      save_to_sent_items: true,
    }
  end

  before do
    stub_graph_token
    stub_request(:get, inbox_url).to_return(status: 200, body: { id: 'inbox-id' }.to_json)
    stub_request(:get, sent_items_url).with(query: hash_including({})).to_return(status: 200,
                                                                                 body: { value: [] }.to_json)
  end

  it 'requires shared_mailbox_address' do
    expect(action.input_schema.field(:shared_mailbox_address).required).to be_truthy
  end

  it 'sends the message from the shared mailbox after the preflight access check' do
    stub = stub_request(:post, send_mail_url).to_return(status: 202, body: '')

    output = run_action(base_input)

    expect(output['sent']).to eq(true)
    expect(stub).to have_been_requested.once
  end

  it 'fails with a clear message when the connection lacks access to the shared mailbox' do
    stub_request(:get, inbox_url).to_return(status: 403, body: '')

    expect { run_action(base_input) }
      .to raise_error(IPaaS::Job::FailJob, "This connection does not have access to #{shared_mailbox}.")
  end
end
