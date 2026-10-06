require 'spec_helper'

describe 'Microsoft Graph Upload File Action', :action, :microsoft_graph do
  let(:action_template_id) { '019ff9e8-8af5-742f-86bc-75cb94125756' }
  let(:upload_url) { 'https://graph.microsoft.com/v1.0/users/jane@contoso.com/drive/root:/Documents/report.pdf:/content' }

  before { stub_graph_token }

  it 'requires user_id, file_path, and content' do
    expect(action.input_schema.field(:user_id).required).to be_truthy
    expect(action.input_schema.field(:file_path).required).to be_truthy
    expect(action.input_schema.field(:content).required).to be_truthy
  end

  it 'uploads the decoded content to the given path' do
    stub = stub_request(:put, upload_url)
           .with(body: 'hello world', headers: { 'Content-Type' => 'application/octet-stream' })
           .to_return(status: 201, body: { id: 'item-1', name: 'report.pdf',
                                           webUrl: 'https://contoso.sharepoint.com/report.pdf', size: 11, }.to_json)

    output = run_action({
      user_id: 'jane@contoso.com',
      file_path: '/Documents/report.pdf',
      content: Base64.strict_encode64('hello world'),
    })

    expect(output).to eq({ 'item_id' => 'item-1', 'name' => 'report.pdf',
                           'web_url' => 'https://contoso.sharepoint.com/report.pdf', 'size' => 11, })
    expect(stub).to have_been_requested.once
  end

  it 'strips a leading slash from the file path before building the URL' do
    stub = stub_request(:put, upload_url).to_return(status: 201, body: { id: 'item-1' }.to_json)

    run_action({ user_id: 'jane@contoso.com', file_path: 'Documents/report.pdf', content: Base64.strict_encode64('x') })

    expect(stub).to have_been_requested.once
  end

  it 'uses the provided content_type header when given' do
    stub = stub_request(:put, upload_url)
           .with(headers: { 'Content-Type' => 'application/pdf' })
           .to_return(status: 201, body: { id: 'item-1' }.to_json)

    run_action({
      user_id: 'jane@contoso.com',
      file_path: '/Documents/report.pdf',
      content: Base64.strict_encode64('x'),
      content_type: 'application/pdf',
    })

    expect(stub).to have_been_requested.once
  end

  it 'fails when the upload is rejected' do
    stub_request(:put, upload_url)
      .to_return(status: 413, body: { error: { code: 'ErrorFileSizeTooLarge', message: 'File too large.' } }.to_json)

    expect do
      run_action({ user_id: 'jane@contoso.com', file_path: '/Documents/report.pdf',
                   content: Base64.strict_encode64('x'), })
    end
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [ErrorFileSizeTooLarge]: File too large.')
  end
end
