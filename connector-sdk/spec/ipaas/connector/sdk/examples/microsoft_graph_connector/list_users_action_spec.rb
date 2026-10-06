require 'spec_helper'

describe 'Microsoft Graph List Users Action', :action, :microsoft_graph do
  let(:action_template_id) { '019ff9e8-8af5-7110-b964-3a7e3beb2691' }
  let(:users_url) { 'https://graph.microsoft.com/v1.0/users' }

  let(:sample_user) do
    {
      id: 'user-1',
      displayName: 'Jane Doe',
      userPrincipalName: 'jane@contoso.com',
      mail: 'jane@contoso.com',
      jobTitle: 'Engineer',
      officeLocation: 'HQ',
      mobilePhone: '555-1234',
      accountEnabled: true,
    }
  end

  before { stub_graph_token }

  describe 'input_schema' do
    it 'defines optional filter field' do
      expect(action.input_schema.field(:filter).required).to be_falsey
    end

    it 'defines page_size with a default of 100' do
      field = action.input_schema.field(:page_size)
      expect(field.default).to eq(100)
      expect(field.max).to eq(999)
    end
  end

  describe 'run' do
    it 'lists users and maps fields to snake_case' do
      stub_request(:get, users_url).with(query: { '$top' => '100' })
                                   .to_return(status: 200, body: { value: [sample_user] }.to_json)

      output = run_action({})

      expect(output[:has_next_page]).to eq(false)
      user = output[:users].first
      expect(user[:id]).to eq('user-1')
      expect(user[:display_name]).to eq('Jane Doe')
      expect(user[:user_principal_name]).to eq('jane@contoso.com')
      expect(user[:account_enabled]).to eq(true)
    end

    it 'includes the $filter parameter when provided' do
      stub = stub_request(:get, users_url)
             .with(query: { '$top' => '100', '$filter' => 'accountEnabled eq true' })
             .to_return(status: 200, body: { value: [] }.to_json)

      run_action({ filter: 'accountEnabled eq true' })

      expect(stub).to have_been_requested.once
    end

    context 'pagination' do
      let(:next_link) { 'https://graph.microsoft.com/v1.0/users?$top=100&$skiptoken=abc' }

      it 'sets has_next_page and stores the next link when more pages remain' do
        stub_request(:get, users_url).with(query: { '$top' => '100' })
                                     .to_return(status: 200, body: { value: [sample_user],
                                                                     '@odata.nextLink': next_link, }.to_json)

        expect(action({})).to receive(:iteration_state_value=).with({ next_link: next_link }).and_call_original

        output = run_action({})
        expect(output[:has_next_page]).to eq(true)
      end

      it 'follows the stored next link on a subsequent iteration' do
        stub = stub_request(:get, next_link).to_return(status: 200, body: { value: [sample_user] }.to_json)

        action({}).send(:iteration_state_value=, { next_link: next_link })
        output = run_action({})

        expect(stub).to have_been_requested.once
        expect(output[:has_next_page]).to eq(false)
      end

      it 'clears iteration state when no next link is returned' do
        stub_request(:get, users_url).with(query: { '$top' => '100' })
                                     .to_return(status: 200, body: { value: [sample_user] }.to_json)

        expect(action({})).to receive(:iteration_state_value=).with(nil).and_call_original

        run_action({})
      end
    end

    describe 'error handling' do
      let(:insufficient_privileges_body) do
        { error: { code: 'Authorization_RequestDenied', message: 'Insufficient privileges.' } }.to_json
      end

      it 'fails with the Graph error code and message' do
        stub_request(:get, users_url).with(query: { '$top' => '100' })
                                     .to_return(status: 403, body: insufficient_privileges_body)

        expect { run_action({}) }
          .to raise_error(
            IPaaS::Job::FailJob,
            'Microsoft Graph API error [Authorization_RequestDenied]: Insufficient privileges.',
          )
      end

      it 'backs off on 429 with Retry-After' do
        stub_request(:get, users_url).with(query: { '$top' => '100' })
                                     .to_return(status: 429, headers: { 'Retry-After' => '30' })

        Timecop.freeze do
          expect { run_action({}) }
            .to raise_error(IPaaS::Job::RescheduleJob) do |error|
              expect(error.reschedule_after).to eq(30.seconds.from_now)
            end
        end
      end

      it 'backs off on 503' do
        stub_request(:get, users_url).with(query: { '$top' => '100' }).to_return(status: 503)

        expect { run_action({}) }.to raise_error(IPaaS::Job::RescheduleJob)
      end

      it 'fails on a non-JSON response' do
        stub_request(:get, users_url).with(query: { '$top' => '100' }).to_return(status: 200, body: 'not json')

        expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, /non-JSON response/)
      end

      it 'fails on an unexpected HTTP error without a Graph error body' do
        stub_request(:get, users_url).with(query: { '$top' => '100' }).to_return(status: 500, body: 'boom')

        expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, "HTTP error from Microsoft Graph API: 500 'boom'")
      end
    end
  end
end
