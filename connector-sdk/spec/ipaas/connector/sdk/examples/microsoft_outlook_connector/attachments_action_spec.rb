require 'spec_helper'

describe 'Microsoft Outlook Attachment Actions', :action, :microsoft_outlook do
  let(:message_id) { 'AAMkAGQzOGVlNTJk=' }
  let(:attachment_id) { 'AAMkAGQzOGVlNTJkLWMzMzY=' }
  let(:attachments_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/messages/#{message_id}/attachments" }
  let(:attachment_url) { "#{attachments_url}/#{attachment_id}" }
  let(:summary_select) { MicrosoftOutlookConnector::ATTACHMENT_SELECT.join(',') }
  let(:content_select) { MicrosoftOutlookConnector::ATTACHMENT_CONTENT_SELECT.join(',') }

  # The keys of a row Graph really answers under ATTACHMENT_SELECT. Graph adds @odata.type, and for a file
  # @odata.mediaContentType, although the select names neither and a select that named @odata.type is HTTP 400.
  def file_row(overrides = {})
    {
      '@odata.type': '#microsoft.graph.fileAttachment',
      '@odata.mediaContentType': 'text/plain',
      id: attachment_id,
      name: 'small.txt',
      contentType: 'text/plain',
      size: 1163,
      isInline: false,
    }.merge(overrides)
  end

  # A message attached to a message. Graph reports a name and a size for it, and no content type at all.
  def item_row(overrides = {})
    {
      '@odata.type': MicrosoftOutlookConnector::ITEM_ATTACHMENT_TYPE,
      id: attachment_id,
      name: 'attached message',
      contentType: nil,
      size: 1247,
      isInline: false,
    }.merge(overrides)
  end

  def content_row(overrides = {})
    {
      id: attachment_id,
      name: 'small.txt',
      contentType: 'text/plain',
      contentBytes: Base64.strict_encode64('hello'),
    }.merge(overrides)
  end

  def list_input(**overrides)
    { message_id: message_id, mailbox: nil }.merge(overrides)
  end

  def download_input(**overrides)
    { message_id: message_id, attachment_id: attachment_id, mailbox: nil }.merge(overrides)
  end

  def json_response(body, status)
    { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  # A stub registered on a bare URL matches only a request that carries no query, so a stub that is not there
  # to pin the query takes any query and the example asserts the query separately.
  def stub_list(body, status: 200)
    stub_request(:get, attachments_url).with(query: hash_including({})).to_return(json_response(body, status))
  end

  # Download reads one URL twice and the two reads differ only by the select, so each stub pins its own. A
  # stub that took any query would answer both reads with one body and leave the two reads untested.
  def stub_summary(body, status: 200)
    stub_request(:get, attachment_url).with(query: { '$select' => summary_select })
                                      .to_return(json_response(body, status))
  end

  def stub_content(body, status: 200)
    stub_request(:get, attachment_url).with(query: { '$select' => content_select })
                                      .to_return(json_response(body, status))
  end

  describe 'List Attachments' do
    let(:action_template_id) { '82d33e8f-e4c2-4d12-8b15-6edac6c36e2c' }

    # An exact query, not a subset: the whole point of the select is that the bytes of every file stay behind,
    # and a subset match would still pass with the content field appended.
    it 'asks Graph for the five names that describe an attachment without its bytes' do
      stub_list({ value: [file_row] })
      run_action(list_input)
      expect(a_request(:get, attachments_url).with(query: { '$select' => summary_select })).to have_been_made
    end

    # The resolved output round-trips through the schema, so a row comes back with string keys.
    it 'maps a file attachment onto the output fields' do
      stub_list({ value: [file_row] })
      expect(run_action(list_input)[:attachments]).to eq([{
        'attachment_id' => attachment_id,
        'name' => 'small.txt',
        'content_type' => 'text/plain',
        'size_in_bytes' => 1163,
        'is_inline' => false,
      }])
    end

    # Observed against the real tenant: a message attached to a message is listed beside the files, with a
    # name and a size and a null content type. It is listed rather than hidden, and Download refuses it.
    it 'lists a message attached to a message with no content type' do
      stub_list({ value: [item_row] })
      expect(run_action(list_input)[:attachments].first['content_type']).to be_nil
    end

    it 'lists every attachment of the message in the order Graph returns them' do
      stub_list({ value: [file_row, item_row(id: 'AAMkAGQzSXRlbQ=')] })
      expect(run_action(list_input)[:attachments].map { |row| row['name'] })
        .to eq(['small.txt', 'attached message'])
    end

    it 'answers with an empty list when the message holds no attachment' do
      stub_list({ value: [] })
      expect(run_action(list_input)[:attachments]).to eq([])
    end

    it 'reads the mailbox the step names rather than the one on the connection' do
      other_url = "https://graph.microsoft.com/v1.0/users/sales@contoso.com/messages/#{message_id}/attachments"
      stub_request(:get, other_url).with(query: hash_including({})).to_return(json_response({ value: [] }, 200))
      run_action(list_input(mailbox: 'sales@contoso.com'))
      expect(a_request(:get, other_url).with(query: hash_including({}))).to have_been_made
    end

    # The assertion: a Graph collection answers with value as a list, so anything else is a state that cannot
    # happen while Graph keeps its contract.
    it 'raises when the attachment list value is not a list' do
      stub_list({ value: { id: attachment_id } })
      expect { run_action(list_input) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph returned an attachment list whose value is not a list')
    end

    # Observed against the real tenant: a message id Graph cannot read is HTTP 400, not HTTP 404.
    it 'fails the job with Microsoft own words when the message id is malformed' do
      stub_list({ error: { code: 'ErrorInvalidIdMalformed', message: 'Id is malformed.' } }, status: 400)
      expect { run_action(list_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 400 ErrorInvalidIdMalformed: Id is malformed.')
    end

    it 'names the mailbox when Microsoft refuses the application on the attachment list' do
      stub_list({ error: { code: 'ErrorAccessDenied', message: 'Access is denied.' } }, status: 403)
      expect { run_action(list_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Microsoft Graph returned HTTP 403 ErrorAccessDenied while reading mailbox '#{mailbox}': " \
                        'Access is denied.')
    end

    # Observed against the real tenant: Graph throttles a mailbox on how many requests run at once, so this
    # arrives on an ordinary read rather than only under a burst.
    it 'reschedules rather than failing when Graph asks for a pause' do
      stub_request(:get, attachments_url).with(query: hash_including({}))
                                         .to_return(status: 429, body: '', headers: { 'Retry-After' => '3' })
      expect_reschedule_after(3, /rate limit hit/) { run_action(list_input) }
    end

    it 'reschedules rather than failing when Graph answers 503' do
      stub_request(:get, attachments_url).with(query: hash_including({})).to_return(status: 503, body: '')
      expect_reschedule_after(60, /not available/) { run_action(list_input) }
    end
  end

  describe 'Download Attachment' do
    let(:action_template_id) { 'a68d267e-7781-4758-b314-7ad76d97ad90' }

    # The one assertion no stubbed response could ever make for us. contentBytes lives on the file attachment
    # type and not on the type every attachment shares, so the plain spelling is HTTP 400 on every read.
    it 'asks for the bytes through the file attachment type, the only spelling Graph accepts' do
      stub_summary(file_row)
      stub_content(content_row)
      run_action(download_input)
      expect(a_request(:get, attachment_url).with(query: { '$select' => content_select })).to have_been_made
    end

    # The first read exists to carry the size and the kind, which the content read does not return, so it asks
    # for the five names and no bytes. An exact query: a subset match would pass with the bytes appended.
    it 'reads the size and the kind first, in a request that carries no bytes' do
      stub_summary(file_row)
      stub_content(content_row)
      run_action(download_input)
      expect(a_request(:get, attachment_url).with(query: { '$select' => summary_select })).to have_been_made
    end

    it 'hands the runbook the base64 text Graph sent, character for character' do
      encoded = Base64.strict_encode64('A' * 60_000)
      stub_summary(file_row(size: 60_180))
      stub_content(content_row(contentBytes: encoded))
      expect(run_action(download_input)[:content_bytes]).to eq(encoded)
    end

    # Measured against the real tenant with a PNG attachment on 28 Sep 2026. run_action writes the whole
    # output with JSON.generate before it returns, in IPaaS::Job::MemoryStore#write, so decoded bytes end
    # the run rather than reach the runbook.
    it 'carries a PNG through, which decoding to raw bytes could not' do
      png = "\x89PNG\r\n\x1A\n".b
      stub_summary(file_row(name: 'set.png', contentType: 'image/png'))
      stub_content(content_row(name: 'set.png', contentBytes: Base64.strict_encode64(png)))
      expect(run_action(download_input)[:content_bytes]).to eq(Base64.strict_encode64(png))
    end

    # The name and the media type come from the content read, which is why the two rows disagree here.
    it 'names the file and its media type from the read that carried the bytes' do
      stub_summary(file_row)
      stub_content(content_row(name: 'report.pdf', contentType: 'application/pdf'))
      output = run_action(download_input)
      expect(output[:name]).to eq('report.pdf')
      expect(output[:content_type]).to eq('application/pdf')
    end

    # Observed against the real tenant: the item attachment sits in the list with a name and a size, so a
    # runbook can reach this step with one, and the only thing that tells it apart is the type.
    it 'refuses a message attached to a message and never asks for its bytes' do
      stub_summary(item_row)
      expect { run_action(download_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Attachment 'attached message' is #microsoft.graph.itemAttachment and carries no file.")
      expect(a_request(:get, attachment_url).with(query: { '$select' => content_select })).not_to have_been_made
    end

    it 'refuses a link to a cloud file, which carries no bytes either' do
      stub_summary(file_row('@odata.type': MicrosoftOutlookConnector::REFERENCE_ATTACHMENT_TYPE,
                            name: 'design.fig'))
      expect { run_action(download_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Attachment 'design.fig' is #microsoft.graph.referenceAttachment and carries no file.")
    end

    it 'refuses a file above the size this step reads in one go, before any bytes move' do
      stub_summary(file_row(name: 'big.bin', size: MicrosoftOutlookConnector::MAX_ATTACHMENT_BYTES + 1))
      expect { run_action(download_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Attachment 'big.bin' is 3145729 bytes, and this step reads at most 3145728 bytes " \
                        'in one go.')
      expect(a_request(:get, attachment_url).with(query: { '$select' => content_select })).not_to have_been_made
    end

    it 'reads a file that is exactly as big as the step allows' do
      stub_summary(file_row(size: MicrosoftOutlookConnector::MAX_ATTACHMENT_BYTES))
      stub_content(content_row)
      expect(run_action(download_input)[:content_bytes]).to eq('aGVsbG8=')
    end

    # The assertion: the size guard compares against the number Graph reports, and a missing size reads as nil
    # whose to_i is zero, which would wave every file through however big it is.
    it 'raises when the first read reports a size that is not a whole number of bytes' do
      stub_summary(file_row.except(:size))
      stub_content(content_row)
      expect { run_action(download_input) }.to raise_error(IPaaS::Error, /which is not a whole number of bytes/)
    end

    # The assertion: Graph returns @odata.type on every attachment under every select and a select may not ask
    # for it, so a blank one cannot happen. It would leave a message and a link looking like a file.
    it 'raises when the first read carries no attachment type' do
      stub_summary(file_row.except(:'@odata.type'))
      stub_content(content_row)
      expect { run_action(download_input) }.to raise_error(IPaaS::Error, /with no '@odata.type'/)
    end

    # Observed against the real tenant: an attachment id Graph cannot read is HTTP 404, where a message id it
    # cannot read is HTTP 400, so the two inputs fail with different statuses.
    it 'fails the job with Microsoft own words when the attachment does not exist' do
      stub_summary({ error: { code: 'ErrorItemNotFound',
                              message: 'The specified object was not found in the store.', } }, status: 404)
      expect { run_action(download_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 404 ErrorItemNotFound: The specified object was not ' \
                        'found in the store.')
    end

    it 'names the mailbox when Microsoft refuses the application on the read that carries the bytes' do
      stub_summary(file_row)
      stub_content({ error: { code: 'ErrorAccessDenied', message: 'Access is denied.' } }, status: 403)
      expect { run_action(download_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Microsoft Graph returned HTTP 403 ErrorAccessDenied while reading mailbox '#{mailbox}': " \
                        'Access is denied.')
    end

    it 'reschedules when Graph asks for a pause on the read that carries the size' do
      stub_request(:get, attachment_url).with(query: { '$select' => summary_select })
                                        .to_return(status: 429, body: '', headers: { 'Retry-After' => '3' })
      expect_reschedule_after(3, /rate limit hit/) { run_action(download_input) }
    end

    # This step calls Graph twice for one attachment, so it is the second read that doubles the pressure on a
    # throttled mailbox. A run block that backed off only on the first read would fail the job here.
    it 'reschedules when Graph is unavailable on the read that carries the bytes' do
      stub_summary(file_row)
      stub_request(:get, attachment_url).with(query: { '$select' => content_select })
                                        .to_return(status: 503, body: '')
      expect_reschedule_after(60, /not available/) { run_action(download_input) }
    end

    # The assertion: the content read asks for the bytes through the file attachment type and only a file
    # attachment reaches it, so a 200 without them cannot happen. It would hand the runbook an empty file.
    it 'raises when the content read answers without the bytes' do
      stub_summary(file_row)
      stub_content(content_row.except(:contentBytes))
      expect { run_action(download_input) }.to raise_error(IPaaS::Error, /with no contentBytes/)
    end
  end
end
