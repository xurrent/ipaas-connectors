require 'spec_helper'

describe 'Microsoft Entra Update Group Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-7bd0-a77f-f0ccf831d3ce' }
  let(:group_url) { "#{graph}/groups/#{group_id}" }

  def stub_update(status: 204, body: '')
    stub_request(:patch, group_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'requires only the group id' do
      expect(action.input_schema.field(:group_id).required).to be_truthy
      expect(action.input_schema.field(:display_name).required).to be_falsey
      expect(action.input_schema.field(:description).required).to be_falsey
    end
  end

  describe 'output_schema' do
    it 'returns the group id and the updated fields as a string array' do
      schema = action.output_schema.first
      expect(schema.field(:group_id).required).to be_truthy
      expect(schema.field(:updated_fields).array).to eq(true)
    end
  end

  describe 'run' do
    it 'patches only the fields that are set' do
      stub_update
      run_action({ group_id: group_id, description: 'Members of Project Falcon' })
      expect(@sent).to eq('description' => 'Members of Project Falcon')
    end

    it 'returns the Graph names of the fields it sent on 204' do
      stub_update
      output = run_action({ group_id: group_id, display_name: 'Falcon', mail_nickname: 'falcon' })
      expect(output).to eq('group_id' => group_id, 'updated_fields' => %w[displayName mailNickname])
    end

    it 'fails with no request when no field is set' do
      stub = stub_update
      expect { run_action({ group_id: group_id }) }
        .to raise_error(IPaaS::Job::FailJob, 'Set at least one field to update.')
      expect(stub).not_to have_been_requested
    end

    it 'fails with no request when the group id is not a GUID' do
      expect { run_action({ group_id: 'falcon', description: 'x' }) }
        .to raise_error(IPaaS::Job::FailJob, "Group ID 'falcon' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:patch, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'names Group.ReadWrite.All on 403' do
      stub_update(status: 403, body: access_denied.to_json)
      expect { run_action({ group_id: group_id, description: 'x' }) }
        .to raise_error(IPaaS::Job::FailJob,
                        /Permission this action needs: Group\.ReadWrite\.All\. Admin consent is required\./)
    end
  end
end
