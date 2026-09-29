require 'spec_helper'

describe 'Microsoft Outlook Send Email Action', :action, :microsoft_outlook do
  let(:action_template_id) { '71c046bb-7c2a-45fc-b88a-0e25d94a3975' }
  let(:send_mail_url) { "https://graph.microsoft.com/v1.0/users/#{default_mailbox}/sendMail" }
  let(:sent_items_url) { "https://graph.microsoft.com/v1.0/users/#{default_mailbox}/mailFolders/sentitems/messages" }

  let(:base_input) do
    {
      subject: 'Hello',
      body_content: '<p>Hi there</p>',
      to_recipients: [{ address: 'bob@contoso.com' }],
      save_to_sent_items: true,
    }
  end

  before do
    stub_graph_token
    stub_request(:get, sent_items_url).with(query: hash_including({})).to_return(status: 200,
                                                                                 body: { value: [] }.to_json)
  end

  it 'requires subject, body_content, to_recipients, and save_to_sent_items' do
    expect(action.input_schema.field(:subject).required).to be_truthy
    expect(action.input_schema.field(:body_content).required).to be_truthy
    expect(action.input_schema.field(:to_recipients).required).to be_truthy
    expect(action.input_schema.field(:save_to_sent_items).required).to be_truthy
  end

  it 'defaults body_content_type to HTML' do
    expect(action.input_schema.field(:body_content_type).default).to eq('HTML')
  end

  it 'sends the message to the Default mailbox with the expected payload' do
    stub = stub_request(:post, send_mail_url)
           .with(body: {
             message: {
               subject: 'Hello',
               body: { contentType: 'HTML', content: '<p>Hi there</p>' },
               toRecipients: [{ emailAddress: { address: 'bob@contoso.com' } }],
             },
             saveToSentItems: true,
           }.to_json)
           .to_return(status: 202, body: '')

    output = run_action(base_input)

    expect(output).to eq({ 'sent' => true, 'internet_message_id' => nil })
    expect(stub).to have_been_requested.once
  end

  it 'sends from the Target mailbox override when provided' do
    stub = stub_request(:post, 'https://graph.microsoft.com/v1.0/users/other@contoso.com/sendMail')
           .to_return(status: 202, body: '')
    stub_request(:get, 'https://graph.microsoft.com/v1.0/users/other@contoso.com/mailFolders/sentitems/messages')
      .with(query: hash_including({})).to_return(status: 200, body: { value: [] }.to_json)

    run_action(base_input.merge(target_mailbox: 'other@contoso.com'))

    expect(stub).to have_been_requested.once
  end

  it 'includes ccRecipients and bccRecipients with names when provided' do
    stub = stub_request(:post, send_mail_url)
           .with(body: hash_including(
             'message' => hash_including(
               'ccRecipients' => [{ 'emailAddress' => { 'address' => 'cc@contoso.com', 'name' => 'CC Person' } }],
               'bccRecipients' => [{ 'emailAddress' => { 'address' => 'bcc@contoso.com' } }],
             ),
           ))
           .to_return(status: 202, body: '')

    run_action(base_input.merge(
                 cc_recipients: [{ address: 'cc@contoso.com', name: 'CC Person' }],
                 bcc_recipients: [{ address: 'bcc@contoso.com' }],
               ))

    expect(stub).to have_been_requested.once
  end

  it 'includes importance when provided' do
    stub = stub_request(:post, send_mail_url)
           .with(body: hash_including('message' => hash_including('importance' => 'high')))
           .to_return(status: 202, body: '')

    run_action(base_input.merge(importance: 'high'))

    expect(stub).to have_been_requested.once
  end

  describe 'attachments' do
    let(:small_content) { Base64.strict_encode64('a' * 100) }

    it 'includes attachments as fileAttachment objects' do
      stub = stub_request(:post, send_mail_url)
             .with(body: hash_including(
               'message' => hash_including(
                 'attachments' => [{
                   '@odata.type' => '#microsoft.graph.fileAttachment',
                   'name' => 'report.pdf',
                   'contentBytes' => small_content,
                   'contentType' => 'application/pdf',
                 }],
               ),
             ))
             .to_return(status: 202, body: '')

      run_action(base_input.merge(
                   attachments: [{ name: 'report.pdf', content_bytes: small_content, content_type: 'application/pdf' }],
                 ))

      expect(stub).to have_been_requested.once
    end

    it 'defaults content_type to application/octet-stream when not provided' do
      stub = stub_request(:post, send_mail_url)
             .with(body: hash_including(
               'message' => hash_including(
                 'attachments' => [hash_including('contentType' => 'application/octet-stream')],
               ),
             ))
             .to_return(status: 202, body: '')

      run_action(base_input.merge(attachments: [{ name: 'file.bin', content_bytes: small_content }]))

      expect(stub).to have_been_requested.once
    end

    it 'falls back to raw string bytesize when content_bytes is not valid base64' do
      stub = stub_request(:post, send_mail_url).to_return(status: 202, body: '')

      run_action(base_input.merge(attachments: [{ name: 'f', content_bytes: 'not-valid-base64!!!' }]))

      expect(stub).to have_been_requested.once
    end

    it 'fails when an attachment exceeds the 3 MB MVP limit' do
      big_content = Base64.strict_encode64('a' * ((3 * 1024 * 1024) + 1))

      expect { run_action(base_input.merge(attachments: [{ name: 'big.bin', content_bytes: big_content }])) }
        .to raise_error(IPaaS::Job::FailJob, /exceeds the 3 MB MVP limit/)
    end
  end

  describe 'internet_message_id lookup' do
    it 'returns the internet message id of the most recently sent matching message' do
      stub_request(:post, send_mail_url).to_return(status: 202, body: '')
      stub_request(:get, sent_items_url)
        .with(query: { '$top' => '1', '$orderby' => 'sentDateTime desc', '$filter' => "subject eq 'Hello'" })
        .to_return(status: 200, body: { value: [{ internetMessageId: '<abc@contoso.com>' }] }.to_json)

      output = run_action(base_input)

      expect(output['internet_message_id']).to eq('<abc@contoso.com>')
    end

    it 'returns nil without failing the action when the lookup itself fails' do
      stub_request(:post, send_mail_url).to_return(status: 202, body: '')
      stub_request(:get, sent_items_url)
        .with(query: { '$top' => '1', '$orderby' => 'sentDateTime desc', '$filter' => "subject eq 'Hello'" })
        .to_return(status: 500, body: 'boom')

      output = run_action(base_input)

      expect(output['internet_message_id']).to be_nil
      expect(output['sent']).to eq(true)
    end
  end

  it 'fails when Microsoft Graph rejects the request' do
    stub_request(:post, send_mail_url)
      .to_return(status: 400, body: { error: { code: 'ErrorInvalidRecipients',
                                               message: 'Invalid recipients.', } }.to_json)

    expect { run_action(base_input) }
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [ErrorInvalidRecipients]: Invalid recipients.')
  end
end
