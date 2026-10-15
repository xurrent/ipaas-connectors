require 'spec_helper'

# One run_action per example, always. action(input) memoizes on its first call, so a second call in
# the same example silently re-runs the first action with the first input and proves nothing.
describe 'Microsoft Outlook Get Email Action', :action, :microsoft_outlook do
  let(:action_template_id) { '2c220667-3750-487b-a600-dad37fa674d4' }
  let(:message_id) { 'AAMkAGQz=' }
  let(:message_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/messages/#{message_id}" }

  def message(overrides = {})
    graph_message(id: message_id,
                  body: { contentType: 'html', content: '<p>Your message could not be delivered</p>' })
      .merge(overrides)
  end

  def stub_message(body, status: 200, url: message_url)
    stub_request(:get, url).with(query: hash_including({}))
                           .to_return(status: status, body: body.to_json,
                                      headers: { 'Content-Type' => 'application/json' })
  end

  def input(**overrides)
    { message_id: message_id, mailbox: nil, body_format: nil }.merge(overrides)
  end

  describe 'what it asks Microsoft for' do
    it 'asks for the summary fields and the body' do
      stub_message(message)
      run_action(input)
      expect(a_request(:get, message_url)
        .with(query: { '$select' => MicrosoftOutlookConnector::MESSAGE_DETAIL_SELECT.join(',') }))
        .to have_been_made
    end

    # The header is how the body format is chosen. Microsoft answers HTML when it is absent, so a
    # dropped header looks like a working action that ignores the builder's choice.
    it 'asks for plain text with the header, not with a query parameter' do
      stub_message(message)
      run_action(input(body_format: 'Plain text'))
      expect(a_request(:get, message_url)
        .with(query: hash_including({}),
              headers: { 'Prefer' => 'outlook.body-content-type="text"' })).to have_been_made
    end

    it 'asks for HTML when the step leaves the format empty' do
      stub_message(message)
      run_action(input)
      expect(a_request(:get, message_url)
        .with(query: hash_including({}),
              headers: { 'Prefer' => 'outlook.body-content-type="html"' })).to have_been_made
    end

    it 'reads the mailbox the step names rather than the connection default' do
      other = 'shared@contoso.com'
      url = "https://graph.microsoft.com/v1.0/users/#{other}/messages/#{message_id}"
      stub_message(message, url: url)
      run_action(input(mailbox: other))
      expect(a_request(:get, url).with(query: hash_including({}))).to have_been_made
    end
  end

  describe 'what it gives the runbook' do
    # The resolved output round-trips through the schema, so it comes back with string keys.
    it 'returns the body and the format Microsoft actually used' do
      stub_message(message)
      output = run_action(input)
      expect(output['body']).to eq('<p>Your message could not be delivered</p>')
      expect(output['body_format']).to eq('html')
    end

    it 'returns everything List Emails returns as well' do
      stub_message(message)
      output = run_action(input)
      expect(output['message_id']).to eq(message_id)
      expect(output['subject']).to eq('Undeliverable: Testing from within iPaaS')
      expect(output['from']).to eq({ 'name' => 'Microsoft Outlook', 'address' => 'postmaster@contoso.com' })
      expect(output['has_attachments']).to be(false)
    end

    # Microsoft leaves the body out entirely on some messages.
    it 'returns an empty body rather than failing when Microsoft sends none' do
      stub_message(message.except(:body))
      expect(run_action(input)['body']).to eq('')
    end
  end

  describe 'what it refuses and what it reports' do
    it 'refuses an id that is already percent encoded, before it calls Microsoft' do
      expect { run_action(input(message_id: 'AAMk%2Ffake')) }
        .to raise_error(IPaaS::Job::FailJob, /already URL encoded/)
      expect(a_request(:get, /graph\.microsoft\.com/).with(query: hash_including({}))).not_to have_been_made
    end

    # The message must name the mailbox: a step that left it empty fell back to the connection
    # default, and without the name there is no way to see where it looked.
    it 'names the mailbox it read when Microsoft has no such message' do
      stub_message({ error: { code: 'ErrorItemNotFound', message: 'not found' } }, status: 404)
      expect { run_action(input) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Microsoft Graph has no message '#{message_id}' in mailbox '#{mailbox}'.")
    end

    it 'names the status when Microsoft answers 403 with a page that is not JSON' do
      stub_request(:get, message_url).with(query: hash_including({}))
                                     .to_return(status: 403, body: '<html><body>Forbidden</body></html>')
      expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /HTTP 403/)
    end

    # 429 and 503 are the platform default every other connector takes.
    it 'fails rather than rescheduling when Microsoft answers 504' do
      stub_request(:get, message_url).with(query: hash_including({})).to_return(status: 504, body: '')
      expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /HTTP 504/)
    end

    it 'reschedules when Microsoft is unavailable' do
      stub_request(:get, message_url).with(query: hash_including({})).to_return(status: 503, body: '')
      expect_reschedule_after(60, /not available/) { run_action(input) }
    end

    it 'reschedules rather than failing when Microsoft asks for a pause' do
      stub_request(:get, message_url).with(query: hash_including({}))
                                     .to_return(status: 429, body: '', headers: { 'Retry-After' => '30' })
      expect_reschedule_after(30) { run_action(input) }
    end
  end
end
