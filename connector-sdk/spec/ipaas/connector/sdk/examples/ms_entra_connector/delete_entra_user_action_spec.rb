require 'spec_helper'

describe 'Microsoft Entra Delete User Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-71ed-a4ea-6f92cb341908' }
  let(:user_url) { "#{graph}/users/#{user_id}" }

  def stub_delete(status: 204, body: '')
    stub_request(:delete, user_url).to_return(status: status, body: body,
                                              headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'defines a required user id string' do
      expect(action.input_schema.field(:user_id).type).to eq(:string)
      expect(action.input_schema.field(:user_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'defines a required user id and a required existed boolean' do
      schema = action.output_schema.first
      expect(schema.field(:user_id).required).to be_truthy
      expect(schema.field(:existed).type).to eq(:boolean)
      expect(schema.field(:existed).required).to be_truthy
    end
  end

  describe 'run' do
    it 'sends a delete for the user' do
      stub_delete
      run_action({ user_id: user_id })
      expect(a_request(:delete, user_url)).to have_been_made.once
    end

    it 'reports that the user existed when Graph answers 204' do
      stub_delete
      expect(run_action({ user_id: user_id })).to eq('user_id' => user_id, 'existed' => true)
    end

    it 'reports that the user did not exist when Graph answers 404' do
      stub_delete(status: 404, body: graph_error('Request_ResourceNotFound', 'Resource does not exist.'))
      expect(run_action({ user_id: user_id })).to eq('user_id' => user_id, 'existed' => false)
    end

    it 'fails naming User.ReadWrite.All when Graph answers 403' do
      stub_delete(status: 403, body: access_denied.to_json)
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 403 Authorization_RequestDenied: Insufficient privileges. ' \
                        'Permission this action needs: User.ReadWrite.All. Admin consent is required.')
    end
  end
end
