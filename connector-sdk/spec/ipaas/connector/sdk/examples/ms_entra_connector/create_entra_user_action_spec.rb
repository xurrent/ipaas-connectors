require 'spec_helper'

describe 'Microsoft Entra Create User Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c8f4-ea61-7511-b944-fe8b9c8e17d2' }
  let(:users_url) { "#{graph}/users" }
  let(:password) { 'first-sign-in-password' }

  let(:created_user) do
    {
      '@odata.context' => "#{graph}/$metadata#users/$entity", id: user_id, businessPhones: [],
      displayName: 'Adele Vance', givenName: 'Adele', surname: 'Vance', jobTitle: 'Sales Lead',
      mail: 'adele.vance@contoso.com', userPrincipalName: 'adele.vance@contoso.com',
    }
  end

  def user_input(overrides = {})
    {
      display_name: 'Adele Vance', user_principal_name: 'adele.vance@contoso.com', mail_nickname: 'adele.vance',
      password: make_secret_string(password),
    }.merge(overrides)
  end

  def stub_create(status: 201, body: created_user.to_json)
    stub_request(:post, users_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'requires the display name, user principal name, mail alias and password, with the password a secret' do
      schema = action.input_schema
      [:display_name, :user_principal_name, :mail_nickname, :password].each do |id|
        expect(schema.field(id).required).to be_truthy
      end
      expect(schema.field(:password).type).to eq(:secret_string)
    end

    it 'enables the account and forces a password change by default' do
      expect(action.input_schema.field(:account_enabled).default).to eq(true)
      expect(action.input_schema.field(:force_change_password_next_sign_in).default).to eq(true)
    end
  end

  describe 'output_schema' do
    it 'returns the user with a required user id' do
      user = action.output_schema.first.field(:user)
      expect(user.type).to eq(:nested)
      expect(user.field(:user_id).required).to be_truthy
    end
  end

  describe 'the request it sends' do
    it 'posts the decrypted password, enabled and forced to change, and maps the user on 201 without it' do
      stub_create
      output = run_action(user_input)
      expect(@sent).to eq(
        'displayName' => 'Adele Vance', 'userPrincipalName' => 'adele.vance@contoso.com',
        'mailNickname' => 'adele.vance', 'accountEnabled' => true,
        'passwordProfile' => { 'password' => password, 'forceChangePasswordNextSignIn' => true }
      )
      expect(output[:user]).to include(
        'user_id' => user_id, 'display_name' => 'Adele Vance', 'given_name' => 'Adele', 'surname' => 'Vance',
        'job_title' => 'Sales Lead', 'user_principal_name' => 'adele.vance@contoso.com', 'business_phones' => []
      )
      expect(output.to_json).not_to include(password)
    end

    it 'sends account enabled false and no forced change when the step sets both to false' do
      stub_create
      run_action(user_input(account_enabled: false, force_change_password_next_sign_in: 'false'))
      expect(@sent['accountEnabled']).to eq(false)
      expect(@sent['passwordProfile']['forceChangePasswordNextSignIn']).to eq(false)
    end

    it 'sends only the optional fields that are set, under their Graph names' do
      stub_create
      run_action(user_input(job_title: 'Sales Lead', usage_location: ' US ', department: ''))
      expect(@sent).to include('jobTitle' => 'Sales Lead', 'usageLocation' => 'US')
      expect(@sent).not_to have_key('department')
    end
  end

  describe 'the answer' do
    it 'always returns the ten default user keys, nil where the create reply leaves them out' do
      stub_create(body: created_user.merge(accountEnabled: true, department: 'Sales', city: 'Seattle').to_json)
      output = run_action(user_input)
      expect(output[:user].keys).to contain_exactly(
        'user_id', 'display_name', 'given_name', 'surname', 'user_principal_name', 'mail', 'job_title',
        'office_location', 'mobile_phone', 'business_phones'
      )
      expect(output[:user]).to include('office_location' => nil, 'mobile_phone' => nil)
    end
  end

  describe 'errors' do
    it 'fails the job on 503 instead of retrying, because the user may already exist' do
      stub = stub_create(status: 503, body: graph_error('serviceNotAvailable', 'Service unavailable'))
      expect { run_action(user_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 503 serviceNotAvailable: Service unavailable')
      expect(stub).to have_been_requested.once
    end

    it 'names User.Create on 403' do
      stub_create(status: 403, body: access_denied.to_json)
      expect { run_action(user_input) }.to raise_error(
        IPaaS::Job::FailJob,
        'Microsoft Graph returned HTTP 403 Authorization_RequestDenied: Insufficient privileges. ' \
        'Permission this action needs: User.Create. Admin consent is required.'
      )
    end
  end
end
