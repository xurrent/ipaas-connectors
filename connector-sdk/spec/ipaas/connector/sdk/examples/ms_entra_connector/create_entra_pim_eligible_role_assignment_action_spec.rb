require 'spec_helper'

describe 'Microsoft Entra Create PIM Eligible Role Assignment Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c904-3c60-780b-9a1c-7b4f9d5147a5' }
  let(:requests_url) { "#{graph}/roleManagement/directory/roleEligibilityScheduleRequests" }
  let(:role_id) { '8424c6f0-a189-499e-bbd0-26c1753c96d4' }
  let(:request_id) { '50877283-9d40-433c-bab8-7986dc10458a' }

  let(:created_request) do
    {
      id: request_id, status: 'Provisioned', action: 'adminAssign', principalId: user_id,
      roleDefinitionId: role_id, directoryScopeId: '/', targetScheduleId: request_id,
    }
  end

  def eligible_input(overrides = {})
    { principal_id: user_id, role_definition_id: role_id }.merge(overrides)
  end

  def stub_eligible(status: 201, body: created_request.to_json)
    stub_request(:post, requests_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'requires the principal and the role, and defaults the scope to the whole tenant' do
      schema = action.input_schema
      expect(schema.field(:principal_id).required).to be_truthy
      expect(schema.field(:role_definition_id).required).to be_truthy
      expect(schema.field(:directory_scope_id).default).to eq('/')
    end
  end

  describe 'output_schema' do
    it 'returns a required request id' do
      expect(action.output_schema.first.field(:request_id).required).to be_truthy
    end
  end

  describe 'run' do
    it 'asks for an eligibility from now with no end when no dates are set, and maps the request on 201' do
      stub_eligible
      output = Timecop.freeze(Time.utc(2026, 11, 11, 9, 30, 0)) { run_action(eligible_input) }
      expect(@sent).to eq(
        'action' => 'adminAssign', 'principalId' => user_id, 'roleDefinitionId' => role_id,
        'directoryScopeId' => '/',
        'scheduleInfo' => { 'startDateTime' => '2026-11-11T09:30:00Z', 'expiration' => { 'type' => 'noExpiration' } }
      )
      expect(output).to eq('request_id' => request_id, 'status' => 'Provisioned', 'principal_id' => user_id,
                           'role_definition_id' => role_id, 'directory_scope_id' => '/',
                           'target_schedule_id' => request_id)
    end

    it 'sends the start, the end and the justification when they are set' do
      stub_eligible
      run_action(eligible_input(start_date_time: '2026-12-01T00:00:00Z', end_date_time: '2027-04-10T00:00:00Z',
                                justification: ' On-call rota '))
      expect(@sent['scheduleInfo']).to eq(
        'startDateTime' => '2026-12-01T00:00:00+00:00',
        'expiration' => { 'type' => 'afterDateTime', 'endDateTime' => '2027-04-10T00:00:00+00:00' }
      )
      expect(@sent['justification']).to eq('On-call rota')
    end

    it 'fails the job when Graph answers 201 with the request in status Failed' do
      stub_eligible(body: created_request.merge(status: 'Failed').to_json)
      expect { run_action(eligible_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Microsoft Graph answered with request '#{request_id}' in status Failed, so the eligible " \
                        'role assignment was not made.')
    end

    it 'fails the job when Graph answers 201 with the request in status Denied' do
      stub_eligible(body: created_request.merge(status: 'Denied').to_json)
      expect { run_action(eligible_input) }.to raise_error(IPaaS::Job::FailJob, /in status Denied, so the eligible/)
    end

    it 'fails the job when Graph answers 201 with the request in status Canceled' do
      stub_eligible(body: created_request.merge(status: 'Canceled').to_json)
      expect { run_action(eligible_input) }.to raise_error(IPaaS::Job::FailJob, /in status Canceled, so the eligible/)
    end

    it 'fails the job when Graph answers 201 with the request in status Revoked' do
      stub_eligible(body: created_request.merge(status: 'Revoked').to_json)
      expect { run_action(eligible_input) }.to raise_error(IPaaS::Job::FailJob, /in status Revoked, so the eligible/)
    end

    it 'returns a request that is still pending approval' do
      stub_eligible(body: created_request.merge(status: 'PendingApproval').to_json)
      expect(run_action(eligible_input)['status']).to eq('PendingApproval')
    end

    it 'fails with no request when the principal id is not a GUID' do
      expect { run_action(eligible_input(principal_id: 'adele@contoso.com')) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Principal ID 'adele@contoso.com' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails the job on 503 instead of retrying, because the request may already be accepted' do
      stub = stub_eligible(status: 503, body: graph_error('serviceNotAvailable', 'Service unavailable'))
      expect { run_action(eligible_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 503 serviceNotAvailable: Service unavailable')
      expect(stub).to have_been_requested.once
    end

    it 'names RoleEligibilitySchedule.ReadWrite.Directory on 403' do
      stub_eligible(status: 403, body: access_denied.to_json)
      expect { run_action(eligible_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: RoleEligibilitySchedule.ReadWrite.Directory. ' \
                                'Admin consent is required.'))
    end
  end
end
