require 'spec_helper'

describe 'Microsoft Entra Get Group By ID Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-7203-a795-ae91d9efe502' }
  let(:group_url) { "#{graph}/groups/#{group_id}" }

  let(:graph_group) do
    {
      id: group_id, displayName: 'Project Falcon', description: 'Falcon team', mailNickname: 'project-falcon',
      mail: 'project-falcon@contoso.com', mailEnabled: true, securityEnabled: false, groupTypes: ['Unified'],
      visibility: 'Public', isAssignableToRole: true, createdDateTime: '2026-11-03T10:00:00Z',
    }
  end

  def stub_get(status: 200, body: graph_group.to_json)
    stub_request(:get, group_url)
      .with(query: { '$select' => MsEntraConnector::GROUP_SELECT })
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'requires the group id' do
      expect(action.input_schema.field(:group_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the group with a required group id' do
      group = action.output_schema.first.field(:group)
      expect(group.type).to eq(:nested)
      expect(group.field(:group_id).required).to be_truthy
    end
  end

  describe 'run' do
    it 'asks Graph for the group with the group select list' do
      stub = stub_get
      run_action({ group_id: group_id })
      expect(stub).to have_been_requested.once
    end

    it 'asks Graph whether the group can be assigned to a role' do
      stub_get
      run_action({ group_id: group_id })
      expect(a_request(:get, group_url).with(query: hash_including('$select' => /\bisAssignableToRole\b/)))
        .to have_been_made.once
    end

    it 'maps the group' do
      stub_get
      output = run_action({ group_id: group_id })
      expect(output['group']).to eq(
        'group_id' => group_id, 'display_name' => 'Project Falcon', 'description' => 'Falcon team',
        'mail_nickname' => 'project-falcon', 'mail' => 'project-falcon@contoso.com', 'mail_enabled' => true,
        'security_enabled' => false, 'group_types' => ['Unified'], 'visibility' => 'Public',
        'is_assignable_to_role' => true, 'created_date_time' => '2026-11-03T10:00:00Z'
      )
    end

    it 'fails with no request when the group id is not a GUID' do
      expect { run_action({ group_id: 'falcon' }) }
        .to raise_error(IPaaS::Job::FailJob, "Group ID 'falcon' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:get, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'names Group.Read.All on 403' do
      stub_get(status: 403, body: access_denied.to_json)
      expect { run_action({ group_id: group_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: Group.Read.All. Admin consent is required.'))
    end
  end
end
