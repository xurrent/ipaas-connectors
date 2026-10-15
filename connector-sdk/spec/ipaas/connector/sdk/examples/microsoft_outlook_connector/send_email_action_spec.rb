require 'spec_helper'

describe 'Microsoft Outlook Send Email Action', :action, :microsoft_outlook do
  let(:action_template_id) { '0c405a38-d2a3-4b45-9651-83b9b36709bc' }
  let(:send_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/sendMail" }

  # Every field the schema declares is named here. A field left out of the hash is filled from the schema's
  # generated example instead of arriving empty, so leaving one out would send a value no step ever mapped.
  def input(overrides = {})
    {
      mailbox: nil,
      to_recipients: ['blake@contoso.com'],
      cc_recipients: nil,
      bcc_recipients: nil,
      subject: 'Quarterly report',
      body: 'The report is attached.',
      body_type: nil,
    }.merge(overrides)
  end

  def stub_send(status: 202, body: '', url: send_url, headers: {})
    stub_request(:post, url).to_return(status: status, body: body, headers: headers)
  end

  def stub_error(status, code, message, headers: {})
    stub_request(:post, send_url)
      .to_return(status: status, body: { error: { code: code, message: message } }.to_json,
                 headers: headers.merge('Content-Type' => 'application/json'))
  end

  describe 'the message it sends' do
    it 'posts the message Microsoft expects and asks for a copy in Sent Items' do
      stub_send
      run_action(input(cc_recipients: ['cc@contoso.com'], bcc_recipients: ['bcc@contoso.com']))
      expect(a_request(:post, send_url).with(body: {
        message: {
          subject: 'Quarterly report',
          body: { contentType: 'text', content: 'The report is attached.' },
          toRecipients: [{ emailAddress: { address: 'blake@contoso.com' } }],
          ccRecipients: [{ emailAddress: { address: 'cc@contoso.com' } }],
          bccRecipients: [{ emailAddress: { address: 'bcc@contoso.com' } }],
        },
        saveToSentItems: true,
      })).to have_been_made
    end

    # Measured against the real tenant: the same payload without this header is refused with HTTP 415
    # RequestBodyRead. http_post does not set it, so the run block has to.
    it 'declares the JSON content type that Graph refuses the send without' do
      stub_send
      run_action(input)
      expect(a_request(:post, send_url).with(headers: { 'Content-Type' => 'application/json' }))
        .to have_been_made
    end

    it 'sends from the mailbox the step names' do
      shared_url = 'https://graph.microsoft.com/v1.0/users/support@contoso.com/sendMail'
      stub_send(url: shared_url)
      run_action(input(mailbox: 'support@contoso.com'))
      expect(a_request(:post, shared_url)).to have_been_made
    end

    it 'sends from the default mailbox of the connection when the step leaves Mailbox empty' do
      stub_send
      run_action(input)
      expect(a_request(:post, send_url)).to have_been_made
    end

    it 'strips a mailto prefix and the spaces around an address, on the wire and in what it reports' do
      stub_send
      cleaned = [{ 'emailAddress' => { 'address' => 'blake@contoso.com' } }]
      output = run_action(input(to_recipients: ['  MAILTO:blake@contoso.com  ']))
      expect(a_request(:post, send_url)
        .with(body: hash_including('message' => hash_including('toRecipients' => cleaned))))
        .to have_been_made
      expect(output['to_recipients']).to eq(['blake@contoso.com'])
    end

    # to_json writes the angle brackets and the ampersand as JSON unicode escapes, so the markup never
    # appears literally on the wire, as the pattern below spells out.
    # That is valid JSON and Graph decodes it, but whoever reads a request log will see the escaped form.
    it 'sends an html body as markup, escaped' do
      stub_send
      run_action(input(body: '<b>hi</b> & bye', body_type: 'html'))
      expect(a_request(:post, send_url)
        .with(body: %r{"contentType":"html","content":"\\u003cb\\u003ehi\\u003c/b\\u003e \\u0026 bye"}))
        .to have_been_made
    end
  end

  describe 'what it reports back' do
    # The resolved output round-trips through the schema, so every key comes back as a string.
    it 'reports what was sent, so a later step names it without mapping the same values again' do
      stub_send
      expect(run_action(input(cc_recipients: ['cc@contoso.com']))).to eq({
        'sent' => true,
        'mailbox' => mailbox,
        'to_recipients' => ['blake@contoso.com'],
        'cc_recipients' => ['cc@contoso.com'],
        'bcc_recipients' => [],
        'subject' => 'Quarterly report',
      })
    end

    # Measured against the real tenant: the send answers 202 with a zero-length body and no Content-Type
    # header at all. The body is the empty string, not nil, and there is no JSON on the success path to read.
    it 'reads an accepted send from the status alone, because the answer carries no body' do
      stub_send(status: 202, body: '')
      expect(run_action(input)['sent']).to be(true)
    end

    it 'fails the job when Graph answers a success status that is not the accepted one' do
      stub_send(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /HTTP 200/)
    end
  end

  describe 'when Microsoft refuses the message' do
    it 'fails the job with Microsoft own words when it refuses a recipient' do
      stub_error(400, 'ErrorInvalidRecipients', 'At least one recipient is not valid.')
      expect { run_action(input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 400 ErrorInvalidRecipients: At least one recipient ' \
                        'is not valid.')
    end

    # Measured against the real tenant on an Exchange endpoint whose permission was missing: the answer is
    # ErrorAccessDenied and it names no permission, so what the step reports is Microsoft own sentence.
    it 'fails the job when Microsoft refuses the send outright' do
      stub_error(403, 'ErrorAccessDenied', 'Access is denied. Check credentials and try again.')
      expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /HTTP 403 ErrorAccessDenied/)
    end

    # A paused step runs the whole action again from the top, which posts to /sendMail a second time, and a
    # server error does not say the message was left unsent. 503 is the status the backoff helper pauses on
    # unless it is told otherwise, so this example goes red the moment that argument is dropped.
    it 'fails the job rather than pausing when Graph answers 503, because a pause would send it twice' do
      stub_error(503, 'ServiceUnavailable', 'Server is busy.')
      expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /HTTP 503 ServiceUnavailable/)
    end

    # The other half of the same decision: 502 is in the list List Emails pauses on, and Send Email must not
    # reuse that list.
    it 'fails the job rather than pausing when Graph answers 502' do
      stub_send(status: 502, body: '')
      expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /HTTP 502/)
    end

    # Microsoft rejected this request outright, so running the action again sends one message, not two.
    it 'pauses the step and runs it again when Graph asks for a pause' do
      stub_error(429, 'ApplicationThrottled', 'Application is over its MailboxConcurrency limit.',
                 headers: { 'Retry-After' => '6' })
      expect_reschedule_after(6) { run_action(input) }
    end
  end

  describe 'what it refuses before it calls Microsoft' do
    it 'refuses an address wrapped in a display name, and sends nothing' do
      stub_send
      expect { run_action(input(to_recipients: ['"Blake" <blake@contoso.com>'])) }
        .to raise_error(IPaaS::Job::FailJob, /which is not an email address/)
      expect(a_request(:post, send_url)).not_to have_been_made
    end

    it 'refuses a Cc list holding an empty address, and sends nothing' do
      stub_send
      expect { run_action(input(cc_recipients: ['cc@contoso.com', ''])) }
        .to raise_error(IPaaS::Job::FailJob, 'Cc holds an empty address. Remove the empty value, or map an ' \
                                             'address into it.')
      expect(a_request(:post, send_url)).not_to have_been_made
    end

    context 'when the connection carries no default mailbox' do
      let(:default_mailbox) { nil }

      it 'refuses to send when no mailbox is set on the step or on the connection' do
        stub_send
        expect { run_action(input) }
          .to raise_error(IPaaS::Job::FailJob,
                          'No mailbox. Set Mailbox on this step, or Default mailbox on the connection.')
        expect(a_request(:post, send_url)).not_to have_been_made
      end
    end
  end
end
