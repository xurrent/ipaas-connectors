require 'spec_helper'

describe 'Microsoft Entra Delete Group Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-7126-9e3b-d99a994d165a' }
  let(:group_url) { "#{graph}/groups/#{group_id}" }

  describe 'input_schema' do
    it 'requires the group id' do
      expect(action.input_schema.field(:group_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the group id and whether it existed' do
      schema = action.output_schema.first
      expect(schema.field(:group_id).required).to be_truthy
      expect(schema.field(:existed).type).to eq(:boolean)
    end
  end

  describe 'run' do
    it 'reports existed true on 204' do
      stub = stub_request(:delete, group_url).to_return(status: 204)
      output = run_action({ group_id: group_id })
      expect(output).to eq('group_id' => group_id, 'existed' => true)
      expect(stub).to have_been_requested.once
    end

    it 'reports existed false on 404' do
      stub_request(:delete, group_url)
        .to_return(status: 404, body: graph_error('Request_ResourceNotFound', 'Resource does not exist.'))
      output = run_action({ group_id: group_id })
      expect(output).to eq('group_id' => group_id, 'existed' => false)
    end

    it 'fails with no request when the group id is not a GUID' do
      expect { run_action({ group_id: 'falcon' }) }
        .to raise_error(IPaaS::Job::FailJob, "Group ID 'falcon' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:delete, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'names Group.ReadWrite.All, and the role permission unless the app owns the group, on 403' do
      permission = 'Group.ReadWrite.All (a group that can be assigned to a role also needs ' \
                   'RoleManagement.ReadWrite.Directory, unless the app owns the group)'
      stub_request(:delete, group_url).to_return(status: 403, body: access_denied.to_json)
      expect { run_action({ group_id: group_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        /Permission this action needs: #{Regexp.escape(permission)}\. Admin consent is required\./)
    end
  end
end
