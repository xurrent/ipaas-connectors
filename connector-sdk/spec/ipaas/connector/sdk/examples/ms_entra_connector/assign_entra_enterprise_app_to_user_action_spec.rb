require 'spec_helper'

describe 'Microsoft Entra Assign Enterprise App To User Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c904-3a41-78b3-b0bf-d64f41edac41' }
  let(:resource_id) { '9028d19c-26a9-4809-8e3f-20ff73e2d75e' }
  let(:app_role_id) { 'ef7437e6-4f94-4a0a-a110-a439eb2aa8f7' }
  let(:assigned_to_url) { "#{graph}/servicePrincipals/#{resource_id}/appRoleAssignedTo" }

  let(:assignment) do
    {
      id: '-WmtM5na7Uus0D8kI1yylpU9Mdo0Pb9OoBJvd3T5eKc', deletedDateTime: nil, appRoleId: app_role_id,
      createdDateTime: '2026-11-11T16:14:59Z', principalDisplayName: 'Adele Vance', principalId: user_id,
      principalType: 'User', resourceDisplayName: 'Fabrikam App', resourceId: resource_id,
    }
  end

  def assign_input(overrides = {})
    { service_principal_id: resource_id, principal_id: user_id, app_role_id: app_role_id }.merge(overrides)
  end

  def stub_assign(status: 201, body: assignment.to_json)
    stub_request(:post, assigned_to_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'requires the app and the principal, and defaults the app role to the empty role id' do
      schema = action.input_schema
      expect(schema.field(:service_principal_id).required).to be_truthy
      expect(schema.field(:principal_id).required).to be_truthy
      expect(schema.field(:app_role_id).default).to eq('00000000-0000-0000-0000-000000000000')
    end
  end

  describe 'output_schema' do
    it 'returns a required assignment id' do
      expect(action.output_schema.first.field(:assignment_id).required).to be_truthy
    end
  end

  describe 'run' do
    it 'posts the principal, the app and the app role, and maps the assignment on 201' do
      stub_assign
      output = run_action(assign_input)
      expect(@sent).to eq('principalId' => user_id, 'resourceId' => resource_id, 'appRoleId' => app_role_id)
      expect(output).to eq(
        'assignment_id' => '-WmtM5na7Uus0D8kI1yylpU9Mdo0Pb9OoBJvd3T5eKc', 'app_role_id' => app_role_id,
        'principal_id' => user_id, 'principal_type' => 'User', 'principal_display_name' => 'Adele Vance',
        'resource_id' => resource_id, 'resource_display_name' => 'Fabrikam App',
        'created_date_time' => '2026-11-11T16:14:59Z'
      )
    end

    it 'sends the empty role id when the step leaves the app role empty' do
      stub_assign
      run_action(assign_input(app_role_id: ''))
      expect(@sent['appRoleId']).to eq('00000000-0000-0000-0000-000000000000')
    end

    it 'fails with no request when the principal id is not a GUID' do
      expect { run_action(assign_input(principal_id: 'adele@contoso.com')) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Principal ID 'adele@contoso.com' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails the job on 503 instead of retrying, because the assignment may already exist' do
      stub = stub_assign(status: 503, body: graph_error('serviceNotAvailable', 'Service unavailable'))
      expect { run_action(assign_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 503 serviceNotAvailable: Service unavailable')
      expect(stub).to have_been_requested.once
    end

    it 'names AppRoleAssignment.ReadWrite.All and Application.Read.All on 403' do
      stub_assign(status: 403, body: access_denied.to_json)
      needed = 'Permission this action needs: AppRoleAssignment.ReadWrite.All and Application.Read.All. ' \
               'Admin consent is required.'
      expect { run_action(assign_input) }.to raise_error(IPaaS::Job::FailJob, include(needed))
    end
  end
end
