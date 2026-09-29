require 'spec_helper'

describe 'Microsoft Graph Get User Action', :action, :microsoft_graph do
  let(:action_template_id) { '019ff9e8-8af5-70fb-8db3-c22f6f6d907f' }

  before { stub_graph_token }

  it 'requires user_id' do
    expect(action.input_schema.field(:user_id).required).to be_truthy
  end

  it 'fetches and maps the user profile' do
    stub_request(:get, 'https://graph.microsoft.com/v1.0/users/jane@contoso.com')
      .to_return(status: 200, body: {
        id: 'user-1',
        displayName: 'Jane Doe',
        userPrincipalName: 'jane@contoso.com',
        mail: 'jane@contoso.com',
        jobTitle: 'Engineer',
        officeLocation: 'HQ',
        mobilePhone: '555-1234',
        accountEnabled: true,
      }.to_json)

    output = run_action({ user_id: 'jane@contoso.com' })

    expect(output).to eq(
      {
        'id' => 'user-1',
        'display_name' => 'Jane Doe',
        'user_principal_name' => 'jane@contoso.com',
        'mail' => 'jane@contoso.com',
        'job_title' => 'Engineer',
        'office_location' => 'HQ',
        'mobile_phone' => '555-1234',
        'account_enabled' => true,
      }
    )
  end

  it 'fails when the user cannot be found' do
    stub_request(:get, 'https://graph.microsoft.com/v1.0/users/missing@contoso.com')
      .to_return(status: 404, body: { error: { code: 'Request_ResourceNotFound',
                                               message: 'Resource not found.', } }.to_json)

    expect { run_action({ user_id: 'missing@contoso.com' }) }
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph API error [Request_ResourceNotFound]: Resource not found.')
  end
end
