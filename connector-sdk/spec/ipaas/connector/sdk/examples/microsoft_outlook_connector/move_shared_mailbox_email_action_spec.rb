require 'spec_helper'

describe 'Microsoft Outlook Move Shared Mailbox Email Action', :action, :microsoft_outlook do
  let(:action_template_id) { 'b21652b0-d776-4f0b-880d-be84a9176f18' }
  let(:shared_mailbox) { 'helpdesk@contoso.com' }
  let(:inbox_url) { "https://graph.microsoft.com/v1.0/users/#{shared_mailbox}/mailFolders/inbox" }
  let(:move_url) { "https://graph.microsoft.com/v1.0/users/#{shared_mailbox}/messages/msg-1/move" }

  before do
    stub_graph_token
    stub_request(:get, inbox_url).to_return(status: 200, body: { id: 'inbox-id' }.to_json)
  end

  it 'requires shared_mailbox_address and destination_folder_id' do
    expect(action.input_schema.field(:shared_mailbox_address).required).to be_truthy
    expect(action.input_schema.field(:destination_folder_id).required).to be_truthy
  end

  it 'moves a message in the shared mailbox after the preflight access check' do
    stub = stub_request(:post, move_url).with(body: { destinationId: 'processed' }.to_json)
                                        .to_return(status: 200, body: { id: 'msg-1',
                                                                        parentFolderId: 'processed-id', }.to_json)

    output = run_action({ shared_mailbox_address: shared_mailbox, message_id: 'msg-1',
                          destination_folder_id: 'processed', })

    expect(output).to eq({ 'message_id' => 'msg-1', 'parent_folder_id' => 'processed-id' })
    expect(stub).to have_been_requested.once
  end

  it 'fails with a clear message when the connection lacks access to the shared mailbox' do
    stub_request(:get, inbox_url).to_return(status: 403, body: '')

    expect do
      run_action({ shared_mailbox_address: shared_mailbox, message_id: 'msg-1', destination_folder_id: 'processed' })
    end
      .to raise_error(IPaaS::Job::FailJob, "This connection does not have access to #{shared_mailbox}.")
  end
end
