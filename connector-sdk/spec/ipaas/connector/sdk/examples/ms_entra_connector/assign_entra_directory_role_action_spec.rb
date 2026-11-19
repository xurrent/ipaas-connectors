require 'spec_helper'

describe 'Microsoft Entra Assign Directory Role Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c904-3bf9-70f0-ad58-d5cbf46927ba' }
  let(:assignments_url) { "#{graph}/roleManagement/directory/roleAssignments" }
  let(:role_id) { 'c2cf284d-6c41-4e6b-afac-4b80928c9034' }
  let(:assignment_id) { 'YUb1sHQtUEyvox7IA_Eu_mm3jqnUe4lEhvatluHVi2I-1' }

  def stub_assign(status: 201, body: nil)
    body ||= { id: assignment_id, roleDefinitionId: role_id, principalId: user_id, directoryScopeId: '/' }.to_json
    stub_request(:post, assignments_url)
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
    it 'returns a required assignment id' do
      expect(action.output_schema.first.field(:assignment_id).required).to be_truthy
    end
  end

  describe 'run' do
    it 'posts the role for the whole tenant when no scope is set, and maps the assignment on 201' do
      stub_assign
      output = run_action({ principal_id: user_id, role_definition_id: role_id, directory_scope_id: '' })
      expect(@sent).to eq('principalId' => user_id, 'roleDefinitionId' => role_id, 'directoryScopeId' => '/')
      expect(output).to eq('assignment_id' => assignment_id, 'role_definition_id' => role_id,
                           'principal_id' => user_id, 'directory_scope_id' => '/')
    end

    it 'sends the scope of an administrative unit when it is set' do
      scope = '/administrativeUnits/5d107bba-d8e2-4e13-b6ae-884be90e5d1a'
      stub_assign
      run_action({ principal_id: user_id, role_definition_id: role_id, directory_scope_id: scope })
      expect(@sent['directoryScopeId']).to eq(scope)
    end

    it 'fails with no request when the role id is not a GUID' do
      expect { run_action({ principal_id: user_id, role_definition_id: 'Helpdesk Administrator' }) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Role definition ID 'Helpdesk Administrator' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails the job on 503 instead of retrying, because the assignment may already exist' do
      stub = stub_assign(status: 503, body: graph_error('serviceNotAvailable', 'Service unavailable'))
      expect { run_action({ principal_id: user_id, role_definition_id: role_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 503 serviceNotAvailable: Service unavailable')
      expect(stub).to have_been_requested.once
    end

    it 'names RoleManagement.ReadWrite.Directory on 403' do
      stub_assign(status: 403, body: access_denied.to_json)
      expect { run_action({ principal_id: user_id, role_definition_id: role_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: RoleManagement.ReadWrite.Directory. ' \
                                'Admin consent is required.'))
    end
  end
end
