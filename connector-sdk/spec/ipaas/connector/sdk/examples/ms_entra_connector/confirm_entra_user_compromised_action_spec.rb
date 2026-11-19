require 'spec_helper'

describe 'Microsoft Entra Confirm User Compromised Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c904-3d42-7a21-83c1-c08626f302c3' }
  let(:confirm_url) { "#{graph}/identityProtection/riskyUsers/confirmCompromised" }
  let(:other_user_id) { '20f91ec9-d140-4d90-9cd9-f618587a1471' }

  def stub_confirm(status: 204, body: '')
    stub_request(:post, confirm_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'requires a list of user ids' do
      field = action.input_schema.field(:user_ids)
      expect(field.required).to be_truthy
      expect(field.array).to eq(true)
    end
  end

  describe 'output_schema' do
    it 'returns the list of user ids' do
      expect(action.output_schema.first.field(:user_ids).array).to eq(true)
    end
  end

  describe 'run' do
    it 'posts the trimmed distinct user ids and returns them on 204' do
      stub_confirm
      output = run_action({ user_ids: [" #{user_id} ", other_user_id, user_id, ''] })
      expect(@sent).to eq('userIds' => [user_id, other_user_id])
      expect(output).to eq('user_ids' => [user_id, other_user_id])
    end

    it 'fails with no request when every user id is blank' do
      expect { run_action({ user_ids: [' '] }) }.to raise_error(IPaaS::Job::FailJob, 'Set at least one user ID.')
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails with no request when a user id is not a GUID' do
      expect { run_action({ user_ids: ['adele@contoso.com'] }) }
        .to raise_error(IPaaS::Job::FailJob, "User ID 'adele@contoso.com' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'names IdentityRiskyUser.ReadWrite.All and the Microsoft Entra ID P2 license on 403' do
      stub_confirm(status: 403, body: access_denied.to_json)
      expect { run_action({ user_ids: [user_id] }) }.to raise_error(
        IPaaS::Job::FailJob,
        'Microsoft Graph returned HTTP 403 Authorization_RequestDenied: Insufficient privileges. Permission this ' \
        'action needs: IdentityRiskyUser.ReadWrite.All (the tenant also needs a Microsoft Entra ID P2 license). ' \
        'Admin consent is required.'
      )
    end

    it 'keeps the license reason Microsoft Graph gives on 403 before the permission it needs' do
      stub_confirm(status: 403, body: graph_error('NoLicense', 'Your tenant is not licensed for this feature.'))
      expect { run_action({ user_ids: [user_id] }) }.to raise_error(
        IPaaS::Job::FailJob,
        'Microsoft Graph returned HTTP 403 NoLicense: Your tenant is not licensed for this feature. Permission ' \
        'this action needs: IdentityRiskyUser.ReadWrite.All (the tenant also needs a Microsoft Entra ID P2 ' \
        'license). Admin consent is required.'
      )
    end
  end
end
