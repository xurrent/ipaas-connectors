require 'spec_helper'

describe 'Microsoft Graph Move Mail Message Action', :action, :microsoft_graph do
  let(:action_template_id) { '019ff9e8-8af5-7e12-b3d0-9b16fa604a52' }
  let(:move_url) { 'https://graph.microsoft.com/v1.0/users/jane@contoso.com/messages/msg-1/move' }

  before { stub_graph_token }

  it 'requires user_id, message_id, and destination_folder_id' do
    expect(action.input_schema.field(:user_id).required).to be_truthy
    expect(action.input_schema.field(:message_id).required).to be_truthy
    expect(action.input_schema.field(:destination_folder_id).required).to be_truthy
  end

  it 'moves the message to the destination folder' do
    stub = stub_request(:post, move_url)
           .with(body: { destinationId: 'archive' }.to_json)
           .to_return(status: 201, body: { id: 'msg-1-new', parentFolderId: 'archive-folder-id' }.to_json)

    output = run_action({ user_id: 'jane@contoso.com', message_id: 'msg-1', destination_folder_id: 'archive' })

    expect(output).to eq({ 'message_id' => 'msg-1-new', 'parent_folder_id' => 'archive-folder-id' })
    expect(stub).to have_been_requested.once
  end

  it 'fails when the message cannot be found' do
    stub_request(:post, move_url)
      .to_return(status: 404, body: { error: { code: 'ErrorItemNotFound', message: 'Message not found.' } }.to_json)

    expect { run_action({ user_id: 'jane@contoso.com', message_id: 'msg-1', destination_folder_id: 'archive' }) }
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [ErrorItemNotFound]: Message not found.')
  end
end
