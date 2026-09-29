require 'spec_helper'

describe 'Microsoft Outlook Get Email Action', :action, :microsoft_outlook do
  let(:action_template_id) { '62dd41d4-fb3d-4b29-be5e-921bf55b6896' }
  let(:message_url) { "https://graph.microsoft.com/v1.0/users/#{default_mailbox}/messages/msg-1" }

  let(:sample_message) do
    {
      id: 'msg-1',
      subject: 'Hello',
      from: { emailAddress: { address: 'bob@contoso.com', name: 'Bob' } },
      toRecipients: [{ emailAddress: { address: 'jane@contoso.com', name: 'Jane' } }],
      ccRecipients: [{ emailAddress: { address: 'cc@contoso.com' } }],
      bccRecipients: [],
      receivedDateTime: '2026-08-01T00:00:00Z',
      sentDateTime: '2026-08-01T00:00:00Z',
      importance: 'normal',
      categories: ['Blue Category'],
      isRead: true,
      hasAttachments: false,
      conversationId: 'conv-1',
      internetMessageId: '<abc@contoso.com>',
      bodyPreview: 'Hi there',
      body: { contentType: 'html', content: '<p>Hi there</p>' },
      parentFolderId: 'folder-1',
    }
  end

  before { stub_graph_token }

  it 'requires message_id' do
    expect(action.input_schema.field(:message_id).required).to be_truthy
  end

  it 'defaults include_html_body to true' do
    expect(action.input_schema.field(:include_html_body).default).to eq(true)
  end

  it 'fetches and maps the message with the HTML body' do
    stub_request(:get, message_url)
      .with(headers: { 'Prefer' => 'outlook.body-content-type="html"' })
      .to_return(status: 200, body: sample_message.to_json)

    output = run_action({ message_id: 'msg-1' })

    expect(output['message_id']).to eq('msg-1')
    expect(output['subject']).to eq('Hello')
    expect(output['from_address']).to eq('bob@contoso.com')
    expect(output['from_name']).to eq('Bob')
    expect(output['to_recipients']).to eq([{ 'name' => 'Jane', 'address' => 'jane@contoso.com' }])
    expect(output['cc_recipients']).to eq([{ 'name' => nil, 'address' => 'cc@contoso.com' }])
    expect(output['bcc_recipients']).to eq([])
    expect(output['is_read']).to eq(true)
    expect(output['conversation_id']).to eq('conv-1')
    expect(output['internet_message_id']).to eq('<abc@contoso.com>')
    expect(output['html_body']).to eq('<p>Hi there</p>')
    expect(output['text_body']).to be_nil
    expect(output['folder']).to eq('folder-1')
  end

  it 'requests the plain text body when include_html_body is false' do
    text_message = sample_message.merge(body: { contentType: 'text', content: 'Hi there' })
    stub_request(:get, message_url)
      .with(headers: { 'Prefer' => 'outlook.body-content-type="text"' })
      .to_return(status: 200, body: text_message.to_json)

    output = run_action({ message_id: 'msg-1', include_html_body: false })

    expect(output['html_body']).to be_nil
    expect(output['text_body']).to eq('Hi there')
  end

  it 'reads from the Target mailbox override when provided' do
    stub = stub_request(:get, 'https://graph.microsoft.com/v1.0/users/other@contoso.com/messages/msg-1')
           .to_return(status: 200, body: sample_message.to_json)

    run_action({ message_id: 'msg-1', target_mailbox: 'other@contoso.com' })

    expect(stub).to have_been_requested.once
  end

  it 'fails when the message cannot be found' do
    stub_request(:get, message_url)
      .to_return(status: 404, body: { error: { code: 'ErrorItemNotFound', message: 'Not found.' } }.to_json)

    expect { run_action({ message_id: 'msg-1' }) }
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [ErrorItemNotFound]: Not found.')
  end
end
