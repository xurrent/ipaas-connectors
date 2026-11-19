require 'spec_helper'

describe 'Microsoft Entra List User Authentication Methods Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c904-3903-7545-ab54-e1c6d28bfc63' }
  let(:methods_url) { "#{graph}/users/#{user_id}/authentication/methods" }

  let(:listed_methods) do
    {
      value: [
        { '@odata.type' => '#microsoft.graph.phoneAuthenticationMethod', id: '3179e48a-750b-4051-897c-87b9720928f7',
          phoneNumber: '+1 5555551234', phoneType: 'mobile', smsSignInState: 'notSupported', },
        { '@odata.type' => '#microsoft.graph.fido2AuthenticationMethod', id: '-2_GRUg2-HYz6_1YG4YRAQ2',
          displayName: 'Red key', model: 'NFC key', },
        { '@odata.type' => '#microsoft.graph.emailAuthenticationMethod', id: '3ddfcfc8-9383-446f-83cc-3ab9be4be18f',
          emailAddress: 'adele@fabrikam.com', },
      ],
    }
  end

  def stub_list(status: 200, body: listed_methods.to_json)
    stub_request(:get, methods_url).to_return(status: status, body: body,
                                              headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'requires the user id' do
      expect(action.input_schema.field(:user_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the methods with a required method id' do
      methods = action.output_schema.first.field(:methods)
      expect(methods.array).to eq(true)
      expect(methods.field(:method_id).required).to be_truthy
    end
  end

  describe 'run' do
    it 'maps every method with its type and the fields of its kind' do
      stub_list
      expect(run_action({ user_id: user_id })[:methods]).to eq(
        [
          { 'method_id' => '3179e48a-750b-4051-897c-87b9720928f7',
            'odata_type' => '#microsoft.graph.phoneAuthenticationMethod', 'display_name' => nil,
            'phone_number' => '+1 5555551234', 'phone_type' => 'mobile', 'email_address' => nil, },
          { 'method_id' => '-2_GRUg2-HYz6_1YG4YRAQ2', 'odata_type' => '#microsoft.graph.fido2AuthenticationMethod',
            'display_name' => 'Red key', 'phone_number' => nil, 'phone_type' => nil, 'email_address' => nil, },
          { 'method_id' => '3ddfcfc8-9383-446f-83cc-3ab9be4be18f',
            'odata_type' => '#microsoft.graph.emailAuthenticationMethod', 'display_name' => nil,
            'phone_number' => nil, 'phone_type' => nil, 'email_address' => 'adele@fabrikam.com', },
        ]
      )
    end

    it 'returns no methods when the user has none' do
      stub_list(body: { value: [] }.to_json)
      expect(run_action({ user_id: user_id })[:methods]).to eq([])
    end

    it 'fails when Graph answers without a list' do
      stub_list(body: {}.to_json)
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph returned no list of authentication methods')
    end

    it 'names UserAuthenticationMethod.Read.All on 403' do
      stub_list(status: 403, body: access_denied.to_json)
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: UserAuthenticationMethod.Read.All. ' \
                                'Admin consent is required.'))
    end
  end
end
