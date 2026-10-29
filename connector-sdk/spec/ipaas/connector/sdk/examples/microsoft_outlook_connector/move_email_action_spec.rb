require 'spec_helper'

describe 'Microsoft Outlook Move Email Action', :action, :microsoft_outlook do
  let(:action_template_id) { '08d4e767-e3f3-4783-a1f7-2bbc200fa24c' }
  let(:batch_url) { 'https://graph.microsoft.com/v1.0/$batch' }

  # A real Graph message id is 152 characters of base64url ending in the padding sign. A short stand-in such
  # as 'AAMkAGQz=' passes MESSAGE_ID_PATTERN without ever carrying the shape a mailbox hands out.
  def message_id(tag)
    "#{"AAMkAGQzNmZhNTIyLTk5ZDUtNGJlZi1iZTBkLTRjMzM4Zjg5#{tag}".ljust(151, 'AQAAAAAA')}="
  end

  def new_message_id(tag)
    "#{"AAMkAGQzNmZhNTIyLTk5ZDUtNGJlZi1iZTBkLTRjMzM4Zjg5#{tag}".ljust(151, 'BQAfXqjN')}="
  end

  def move_input(ids, overrides = {})
    { message_ids: ids, destination_folder: 'archive' }.merge(overrides)
  end

  def inner_url(message_id, for_mailbox: mailbox)
    "/users/#{for_mailbox}/messages/#{message_id}/move"
  end

  # Microsoft answers a moved message with 201 and the whole moved resource, whose id is the new id.
  def moved_row(request_id, new_id)
    { id: request_id.to_s, status: 201, headers: { 'Content-Type' => 'application/json' },
      body: { id: new_id, subject: 'Quarterly report' }, }
  end

  def failed_row(request_id, status: 404, code: 'ErrorItemNotFound',
                 message: 'The specified object was not found in the store.')
    { id: request_id.to_s, status: status, body: { error: { code: code, message: message } } }
  end

  # WebMock hands the matcher block the request on its way out, so the batch the connector built is kept here
  # and an example can assert on what left rather than on the answer it stubbed.
  def stub_batch(rows, status: 200)
    stub_request(:post, batch_url)
      .with { |request| @batch_sent = JSON.parse(request.body) }
      .to_return(status: status, body: { responses: rows }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def stub_batch_body(body, status: 200)
    stub_request(:post, batch_url)
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def requests_sent
    @batch_sent.fetch('requests')
  end

  describe 'the batch it sends' do
    it 'posts every move as one batch to the Graph batch endpoint' do
      stub_batch([moved_row(0, new_message_id('01')), moved_row(1, new_message_id('02'))])
      run_action(move_input([message_id('01'), message_id('02')]))
      expect(a_request(:post, batch_url)).to have_been_made.once
      expect(requests_sent.length).to eq(2)
    end

    # A request carried inside a batch names its url from the version root. Building that url the way every
    # other call is built repeats the version, and Microsoft answers 400 on every row inside an outer 200,
    # which reads as a job that worked and moved nothing.
    it 'addresses a message from the version root, so the url inside the batch carries no API version' do
      stub_batch([moved_row(0, new_message_id('01'))])
      run_action(move_input([message_id('01')]))
      expect(requests_sent.map { |request| request['url'] }).to eq([inner_url(message_id('01'))])
    end

    # The outer header and the inner ones are set in two different places, so each needs its own example.
    it 'sends the batch itself as JSON' do
      stub_batch([moved_row(0, new_message_id('01'))])
      run_action(move_input([message_id('01')]))
      expect(a_request(:post, batch_url).with(headers: { 'Content-Type' => 'application/json' }))
        .to have_been_made
    end

    # Without this header Microsoft refuses the WHOLE batch with an outer 400, so no message moves at all.
    it 'puts the JSON content type on every request inside the batch' do
      stub_batch([moved_row(0, new_message_id('01')), moved_row(1, new_message_id('02'))])
      run_action(move_input([message_id('01'), message_id('02')]))
      expect(requests_sent.map { |request| request['headers'] })
        .to eq([{ 'Content-Type' => 'application/json' }, { 'Content-Type' => 'application/json' }])
    end

    it 'names the destination folder the step asked for in every request inside the batch' do
      stub_batch([moved_row(0, new_message_id('01')), moved_row(1, new_message_id('02'))])
      run_action(move_input([message_id('01'), message_id('02')], { destination_folder: 'deleteditems' }))
      expect(requests_sent.map { |request| request['body'] })
        .to eq([{ 'destinationId' => 'deleteditems' }, { 'destinationId' => 'deleteditems' }])
    end

    it 'sends one POST per message id and numbers them from zero' do
      stub_batch([moved_row(0, new_message_id('01')), moved_row(1, new_message_id('02'))])
      run_action(move_input([message_id('01'), message_id('02')]))
      expect(requests_sent.map { |request| [request['id'], request['method']] })
        .to eq([%w[0 POST], %w[1 POST]])
    end

    # Microsoft runs the requests inside one batch in an order of its own, so the same id sent twice races
    # itself: one copy moves and the other answers 404 for a message that did move.
    it 'sends a repeated message id once' do
      stub_batch([moved_row(0, new_message_id('01'))])
      run_action(move_input([message_id('01'), message_id('01')]))
      expect(requests_sent.map { |request| request['url'] }).to eq([inner_url(message_id('01'))])
    end

    it 'reads the mailbox the step names rather than the one on the connection' do
      stub_batch([moved_row(0, new_message_id('01'))])
      run_action(move_input([message_id('01')], { mailbox: 'shared.support@contoso.com' }))
      expect(requests_sent.map { |request| request['url'] })
        .to eq([inner_url(message_id('01'), for_mailbox: 'shared.support@contoso.com')])
    end
  end

  describe 'the rows it answers with' do
    it 'answers one row per message id carrying the new id Microsoft gave it' do
      stub_batch([moved_row(0, new_message_id('01'))])
      expect(run_action(move_input([message_id('01')]))[:results]).to eq([{
        'message_id' => message_id('01'),
        'new_message_id' => new_message_id('01'),
        'moved' => true,
        'error' => nil,
      }])
    end

    # Microsoft answers the rows in an order of its own. Reading them by position blames the wrong message:
    # here the row that failed was sent last and answered first.
    it 'takes each row from the request id it was sent with, not from the position Microsoft answered in' do
      stub_batch([failed_row(2), moved_row(0, new_message_id('01')), moved_row(1, new_message_id('02'))])
      results = run_action(move_input([message_id('01'), message_id('02'), message_id('03')]))[:results]
      expect(results.map { |row| [row['message_id'], row['moved']] })
        .to eq([[message_id('01'), true], [message_id('02'), true], [message_id('03'), false]])
    end

    # A bad id is a failed row, never a failed job: the action promises one row per id that went in.
    it 'answers a failed row beside a moved row and does not fail the job' do
      stub_batch([moved_row(0, new_message_id('01')), failed_row(1)])
      results = run_action(move_input([message_id('01'), message_id('02')]))[:results]
      expect(results).to eq([
        { 'message_id' => message_id('01'), 'new_message_id' => new_message_id('01'),
          'moved' => true, 'error' => nil, },
        { 'message_id' => message_id('02'), 'new_message_id' => nil, 'moved' => false,
          'error' => 'Microsoft Graph returned HTTP 404 ErrorItemNotFound: ' \
                     'The specified object was not found in the store.', },
      ])
    end

    # A destination that passes the folder guard but does not exist fails every row with this one text, and
    # a malformed message id produces the same words, so the row carries Microsoft's own message unchanged.
    it 'carries Microsoft own words on a row the destination folder broke' do
      stub_batch([failed_row(0, status: 400, code: 'ErrorInvalidIdMalformed', message: 'Id is malformed.')])
      expect(run_action(move_input([message_id('01')]))[:results].first['error'])
        .to eq('Microsoft Graph returned HTTP 400 ErrorInvalidIdMalformed: Id is malformed.')
    end

    it 'says so when Microsoft answers the batch without a row for a message that was sent' do
      stub_batch([moved_row(0, new_message_id('01'))])
      results = run_action(move_input([message_id('01'), message_id('02')]))[:results]
      expect(results.last)
        .to eq({ 'message_id' => message_id('02'), 'new_message_id' => nil, 'moved' => false,
                 'error' => 'Microsoft Graph returned no answer for this request.', })
    end
  end

  describe 'what it refuses before it calls Microsoft' do
    it 'refuses more message ids than one batch holds' do
      ids = (1..21).map { |number| message_id(number.to_s.rjust(2, '0')) }
      expect { run_action(move_input(ids)) }
        .to raise_error(IPaaS::Job::FailJob, /21 message ids were passed.*at most 20 messages/m)
      expect(a_request(:post, batch_url)).not_to have_been_made
    end

    it 'refuses a message id copied from a browser address bar' do
      expect { run_action(move_input(['AAMkAGQz%2FAAA%3D'])) }
        .to raise_error(IPaaS::Job::FailJob, /not a Microsoft Graph message id/)
      expect(a_request(:post, batch_url)).not_to have_been_made
    end

    it 'refuses a list of message ids whose entries are all blank' do
      expect { run_action(move_input(['', '  '])) }
        .to raise_error(IPaaS::Job::FailJob, /No message ids to move/)
      expect(a_request(:post, batch_url)).not_to have_been_made
    end

    it 'refuses a destination folder that is a display name' do
      expect { run_action(move_input([message_id('01')], { destination_folder: 'Sent Items' })) }
        .to raise_error(IPaaS::Job::FailJob, /A display name such as Sent Items is not accepted/)
      expect(a_request(:post, batch_url)).not_to have_been_made
    end
  end

  describe 'what it says when Microsoft is the one that is broken' do
    # Microsoft refuses a batch it will not run at all with an outer error, and then nothing moved, so this
    # one is a failed job rather than a set of failed rows.
    it 'fails the job with Microsoft own words when the whole batch is refused' do
      stub_batch_body({ error: { code: 'BadRequest', message: 'Number of requests inside batch exceed the limit.' } }
                        .to_json, status: 400)
      expect { run_action(move_input([message_id('01')])) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 400 BadRequest: ' \
                        'Number of requests inside batch exceed the limit.')
    end

    it 'reschedules rather than failing when Graph asks for a pause' do
      stub_request(:post, batch_url).to_return(status: 429, body: '', headers: { 'Retry-After' => '30' })
      expect_reschedule_after(30) { run_action(move_input([message_id('01')])) }
    end

    it 'reschedules rather than failing when Graph answers 503' do
      stub_request(:post, batch_url).to_return(status: 503, body: '')
      expect_reschedule_after(60) { run_action(move_input([message_id('01')])) }
    end

    # The assertion: a batch answer names its rows in a list, so anything else is a state that cannot happen
    # while Graph keeps its contract.
    it 'raises when the batch answer holds no list of rows' do
      stub_batch_body({ responses: { id: '0', status: 201 } }.to_json)
      expect { run_action(move_input([message_id('01')])) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph returned a batch answer whose responses are not a list')
    end

    it 'raises when the batch answer holds a row that is not an object' do
      stub_batch_body({ responses: [7] }.to_json)
      expect { run_action(move_input([message_id('01')])) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph returned a batch answer with a response that is not an object')
    end

    # The assertion: a row can only answer a request this batch sent, and the ids are the connector's own.
    it 'raises when Microsoft answers a request the batch never sent' do
      stub_batch([moved_row(7, new_message_id('01'))])
      expect { run_action(move_input([message_id('01')])) }
        .to raise_error(IPaaS::Error, "Microsoft Graph answered request '7', which this batch never sent")
    end

    # The assertion: the new id is what a later step reads the message with, so a move Microsoft reports as
    # done without naming one would hand the runbook an empty id and no error.
    it 'raises when Microsoft reports a move without naming the new message id' do
      stub_batch([{ id: '0', status: 201, body: { subject: 'Quarterly report' } }])
      expect { run_action(move_input([message_id('01')])) }
        .to raise_error(IPaaS::Error, /moved message '#{message_id('01')}' without naming its new id/)
    end
  end

  describe 'Archive Email' do
    let(:action_template_id) { 'adcaf794-39e7-4185-9432-4fb7de67fbf6' }

    def archive_input(ids, overrides = {})
      { message_ids: ids }.merge(overrides)
    end

    it 'sends every message to the archive folder and asks the step for no folder' do
      stub_batch([moved_row(0, new_message_id('01')), moved_row(1, new_message_id('02'))])
      run_action(archive_input([message_id('01'), message_id('02')]))
      expect(requests_sent.map { |request| request['body'] })
        .to eq([{ 'destinationId' => 'archive' }, { 'destinationId' => 'archive' }])
    end

    it 'addresses an archived message from the version root, so its url carries no API version' do
      stub_batch([moved_row(0, new_message_id('01'))])
      run_action(archive_input([message_id('01')]))
      expect(requests_sent.map { |request| request['url'] }).to eq([inner_url(message_id('01'))])
    end

    it 'answers one row per message id carrying the new id the archive folder gave it' do
      stub_batch([moved_row(0, new_message_id('01'))])
      expect(run_action(archive_input([message_id('01')]))[:results]).to eq([{
        'message_id' => message_id('01'),
        'new_message_id' => new_message_id('01'),
        'moved' => true,
        'error' => nil,
      }])
    end

    it 'answers a failed archive row beside a moved one and does not fail the job' do
      stub_batch([moved_row(0, new_message_id('01')), failed_row(1)])
      results = run_action(archive_input([message_id('01'), message_id('02')]))[:results]
      expect(results.map { |row| [row['message_id'], row['moved']] })
        .to eq([[message_id('01'), true], [message_id('02'), false]])
    end

    it 'refuses more message ids to archive than one batch holds' do
      ids = (1..21).map { |number| message_id(number.to_s.rjust(2, '0')) }
      expect { run_action(archive_input(ids)) }
        .to raise_error(IPaaS::Job::FailJob, /21 message ids were passed.*at most 20 messages/m)
      expect(a_request(:post, batch_url)).not_to have_been_made
    end
  end
end
