require 'spec_helper'

describe 'Microsoft Outlook Search Emails Action', :action, :microsoft_outlook do
  let(:action_template_id) { '74a57eb7-eb5b-4c95-8ac1-7000eb7853b1' }
  let(:mailbox_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/messages" }
  let(:drafts_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/mailFolders/drafts/messages" }
  # Graph answers a request for .../mailFolders/drafts/messages with the folder written as an OData key.
  let(:drafts_next_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/mailFolders('drafts')/messages" }
  let(:summary_fields) { MicrosoftOutlookConnector::MESSAGE_SELECT.join(',') }

  def recipient(address)
    { emailAddress: { name: 'Adele Vance', address: address } }
  end

  # Every field is named, because an unmapped field is filled from the schema's generated example
  # (spec/support/field_mapping_helper.rb:6) and a criterion nobody asked for would reach Graph.
  def input(**overrides)
    { mailbox: nil, folder: nil, from_address: nil, to_address: nil, subject_contains: nil,
      received_after: nil, received_before: nil, has_attachments: nil, is_unread: nil,
      search_text: nil, page_size: nil, result_limit: nil, }.merge(overrides)
  end

  # A stub registered on a bare URL matches only a request that carries no query, so every page stub takes
  # any query and the examples assert the query separately.
  def stub_page(body, url: mailbox_url, status: 200)
    stub_request(:get, url).with(query: hash_including({}))
                           .to_return(status: status, body: body.to_json,
                                      headers: { 'Content-Type' => 'application/json' })
  end

  # The two legs of a search leave for the same URL, so each leg is stubbed by the parameter that tells
  # them apart rather than by the address.
  def stub_leg(parameter, body, url: mailbox_url)
    stub_request(:get, url).with(query: hash_including(parameter))
                           .to_return(status: 200, body: body.to_json,
                                      headers: { 'Content-Type' => 'application/json' })
  end

  describe 'what one request carries' do
    # An exact query, not a subset: the point is that a step which filled nothing asks Graph to narrow
    # nothing, so a phantom $filter or $search built from an unmapped field would fail here.
    it 'asks for the summary fields and nothing else when the step filled no criterion' do
      stub_page({ value: [] })
      run_action(input)
      expect(a_request(:get, mailbox_url)
        .with(query: { '$select' => summary_fields, '$top' => '25' })).to have_been_made
    end

    it 'searches one folder when the step names one' do
      stub_page({ value: [] }, url: drafts_url)
      run_action(input(folder: 'drafts'))
      expect(a_request(:get, drafts_url).with(query: hash_including({}))).to have_been_made
    end

    it 'writes one clause per criterion Graph can filter on' do
      stub_page({ value: [] })
      run_action(input(from_address: 'postmaster@contoso.com', subject_contains: 'Testing', is_unread: true))
      expect(a_request(:get, mailbox_url)
        .with(query: hash_including('$filter' => "from/emailAddress/address eq 'postmaster@contoso.com' and " \
                                                 "contains(subject,'Testing') and isRead eq false")))
        .to have_been_made
    end

    # The two moments arrive as DateTime, because the mapping coerces a :date_time field before the run
    # block reads it. What Graph compares receivedDateTime against is the UTC literal.
    it 'writes the two moments as the UTC literals Graph compares against' do
      stub_page({ value: [] })
      run_action(input(received_after: '2026-01-02T03:04:05+02:00', received_before: '2026-02-01T00:00:00Z',
                       has_attachments: true))
      expect(a_request(:get, mailbox_url)
        .with(query: hash_including('$filter' => 'receivedDateTime ge 2026-01-02T01:04:05Z and ' \
                                                 'receivedDateTime le 2026-02-01T00:00:00Z and ' \
                                                 'hasAttachments eq true'))).to have_been_made
    end

    it 'reads the page size the step supplied' do
      stub_page({ value: [] })
      run_action(input(page_size: 5))
      expect(a_request(:get, mailbox_url).with(query: hash_including('$top' => '5'))).to have_been_made
    end

    it 'maps a message onto the output fields' do
      stub_page({ value: [graph_message] })
      expect(run_action(input)[:messages]).to eq([{
        'message_id' => 'AAMkAGQz=',
        'subject' => 'Undeliverable: Testing from within iPaaS',
        'from' => { 'name' => 'Microsoft Outlook', 'address' => 'postmaster@contoso.com' },
        'received_date_time' => '2026-09-24T09:27:49Z',
        'has_attachments' => false,
        'is_read' => false,
        'importance' => 'normal',
        'body_preview' => 'Your message could not be delivered',
      }])
    end
  end

  describe 'the free text and the filter, which Graph refuses to carry together' do
    # Graph answers HTTP 400 SearchWithFilter when $search and $filter travel in one request, so a step
    # that fills both is answered by two requests whose results are intersected.
    it 'sends the text in one request and the filter in another, never both in one' do
      stub_leg({ '$search' => '"invoice"' }, { value: [graph_message] })
      stub_leg({ '$filter' => "from/emailAddress/address eq 'postmaster@contoso.com'" }, { value: [graph_message] })
      run_action(input(search_text: 'invoice', from_address: 'postmaster@contoso.com'))
      expect(a_request(:get, mailbox_url).with(query: hash_including('$search' => '"invoice"'))).to have_been_made.once
      expect(a_request(:get, mailbox_url)
        .with(query: hash_including('$filter' => "from/emailAddress/address eq 'postmaster@contoso.com'")))
        .to have_been_made.once
      expect(a_request(:get, mailbox_url).with(query: hash_including('$search', '$filter'))).not_to have_been_made
    end

    it 'sends the text as a free-text search and no filter when it is the only criterion' do
      stub_page({ value: [graph_message] })
      run_action(input(search_text: 'invoice'))
      expect(a_request(:get, mailbox_url)
        .with(query: { '$select' => summary_fields, '$top' => '25', '$search' => '"invoice"' }))
        .to have_been_made
    end

    # Graph answers HTTP 400 SearchWithOrderBy for $search with $orderby, and HTTP 400 InefficientFilter
    # for contains(subject,...) with $orderby, so neither leg may ask for an order.
    it 'asks for no order on either request' do
      stub_leg({ '$search' => '"invoice"' }, { value: [graph_message] })
      stub_leg({ '$filter' => "contains(subject,'Testing')" }, { value: [graph_message] })
      run_action(input(search_text: 'invoice', subject_contains: 'Testing'))
      expect(a_request(:get, mailbox_url).with(query: hash_including('$select'))).to have_been_made.twice
      expect(a_request(:get, mailbox_url).with(query: hash_including('$orderby'))).not_to have_been_made
    end

    it 'keeps only the messages both answers hold, matched on the message id' do
      stub_leg({ '$search' => '"invoice"' },
               { value: [graph_message(id: 'text-only'), graph_message(id: 'in-both')] })
      stub_leg({ '$filter' => "from/emailAddress/address eq 'postmaster@contoso.com'" },
               { value: [graph_message(id: 'in-both'), graph_message(id: 'sender-only')] })
      output = run_action(input(search_text: 'invoice', from_address: 'postmaster@contoso.com'))
      expect(output[:messages].map { |kept| kept['message_id'] }).to eq(['in-both'])
    end

    it 'answers with nothing when the two answers hold no message in common' do
      stub_leg({ '$search' => '"invoice"' }, { value: [graph_message(id: 'text-only')] })
      stub_leg({ '$filter' => 'isRead eq false' }, { value: [graph_message(id: 'unread-only')] })
      expect(run_action(input(search_text: 'invoice', is_unread: true))[:messages]).to eq([])
    end

    # An empty text leg is the empty set, not the absence of a constraint. Read the other way, a
    # search that matched nothing returns every message the filter matched, and says it is complete.
    it 'answers with nothing when the text leg matched nothing at all' do
      stub_leg({ '$search' => '"invoice"' }, { value: [] })
      stub_leg({ '$filter' => "from/emailAddress/address eq 'billing@vendor.com'" },
               { value: [graph_message(id: 'sender-only'), graph_message(id: 'sender-too')] })
      output = run_action(input(search_text: 'invoice', from_address: 'billing@vendor.com'))
      expect(output[:messages]).to eq([])
      expect(output[:more_results_exist]).to be(false)
    end

    # The intersection is empty whatever the filter would have matched, so the second call is waste.
    it 'does not call Graph a second time when the text leg matched nothing' do
      stub_leg({ '$search' => '"invoice"' }, { value: [] })
      run_action(input(search_text: 'invoice', from_address: 'billing@vendor.com'))
      expect(a_request(:get, mailbox_url).with(query: hash_including('$filter'))).not_to have_been_made
    end
  end

  describe 'the To address, which Graph will not filter on' do
    it 'asks for the recipients as well and keeps only the message addressed to that person' do
      stub_page({ value: [graph_message(id: 'to-adele', toRecipients: [recipient('Adele@Contoso.com')]),
                          graph_message(id: 'to-someone-else', toRecipients: [recipient('other@contoso.com')]),] })
      output = run_action(input(to_address: 'adele@contoso.com'))
      expect(output[:messages].map { |kept| kept['message_id'] }).to eq(['to-adele'])
      expect(a_request(:get, mailbox_url)
        .with(query: hash_including('$select' => "#{summary_fields},toRecipients"))).to have_been_made
    end

    # The assertion: the request asked for toRecipients, so a message without the key means it did not,
    # and every message would be dropped without a word.
    it 'raises when a message comes back with no recipients although the request asked for them' do
      stub_page({ value: [graph_message] })
      expect { run_action(input(to_address: 'adele@contoso.com')) }
        .to raise_error(IPaaS::Error, /carries no toRecipients/)
    end
  end

  describe 'reading more than one page' do
    it 'follows the next page link Graph hands back, with the folder rewritten as an OData key' do
      stub_request(:get, drafts_url).with(query: hash_including({}))
                                    .to_return(status: 200,
                                               body: { value: [graph_message(id: 'first-page')],
                                                       '@odata.nextLink': "#{drafts_next_url}?%24skiptoken=MSZZ", }
                                                 .to_json,
                                               headers: { 'Content-Type' => 'application/json' })
      stub_page({ value: [graph_message(id: 'second-page')] }, url: drafts_next_url)
      output = run_action(input(folder: 'drafts'))
      expect(output[:messages].map { |kept| kept['message_id'] }).to eq(%w[first-page second-page])
      expect(a_request(:get, drafts_next_url).with(query: { '$skiptoken' => 'MSZZ' })).to have_been_made
    end

    # Graph pages a filtered query with $skip, so a message that arrives while the run is part-way through
    # shifts the window and the same message can appear on two pages. The runbook must see it once.
    it 'returns a message once when two pages of the same answer both carry it' do
      stub_request(:get, mailbox_url).with(query: hash_including({}))
                                     .to_return({ status: 200,
                                                  body: { value: [graph_message(id: 'on-both-pages')],
                                                          '@odata.nextLink': "#{mailbox_url}?%24skip=1", }.to_json,
                                                  headers: { 'Content-Type' => 'application/json' }, },
                                                { status: 200,
                                                  body: { value: [graph_message(id: 'on-both-pages')] }.to_json,
                                                  headers: { 'Content-Type' => 'application/json' }, })
      output = run_action(input(result_limit: 10))
      expect(output[:messages].map { |kept| kept['message_id'] }).to eq(['on-both-pages'])
    end

    it 'keeps Result limit messages and reports that more matches exist' do
      stub_page({ value: [graph_message(id: 'kept'), graph_message(id: 'left-behind')] })
      output = run_action(input(result_limit: 1))
      expect(output[:messages].map { |kept| kept['message_id'] }).to eq(['kept'])
      expect(output[:more_results_exist]).to be(true)
    end

    it 'reports that no more matches exist when the answer ended inside Result limit' do
      stub_page({ value: [graph_message] })
      expect(run_action(input(result_limit: 5))[:more_results_exist]).to be(false)
    end

    # Search Emails runs once and reads its pages inside that run, so the cap is what stops a small Page
    # size against a large Result limit from asking Graph for pages all day.
    it 'stops after the request cap and reports that more matches exist' do
      stub_page({ value: [graph_message], '@odata.nextLink': "#{mailbox_url}?%24skiptoken=MSZZ" })
      output = run_action(input(result_limit: 1000))
      expect(a_request(:get, mailbox_url).with(query: hash_including({})))
        .to have_been_made.times(MicrosoftOutlookConnector::MAX_SEARCH_REQUESTS)
      expect(output[:more_results_exist]).to be(true)
    end

    # The two legs share the one cap. Here the text leg spends every request and ends cleanly, so the filter
    # leg is never sent at all. The answer is empty, and saying no more matches exist would be a false report.
    it 'reports that more matches exist when the text leg spent the whole request cap' do
      last_page = { status: 200, body: { value: [graph_message] }.to_json,
                    headers: { 'Content-Type' => 'application/json' }, }
      offered = { status: 200,
                  body: { value: [graph_message],
                          '@odata.nextLink': "#{mailbox_url}?%24search=%22invoice%22&%24skiptoken=MSZZ", }.to_json,
                  headers: { 'Content-Type' => 'application/json' }, }
      pages = Array.new(MicrosoftOutlookConnector::MAX_SEARCH_REQUESTS - 1, offered) << last_page
      stub_request(:get, mailbox_url).with(query: hash_including('$search' => '"invoice"')).to_return(*pages)
      output = run_action(input(search_text: 'invoice', is_unread: true))
      expect(output[:messages]).to eq([])
      expect(output[:more_results_exist]).to be(true)
      expect(a_request(:get, mailbox_url).with(query: hash_including('$search')))
        .to have_been_made.times(MicrosoftOutlookConnector::MAX_SEARCH_REQUESTS)
      expect(a_request(:get, mailbox_url).with(query: hash_including('$filter'))).not_to have_been_made
    end
  end

  describe 'what it refuses and what it reports' do
    it 'refuses search text that holds a double quote before it calls Graph' do
      expect { run_action(input(search_text: 'say "hi"')) }
        .to raise_error(IPaaS::Job::FailJob, /Search text holds a double quote/)
      expect(a_request(:get, mailbox_url).with(query: hash_including({}))).not_to have_been_made
    end

    it 'refuses a folder that is a display name before it calls Graph' do
      expect { run_action(input(folder: 'Sent Items')) }
        .to raise_error(IPaaS::Job::FailJob, /A display name such as Sent Items is not accepted/)
      expect(a_request(:get, mailbox_url).with(query: hash_including({}))).not_to have_been_made
    end

    it 'fails the job with Microsoft own words when Graph refuses the query' do
      stub_page({ error: { code: 'SearchWithFilter',
                           message: "The query parameter '$filter' is not supported with '$search'.", } },
                status: 400)
      expect { run_action(input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 400 SearchWithFilter: ' \
                        "The query parameter '$filter' is not supported with '$search'.")
    end

    it 'reschedules rather than failing when Graph asks for a pause' do
      stub_request(:get, mailbox_url).with(query: hash_including({}))
                                     .to_return(status: 429, body: '', headers: { 'Retry-After' => '30' })
      expect_reschedule_after(30) { run_action(input) }
    end

    # The assertion: a Graph collection answers with value as a list, so anything else is a state that
    # cannot happen while Graph keeps its contract.
    it 'raises when the page value is not a list' do
      stub_page({ value: { id: 'AAMkAGQz=' } })
      expect { run_action(input) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph returned a page whose value is not a list')
    end
  end
end
