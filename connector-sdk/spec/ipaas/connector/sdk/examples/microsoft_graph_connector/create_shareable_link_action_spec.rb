require 'spec_helper'

describe 'Microsoft Graph Create Shareable Link Action', :action, :microsoft_graph do
  let(:action_template_id) { '019ff9e8-8af5-7800-b158-cfe71c494c0e' }
  let(:create_link_url) { 'https://graph.microsoft.com/v1.0/users/jane@contoso.com/drive/items/item-1/createLink' }

  before { stub_graph_token }

  it 'defaults link_type to view and link_scope to organization' do
    expect(action.input_schema.field(:link_type).default).to eq('view')
    expect(action.input_schema.field(:link_scope).default).to eq('organization')
  end

  it 'creates a link with the requested type and scope' do
    stub = stub_request(:post, create_link_url)
           .with(body: { type: 'edit', scope: 'anonymous' }.to_json)
           .to_return(status: 201, body: {
             id: 'perm-1',
             link: { type: 'edit', scope: 'anonymous', webUrl: 'https://contoso.sharepoint.com/s/abc' },
           }.to_json)

    output = run_action({ user_id: 'jane@contoso.com', item_id: 'item-1', link_type: 'edit', link_scope: 'anonymous' })

    expect(output).to eq({ 'id' => 'perm-1', 'web_url' => 'https://contoso.sharepoint.com/s/abc',
                           'link_type' => 'edit', 'link_scope' => 'anonymous', })
    expect(stub).to have_been_requested.once
  end

  it 'fails when link creation is rejected' do
    stub_request(:post, create_link_url)
      .to_return(status: 403, body: { error: { code: 'accessDenied', message: 'Sharing is disabled.' } }.to_json)

    expect { run_action({ user_id: 'jane@contoso.com', item_id: 'item-1' }) }
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [accessDenied]: Sharing is disabled.')
  end
end
