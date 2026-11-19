require 'spec_helper'

describe 'Microsoft Entra Update User Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-7527-bc54-6cfcdee8df58' }
  let(:user_url) { "#{graph}/users/#{user_id}" }

  def stub_patch(status: 204, body: '')
    stub_request(:patch, user_url).to_return(status: status, body: body,
                                             headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'defines a required user id string' do
      expect(action.input_schema.field(:user_id).type).to eq(:string)
      expect(action.input_schema.field(:user_id).required).to be_truthy
    end

    it 'defines optional strings with the Graph length limits on company name and employee id' do
      expect(action.input_schema.field(:job_title).required).to be_falsey
      expect(action.input_schema.field(:company_name).max_length).to eq(64)
      expect(action.input_schema.field(:employee_id).max_length).to eq(16)
    end

    it 'defines account enabled as an optional boolean' do
      expect(action.input_schema.field(:account_enabled).type).to eq(:boolean)
      expect(action.input_schema.field(:account_enabled).required).to be_falsey
    end
  end

  describe 'output_schema' do
    it 'defines a required user id and an updated fields string array' do
      schema = action.output_schema.first
      expect(schema.field(:user_id).required).to be_truthy
      expect(schema.field(:updated_fields).type).to eq(:string)
      expect(schema.field(:updated_fields).array).to eq(true)
    end
  end

  describe 'run' do
    it 'sends only the fields that are set, under their Graph names' do
      stub_patch
      run_action({ user_id: user_id, job_title: 'Sales Lead', department: ' Sales ', city: '' })
      expect(a_request(:patch, user_url).with(body: { jobTitle: 'Sales Lead', department: 'Sales' }))
        .to have_been_made.once
    end

    it 'sends the business phone as a one element business phones list' do
      stub_patch
      run_action({ user_id: user_id, business_phone: '+1 425 555 0100' })
      expect(a_request(:patch, user_url).with(body: { businessPhones: ['+1 425 555 0100'] })).to have_been_made.once
    end

    it 'sends account enabled false when the step maps the string false' do
      stub_patch
      run_action({ user_id: user_id, account_enabled: 'false' })
      expect(a_request(:patch, user_url).with(body: { accountEnabled: false })).to have_been_made.once
    end

    it 'sends account enabled false when the step maps the boolean false' do
      stub_patch
      run_action({ user_id: user_id, account_enabled: false })
      expect(a_request(:patch, user_url).with(body: { accountEnabled: false })).to have_been_made.once
    end

    it 'reports the user and the Graph properties it sent when Graph answers 204' do
      stub_patch
      expect(run_action({ user_id: user_id, job_title: 'Sales Lead', account_enabled: true }))
        .to eq('user_id' => user_id, 'updated_fields' => %w[jobTitle accountEnabled])
    end

    it 'fails without a request when no field is set' do
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob, 'Set at least one field to update.')
      expect(a_request(:patch, user_url)).not_to have_been_made
    end

    it 'fails when Graph answers 200 where 204 is expected' do
      stub_patch(status: 200, body: '{}')
      expect { run_action({ user_id: user_id, job_title: 'Sales Lead' }) }
        .to raise_error(IPaaS::Job::FailJob, /Microsoft Graph returned HTTP 200/)
    end

    it 'fails naming User.ReadWrite.All when Graph answers 403' do
      stub_patch(status: 403, body: access_denied.to_json)
      expect { run_action({ user_id: user_id, job_title: 'Sales Lead' }) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: User.ReadWrite.All (Account enabled also needs ' \
                                'User.EnableDisableAccount.All, and phone numbers also need ' \
                                'User-Phone.ReadWrite.All). Admin consent is required.'))
    end

    it 'returns the new user principal name as user_id after a rename' do
      stub_request(:patch, "#{graph}/users/adele@contoso.com").to_return(status: 204, body: '')
      output = run_action({ user_id: 'adele@contoso.com', user_principal_name: 'adele.vance@contoso.com' })
      expect(output['user_id']).to eq('adele.vance@contoso.com')
    end

    it 'keeps the object ID as user_id after a rename, because the ID does not change' do
      stub_patch
      output = run_action({ user_id: user_id, user_principal_name: 'adele.vance@contoso.com' })
      expect(output['user_id']).to eq(user_id)
    end

    it 'reschedules the job when Graph answers 503' do
      stub_patch(status: 503, body: 'Service Unavailable')
      expect { run_action({ user_id: user_id, job_title: 'Sales Lead' }) }
        .to raise_error(IPaaS::Job::RescheduleJob, /Microsoft API not available/)
    end
  end
end
