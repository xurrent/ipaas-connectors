require 'spec_helper'

describe 'Microsoft Entra Remove Member From Group Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-7799-a9de-11a0c8bb324e' }
  let(:member_ref_url) { "#{graph}/groups/#{group_id}/members/#{user_id}/$ref" }
  let(:member_object_url) { "#{graph}/groups/#{group_id}/members/#{user_id}" }

  def remove_input
    { group_id: group_id, member_id: user_id }
  end

  def stub_remove_not_found
    stub_request(:delete, member_ref_url)
      .to_return(status: 404, body: graph_error('Request_ResourceNotFound', 'Resource does not exist.'))
  end

  def stub_group(status:, body:)
    stub_request(:get, "#{graph}/groups/#{group_id}").with(query: { '$select' => 'id' })
                                                     .to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'requires the group id and the member id' do
      expect(action.input_schema.field(:group_id).required).to be_truthy
      expect(action.input_schema.field(:member_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the group id, the member id and whether it was a member' do
      schema = action.output_schema.first
      expect(schema.field(:member_id).required).to be_truthy
      expect(schema.field(:existed).type).to eq(:boolean)
    end
  end

  describe 'run' do
    it 'deletes the membership reference, whose path ends with $ref' do
      stub = stub_request(:delete, member_ref_url).to_return(status: 204)
      run_action(remove_input)
      expect(stub).to have_been_requested.once
    end

    it 'never deletes the member path without $ref' do
      stub_request(:delete, member_ref_url).to_return(status: 204)
      stub_request(:delete, member_object_url).to_return(status: 204)
      run_action(remove_input)
      expect(a_request(:delete, member_object_url)).not_to have_been_made
    end

    it 'reports existed true on 204' do
      stub_request(:delete, member_ref_url).to_return(status: 204)
      output = run_action(remove_input)
      expect(output).to eq('group_id' => group_id, 'member_id' => user_id, 'existed' => true)
    end

    it 'reports existed false on 404 when the group exists' do
      stub_remove_not_found
      stub_group(status: 200, body: { id: group_id }.to_json)
      output = run_action(remove_input)
      expect(output).to eq('group_id' => group_id, 'member_id' => user_id, 'existed' => false)
    end

    it 'fails, naming the group, on 404 when Microsoft Graph has no group with that ID' do
      stub_remove_not_found
      stub_group(status: 404, body: graph_error('Request_ResourceNotFound', 'Resource does not exist.'))
      expect { run_action(remove_input) }
        .to raise_error(IPaaS::Job::FailJob, "Microsoft Graph has no group with ID #{group_id}.")
    end

    it 'names GroupMember.Read.All when the check of the group after a 404 answers 403' do
      stub_remove_not_found
      stub_group(status: 403, body: access_denied.to_json)
      expect { run_action(remove_input) }
        .to raise_error(IPaaS::Job::FailJob, /Permission this action needs: GroupMember\.Read\.All\./)
    end

    it 'does not read the group when the member is removed' do
      stub_request(:delete, member_ref_url).to_return(status: 204)
      run_action(remove_input)
      expect(a_request(:get, %r{/groups/#{group_id}})).not_to have_been_made
    end

    it 'fails with no request when the group id is not a GUID' do
      expect { run_action({ group_id: 'falcon', member_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob, "Group ID 'falcon' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:delete, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'names GroupMember.ReadWrite.All, and the role permission for a role-assignable group, on 403' do
      permission = 'GroupMember.ReadWrite.All (a group that can be assigned to a role also needs ' \
                   'RoleManagement.ReadWrite.Directory)'
      stub_request(:delete, member_ref_url).to_return(status: 403, body: access_denied.to_json)
      expect { run_action(remove_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        /Permission this action needs: #{Regexp.escape(permission)}\. Admin consent is required\./)
    end
  end
end
