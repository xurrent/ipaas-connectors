require 'spec_helper'

describe 'Microsoft Entra Remove Enterprise App Assignment Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c904-3aaa-797f-9746-c036ef90f363' }
  let(:resource_id) { '9028d19c-26a9-4809-8e3f-20ff73e2d75e' }
  let(:assignment_id) { '-WmtM5na7Uus0D8kI1yylpU9Mdo0Pb9OoBJvd3T5eKc' }
  let(:assignment_url) { "#{graph}/servicePrincipals/#{resource_id}/appRoleAssignedTo/#{assignment_id}" }

  def stub_delete(status: 204, body: '')
    stub_request(:delete, assignment_url).to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'requires the app and the assignment id' do
      expect(action.input_schema.field(:service_principal_id).required).to be_truthy
      expect(action.input_schema.field(:assignment_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the ids and whether the assignment existed' do
      schema = action.output_schema.first
      expect(schema.field(:assignment_id).required).to be_truthy
      expect(schema.field(:existed).type).to eq(:boolean)
    end
  end

  describe 'run' do
    it 'deletes the assignment of the app and reports it existed on 204' do
      stub = stub_delete
      output = run_action({ service_principal_id: resource_id, assignment_id: assignment_id })
      expect(stub).to have_been_requested.once
      expect(output).to eq('service_principal_id' => resource_id, 'assignment_id' => assignment_id,
                           'existed' => true)
    end

    it 'reports existed false on 404' do
      stub_delete(status: 404, body: graph_error('Request_ResourceNotFound', 'Resource does not exist.'))
      expect(run_action({ service_principal_id: resource_id, assignment_id: assignment_id })['existed']).to eq(false)
    end

    it 'reports existed false when the 404 names the assignment' do
      stub_delete(status: 404, body: graph_error('Request_ResourceNotFound',
                                                 "Resource '#{assignment_id}' does not exist or one of its queried " \
                                                 'reference-property objects are not present.'))
      expect(run_action({ service_principal_id: resource_id, assignment_id: assignment_id })['existed']).to eq(false)
    end

    it 'fails, naming the Object ID, when the 404 names the enterprise application' do
      stub_delete(status: 404, body: graph_error('Request_ResourceNotFound',
                                                 "Resource '#{resource_id.upcase}' does not exist or one of its " \
                                                 'queried reference-property objects are not present.'))
      expect { run_action({ service_principal_id: resource_id, assignment_id: assignment_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Microsoft Graph has no enterprise application with ID #{resource_id}. Use the Object ID " \
                        'of the enterprise application, not its Application (client) ID.')
    end

    it 'fails with no request when the app id is not a GUID' do
      expect { run_action({ service_principal_id: 'Fabrikam App', assignment_id: assignment_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Enterprise application ID 'Fabrikam App' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:delete, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails with no request when the assignment id is a dot segment' do
      expect { run_action({ service_principal_id: resource_id, assignment_id: '.' }) }
        .to raise_error(IPaaS::Job::FailJob, "Assignment ID '.' is not a valid id.")
      expect(a_request(:delete, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'names AppRoleAssignment.ReadWrite.All on 403' do
      stub_delete(status: 403, body: access_denied.to_json)
      expect { run_action({ service_principal_id: resource_id, assignment_id: assignment_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        /Permission this action needs: AppRoleAssignment\.ReadWrite\.All\. Admin consent is required\./)
    end
  end
end
