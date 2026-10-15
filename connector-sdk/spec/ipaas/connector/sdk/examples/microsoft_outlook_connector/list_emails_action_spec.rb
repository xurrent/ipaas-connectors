require 'spec_helper'

describe 'Microsoft Outlook List Emails Action', :action, :microsoft_outlook do
  let(:action_template_id) { '01a0d336-be94-7be9-9d8b-3bd3998d055b' }
  let(:messages_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/mailFolders/inbox/messages" }
  # Graph answers a request for .../mailFolders/inbox/messages with the folder written as an OData key.
  let(:next_link_url) { "https://graph.microsoft.com/v1.0/users/#{mailbox}/mailFolders('inbox')/messages" }
  let(:next_link) { "#{next_link_url}?%24top=25&%24skip=25" }

  # A stub registered on a bare URL matches only a request that carries no query, so every page stub takes
  # any query and the examples assert the query separately.
  def stub_page(body, url: messages_url, status: 200)
    stub_request(:get, url).with(query: hash_including({}))
                           .to_return(status: status, body: body.to_json,
                                      headers: { 'Content-Type' => 'application/json' })
  end

  # action(input) memoizes on its first call, so the input must be handed over here: calling action with no
  # argument first would build the step from the schema defaults and silently ignore the input that follows.
  def stored_state(link, input = {}, **overrides)
    value = { next_link: link, mailbox: mailbox, folder: 'inbox',
              graph_host: 'https://graph.microsoft.com', }.merge(overrides)
    allow(action(input)).to receive(:iteration_state).and_return({ count: 1, value: value })
  end

  # What a round stores: the link, and what the link was for. The three identity fields exist so the next
  # round can tell that the connection still points where the first round pointed.
  def position(link)
    { next_link: link, mailbox: mailbox, folder: 'inbox', graph_host: 'https://graph.microsoft.com' }
  end

  describe 'the first round' do
    it 'asks Graph for the summary fields, newest first, a page at a time' do
      stub_page({ value: [graph_message] })
      run_action({ page_size: 10 })
      expect(a_request(:get, messages_url)
        .with(query: { '$select' => MicrosoftOutlookConnector::MESSAGE_SELECT.join(','),
                       '$orderby' => MicrosoftOutlookConnector::MESSAGE_ORDER_BY,
                       '$top' => '10', })).to have_been_made
    end

    it 'asks for the default page size when the step leaves it empty' do
      stub_page({ value: [] })
      run_action({})
      expect(a_request(:get, messages_url)
        .with(query: hash_including('$top' => MicrosoftOutlookConnector::DEFAULT_PAGE_SIZE.to_s)))
        .to have_been_made
    end

    it 'asks for the default page size when the step maps the page size to an empty value' do
      stub_page({ value: [] })
      run_action({ page_size: '' })
      expect(a_request(:get, messages_url)
        .with(query: hash_including('$top' => MicrosoftOutlookConnector::DEFAULT_PAGE_SIZE.to_s)))
        .to have_been_made
    end

    # The resolved output round-trips through the schema, so a message comes back with string keys.
    it 'maps a message onto the output fields' do
      stub_page({ value: [graph_message] })
      expect(run_action({})[:messages]).to eq([{
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

    it 'answers with an empty list when the folder holds nothing' do
      stub_page({ value: [] })
      expect(run_action({})[:messages]).to eq([])
    end

    # A draft has no sender, so Graph leaves from out rather than sending null fields.
    it 'maps a message that has no sender onto an empty name and address' do
      stub_page({ value: [graph_message.except(:from)] })
      expect(run_action({})[:messages].first['from']).to eq({ 'name' => nil, 'address' => nil })
    end

    # The assertion: a Graph collection answers with value as a list, so anything else is a state that cannot
    # happen while Graph keeps its contract.
    it 'raises when the page value is not a list' do
      stub_page({ value: { id: 'AAMkAGQz=' } })
      expect { run_action({}) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph returned a page whose value is not a list')
    end

    # The assertion: every message Graph returns carries an id, and the output field is required, so a message
    # without one is a state that cannot happen while Graph keeps its contract.
    it 'raises when Graph returns a message with no id' do
      stub_page({ value: [graph_message.except(:id)] })
      expect { run_action({}) }.to raise_error(IPaaS::Error, 'Microsoft Graph returned a message with no id')
    end
  end

  describe 'paging' do
    it 'stores the next link and reports another page when the limit allows one' do
      step_input = { page_limit: 2 }
      stub_page({ value: [graph_message], '@odata.nextLink': next_link })
      expect(action(step_input)).to receive(:iteration_state_value=)
        .with(position(next_link)).and_call_original
      expect(run_action(step_input)[:has_next_page]).to be(true)
    end

    it 'stops at the page limit even though Graph offers another page' do
      step_input = { page_limit: 1 }
      stub_page({ value: [graph_message], '@odata.nextLink': next_link })
      expect(action(step_input)).to receive(:iteration_state_value=).with(nil).and_call_original
      expect(run_action(step_input)[:has_next_page]).to be(false)
    end

    it 'refuses a next link on another host instead of storing it for the next round' do
      stub_page({ value: [graph_message], '@odata.nextLink': 'https://evil.example.com/v1.0/users/x/messages' })
      expect { run_action({ page_limit: 2 }) }
        .to raise_error(IPaaS::Error, %r{next page link that is not on https://graph\.microsoft\.com})
    end

    it 'stops when Graph offers no further page' do
      step_input = { page_limit: 5 }
      stub_page({ value: [graph_message] })
      expect(action(step_input)).to receive(:iteration_state_value=).with(nil).and_call_original
      expect(run_action(step_input)[:has_next_page]).to be(false)
    end

    it 'keeps going past the page limit when Fetch all pages is on' do
      stub_page({ value: [graph_message], '@odata.nextLink': next_link })
      expect(run_action({ page_limit: 1, all_pages: true })[:has_next_page]).to be(true)
    end

    # A step can carry the word false into a boolean field. The platform casts it before the run block reads
    # it (connector/lib/ipaas/connector/types/boolean_type.rb:13-14), so these two examples pin that contract:
    # if the cast ever stopped happening, the first would go green for a mailbox that should have stopped.
    it 'leaves paging off when the value false reaches the boolean field as a word' do
      stub_page({ value: [graph_message], '@odata.nextLink': next_link })
      expect(run_action({ page_limit: 1, all_pages: 'false' })[:has_next_page]).to be(false)
    end

    it 'turns paging on when the value true reaches the boolean field as a word' do
      stub_page({ value: [graph_message], '@odata.nextLink': next_link })
      expect(run_action({ page_limit: 1, all_pages: 'true' })[:has_next_page]).to be(true)
    end

    it 'falls back to the default page limit when the limit arrives empty' do
      stub_page({ value: [graph_message], '@odata.nextLink': next_link })
      expect(run_action({ page_limit: '' })[:has_next_page]).to be(false)
    end

    it 'reads a page limit that reaches the integer field as digits' do
      stub_page({ value: [graph_message], '@odata.nextLink': next_link })
      expect(run_action({ page_limit: '3' })[:has_next_page]).to be(true)
    end
  end

  describe 'the rounds after the first' do
    it 'follows the link Graph stored and sends no query of its own' do
      step_input = { page_limit: 5 }
      stub_page({ value: [graph_message] }, url: next_link_url)
      stored_state(next_link, step_input)
      expect(run_action(step_input)[:messages].length).to eq(1)
      # An exact query, not a subset: the point is that nothing of our own is added to the link Graph gave
      # us, and a subset match would still pass with $select and $top appended.
      expect(a_request(:get, next_link_url).with(query: { '$top' => '25', '$skip' => '25' })).to have_been_made
      expect(a_request(:get, messages_url).with(query: hash_including({}))).not_to have_been_made
    end

    it 'counts the rounds already done against the page limit' do
      step_input = { page_limit: 2 }
      stub_page({ value: [graph_message], '@odata.nextLink': next_link }, url: next_link_url)
      stored_state(next_link, step_input)
      # One round is already done, so this second one reaches the limit of two and stops, although Graph
      # offers a further page. A run block that ignored the stored count would report another page here.
      expect(run_action(step_input)[:has_next_page]).to be(false)
    end
  end

  describe 'the connection changing under a part-way run' do
    it 'refuses to carry on when the mailbox the step resolves is not the one the stored page came from' do
      step_input = { page_limit: 5 }
      stored_state(next_link, step_input, mailbox: 'someone.else@contoso.com')
      expect { run_action(step_input) }
        .to raise_error(IPaaS::Job::FailJob, /came from mailbox 'someone.else@contoso.com'/)
    end

    it 'refuses to carry on when the folder changed' do
      step_input = { page_limit: 5 }
      stored_state(next_link, step_input, folder: 'archive')
      expect { run_action(step_input) }.to raise_error(IPaaS::Job::FailJob, /folder 'archive'/)
    end

    it 'refuses to carry on when the cloud changed' do
      step_input = { page_limit: 5 }
      stored_state(next_link, step_input, graph_host: 'https://microsoftgraph.chinacloudapi.cn')
      expect { run_action(step_input) }
        .to raise_error(IPaaS::Job::FailJob, %r{host 'https://microsoftgraph.chinacloudapi.cn'})
    end

    # A run that started before this change stored a link and nothing else. It must finish, not fail.
    it 'follows a link stored before the identity fields existed' do
      step_input = { page_limit: 5 }
      stub_page({ value: [graph_message] }, url: next_link_url)
      allow(action(step_input)).to receive(:iteration_state)
        .and_return({ count: 1, value: { next_link: next_link } })
      expect(run_action(step_input)[:messages].length).to eq(1)
    end
  end

  describe 'what it says when Microsoft is the one that is broken' do
    # The assertion: the status is read before the body, so an outage that answers with an error page is
    # reported as that status rather than as unreadable JSON.
    it 'names the status when Graph answers 403 with a page that is not JSON' do
      stub_request(:get, messages_url).with(query: hash_including({}))
                                      .to_return(status: 403, body: '<html><body>Forbidden</body></html>')
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, /HTTP 403/)
    end

    # 429 and 503 are the platform default every other connector takes.
    it 'fails rather than rescheduling when Graph answers 502' do
      stub_request(:get, messages_url).with(query: hash_including({}))
                                      .to_return(status: 502, body: '')
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, /HTTP 502/)
    end

    it 'fails rather than rescheduling when Graph answers 504' do
      stub_request(:get, messages_url).with(query: hash_including({}))
                                      .to_return(status: 504, body: '')
      expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, /HTTP 504/)
    end

    it 'reschedules when Graph is unavailable, which is the one server status it waits on' do
      stub_request(:get, messages_url).with(query: hash_including({}))
                                      .to_return(status: 503, body: '')
      expect_reschedule_after(60, /not available/) { run_action({}) }
    end
  end

  describe 'what it refuses and what it reports' do
    it 'refuses a folder that is a display name before it calls Graph' do
      expect { run_action({ folder: 'Sent Items' }) }
        .to raise_error(IPaaS::Job::FailJob, /A display name such as Sent Items is not accepted/)
      expect(a_request(:get, messages_url).with(query: hash_including({}))).not_to have_been_made
    end

    it 'reads the folder a step names' do
      archive_url = "https://graph.microsoft.com/v1.0/users/#{mailbox}/mailFolders/archive/messages"
      stub_page({ value: [] }, url: archive_url)
      run_action({ folder: 'archive' })
      expect(a_request(:get, archive_url).with(query: hash_including({}))).to have_been_made
    end

    it 'fails the job with Microsoft own words when the folder does not exist' do
      stub_page({ error: { code: 'ErrorInvalidIdMalformed', message: 'Id is malformed.' } }, status: 400)
      expect { run_action({}) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 400 ErrorInvalidIdMalformed: Id is malformed.')
    end

    it 'reschedules rather than failing when Graph asks for a pause' do
      stub_request(:get, messages_url).with(query: hash_including({}))
                                      .to_return(status: 429, body: '', headers: { 'Retry-After' => '30' })
      expect_reschedule_after(30) { run_action({}) }
    end
  end
end
