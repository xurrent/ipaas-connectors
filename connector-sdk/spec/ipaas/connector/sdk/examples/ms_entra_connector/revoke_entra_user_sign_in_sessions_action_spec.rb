require 'spec_helper'

describe 'Microsoft Entra Revoke User Sign-in Sessions Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-7957-8f3e-8d470af6b22f' }
  let(:revoke_url) { "#{graph}/users/#{user_id}/revokeSignInSessions" }

  def stub_revoke(status: 200, body: { value: true }.to_json)
    stub_request(:post, revoke_url).to_return(status: status, body: body,
                                              headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'defines a required user id string' do
      expect(action.input_schema.field(:user_id).type).to eq(:string)
      expect(action.input_schema.field(:user_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'defines a required user id and a required revoked boolean' do
      schema = action.output_schema.first
      expect(schema.field(:user_id).required).to be_truthy
      expect(schema.field(:revoked).type).to eq(:boolean)
      expect(schema.field(:revoked).required).to be_truthy
    end
  end

  describe 'run' do
    it 'posts to the revoke sign-in sessions endpoint of the user' do
      stub_revoke
      run_action({ user_id: user_id })
      expect(a_request(:post, revoke_url)).to have_been_made.once
    end

    it 'reports the sessions as revoked when Graph answers value true' do
      stub_revoke
      expect(run_action({ user_id: user_id })).to eq('user_id' => user_id, 'revoked' => true)
    end

    it 'reports the sessions as not revoked when Graph answers value false' do
      stub_revoke(body: { value: false }.to_json)
      expect(run_action({ user_id: user_id })).to eq('user_id' => user_id, 'revoked' => false)
    end

    it 'fails naming User.RevokeSessions.All when Graph answers 403' do
      stub_revoke(status: 403, body: access_denied.to_json)
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        /Permission this action needs: User\.RevokeSessions\.All\. Admin consent is required\./)
    end
  end
end
