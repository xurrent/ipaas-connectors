require 'spec_helper'

describe 'Microsoft Entra Search Transitive Group Members Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-792d-bd1a-c75b96378489' }
  let(:members_url) { "#{graph}/groups/#{group_id}/transitiveMembers" }
  let(:foreign_link) { 'https://graph.example.com/v1.0/groups/next?$skiptoken=abc' }

  let(:graph_members) do
    [
      { '@odata.type' => '#microsoft.graph.user', id: user_id, displayName: 'Adele Vance',
        userPrincipalName: 'adele@contoso.com', mail: 'adele@contoso.com', },
      { '@odata.type' => '#microsoft.graph.group', id: '6e1d2c3b-4a5f-4e6d-8c7b-9a0f1e2d3c04',
        displayName: 'Falcon leads', },
    ]
  end

  def page_body(value: graph_members, next_link: nil)
    body = { '@odata.count' => value.length, value: value }
    body['@odata.nextLink'] = next_link if next_link
    body.to_json
  end

  def stub_members(url = members_url, status: 200, body: page_body)
    stub_request(:get, url)
      .with(query: hash_including({}))
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'requires the group id' do
      expect(action.input_schema.field(:group_id).required).to be_truthy
    end

    it 'offers All, Users, Groups and Devices as member types and defaults to All' do
      action.input_schema.field(:member_type).tap do |field|
        expect(field.enumeration.pluck(:id)).to eq(%w[All Users Groups Devices])
        expect(field.default).to eq('All')
      end
    end

    it 'defines an optional page size from 1 to 999 that defaults to 100' do
      action.input_schema.field(:page_size).tap do |field|
        expect(field.visibility).to eq('optional')
        expect(field.min).to eq(1)
        expect(field.max).to eq(999)
        expect(field.default).to eq(100)
      end
    end
  end

  describe 'output_schema' do
    it 'only has the page output schema' do
      expect(action.output_schema.map(&:reference)).to contain_exactly('page')
    end

    it 'returns members as a nested array with a required member id' do
      members = action.output_schema.first.field(:members)
      expect(members.array).to eq(true)
      expect(members.field(:member_id).required).to be_truthy
    end

    it 'keeps the next link in a required iteration state field' do
      expect(action.iteration_state_schema.field(:odata_nextLink).required).to be_truthy
    end
  end

  describe 'the request it sends' do
    it 'lists all transitive members with no type cast' do
      stub = stub_members
      run_action({ group_id: group_id })
      expect(stub).to have_been_requested.once
    end

    it 'lists all transitive members with no type cast when the member type is empty' do
      stub = stub_members
      run_action({ group_id: group_id, member_type: '' })
      expect(stub).to have_been_requested.once
    end

    it 'casts to users when the member type is Users' do
      stub = stub_members("#{members_url}/microsoft.graph.user")
      run_action({ group_id: group_id, member_type: 'Users' })
      expect(stub).to have_been_requested.once
    end

    it 'casts to groups when the member type is Groups' do
      stub = stub_members("#{members_url}/microsoft.graph.group")
      run_action({ group_id: group_id, member_type: 'Groups' })
      expect(stub).to have_been_requested.once
    end

    it 'casts to devices when the member type is Devices' do
      stub = stub_members("#{members_url}/microsoft.graph.device")
      run_action({ group_id: group_id, member_type: 'Devices' })
      expect(stub).to have_been_requested.once
    end

    it 'gives each member the type of the cast when Microsoft Graph leaves @odata.type out' do
      stub_members("#{members_url}/microsoft.graph.user", body: page_body(value: [{ id: user_id }]))
      output = run_action({ group_id: group_id, member_type: 'Users' })
      expect(output['members'].first['odata_type']).to eq('#microsoft.graph.user')
    end

    it 'gives no type when Microsoft Graph leaves @odata.type out and no cast was asked for' do
      stub_members(body: page_body(value: [{ id: user_id }]))
      expect(run_action({ group_id: group_id })['members'].first['odata_type']).to be_nil
    end

    it 'sends ConsistencyLevel eventual and asks for the count' do
      stub_members
      run_action({ group_id: group_id })
      expect(a_request(:get, members_url)
        .with(query: hash_including('$count' => 'true', '$top' => '100'),
              headers: { 'ConsistencyLevel' => 'eventual' })).to have_been_made.once
    end

    it 'searches the display name in quotes' do
      stub_members
      run_action({ group_id: group_id, search: 'Adele' })
      expect(a_request(:get, members_url)
        .with(query: hash_including('$search' => '"displayName:Adele"'))).to have_been_made.once
    end

    it 'sends no search parameter when no search text is set' do
      stub_members
      run_action({ group_id: group_id })
      expect(a_request(:get, members_url).with(query: hash_including('$search' => /.*/))).not_to have_been_made
    end
  end

  describe 'the answer' do
    it 'maps the members' do
      stub_members
      output = run_action({ group_id: group_id })
      expect(output['members']).to eq(
        [
          { 'member_id' => user_id, 'odata_type' => '#microsoft.graph.user', 'display_name' => 'Adele Vance',
            'user_principal_name' => 'adele@contoso.com', 'mail' => 'adele@contoso.com', },
          { 'member_id' => '6e1d2c3b-4a5f-4e6d-8c7b-9a0f1e2d3c04', 'odata_type' => '#microsoft.graph.group',
            'display_name' => 'Falcon leads', 'user_principal_name' => nil, 'mail' => nil, },
        ]
      )
    end

    it 'returns the count and no next page when Graph sends no next link' do
      stub_members
      output = run_action({ group_id: group_id })
      expect(output['odata_count']).to eq(2)
      expect(output['has_next_page']).to eq(false)
    end

    it 'fails when Graph answers with a next link on another host' do
      stub_members(body: page_body(next_link: foreign_link))
      expect { run_action({ group_id: group_id }) }
        .to raise_error(IPaaS::Job::FailJob, %r{next page link that is not on https://graph\.microsoft\.com/v1\.0})
    end

    it 'fails without a request when the stored next link is on another host' do
      stub_request(:get, /graph\.example\.com/).to_return(status: 200, body: page_body)
      action({ group_id: group_id }).send(:iteration_state_value=, { odata_nextLink: foreign_link })
      expect { run_action({ group_id: group_id }) }
        .to raise_error(IPaaS::Job::FailJob, /next page link that is not on/)
      expect(a_request(:get, /graph\.example\.com/)).not_to have_been_made
    end

    it 'names GroupMember.Read.All on 403' do
      stub_members(status: 403, body: access_denied.to_json)
      expect { run_action({ group_id: group_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        /Permission this action needs: GroupMember\.Read\.All\. Admin consent is required\./)
    end
  end
end
