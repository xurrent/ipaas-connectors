require 'spec_helper'

describe 'Microsoft Outlook Execute Microsoft Graph API Request Action', :action, :microsoft_outlook do
  let(:action_template_id) { 'd056b997-b39d-4081-9126-0e541098cf82' }

  before { stub_graph_token }

  it 'requires method and graph_path' do
    expect(action.input_schema.field(:method).required).to be_truthy
    expect(action.input_schema.field(:graph_path).required).to be_truthy
  end

  it 'rejects a graph_path that is not a relative path' do
    expect(action.input_schema.field(:graph_path).pattern).to match('/me/messages')
    expect(action.input_schema.field(:graph_path).pattern).not_to match('https://evil.com/me/messages')
  end

  it 'issues a GET request with query parameters and returns the raw body and status' do
    stub = stub_request(:get, 'https://graph.microsoft.com/v1.0/me/outlook/masterCategories')
           .with(query: { '$top' => '5' })
           .to_return(status: 200, body: { value: [{ displayName: 'Red' }] }.to_json)

    output = run_action({
      method: 'GET', graph_path: '/me/outlook/masterCategories',
      query_parameters: [{ name: '$top', value: '5' }],
    })

    expect(output['status']).to eq(200)
    expect(JSON.parse(output['body'])).to eq({ 'value' => [{ 'displayName' => 'Red' }] })
    expect(stub).to have_been_requested.once
  end

  it 'issues a POST request with a JSON body and custom headers' do
    stub = stub_request(:post, 'https://graph.microsoft.com/v1.0/me/outlook/masterCategories')
           .with(body: '{"displayName":"Green","color":"preset1"}',
                 headers: { 'Content-Type' => 'application/json', 'X-Custom' => 'value' })
           .to_return(status: 201, body: '{}')

    output = run_action({
      method: 'POST', graph_path: '/me/outlook/masterCategories',
      request_body: '{"displayName":"Green","color":"preset1"}',
      headers: [{ name: 'X-Custom', value: 'value' }],
    })

    expect(output['status']).to eq(201)
    expect(stub).to have_been_requested.once
  end

  it 'issues a PATCH request with a JSON body' do
    stub = stub_request(:patch, 'https://graph.microsoft.com/v1.0/me/outlook/masterCategories/cat-1')
           .with(body: '{"displayName":"Blue"}')
           .to_return(status: 200, body: '{}')

    output = run_action({
      method: 'PATCH', graph_path: '/me/outlook/masterCategories/cat-1',
      request_body: '{"displayName":"Blue"}',
    })

    expect(output['status']).to eq(200)
    expect(stub).to have_been_requested.once
  end

  it 'issues a PUT request with a JSON body' do
    stub = stub_request(:put, 'https://graph.microsoft.com/v1.0/me/outlook/masterCategories/cat-1')
           .with(body: '{"displayName":"Yellow"}')
           .to_return(status: 200, body: '{}')

    output = run_action({
      method: 'PUT', graph_path: '/me/outlook/masterCategories/cat-1',
      request_body: '{"displayName":"Yellow"}',
    })

    expect(output['status']).to eq(200)
    expect(stub).to have_been_requested.once
  end

  it 'issues a POST request without a body when request_body is not provided' do
    stub = stub_request(:post, 'https://graph.microsoft.com/v1.0/me/sendMail').to_return(status: 202, body: '')

    output = run_action({ method: 'POST', graph_path: '/me/sendMail' })

    expect(output['status']).to eq(202)
    expect(stub).to have_been_requested.once
  end

  it 'issues a PATCH request without a body when request_body is not provided' do
    stub = stub_request(:patch, 'https://graph.microsoft.com/v1.0/me/outlook/masterCategories/cat-1')
           .to_return(status: 200, body: '{}')

    output = run_action({ method: 'PATCH', graph_path: '/me/outlook/masterCategories/cat-1' })

    expect(output['status']).to eq(200)
    expect(stub).to have_been_requested.once
  end

  it 'issues a PUT request without a body when request_body is not provided' do
    stub = stub_request(:put, 'https://graph.microsoft.com/v1.0/me/outlook/masterCategories/cat-1')
           .to_return(status: 200, body: '{}')

    output = run_action({ method: 'PUT', graph_path: '/me/outlook/masterCategories/cat-1' })

    expect(output['status']).to eq(200)
    expect(stub).to have_been_requested.once
  end

  it 'issues a DELETE request' do
    stub = stub_request(:delete, 'https://graph.microsoft.com/v1.0/me/outlook/masterCategories/cat-1')
           .to_return(status: 204, body: '')

    output = run_action({ method: 'DELETE', graph_path: '/me/outlook/masterCategories/cat-1' })

    expect(output['status']).to eq(204)
    expect(stub).to have_been_requested.once
  end

  it 'extracts @odata.nextLink when present in the response body' do
    next_link = 'https://graph.microsoft.com/v1.0/me/messages?$skiptoken=abc'
    stub_request(:get, 'https://graph.microsoft.com/v1.0/me/messages')
      .to_return(status: 200, body: { value: [], '@odata.nextLink': next_link }.to_json)

    output = run_action({ method: 'GET', graph_path: '/me/messages' })

    expect(output['next_link']).to eq(next_link)
  end

  it 'returns nil next_link for a non-JSON response body' do
    stub_request(:get, 'https://graph.microsoft.com/v1.0/me/outlook/masterCategories').to_return(status: 200,
                                                                                                 body: 'not json')

    output = run_action({ method: 'GET', graph_path: '/me/outlook/masterCategories' })

    expect(output['next_link']).to be_nil
  end

  it 'fails when Microsoft Graph rejects the request' do
    stub_request(:get, 'https://graph.microsoft.com/v1.0/me/messages')
      .to_return(status: 403, body: { error: { code: 'ErrorAccessDenied', message: 'Access denied.' } }.to_json)

    expect { run_action({ method: 'GET', graph_path: '/me/messages' }) }
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [ErrorAccessDenied]: Access denied.')
  end
end
