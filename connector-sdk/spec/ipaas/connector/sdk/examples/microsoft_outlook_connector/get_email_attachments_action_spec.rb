require 'spec_helper'

describe 'Microsoft Outlook Get Email Attachments Action', :action, :microsoft_outlook do
  let(:action_template_id) { 'bf04a725-708d-4e1c-a8b8-cfff4dfa32cb' }
  let(:attachments_url) { "https://graph.microsoft.com/v1.0/users/#{default_mailbox}/messages/msg-1/attachments" }

  before { stub_graph_token }

  it 'requires message_id' do
    expect(action.input_schema.field(:message_id).required).to be_truthy
  end

  it 'lists attachment metadata without content' do
    stub_request(:get, attachments_url).to_return(status: 200, body: { value: [
      { id: 'att-1', name: 'report.pdf', size: 1024, contentType: 'application/pdf', isInline: false,
        contentBytes: 'should-not-appear', },
    ] }.to_json)

    output = run_action({ message_id: 'msg-1' })

    expect(output['attachments']).to eq(
      [{ 'attachment_id' => 'att-1', 'name' => 'report.pdf', 'size_in_bytes' => 1024,
         'content_type' => 'application/pdf', 'is_inline' => false, }],
    )
  end

  it 'fails when the message cannot be found' do
    stub_request(:get, attachments_url)
      .to_return(status: 404, body: { error: { code: 'ErrorItemNotFound', message: 'Not found.' } }.to_json)

    expect { run_action({ message_id: 'msg-1' }) }
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [ErrorItemNotFound]: Not found.')
  end
end
