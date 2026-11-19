require 'spec_helper'

describe 'Microsoft Entra Create Group Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-7155-9ff2-4b9f575c138e' }
  let(:groups_url) { "#{graph}/groups" }
  let(:owner_id) { '5f2c1a9e-3b7d-4c8e-9a1f-2d6b8e4c7a01' }
  let(:member_id) { 'a3e9d7c1-6b2f-4e8a-b5d4-9c1f7e2a3b02' }

  let(:created_group) do
    {
      id: group_id, displayName: 'Project Falcon', description: 'Falcon team', mailNickname: 'project-falcon',
      mail: nil, mailEnabled: false, securityEnabled: true, groupTypes: [], visibility: 'Private',
      isAssignableToRole: nil, createdDateTime: '2026-11-03T10:00:00Z',
    }
  end

  def guid(number)
    format('00000000-0000-4000-8000-%012d', number)
  end

  def directory_object(id)
    "#{graph}/directoryObjects/#{id}"
  end

  def group_input(overrides = {})
    { display_name: 'Project Falcon', mail_nickname: 'project-falcon' }.merge(overrides)
  end

  def stub_create(status: 201, body: created_group.to_json, headers: {})
    stub_request(:post, groups_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' }.merge(headers))
  end

  describe 'input_schema' do
    it 'requires the display name and the mail alias' do
      expect(action.input_schema.field(:display_name).required).to be_truthy
      expect(action.input_schema.field(:mail_nickname).required).to be_truthy
    end

    it 'offers Security and Microsoft 365 as group types and defaults to Security' do
      action.input_schema.field(:group_type).tap do |field|
        expect(field.enumeration.pluck(:id)).to eq(['Security', 'Microsoft 365'])
        expect(field.default).to eq('Security')
      end
    end

    it 'takes owner and member ids as string arrays' do
      expect(action.input_schema.field(:owner_ids).array).to eq(true)
      expect(action.input_schema.field(:member_ids).array).to eq(true)
    end
  end

  describe 'output_schema' do
    it 'returns the group with a required group id' do
      group = action.output_schema.first.field(:group)
      expect(group.type).to eq(:nested)
      expect(group.field(:group_id).required).to be_truthy
      expect(group.field(:group_types).array).to eq(true)
    end
  end

  describe 'the request it sends' do
    it 'posts a security group as not mail enabled, security enabled and with no group types' do
      stub_create
      run_action(group_input(group_type: 'Security'))
      expect(@sent).to include('mailEnabled' => false, 'securityEnabled' => true, 'groupTypes' => [])
    end

    it 'posts a Microsoft 365 group as mail enabled, not security enabled and Unified' do
      stub_create
      run_action(group_input(group_type: 'Microsoft 365'))
      expect(@sent).to include('mailEnabled' => true, 'securityEnabled' => false, 'groupTypes' => ['Unified'])
    end

    it 'sends the display name and mail alias' do
      stub_create
      run_action(group_input)
      expect(@sent).to include('displayName' => 'Project Falcon', 'mailNickname' => 'project-falcon')
    end

    it 'sends the description when it is set' do
      stub_create
      run_action(group_input(description: ' Falcon team '))
      expect(@sent['description']).to eq('Falcon team')
    end

    it 'sends the visibility when it is set' do
      stub_create
      run_action(group_input(visibility: 'Private'))
      expect(@sent['visibility']).to eq('Private')
    end

    it 'binds owners and members as directory object urls' do
      stub_create
      run_action(group_input(owner_ids: [owner_id], member_ids: [member_id]))
      expect(@sent['owners@odata.bind']).to eq([directory_object(owner_id)])
      expect(@sent['members@odata.bind']).to eq([directory_object(member_id)])
    end

    it 'sends no bind keys when no owner or member is set' do
      stub_create
      run_action(group_input)
      expect(@sent.keys).not_to include('owners@odata.bind', 'members@odata.bind')
    end

    it 'sends twenty owners and members together' do
      stub_create
      run_action(group_input(owner_ids: (1..10).map { |n| guid(n) }, member_ids: (11..20).map { |n| guid(n) }))
      expect(@sent['owners@odata.bind'].length + @sent['members@odata.bind'].length).to eq(20)
    end
  end

  describe 'input checks' do
    it 'fails with no request when owners and members together are twenty one' do
      stub = stub_create
      input = group_input(owner_ids: (1..10).map { |n| guid(n) }, member_ids: (11..21).map { |n| guid(n) })
      expect { run_action(input) }
        .to raise_error(IPaaS::Job::FailJob, /at most 20 owners and members together/)
      expect(stub).not_to have_been_requested
    end

    it 'fails with no request when an owner id is not a GUID' do
      stub = stub_create
      expect { run_action(group_input(owner_ids: ['adele@contoso.com'])) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Owner ID 'adele@contoso.com' is not a Microsoft Entra object id (a GUID).")
      expect(stub).not_to have_been_requested
    end
  end

  describe 'the answer' do
    it 'maps the created group on 201' do
      stub_create
      output = run_action(group_input)
      expect(output[:group]).to eq(
        'group_id' => group_id, 'display_name' => 'Project Falcon', 'description' => 'Falcon team',
        'mail_nickname' => 'project-falcon', 'mail' => nil, 'mail_enabled' => false, 'security_enabled' => true,
        'group_types' => [], 'visibility' => 'Private', 'is_assignable_to_role' => nil,
        'created_date_time' => '2026-11-03T10:00:00Z'
      )
    end

    it 'fails the job on 503 instead of retrying, because the group may already exist' do
      stub = stub_create(status: 503, body: graph_error('serviceNotAvailable', 'Service unavailable'))
      expect { run_action(group_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 503 serviceNotAvailable: Service unavailable')
      expect(stub).to have_been_requested.once
    end

    it 'reschedules the job on 429' do
      stub_create(status: 429, body: 'Too many requests', headers: { 'Retry-After' => '7' })
      expect { run_action(group_input) }.to raise_error(IPaaS::Job::RescheduleJob, /rate limit hit \(retry after: 7\)/)
    end

    it 'names Group.ReadWrite.All on 403' do
      stub_create(status: 403, body: access_denied.to_json)
      expect { run_action(group_input) }.to raise_error(
        IPaaS::Job::FailJob,
        'Microsoft Graph returned HTTP 403 Authorization_RequestDenied: Insufficient privileges. ' \
        'Permission this action needs: Group.ReadWrite.All. Admin consent is required.'
      )
    end
  end
end
