require 'spec_helper'

describe 'Microsoft Entra Get User Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-74ef-8177-c76b3080d857' }
  let(:user_url) { "#{graph}/users/#{user_id}" }
  let(:select_query) { { '$select' => MsEntraConnector::USER_SELECT } }

  let(:graph_user) do
    {
      id: user_id, displayName: 'Adele Vance', givenName: 'Adele', surname: 'Vance',
      userPrincipalName: 'adele.vance@contoso.com', mail: 'adele.vance@contoso.com', jobTitle: 'Sales Lead',
      department: 'Sales', officeLocation: '18/2111', mobilePhone: '+1 425 555 0109',
      businessPhones: ['+1 425 555 0100'], accountEnabled: true, usageLocation: 'US', employeeId: 'E1001',
      companyName: 'Contoso', city: 'Redmond', country: 'United States', createdDateTime: '2024-03-01T10:00:00Z',
    }
  end

  def stub_user(url: user_url, status: 200, body: graph_user.to_json)
    stub_request(:get, url).with(query: hash_including({}))
                           .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'defines a required user id string' do
      action.input_schema.field(:user_id).tap do |field|
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end
    end
  end

  describe 'output_schema' do
    it 'defines a required nested user with a required user id' do
      user_field = action.output_schema.first.field(:user)
      expect(user_field.type).to eq(:nested)
      expect(user_field.required).to be_truthy
      expect(user_field.field(:user_id).required).to be_truthy
    end

    it 'defines business phones as a string array, account enabled as a boolean and created as a date time' do
      user_field = action.output_schema.first.field(:user)
      expect(user_field.field(:business_phones).array).to eq(true)
      expect(user_field.field(:account_enabled).type).to eq(:boolean)
      expect(user_field.field(:created_date_time).type).to eq(:date_time)
    end
  end

  describe 'run' do
    it 'asks Graph for the user with the user select list' do
      stub_user
      run_action({ user_id: user_id })
      expect(a_request(:get, user_url).with(query: select_query)).to have_been_made.once
    end

    it 'maps the Graph user onto snake case output fields' do
      stub_user
      expect(run_action({ user_id: user_id })['user']).to eq(
        'user_id' => user_id, 'display_name' => 'Adele Vance', 'given_name' => 'Adele', 'surname' => 'Vance',
        'user_principal_name' => 'adele.vance@contoso.com', 'mail' => 'adele.vance@contoso.com',
        'job_title' => 'Sales Lead', 'department' => 'Sales', 'office_location' => '18/2111',
        'mobile_phone' => '+1 425 555 0109', 'business_phones' => ['+1 425 555 0100'], 'account_enabled' => true,
        'usage_location' => 'US', 'employee_id' => 'E1001', 'company_name' => 'Contoso', 'city' => 'Redmond',
        'country' => 'United States', 'created_date_time' => '2024-03-01T10:00:00Z'
      )
    end

    it 'escapes a hash sign in a user principal name' do
      escaped_url = "#{graph}/users/guest%23EXT%23@contoso.com"
      stub_user(url: escaped_url)
      run_action({ user_id: 'guest#EXT#@contoso.com' })
      expect(a_request(:get, escaped_url).with(query: select_query)).to have_been_made.once
    end

    it 'escapes a slash in a user principal name' do
      escaped_url = "#{graph}/users/a%2Fb@contoso.com"
      stub_user(url: escaped_url)
      run_action({ user_id: 'a/b@contoso.com' })
      expect(a_request(:get, escaped_url).with(query: select_query)).to have_been_made.once
    end

    it 'escapes a space in a user principal name' do
      escaped_url = "#{graph}/users/adele%20vance@contoso.com"
      stub_user(url: escaped_url)
      run_action({ user_id: 'adele vance@contoso.com' })
      expect(a_request(:get, escaped_url).with(query: select_query)).to have_been_made.once
    end

    it 'doubles a single quote in a user id that starts with a dollar sign' do
      quoted_url = "#{graph}/users('$o''neil@contoso.com')"
      stub_user(url: quoted_url)
      run_action({ user_id: "$o'neil@contoso.com" })
      expect(a_request(:get, quoted_url).with(query: select_query)).to have_been_made.once
    end

    it 'addresses a user id that starts with a dollar sign by key, in quotes' do
      quoted_url = "#{graph}/users('$adele@contoso.com')"
      stub_user(url: quoted_url)
      run_action({ user_id: '$adele@contoso.com' })
      expect(a_request(:get, quoted_url).with(query: select_query)).to have_been_made.once
    end

    it 'fails naming User.Read.All when Graph answers 403' do
      stub_user(status: 403, body: access_denied.to_json)
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 403 Authorization_RequestDenied: Insufficient privileges. ' \
                        'Permission this action needs: User.Read.All. Admin consent is required.')
    end

    it 'fails when Graph has no such user' do
      stub_user(status: 404, body: graph_error('Request_ResourceNotFound', 'Resource does not exist.'))
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 404 Request_ResourceNotFound: Resource does not exist.')
    end
  end
end
