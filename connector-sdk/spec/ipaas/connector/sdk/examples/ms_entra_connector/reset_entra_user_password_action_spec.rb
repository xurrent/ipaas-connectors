require 'spec_helper'

describe 'Microsoft Entra Reset User Password Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c904-3826-7215-b9e9-5462f1e399b6' }
  let(:user_url) { "#{graph}/users/#{user_id}" }
  let(:password) { 'new-first-password' }

  def stub_patch(url = user_url, status: 204, body: '')
    stub_request(:patch, url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'requires the user id and a secret password, and forces a change by default' do
      schema = action.input_schema
      expect(schema.field(:user_id).required).to be_truthy
      expect(schema.field(:password).required).to be_truthy
      expect(schema.field(:password).type).to eq(:secret_string)
      expect(schema.field(:force_change_password_next_sign_in).default).to eq(true)
    end
  end

  describe 'output_schema' do
    it 'returns the user id and whether a change is forced' do
      schema = action.output_schema.first
      expect(schema.field(:user_id).required).to be_truthy
      expect(schema.field(:force_change_password_next_sign_in).type).to eq(:boolean)
    end
  end

  describe 'run' do
    it 'patches only the password profile with the decrypted password and returns the user on 204' do
      stub_patch
      output = run_action({ user_id: user_id, password: make_secret_string(password) })
      expect(@sent).to eq('passwordProfile' => { 'password' => password, 'forceChangePasswordNextSignIn' => true })
      expect(output).to eq('user_id' => user_id, 'force_change_password_next_sign_in' => true)
      expect(output.to_json).not_to include(password)
    end

    it 'sends no forced change when the step sets it to false' do
      stub_patch
      output = run_action({ user_id: user_id, password: make_secret_string(password),
                            force_change_password_next_sign_in: false, })
      expect(@sent['passwordProfile']['forceChangePasswordNextSignIn']).to eq(false)
      expect(output['force_change_password_next_sign_in']).to eq(false)
    end

    it 'patches the user by user principal name when the user id is one' do
      upn_stub = stub_patch("#{graph}/users/adele.vance@contoso.com")
      output = run_action({ user_id: 'adele.vance@contoso.com', password: make_secret_string(password) })
      expect(upn_stub).to have_been_requested.once
      expect(output['user_id']).to eq('adele.vance@contoso.com')
    end

    it 'names User-PasswordProfile.ReadWrite.All and the User Administrator role on 403' do
      stub_patch(status: 403, body: access_denied.to_json)
      needed = 'Permission this action needs: User-PasswordProfile.ReadWrite.All (the app also needs at least ' \
               'the User Administrator role in Microsoft Entra). Admin consent is required.'
      expect { run_action({ user_id: user_id, password: make_secret_string(password) }) }
        .to raise_error(IPaaS::Job::FailJob, include(needed))
    end
  end
end
