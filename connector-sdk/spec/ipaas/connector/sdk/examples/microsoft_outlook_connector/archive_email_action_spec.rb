require 'spec_helper'

describe 'Microsoft Outlook Archive Email Action', :action, :microsoft_outlook do
  let(:action_template_id) { 'ae525aa1-831d-4f8a-8103-bcb1c84d2061' }
  let(:move_url) { "https://graph.microsoft.com/v1.0/users/#{default_mailbox}/messages/msg-1/move" }

  before { stub_graph_token }

  it 'moves the message to the archive well-known folder' do
    stub = stub_request(:post, move_url).with(body: { destinationId: 'archive' }.to_json)
                                        .to_return(status: 200, body: { id: 'msg-1',
                                                                        parentFolderId: 'archive-id', }.to_json)

    output = run_action({ message_id: 'msg-1' })

    expect(output).to eq({ 'message_id' => 'msg-1', 'parent_folder_id' => 'archive-id' })
    expect(stub).to have_been_requested.once
  end

  it 'fails when neither Message ID nor Message IDs is provided' do
    expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, 'Provide either Message ID or Message IDs.')
  end

  it 'archives a batch of messages via Message IDs' do
    stub = stub_request(:post, 'https://graph.microsoft.com/v1.0/$batch')
           .to_return(status: 200, body: { responses: [{ id: '1', status: 200, body: {} }] }.to_json)

    output = run_action({ message_ids: ['msg-1'] })

    expect(output['results']).to eq([{ 'message_id' => 'msg-1', 'success' => true, 'error' => nil }])
    expect(stub).to have_been_requested.once
  end
end
