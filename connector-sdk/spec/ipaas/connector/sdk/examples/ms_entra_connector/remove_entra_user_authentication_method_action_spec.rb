require 'spec_helper'

describe 'Microsoft Entra Remove User Authentication Method Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c904-396c-701c-8eb9-96b9b41ebbc6' }
  let(:phone_method_id) { '3179e48a-750b-4051-897c-87b9720928f7' }
  let(:phone_type) { '#microsoft.graph.phoneAuthenticationMethod' }
  let(:phone_url) { "#{graph}/users/#{user_id}/authentication/phoneMethods/#{phone_method_id}" }

  def stub_delete(url = phone_url, status: 204, body: '')
    stub_request(:delete, url).to_return(status: status, body: body)
  end

  def remove_input(overrides = {})
    { user_id: user_id, method_id: phone_method_id, method_type: phone_type }.merge(overrides)
  end

  describe 'input_schema' do
    it 'requires the user id, the method id and the method type' do
      schema = action.input_schema
      expect(schema.field(:user_id).required).to be_truthy
      expect(schema.field(:method_id).required).to be_truthy
      expect(schema.field(:method_type).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the user id, the method id and whether it existed' do
      schema = action.output_schema.first
      expect(schema.field(:method_id).required).to be_truthy
      expect(schema.field(:existed).type).to eq(:boolean)
    end
  end

  describe 'run' do
    it 'deletes a phone method through the phone methods path and reports it existed on 204' do
      stub = stub_delete
      expect(run_action(remove_input)).to eq('user_id' => user_id, 'method_id' => phone_method_id, 'existed' => true)
      expect(stub).to have_been_requested.once
    end

    it 'deletes a Microsoft Authenticator method through its own path with the method id escaped' do
      url = "#{graph}/users/#{user_id}/authentication/microsoftAuthenticatorMethods/abc%2Fdef"
      stub = stub_delete(url)
      run_action(remove_input(method_id: 'abc/def',
                              method_type: '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'))
      expect(stub).to have_been_requested.once
    end

    it 'deletes a FIDO2 security key through the fido2Methods path' do
      stub = stub_delete("#{graph}/users/#{user_id}/authentication/fido2Methods/key-1")
      run_action(remove_input(method_id: 'key-1', method_type: '#microsoft.graph.fido2AuthenticationMethod'))
      expect(stub).to have_been_requested.once
    end

    it 'deletes a software OATH token through the softwareOathMethods path' do
      stub = stub_delete("#{graph}/users/#{user_id}/authentication/softwareOathMethods/oath-1")
      run_action(remove_input(method_id: 'oath-1', method_type: '#microsoft.graph.softwareOathAuthenticationMethod'))
      expect(stub).to have_been_requested.once
    end

    it 'deletes an email method through the emailMethods path' do
      stub = stub_delete("#{graph}/users/#{user_id}/authentication/emailMethods/email-1")
      run_action(remove_input(method_id: 'email-1', method_type: '#microsoft.graph.emailAuthenticationMethod'))
      expect(stub).to have_been_requested.once
    end

    it 'deletes a Temporary Access Pass through the temporaryAccessPassMethods path' do
      stub = stub_delete("#{graph}/users/#{user_id}/authentication/temporaryAccessPassMethods/tap-1")
      run_action(remove_input(method_id: 'tap-1',
                              method_type: '#microsoft.graph.temporaryAccessPassAuthenticationMethod'))
      expect(stub).to have_been_requested.once
    end

    it 'deletes a Windows Hello for Business method through the windowsHelloForBusinessMethods path' do
      stub = stub_delete("#{graph}/users/#{user_id}/authentication/windowsHelloForBusinessMethods/hello-1")
      run_action(remove_input(method_id: 'hello-1',
                              method_type: '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod'))
      expect(stub).to have_been_requested.once
    end

    it 'deletes a platform credential through the platformCredentialMethods path' do
      stub = stub_delete("#{graph}/users/#{user_id}/authentication/platformCredentialMethods/mac-1")
      run_action(remove_input(method_id: 'mac-1',
                              method_type: '#microsoft.graph.platformCredentialAuthenticationMethod'))
      expect(stub).to have_been_requested.once
    end

    it 'deletes an external authentication method through its $ref path' do
      stub = stub_delete("#{graph}/users/#{user_id}/authentication/externalAuthenticationMethods/external-1/$ref")
      run_action(remove_input(method_id: 'external-1', method_type: '#microsoft.graph.externalAuthenticationMethod'))
      expect(stub).to have_been_requested.once
    end

    it 'deletes a resource account key through the resourceAccountKeyAuthenticationMethods path' do
      stub = stub_delete("#{graph}/users/#{user_id}/authentication/resourceAccountKeyAuthenticationMethods/key-2")
      run_action(remove_input(method_id: 'key-2',
                              method_type: '#microsoft.graph.resourceAccountKeyAuthenticationMethod'))
      expect(stub).to have_been_requested.once
    end

    it 'reports existed false on 404' do
      stub_delete(status: 404, body: graph_error('NotFound', 'Not found'))
      expect(run_action(remove_input)['existed']).to eq(false)
    end

    it 'refuses the password method with no request' do
      expect { run_action(remove_input(method_type: '#microsoft.graph.passwordAuthenticationMethod')) }
        .to raise_error(IPaaS::Job::FailJob,
                        'The password cannot be removed. Change it with Reset Entra user password.')
      expect(a_request(:delete, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'refuses an unknown method type with no request' do
      expect { run_action(remove_input(method_type: 'phoneAuthenticationMethod')) }
        .to raise_error(IPaaS::Job::FailJob, start_with("Method type 'phoneAuthenticationMethod' cannot be removed " \
                                                        'by this action. Use one of #microsoft.graph.'))
      expect(a_request(:delete, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'names UserAuthenticationMethod.ReadWrite.All on 403' do
      stub_delete(status: 403, body: access_denied.to_json)
      expect { run_action(remove_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: UserAuthenticationMethod.ReadWrite.All. ' \
                                'Admin consent is required.'))
    end
  end
end
