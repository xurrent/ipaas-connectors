require 'spec_helper'

describe 'Microsoft Entra Add Member To Group Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-7138-b3bf-ca8fb41fd9b4' }
  let(:members_ref_url) { "#{graph}/groups/#{group_id}/members/$ref" }

  def stub_add(status: 204, body: '')
    stub_request(:post, members_ref_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body)
  end

  def add_input
    { group_id: group_id, member_id: user_id }
  end

  def record_log
    output = StringIO.new
    action(add_input).logger = Logger.new(output)
    output
  end

  def already_member_line
    "Object #{user_id} is already a member of group #{group_id}, so nothing changed."
  end

  describe 'input_schema' do
    it 'requires the group id and the member id' do
      expect(action.input_schema.field(:group_id).required).to be_truthy
      expect(action.input_schema.field(:member_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the group id, the member id and whether the object was already a member' do
      schema = action.output_schema.first
      expect(schema.field(:group_id).required).to be_truthy
      expect(schema.field(:member_id).required).to be_truthy
      expect(schema.field(:already_member).type).to eq(:boolean)
    end
  end

  describe 'run' do
    it 'posts the member as a directory object reference' do
      stub_add
      run_action(add_input)
      expect(@sent).to eq('@odata.id' => "https://graph.microsoft.com/v1.0/directoryObjects/#{user_id}")
    end

    it 'returns the group id, the member id and already_member false on 204' do
      stub_add
      output = run_action(add_input)
      expect(output).to eq('group_id' => group_id, 'member_id' => user_id, 'already_member' => false)
    end

    it 'succeeds with already_member true on the 400 that says the object is already a member' do
      message = 'One or more added object references already exist for the following modified properties: ' \
                "'members'."
      stub_add(status: 400, body: graph_error('Request_BadRequest', message))
      output = run_action(add_input)
      expect(output).to eq('group_id' => group_id, 'member_id' => user_id, 'already_member' => true)
    end

    it 'logs that nothing changed when the object is already a member' do
      message = 'One or more added object references already exist for the following modified properties: ' \
                "'members'."
      stub_add(status: 400, body: graph_error('Request_BadRequest', message))
      logged = record_log
      run_action(add_input)
      expect(logged.string).to include(already_member_line)
    end

    it 'logs no existing member when Microsoft Graph adds the object' do
      stub_add
      logged = record_log
      run_action(add_input)
      expect(logged.string).not_to include(already_member_line)
    end

    it 'fails on a 400 that says the object is already a member under an error code other than Request_BadRequest' do
      message = 'One or more added object references already exist for the following modified properties: ' \
                "'members'."
      stub_add(status: 400, body: graph_error('Request_UnsupportedQuery', message))
      expect { run_action(add_input) }
        .to raise_error(IPaaS::Job::FailJob, "Microsoft Graph returned HTTP 400 Request_UnsupportedQuery: #{message}")
    end

    it 'fails with the Graph message on a 400 that does not say the object is already a member' do
      message = "Invalid object identifier '#{user_id}'."
      stub_add(status: 400, body: graph_error('Request_BadRequest', message))
      expect { run_action(add_input) }
        .to raise_error(IPaaS::Job::FailJob, "Microsoft Graph returned HTTP 400 Request_BadRequest: #{message}")
    end

    it 'fails with no request when the member id is not a GUID' do
      expect { run_action({ group_id: group_id, member_id: 'adele@contoso.com' }) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Member ID 'adele@contoso.com' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'names GroupMember.ReadWrite.All, Device.ReadWrite.All for a device, and the role permission on 403' do
      permission = 'GroupMember.ReadWrite.All (adding a device also needs Device.ReadWrite.All, and ' \
                   'a group that can be assigned to a role also needs RoleManagement.ReadWrite.Directory)'
      stub_add(status: 403, body: access_denied.to_json)
      expect { run_action(add_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        /Permission this action needs: #{Regexp.escape(permission)}\. Admin consent is required\./)
    end
  end
end
