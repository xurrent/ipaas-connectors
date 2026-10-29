require 'spec_helper'

describe 'Microsoft Outlook Create Calendar Event Action', :action, :microsoft_outlook do
  let(:action_template_id) { '34857f77-8991-4c62-b02b-dd22c475b24f' }
  let(:events_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/events" }
  let(:calendar_id) do
    'AAMkAGQzOGVlNTJkLWMzMzYtNDgzNi04ZWQyLWZhMDc5YmJmNzY4NQBGAAAAAAEGAABIzshfbRZ8SaULyxi-fjtsAAAfXrRjAAA='
  end
  let(:calendar_events_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/calendars/#{calendar_id}/events" }

  let(:mapped_input) do
    {
      mailbox: nil,
      calendar_id: nil,
      subject: 'Zug, Hans Muster, 08:00-10:00',
      start_time: '2026-12-01 08:00',
      end_time: '2026-12-01 10:00',
      time_zone: 'W. Europe Standard Time',
      body: nil,
      body_type: nil,
      location: nil,
      attendees: nil,
      reminder_minutes_before_start: nil,
      transaction_id: nil,
    }
  end

  # Shaped like the answer the live tenant gave on 2026-10-14, cut to the fields the action reads.
  let(:created_event) do
    {
      id: 'AAMkAGQzOGVlNTJkLWMzMzYtNDgzNi04ZWQyLWZhMDc5YmJmNzY4NQBGAAAAAACPEjqyAAA=',
      webLink: 'https://outlook.office365.com/owa/?itemid=AAMkAGQz&exvsurl=1&path=/calendar/item',
      iCalUId: '040000008200E00074C5B7101A82E00800000000AFDF5C85B65BDD01',
      subject: 'Zug, Hans Muster, 08:00-10:00',
      start: { dateTime: '2026-12-01T08:00:00.0000000', timeZone: 'W. Europe Standard Time' },
      end: { dateTime: '2026-12-01T10:00:00.0000000', timeZone: 'W. Europe Standard Time' },
      organizer: { emailAddress: { name: 'Adele Vance', address: mailbox } },
      attendees: [{ type: 'required', status: { response: 'none', time: '0001-01-01T00:00:00Z' },
                    emailAddress: { name: 'Tech One', address: 'tech@contoso.com' }, }],
      location: { displayName: 'Baarerstrasse 1, 6300 Zug', address: { street: 'Baarerstrasse 1' } },
      isReminderOn: true,
      reminderMinutesBeforeStart: 30,
      createdDateTime: '2026-10-14T08:32:17.0568515Z',
    }
  end

  def input(overrides = {})
    mapped_input.merge(overrides)
  end

  def stub_create(url: events_url, status: 201, body: created_event.to_json, headers: {})
    stub_request(:post, url)
      .to_return(status: status, body: body, headers: headers.merge('Content-Type' => 'application/json'))
  end

  def stub_error(status, code, message, url: events_url, headers: {})
    stub_create(url: url, status: status, body: { error: { code: code, message: message } }.to_json, headers: headers)
  end

  describe 'the event it sends' do
    it 'posts every field the step fills in the shape Microsoft expects' do
      stub_create
      run_action(input(
                   body: "Bemerkung\n\nhttps://wwz.example/tasks/1",
                   location: { display_name: 'Baarerstrasse 1, 6300 Zug', street: 'Baarerstrasse 1',
                               postal_code: '6300', city: 'Zug', },
                   attendees: ['tech@contoso.com'],
                   reminder_minutes_before_start: 30,
                   transaction_id: 'delivery-7f3c',
                 ))
      expect(a_request(:post, events_url).with(body: {
        subject: 'Zug, Hans Muster, 08:00-10:00',
        body: { contentType: 'text', content: "Bemerkung\n\nhttps://wwz.example/tasks/1" },
        start: { dateTime: '2026-12-01T08:00:00', timeZone: 'W. Europe Standard Time' },
        end: { dateTime: '2026-12-01T10:00:00', timeZone: 'W. Europe Standard Time' },
        location: { displayName: 'Baarerstrasse 1, 6300 Zug',
                    address: { street: 'Baarerstrasse 1', postalCode: '6300', city: 'Zug' }, },
        attendees: [{ emailAddress: { address: 'tech@contoso.com' }, type: 'required' }],
        isReminderOn: true,
        reminderMinutesBeforeStart: 30,
        transactionId: 'delivery-7f3c',
      })).to have_been_made
    end

    it 'sends only subject, start and end when the step fills nothing else, so Microsoft picks the reminder' do
      stub_create
      run_action(input)
      expect(a_request(:post, events_url).with(body: {
        subject: 'Zug, Hans Muster, 08:00-10:00',
        start: { dateTime: '2026-12-01T08:00:00', timeZone: 'W. Europe Standard Time' },
        end: { dateTime: '2026-12-01T10:00:00', timeZone: 'W. Europe Standard Time' },
      })).to have_been_made
    end

    it 'sends only the location fields that hold a value' do
      stub_create
      run_action(input(location: { display_name: '', street: 'Baarerstrasse 1', postal_code: nil, city: 'Zug' }))
      expect(a_request(:post, events_url)
        .with(body: hash_including('location' => { 'address' => { 'street' => 'Baarerstrasse 1', 'city' => 'Zug' } })))
        .to have_been_made
    end

    it 'sends the body type the step names' do
      stub_create
      run_action(input(body: '<b>Hi</b>', body_type: 'html'))
      expect(a_request(:post, events_url)
        .with(body: hash_including('body' => { 'contentType' => 'html', 'content' => '<b>Hi</b>' })))
        .to have_been_made
    end

    it 'turns the reminder on at the start when the step asks for zero minutes' do
      stub_create
      run_action(input(reminder_minutes_before_start: 0))
      expect(a_request(:post, events_url)
        .with(body: hash_including('isReminderOn' => true, 'reminderMinutesBeforeStart' => 0)))
        .to have_been_made
    end

    it 'declares the JSON content type of the body' do
      stub_create
      run_action(input)
      expect(a_request(:post, events_url).with(headers: { 'Content-Type' => 'application/json' })).to have_been_made
    end

    it 'posts into the calendar that Calendar ID names' do
      stub_create(url: calendar_events_url)
      run_action(input(calendar_id: "  #{calendar_id}  "))
      expect(a_request(:post, calendar_events_url)).to have_been_made
    end

    it 'posts into a calendar whose id is exactly the longest length' do
      longest = 'A' * MicrosoftOutlookConnector::MAX_GRAPH_ID_LENGTH
      longest_url = "https://graph.microsoft.com/v1.0/users/#{mailbox}/calendars/#{longest}/events"
      stub_create(url: longest_url)
      run_action(input(calendar_id: longest))
      expect(a_request(:post, longest_url)).to have_been_made
    end

    it 'posts into the mailbox the step names' do
      shared_url = 'https://graph.microsoft.com/v1.0/users/support@contoso.com/events'
      stub_create(url: shared_url)
      run_action(input(mailbox: 'support@contoso.com'))
      expect(a_request(:post, shared_url)).to have_been_made
    end

    # Measured on 2026-10-14: Graph stores "2026-12-01 08:00" as 08:00, so a webhook that sends the date and
    # the time apart only has to join them. The pattern also takes a one digit hour and Graph's own fractions.
    it 'writes a start with a space, a one digit hour and no seconds, and an end with fractions, as Graph does' do
      stub_create
      run_action(input(start_time: '2026-12-01 8:05', end_time: '2026-12-01T10:00:30.0000000'))
      expect(a_request(:post, events_url).with(body: hash_including(
        'start' => { 'dateTime' => '2026-12-01T08:05:00', 'timeZone' => 'W. Europe Standard Time' },
        'end' => { 'dateTime' => '2026-12-01T10:00:30', 'timeZone' => 'W. Europe Standard Time' },
      ))).to have_been_made
    end

    # Measured on 2026-10-14: Graph refuses a zone it does not know with HTTP 400, so a mapped value padded with
    # spaces is trimmed before it is sent.
    it 'sends the time zone without the spaces around it, for start and end alike' do
      stub_create
      run_action(input(time_zone: '  Europe/Zurich '))
      expect(a_request(:post, events_url).with(body: hash_including(
        'start' => { 'dateTime' => '2026-12-01T08:00:00', 'timeZone' => 'Europe/Zurich' },
        'end' => { 'dateTime' => '2026-12-01T10:00:00', 'timeZone' => 'Europe/Zurich' },
      ))).to have_been_made
    end

    # Measured on 2026-10-14: Graph accepts an event that ends when it starts, and refuses only an earlier end.
    it 'sends an event whose end equals its start' do
      stub_create
      run_action(input(end_time: '2026-12-01T08:00:00'))
      expect(a_request(:post, events_url)).to have_been_made
    end
  end

  describe 'what it reports back' do
    it 'reports the event Microsoft stored, with the id that Delete Calendar Event takes' do
      stub_create
      expect(run_action(input)).to eq({
        'event_id' => 'AAMkAGQzOGVlNTJkLWMzMzYtNDgzNi04ZWQyLWZhMDc5YmJmNzY4NQBGAAAAAACPEjqyAAA=',
        'web_link' => 'https://outlook.office365.com/owa/?itemid=AAMkAGQz&exvsurl=1&path=/calendar/item',
        'i_cal_uid' => '040000008200E00074C5B7101A82E00800000000AFDF5C85B65BDD01',
        'subject' => 'Zug, Hans Muster, 08:00-10:00',
        'start_time' => { 'date_time' => '2026-12-01T08:00:00.0000000', 'time_zone' => 'W. Europe Standard Time' },
        'end_time' => { 'date_time' => '2026-12-01T10:00:00.0000000', 'time_zone' => 'W. Europe Standard Time' },
        'organizer' => { 'name' => 'Adele Vance', 'address' => mailbox },
        'attendees' => [{ 'address' => 'tech@contoso.com', 'name' => 'Tech One', 'type' => 'required' }],
        'location' => 'Baarerstrasse 1, 6300 Zug',
        'is_reminder_on' => true,
        'reminder_minutes_before_start' => 30,
        'created_date_time' => DateTime.parse('2026-10-14T08:32:17.0568515Z'),
        'mailbox' => mailbox,
      })
    end

    it 'reports no attendees, no location and no reminder when Microsoft stored none' do
      stub_create(body: created_event.except(:attendees, :location).merge(isReminderOn: false).to_json)
      expect(run_action(input)).to include('attendees' => [], 'location' => nil, 'is_reminder_on' => false)
    end

    it 'fails the job when Microsoft creates an event and names no id' do
      stub_create(body: created_event.merge(id: nil).to_json)
      expect { run_action(input) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph created an event without naming its id')
    end

    it 'fails the job when Graph answers a success status that is not the created one' do
      stub_create(status: 200)
      expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /HTTP 200/)
    end
  end

  describe 'when Microsoft refuses the event' do
    it 'names the Transaction ID when Microsoft holds an event with other values under it' do
      stub_error(400, 'ErrorDuplicateTransactionId',
                 'The TransactionId specified in the request has already been used to create a different event.')
      expect { run_action(input(transaction_id: ' delivery-7f3c ')) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Transaction ID 'delivery-7f3c' already created an event in mailbox '#{mailbox}' with " \
                        'other values, so Microsoft refused a second one. Map a Transaction ID that changes from ' \
                        'one booking to the next.')
    end

    it 'names the zone it sent and the two kinds of name Microsoft takes when it does not know the zone' do
      stub_error(400, 'TimeZoneNotSupportedException', "A valid TimeZone value must be specified. 'Bern'.")
      expect { run_action(input(time_zone: ' Bern ')) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Microsoft does not know the time zone 'Bern'. Use a Windows name such as W. Europe " \
                        'Standard Time or an IANA name such as Europe/Zurich.')
    end

    # Measured on 2026-10-14: 02:30 to 03:00 on the night the clocks go forward passes the check on the wall
    # times, then Graph moves the start to 03:30 and answers this code with a message that names no field.
    it 'names the times and the clock change when Microsoft refuses a property of the event' do
      stub_error(400, 'ErrorPropertyValidationFailure', 'At least one property failed validation.')
      expect { run_action(input(start_time: '2027-03-28 02:30', end_time: '2027-03-28 03:00')) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft refused the event from 2027-03-28T02:30:00 to 2027-03-28T03:00:00 in W. Europe ' \
                        'Standard Time. A Start in the hour the clocks skip forward is moved later, and the event is ' \
                        'refused when that puts Start after End.')
    end

    it 'names the calendar and the mailbox when the mailbox has no such calendar' do
      stub_error(404, 'ErrorItemNotFound', 'The specified object was not found in the store.', url: calendar_events_url)
      expect { run_action(input(calendar_id: calendar_id)) }
        .to raise_error(IPaaS::Job::FailJob, "Mailbox '#{mailbox}' has no calendar '#{calendar_id}'. Map the id of " \
                                             'a calendar in this mailbox, or leave Calendar ID empty to use its ' \
                                             'default calendar.')
    end

    it "reports Microsoft's own words when the default calendar answers item not found" do
      stub_error(404, 'ErrorItemNotFound', 'The specified object was not found in the store.')
      expect { run_action(input) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned HTTP 404 ErrorItemNotFound: The specified ' \
                                             'object was not found in the store.')
    end

    it "reports Microsoft's own words when the 404 is about the mailbox" do
      stub_error(404, 'ErrorInvalidUser', "The requested user '#{mailbox}' is invalid.", url: calendar_events_url)
      expect { run_action(input(calendar_id: calendar_id)) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned HTTP 404 ErrorInvalidUser: The requested ' \
                                             "user '#{mailbox}' is invalid.")
    end

    it 'names the mailbox and the permission to check when Microsoft refuses the mailbox' do
      stub_error(403, 'ErrorAccessDenied', 'Access is denied. Check credentials and try again.')
      expect { run_action(input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 403 ErrorAccessDenied: Access is denied. Check credentials ' \
                        "and try again. Microsoft refused mailbox '#{mailbox}'. Check that the app holds the " \
                        'Calendars.ReadWrite application permission for this mailbox.')
    end

    # Measured on 2026-10-14: a repeated post with the same transactionId and body returns the event the first
    # post created, so running the step again after a server error books nothing twice.
    it 'pauses the step on a server error when a Transaction ID makes the rerun safe' do
      stub_error(503, 'ServiceUnavailable', 'Server is busy.', headers: { 'Retry-After' => '6' })
      expect_reschedule_after(6) { run_action(input(transaction_id: 'delivery-7f3c')) }
    end

    it 'fails the job on a server error with no Transaction ID, and says the event may exist' do
      stub_error(503, 'ServiceUnavailable', 'Server is busy.')
      expect { run_action(input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 503 ServiceUnavailable: Server is busy. Microsoft may have ' \
                        'created the event before it failed, so look in the calendar before you run the step again, ' \
                        'or map a Transaction ID.')
    end

    it 'treats a Transaction ID of spaces as none, so a server error fails the job' do
      stub_error(503, 'ServiceUnavailable', 'Server is busy.')
      expect { run_action(input(transaction_id: '   ')) }
        .to raise_error(IPaaS::Job::FailJob, /HTTP 503 ServiceUnavailable: Server is busy. Microsoft may have/)
    end

    it 'pauses the step when Graph asks for a pause, because it refused the post outright' do
      stub_error(429, 'ApplicationThrottled', 'Application is over its MailboxConcurrency limit.',
                 headers: { 'Retry-After' => '6' })
      expect_reschedule_after(6) { run_action(input) }
    end
  end

  describe 'what it refuses before it calls Microsoft' do
    before { stub_request(:post, /events/) }

    it 'refuses a start with an offset, because Microsoft would store it in UTC and drop the zone' do
      expect { run_action(input(start_time: '2026-12-01T08:00:00+01:00')) }
        .to raise_error(IPaaS::Job::FailJob, "Start '2026-12-01T08:00:00+01:00' is not a local date and time " \
                                             'such as 2026-12-01 08:00. Convert a time with an offset or Z first, ' \
                                             "such as <value>.in_time_zone('Europe/Zurich').strftime('%Y-%m-%d " \
                                             "%H:%M'), and name the same zone in Time zone. The conversion needs a " \
                                             'colon in the time: it reads 08.00 as midnight.')
      expect(a_request(:post, /events/)).not_to have_been_made
    end

    it 'refuses an end that names a day the calendar does not have' do
      expect { run_action(input(end_time: '2026-02-30 10:00')) }
        .to raise_error(IPaaS::Job::FailJob, "End '2026-02-30 10:00' names a day the calendar does not have.")
      expect(a_request(:post, /events/)).not_to have_been_made
    end

    # Measured on 2026-10-14: Graph answers an earlier end with "At least one property failed validation."
    # and names no field, so the step says which one is wrong.
    it 'refuses an end earlier than the start' do
      expect { run_action(input(end_time: '2026-12-01 07:00')) }
        .to raise_error(IPaaS::Job::FailJob, "End '2026-12-01 07:00' is earlier than Start '2026-12-01 08:00'. An " \
                                             'event that runs past midnight needs the date of the next day in End.')
      expect(a_request(:post, /events/)).not_to have_been_made
    end

    it 'refuses a calendar id holding characters Graph never puts in one' do
      expect { run_action(input(calendar_id: 'Team Calendar')) }
        .to raise_error(IPaaS::Job::FailJob, "Calendar ID 'Team Calendar' is not a Microsoft Graph calendar id. Map " \
                                             'the id of a calendar in the mailbox, or leave Calendar ID empty to use ' \
                                             'its default calendar.')
      expect(a_request(:post, /events/)).not_to have_been_made
    end

    it 'refuses a calendar id longer than any Microsoft Graph id' do
      long_id = 'A' * (MicrosoftOutlookConnector::MAX_GRAPH_ID_LENGTH + 1)
      expect { run_action(input(calendar_id: long_id)) }
        .to raise_error(IPaaS::Job::FailJob, /\ACalendar ID '#{long_id}' is not a Microsoft Graph calendar id/)
      expect(a_request(:post, /events/)).not_to have_been_made
    end

    # Measured on 2026-10-14: Graph accepts "not-an-email" as an attendee and creates the event.
    it 'refuses an attendee that is not an email address' do
      expect { run_action(input(attendees: ['not-an-email'])) }
        .to raise_error(IPaaS::Job::FailJob, "Attendees holds 'not-an-email', which is not an email address. Write " \
                                             'the address on its own, without a display name around it.')
      expect(a_request(:post, /events/)).not_to have_been_made
    end

    context 'when the connection carries no default mailbox' do
      let(:default_mailbox) { nil }

      it 'refuses to create when no mailbox is set on the step or on the connection' do
        expect { run_action(input) }
          .to raise_error(IPaaS::Job::FailJob, 'No mailbox. Set Mailbox on this step, or Default mailbox on the ' \
                                               'connection.')
        expect(a_request(:post, /events/)).not_to have_been_made
      end
    end
  end
end
