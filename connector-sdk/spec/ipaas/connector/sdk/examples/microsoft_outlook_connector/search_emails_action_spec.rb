require 'spec_helper'

describe 'Microsoft Outlook Search Emails Action', :action, :microsoft_outlook do
  let(:action_template_id) { '3137a300-6b66-4720-bea0-d37305036a57' }
  let(:messages_url) { "https://graph.microsoft.com/v1.0/users/#{default_mailbox}/messages" }

  let(:sample_message) { { id: 'msg-1', subject: 'Hello' } }

  before { stub_graph_token }

  it 'searches the whole mailbox with $search when only query_text is given' do
    stub = stub_request(:get, messages_url).with(query: { '$search' => '"invoice"', '$top' => '25' })
                                           .to_return(status: 200, body: { value: [sample_message] }.to_json)

    output = run_action({ query_text: 'invoice' })

    expect(stub).to have_been_requested.once
    expect(output['messages'].first['message_id']).to eq('msg-1')
  end

  it 'scopes the search to a folder when provided' do
    stub = stub_request(:get, "https://graph.microsoft.com/v1.0/users/#{default_mailbox}/mailFolders/inbox/messages")
           .with(query: { '$search' => '"invoice"', '$top' => '25' })
           .to_return(status: 200, body: { value: [] }.to_json)

    run_action({ query_text: 'invoice', folder: 'inbox' })

    expect(stub).to have_been_requested.once
  end

  it 'builds a $filter query from structured fields' do
    stub = stub_request(:get, messages_url)
           .with(query: { '$top' => '25',
                          '$filter' => "from/emailAddress/address eq 'bob@contoso.com' and importance eq 'high' " \
                                       'and hasAttachments eq true and isRead eq false', })
           .to_return(status: 200, body: { value: [] }.to_json)

    run_action({ sender: 'bob@contoso.com', importance: 'high', has_attachments: true, is_read: false })

    expect(stub).to have_been_requested.once
  end

  it 'includes a categories/any clause per category' do
    stub = stub_request(:get, messages_url)
           .with(query: { '$top' => '25', '$filter' => "categories/any(c:c eq 'Red')" })
           .to_return(status: 200, body: { value: [] }.to_json)

    run_action({ categories: ['Red'] })

    expect(stub).to have_been_requested.once
  end

  it 'includes date range clauses' do
    stub = stub_request(:get, messages_url)
           .with(query: { '$top' => '25',
                          '$filter' => 'receivedDateTime ge 2026-01-01T00:00:00+00:00 and receivedDateTime le ' \
                                       '2026-02-01T00:00:00+00:00', })
           .to_return(status: 200, body: { value: [] }.to_json)

    run_action({ received_after: '2026-01-01T00:00:00Z', received_before: '2026-02-01T00:00:00Z' })

    expect(stub).to have_been_requested.once
  end

  it 'defaults to an unfiltered $top-only query when nothing else is given' do
    stub = stub_request(:get, messages_url).with(query: { '$top' => '25' })
                                           .to_return(status: 200, body: { value: [] }.to_json)

    run_action({})

    expect(stub).to have_been_requested.once
  end

  it 'combines $search and $filter with client-side intersection when both are given' do
    search_stub = stub_request(:get, messages_url).with(query: { '$search' => '"invoice"', '$top' => '25' })
                                                  .to_return(status: 200, body: { value: [
                                                    { id: 'msg-1' }, { id: 'msg-2' },
                                                  ] }.to_json)
    filter_stub = stub_request(:get, messages_url)
                  .with(query: { '$filter' => "importance eq 'high'", '$top' => '25' })
                  .to_return(status: 200, body: { value: [{ id: 'msg-2' }, { id: 'msg-3' }] }.to_json)

    output = run_action({ query_text: 'invoice', importance: 'high' })

    expect(search_stub).to have_been_requested.once
    expect(filter_stub).to have_been_requested.once
    expect(output['messages'].map { |m| m['message_id'] }).to eq(['msg-2'])
    expect(output['has_next_page']).to eq(false)
  end

  describe 'pagination' do
    let(:next_link) { "#{messages_url}?$search=%22invoice%22&$top=25&$skiptoken=abc" }

    it 'sets has_next_page and stores the next link when more pages remain' do
      stub_request(:get, messages_url).with(query: { '$top' => '25' })
                                      .to_return(status: 200, body: { value: [sample_message],
                                                                      '@odata.nextLink': next_link, }.to_json)

      expect(action({})).to receive(:iteration_state_value=).with({ next_link: next_link }).and_call_original

      output = run_action({})
      expect(output['has_next_page']).to eq(true)
    end

    it 'follows the stored next link on a subsequent iteration' do
      stub = stub_request(:get, next_link).to_return(status: 200, body: { value: [sample_message] }.to_json)

      action({}).send(:iteration_state_value=, { next_link: next_link })
      output = run_action({})

      expect(stub).to have_been_requested.once
      expect(output['has_next_page']).to eq(false)
    end
  end
end
