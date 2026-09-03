require 'spec_helper'

describe 'Microsoft Graph Download File Action', :action, :microsoft_graph do
  let(:action_template_id) { '019ff9e8-8af5-7ea7-8a15-37afdf2e2b61' }
  let(:content_url) { 'https://graph.microsoft.com/v1.0/users/jane@contoso.com/drive/items/item-1/content' }
  let(:metadata_url) { 'https://graph.microsoft.com/v1.0/users/jane@contoso.com/drive/items/item-1' }

  before { stub_graph_token }

  it 'requires user_id and item_id' do
    expect(action.input_schema.field(:user_id).required).to be_truthy
    expect(action.input_schema.field(:item_id).required).to be_truthy
  end

  it 'downloads content directly and base64-encodes it in the output' do
    stub_request(:get, content_url).to_return(status: 200, body: 'hello world',
                                              headers: { 'Content-Type' => 'text/plain' })
    stub_request(:get, metadata_url).to_return(status: 200, body: { name: 'report.txt', size: 11 }.to_json)

    output = run_action({ user_id: 'jane@contoso.com', item_id: 'item-1' })

    expect(Base64.strict_decode64(output[:content])).to eq('hello world')
    expect(output[:content_type]).to eq('text/plain')
    expect(output[:file_name]).to eq('report.txt')
    expect(output[:size]).to eq(11)
  end

  it 'follows a redirect to the pre-authenticated download URL' do
    redirect_url = 'https://download.contoso.com/pre-signed/report.txt'
    stub_request(:get, content_url).to_return(status: 302, headers: { 'Location' => redirect_url })
    stub_request(:get, redirect_url).to_return(status: 200, body: 'hello world',
                                               headers: { 'Content-Type' => 'text/plain' })
    stub_request(:get, metadata_url).to_return(status: 200, body: { name: 'report.txt', size: 11 }.to_json)

    output = run_action({ user_id: 'jane@contoso.com', item_id: 'item-1' })

    expect(Base64.strict_decode64(output[:content])).to eq('hello world')
  end

  it 'fails when the redirect has no Location header' do
    stub_request(:get, content_url).to_return(status: 302)

    expect { run_action({ user_id: 'jane@contoso.com', item_id: 'item-1' }) }
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph did not include a redirect location for the file content.')
  end

  it 'fails on a non-200 response' do
    stub_request(:get, content_url).to_return(status: 404, body: 'not found')

    expect { run_action({ user_id: 'jane@contoso.com', item_id: 'item-1' }) }
      .to raise_error(IPaaS::Job::FailJob, "HTTP error from Microsoft Graph API: 404 'not found'")
  end
end
