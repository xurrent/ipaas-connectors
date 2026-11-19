require 'spec_helper'

describe 'Microsoft Entra Invite Guest User Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c904-3b1b-7c72-a388-e5932ade7ee9' }
  let(:invitations_url) { "#{graph}/invitations" }

  let(:invitation) do
    {
      id: '9071bfde-35e0-47d2-a582-d244ab1b4af6', inviteRedeemUrl: 'https://login.microsoftonline.com/redeem?rd=abc',
      invitedUserType: 'Guest', invitedUserEmailAddress: 'megan@fabrikam.com', status: 'PendingAcceptance',
      invitedUser: { id: 'cbb896f9-8306-49d0-b56b-b8e39cd28825' },
    }
  end

  def invite_input(overrides = {})
    { email_address: ' megan@fabrikam.com ', redirect_url: 'https://myapps.microsoft.com' }.merge(overrides)
  end

  def stub_invite(status: 201, body: invitation.to_json)
    stub_request(:post, invitations_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'requires the email address and the redirect url, and sends no email by default' do
      schema = action.input_schema
      expect(schema.field(:email_address).required).to be_truthy
      expect(schema.field(:redirect_url).required).to be_truthy
      expect(schema.field(:send_invitation_message).default).to eq(false)
    end
  end

  describe 'output_schema' do
    it 'returns a required invitation id and the guest user id' do
      schema = action.output_schema.first
      expect(schema.field(:invitation_id).required).to be_truthy
      expect(schema.field(:user_id).type).to eq(:string)
    end
  end

  describe 'run' do
    it 'posts the email address and redirect url with no email, and maps the invitation on 201' do
      stub_invite
      output = run_action(invite_input)
      expect(@sent).to eq('invitedUserEmailAddress' => 'megan@fabrikam.com',
                          'inviteRedirectUrl' => 'https://myapps.microsoft.com', 'sendInvitationMessage' => false)
      expect(output).to eq(
        'invitation_id' => '9071bfde-35e0-47d2-a582-d244ab1b4af6', 'user_id' => 'cbb896f9-8306-49d0-b56b-b8e39cd28825',
        'invite_redeem_url' => 'https://login.microsoftonline.com/redeem?rd=abc', 'status' => 'PendingAcceptance',
        'invited_user_type' => 'Guest'
      )
    end

    it 'sends the display name and asks Microsoft to send the email when they are set' do
      stub_invite
      run_action(invite_input(display_name: 'Megan Bowen', send_invitation_message: true))
      expect(@sent).to include('invitedUserDisplayName' => 'Megan Bowen', 'sendInvitationMessage' => true)
    end

    it 'returns no user id when Graph answers without the invited user' do
      stub_invite(body: invitation.except(:invitedUser).to_json)
      expect(run_action(invite_input)['user_id']).to be_nil
    end

    it 'fails the job on 503 instead of retrying, because the guest user may already exist' do
      stub = stub_invite(status: 503, body: graph_error('serviceNotAvailable', 'Service unavailable'))
      expect { run_action(invite_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 503 serviceNotAvailable: Service unavailable')
      expect(stub).to have_been_requested.once
    end

    it 'names User.Invite.All on 403' do
      stub_invite(status: 403, body: access_denied.to_json)
      expect { run_action(invite_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: User.Invite.All. Admin consent is required.'))
    end
  end
end
