require 'spec_helper'

describe 'Microsoft Entra Add Group Owner Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c904-39d5-7f42-9276-6d9a336c442d' }
  let(:owners_ref_url) { "#{graph}/groups/#{group_id}/owners/$ref" }

  def stub_add(status: 204, body: '')
    stub_request(:post, owners_ref_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'requires the group id and the owner id' do
      expect(action.input_schema.field(:group_id).required).to be_truthy
      expect(action.input_schema.field(:owner_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the group id, the owner id and whether the object was already an owner' do
      schema = action.output_schema.first
      expect(schema.field(:group_id).required).to be_truthy
      expect(schema.field(:owner_id).required).to be_truthy
      expect(schema.field(:already_owner).type).to eq(:boolean)
    end
  end

  describe 'run' do
    it 'posts the owner as a directory object reference and returns both ids on 204' do
      stub_add
      output = run_action({ group_id: group_id, owner_id: user_id })
      expect(@sent).to eq('@odata.id' => "#{graph}/directoryObjects/#{user_id}")
      expect(output).to eq('group_id' => group_id, 'owner_id' => user_id, 'already_owner' => false)
    end

    it 'succeeds with already_owner true on the 400 that says the object is already an owner' do
      message = "One or more added object references already exist for the following modified properties: 'owners'."
      stub_add(status: 400, body: graph_error('Request_BadRequest', message))
      output = run_action({ group_id: group_id, owner_id: user_id })
      expect(output).to eq('group_id' => group_id, 'owner_id' => user_id, 'already_owner' => true)
    end

    it 'fails with the Graph message on a 400 that does not say the object is already an owner' do
      message = 'Invalid object identifier.'
      stub_add(status: 400, body: graph_error('Request_BadRequest', message))
      expect { run_action({ group_id: group_id, owner_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob, "Microsoft Graph returned HTTP 400 Request_BadRequest: #{message}")
    end

    it 'fails with no request when the owner id is not a GUID' do
      expect { run_action({ group_id: group_id, owner_id: 'adele@contoso.com' }) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Owner ID 'adele@contoso.com' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'names Group.ReadWrite.All on 403' do
      stub_add(status: 403, body: access_denied.to_json)
      expect { run_action({ group_id: group_id, owner_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        /Permission this action needs: Group\.ReadWrite\.All\. Admin consent is required\./)
    end
  end
end
