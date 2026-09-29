require 'spec_helper'

describe 'Microsoft Outlook Download Attachment Action', :action, :microsoft_outlook do
  let(:action_template_id) { '3c9483f9-ab03-4e40-a181-fe3f104553ec' }
  let(:attachment_url) { "https://graph.microsoft.com/v1.0/users/#{default_mailbox}/messages/msg-1/attachments/att-1" }

  before { stub_graph_token }

  it 'requires message_id and attachment_id' do
    expect(action.input_schema.field(:message_id).required).to be_truthy
    expect(action.input_schema.field(:attachment_id).required).to be_truthy
  end

  it 'downloads the attachment content' do
    content = Base64.strict_encode64('file content')
    stub_request(:get, attachment_url).to_return(status: 200, body: {
      name: 'report.pdf', contentBytes: content, contentType: 'application/pdf',
    }.to_json)

    output = run_action({ message_id: 'msg-1', attachment_id: 'att-1' })

    expect(output).to eq({ 'name' => 'report.pdf', 'content_bytes' => content, 'content_type' => 'application/pdf' })
  end

  it 'downloads from the Target mailbox override' do
    stub = stub_request(:get, 'https://graph.microsoft.com/v1.0/users/other@contoso.com/messages/msg-1/attachments/att-1')
           .to_return(status: 200, body: { name: 'x', contentBytes: Base64.strict_encode64('y'),
                                           contentType: 'text/plain', }.to_json)

    run_action({ target_mailbox: 'other@contoso.com', message_id: 'msg-1', attachment_id: 'att-1' })

    expect(stub).to have_been_requested.once
  end

  it 'fails when the attachment cannot be found' do
    stub_request(:get, attachment_url)
      .to_return(status: 404, body: { error: { code: 'ErrorItemNotFound', message: 'Not found.' } }.to_json)

    expect { run_action({ message_id: 'msg-1', attachment_id: 'att-1' }) }
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [ErrorItemNotFound]: Not found.')
  end
end
