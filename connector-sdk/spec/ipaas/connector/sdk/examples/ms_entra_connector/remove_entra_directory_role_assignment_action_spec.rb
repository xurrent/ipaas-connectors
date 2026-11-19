require 'spec_helper'

describe 'Microsoft Entra Remove Directory Role Assignment Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c904-3cd4-7be0-bb32-5d9cfce48a06' }
  let(:assignment_id) { 'lAPpYvVpN0KRkAEhdxReEJC2sEqbR_9Hr48lds9SGHI-1' }
  let(:assignment_url) { "#{graph}/roleManagement/directory/roleAssignments/#{assignment_id}" }

  def stub_delete(status: 204, body: '')
    stub_request(:delete, assignment_url).to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'requires the assignment id' do
      expect(action.input_schema.field(:assignment_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the assignment id and whether it existed' do
      schema = action.output_schema.first
      expect(schema.field(:assignment_id).required).to be_truthy
      expect(schema.field(:existed).type).to eq(:boolean)
    end
  end

  describe 'run' do
    it 'deletes the assignment and reports it existed on 204' do
      stub = stub_delete
      expect(run_action({ assignment_id: assignment_id })).to eq('assignment_id' => assignment_id, 'existed' => true)
      expect(stub).to have_been_requested.once
    end

    it 'reports existed false on 404' do
      stub_delete(status: 404, body: graph_error('Request_ResourceNotFound', 'Resource does not exist.'))
      expect(run_action({ assignment_id: assignment_id })['existed']).to eq(false)
    end

    it 'fails with no request when the assignment id is a dot segment' do
      expect { run_action({ assignment_id: '..' }) }
        .to raise_error(IPaaS::Job::FailJob, "Assignment ID '..' is not a valid id.")
      expect(a_request(:delete, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'names RoleManagement.ReadWrite.Directory on 403' do
      stub_delete(status: 403, body: access_denied.to_json)
      expect { run_action({ assignment_id: assignment_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: RoleManagement.ReadWrite.Directory. ' \
                                'Admin consent is required.'))
    end
  end
end
