require 'spec_helper'

describe 'Microsoft Outlook List Emails Action', :action, :microsoft_outlook do
  let(:action_template_id) { 'b9a6600b-9954-4e2e-9fc9-e07915ed39ee' }
  let(:messages_url) { "https://graph.microsoft.com/v1.0/users/#{default_mailbox}/mailFolders/inbox/messages" }

  let(:sample_message) do
    {
      id: 'msg-1',
      subject: 'Hello',
      from: { emailAddress: { address: 'bob@contoso.com', name: 'Bob' } },
      receivedDateTime: '2026-08-01T00:00:00Z',
      hasAttachments: false,
      isRead: true,
      importance: 'normal',
      bodyPreview: 'Hi there',
    }
  end

  before { stub_graph_token }

  it 'defaults folder to inbox and top to 25 (max 999)' do
    expect(action.input_schema.field(:folder).default).to eq('inbox')
    field = action.input_schema.field(:top)
    expect(field.default).to eq(25)
    expect(field.max).to eq(999)
  end

  it 'lists messages and maps the summary shape' do
    stub_request(:get, messages_url)
      .with(query: { '$top' => '25', '$orderby' => 'receivedDateTime desc' })
      .to_return(status: 200, body: { value: [sample_message] }.to_json)

    output = run_action({})

    expect(output['has_next_page']).to eq(false)
    message = output['messages'].first
    expect(message['message_id']).to eq('msg-1')
    expect(message['from_address']).to eq('bob@contoso.com')
    expect(message['body_preview']).to eq('Hi there')
  end

  it 'lists messages from the Target mailbox override and configured folder' do
    stub = stub_request(:get, 'https://graph.microsoft.com/v1.0/users/other@contoso.com/mailFolders/archive/messages')
           .with(query: { '$top' => '25', '$orderby' => 'receivedDateTime desc' })
           .to_return(status: 200, body: { value: [] }.to_json)

    run_action({ target_mailbox: 'other@contoso.com', folder: 'archive' })

    expect(stub).to have_been_requested.once
  end

  describe 'pagination' do
    let(:next_link) { "#{messages_url}?$top=25&$skiptoken=abc" }

    it 'sets has_next_page and stores the next link when more pages remain' do
      stub_request(:get, messages_url).with(query: { '$top' => '25', '$orderby' => 'receivedDateTime desc' })
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

    it 'clears iteration state when no next link is returned' do
      stub_request(:get, messages_url).with(query: { '$top' => '25', '$orderby' => 'receivedDateTime desc' })
                                      .to_return(status: 200, body: { value: [sample_message] }.to_json)

      expect(action({})).to receive(:iteration_state_value=).with(nil).and_call_original

      run_action({})
    end
  end

  it 'fails on a non-JSON response' do
    stub_request(:get, messages_url).with(query: { '$top' => '25', '$orderby' => 'receivedDateTime desc' })
                                    .to_return(status: 200, body: 'not json')

    expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, /non-JSON response/)
  end

  it 'backs off on 429 with Retry-After' do
    stub_request(:get, messages_url).with(query: { '$top' => '25', '$orderby' => 'receivedDateTime desc' })
                                    .to_return(status: 429, headers: { 'Retry-After' => '30' })

    Timecop.freeze do
      expect { run_action({}) }
        .to raise_error(IPaaS::Job::RescheduleJob) { |error| expect(error.reschedule_after).to eq(30.seconds.from_now) }
    end
  end
end
