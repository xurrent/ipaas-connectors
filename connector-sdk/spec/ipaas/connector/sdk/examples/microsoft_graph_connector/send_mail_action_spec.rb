require 'spec_helper'

describe 'Microsoft Graph Send Mail Action', :action, :microsoft_graph do
  let(:action_template_id) { '019ff9e8-8af5-764a-8c05-e3165e778e98' }
  let(:send_mail_url) { 'https://graph.microsoft.com/v1.0/users/jane@contoso.com/sendMail' }

  let(:base_input) do
    {
      user_id: 'jane@contoso.com',
      subject: 'Hello',
      body_content: '<p>Hi there</p>',
      to_recipients: ['bob@contoso.com'],
    }
  end

  before { stub_graph_token }

  it 'requires subject, body_content, and to_recipients' do
    expect(action.input_schema.field(:subject).required).to be_truthy
    expect(action.input_schema.field(:body_content).required).to be_truthy
    expect(action.input_schema.field(:to_recipients).required).to be_truthy
  end

  it 'defaults body_content_type to HTML and save_to_sent_items to true' do
    expect(action.input_schema.field(:body_content_type).default).to eq('HTML')
    expect(action.input_schema.field(:save_to_sent_items).default).to eq(true)
  end

  it 'sends the message with the expected payload' do
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

    expect(output).to eq({ 'sent' => true })
    expect(stub).to have_been_requested.once
  end

  it 'includes ccRecipients when provided' do
    stub = stub_request(:post, send_mail_url)
           .with(body: hash_including(
             'message' => hash_including('ccRecipients' => [{ 'emailAddress' => { 'address' => 'cc@contoso.com' } }]),
           ))
           .to_return(status: 202, body: '')

    run_action(base_input.merge(cc_recipients: ['cc@contoso.com']))

    expect(stub).to have_been_requested.once
  end

  it 'fails when Microsoft Graph rejects the request' do
    stub_request(:post, send_mail_url)
      .to_return(status: 400, body: { error: { code: 'ErrorInvalidRecipients',
                                               message: 'Invalid recipients.', } }.to_json)

    expect { run_action(base_input) }
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [ErrorInvalidRecipients]: Invalid recipients.')
  end
end
