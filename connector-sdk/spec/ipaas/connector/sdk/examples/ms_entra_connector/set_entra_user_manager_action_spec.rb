require 'spec_helper'

describe 'Microsoft Entra Set User Manager Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c8f4-ead7-7cb5-9e09-43e37ab37a39' }
  let(:manager_id) { '6ea91a8d-e32e-41a1-b7bd-d2d185eed0e0' }
  let(:manager_url) { "#{graph}/users/#{user_id}/manager/$ref" }

  def stub_put(url = manager_url, status: 204, body: '', headers: {})
    stub_request(:put, url).to_return(status: status, body: body, headers: headers)
  end

  describe 'input_schema' do
    it 'requires the user id and the manager id' do
      expect(action.input_schema.field(:user_id).required).to be_truthy
      expect(action.input_schema.field(:manager_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the user id and the manager id' do
      schema = action.output_schema.first
      expect(schema.field(:user_id).required).to be_truthy
      expect(schema.field(:manager_id).required).to be_truthy
    end
  end

  describe 'run' do
    it 'puts the manager as a JSON directory object reference and returns both ids on 204' do
      stub_put
      output = run_action({ user_id: user_id, manager_id: manager_id })
      expect(a_request(:put, manager_url)
        .with(body: { '@odata.id' => "#{graph}/directoryObjects/#{manager_id}" },
              headers: { 'Content-Type' => 'application/json' })).to have_been_made.once
      expect(output).to eq('user_id' => user_id, 'manager_id' => manager_id)
    end

    it 'addresses the user by user principal name' do
      upn_url = "#{graph}/users/adele.vance@contoso.com/manager/$ref"
      stub_put(upn_url)
      output = run_action({ user_id: ' adele.vance@contoso.com ', manager_id: manager_id })
      expect(a_request(:put, upn_url)).to have_been_made.once
      expect(output['user_id']).to eq('adele.vance@contoso.com')
    end

    it 'escapes a caret in the user principal name as %5E' do
      caret_url = "#{graph}/users/o%5Eneil@contoso.com/manager/$ref"
      stub_put(caret_url)
      run_action({ user_id: 'o^neil@contoso.com', manager_id: manager_id })
      expect(a_request(:put, caret_url)).to have_been_made.once
    end

    it 'fails with no request when the manager id is not a GUID' do
      expect { run_action({ user_id: user_id, manager_id: 'megan@contoso.com' }) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Manager ID 'megan@contoso.com' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:put, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'reschedules on 429 for the time in Retry-After' do
      stub_put(status: 429, body: 'Too many requests', headers: { 'Retry-After' => '7' })
      Timecop.freeze do
        expect { run_action({ user_id: user_id, manager_id: manager_id }) }
          .to raise_error(IPaaS::Job::RescheduleJob, /rate limit hit \(retry after: 7\)/) do |error|
            expect(error.reschedule_after).to eq(7.seconds.from_now)
          end
      end
    end

    it 'fails with the Graph message when Graph answers 200 where 204 is expected' do
      stub_put(status: 200, body: '{}')
      expect { run_action({ user_id: user_id, manager_id: manager_id }) }
        .to raise_error(IPaaS::Job::FailJob, /Microsoft Graph returned HTTP 200/)
    end

    it 'names User.ReadWrite.All on 403' do
      stub_put(status: 403, body: access_denied.to_json)
      expect { run_action({ user_id: user_id, manager_id: manager_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        /Permission this action needs: User\.ReadWrite\.All\. Admin consent is required\./)
    end
  end
end
