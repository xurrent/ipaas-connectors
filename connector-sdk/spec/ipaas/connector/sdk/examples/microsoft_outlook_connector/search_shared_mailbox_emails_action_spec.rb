require 'spec_helper'

describe 'Microsoft Outlook Search Shared Mailbox Emails Action', :action, :microsoft_outlook do
  let(:action_template_id) { '73339012-50d8-4e4a-9ddd-e59dc1a7b18e' }
  let(:shared_mailbox) { 'helpdesk@contoso.com' }
  let(:inbox_url) { "https://graph.microsoft.com/v1.0/users/#{shared_mailbox}/mailFolders/inbox" }
  let(:messages_url) { "https://graph.microsoft.com/v1.0/users/#{shared_mailbox}/messages" }

  before do
    stub_graph_token
    stub_request(:get, inbox_url).to_return(status: 200, body: { id: 'inbox-id' }.to_json)
  end

  it 'requires shared_mailbox_address' do
    expect(action.input_schema.field(:shared_mailbox_address).required).to be_truthy
  end

  it 'searches the shared mailbox after the preflight access check' do
    stub = stub_request(:get, messages_url).with(query: { '$top' => '25' })
                                           .to_return(status: 200, body: { value: [{ id: 'msg-1' }] }.to_json)

    output = run_action({ shared_mailbox_address: shared_mailbox })

    expect(stub).to have_been_requested.once
    expect(output['messages'].first['message_id']).to eq('msg-1')
  end

  it 'fails with a clear message when the connection lacks access to the shared mailbox' do
    stub_request(:get, inbox_url).to_return(status: 403, body: '')

    expect { run_action({ shared_mailbox_address: shared_mailbox }) }
      .to raise_error(IPaaS::Job::FailJob, "This connection does not have access to #{shared_mailbox}.")
  end

  describe 'pagination' do
    let(:next_link) { "#{messages_url}?$top=25&$skiptoken=abc" }

    it 'sets has_next_page and stores the next link when more pages remain' do
      stub_request(:get, messages_url).with(query: { '$top' => '25' })
                                      .to_return(status: 200, body: { value: [{ id: 'msg-1' }],
                                                                      '@odata.nextLink': next_link, }.to_json)

      expect(action({ shared_mailbox_address: shared_mailbox }))
        .to receive(:iteration_state_value=).with({ next_link: next_link }).and_call_original

      output = run_action({ shared_mailbox_address: shared_mailbox })
      expect(output['has_next_page']).to eq(true)
    end

    it 'follows the stored next link on a subsequent iteration' do
      stub = stub_request(:get, next_link).to_return(status: 200, body: { value: [{ id: 'msg-1' }] }.to_json)

      action({ shared_mailbox_address: shared_mailbox }).send(:iteration_state_value=, { next_link: next_link })
      output = run_action({ shared_mailbox_address: shared_mailbox })

      expect(stub).to have_been_requested.once
      expect(output['has_next_page']).to eq(false)
    end
  end
end
