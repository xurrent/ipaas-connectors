require 'spec_helper'

describe 'Microsoft Outlook Move Email Action', :action, :microsoft_outlook do
  let(:action_template_id) { '7e175ec7-97ac-4d85-94ed-82880a49c6fc' }
  let(:move_url) { "https://graph.microsoft.com/v1.0/users/#{default_mailbox}/messages/msg-1/move" }
  let(:batch_url) { 'https://graph.microsoft.com/v1.0/$batch' }

  before { stub_graph_token }

  it 'requires destination_folder_id' do
    expect(action.input_schema.field(:destination_folder_id).required).to be_truthy
  end

  it 'moves a single message by Message ID' do
    stub = stub_request(:post, move_url).with(body: { destinationId: 'processed' }.to_json)
                                        .to_return(status: 200, body: { id: 'msg-1',
                                                                        parentFolderId: 'processed-id', }.to_json)

    output = run_action({ message_id: 'msg-1', destination_folder_id: 'processed' })

    expect(output).to eq({ 'message_id' => 'msg-1', 'parent_folder_id' => 'processed-id' })
    expect(stub).to have_been_requested.once
  end

  it 'fails when neither Message ID nor Message IDs is provided' do
    expect { run_action({ destination_folder_id: 'processed' }) }
      .to raise_error(IPaaS::Job::FailJob, 'Provide either Message ID or Message IDs.')
  end

  it 'moves from the Target mailbox override' do
    stub = stub_request(:post, 'https://graph.microsoft.com/v1.0/users/other@contoso.com/messages/msg-1/move')
           .to_return(status: 200, body: { id: 'msg-1', parentFolderId: 'processed-id' }.to_json)

    run_action({ target_mailbox: 'other@contoso.com', message_id: 'msg-1', destination_folder_id: 'processed' })

    expect(stub).to have_been_requested.once
  end

  describe 'batch move (Message IDs)' do
    it 'issues one $batch call with one sub-request per message and maps success/failure' do
      stub = stub_request(:post, batch_url)
             .with(body: {
               requests: [
                 { id: '1', method: 'POST', url: "/users/#{default_mailbox}/messages/msg-1/move",
                   body: { destinationId: 'processed' }, headers: { 'Content-Type' => 'application/json' }, },
                 { id: '2', method: 'POST', url: "/users/#{default_mailbox}/messages/msg-2/move",
                   body: { destinationId: 'processed' }, headers: { 'Content-Type' => 'application/json' }, },
               ],
             }.to_json)
             .to_return(status: 200, body: {
               responses: [
                 { id: '1', status: 200, body: {} },
                 { id: '2', status: 404, body: { error: { code: 'ErrorItemNotFound', message: 'Not found.' } } },
               ],
             }.to_json)

      output = run_action({ message_ids: %w[msg-1 msg-2], destination_folder_id: 'processed' })

      expect(output).to eq(
        { 'results' => [
          { 'message_id' => 'msg-1', 'success' => true, 'error' => nil },
          { 'message_id' => 'msg-2', 'success' => false, 'error' => 'Not found.' },
        ] },
      )
      expect(stub).to have_been_requested.once
    end

    it 'fails when more than 20 message ids are provided' do
      expect { run_action({ message_ids: Array.new(21) { |i| "msg-#{i}" }, destination_folder_id: 'processed' }) }
        .to raise_error(IPaaS::Job::FailJob, 'Move Multiple Emails supports at most 20 message IDs per call.')
    end
  end

  it 'fails on an unexpected HTTP error with a truly empty body' do
    stub_request(:post, move_url).to_return(status: 500, body: '')

    expect { run_action({ message_id: 'msg-1', destination_folder_id: 'processed' }) }
      .to raise_error(IPaaS::Job::FailJob, "HTTP error from Microsoft Graph API: 500 ''")
  end

  it 'fails when Microsoft Graph rejects the move' do
    stub_request(:post, move_url)
      .to_return(status: 404, body: { error: { code: 'ErrorItemNotFound', message: 'Not found.' } }.to_json)

    expect { run_action({ message_id: 'msg-1', destination_folder_id: 'processed' }) }
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [ErrorItemNotFound]: Not found.')
  end
end
