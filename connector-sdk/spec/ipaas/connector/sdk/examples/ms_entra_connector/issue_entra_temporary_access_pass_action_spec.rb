require 'spec_helper'

describe 'Microsoft Entra Issue Temporary Access Pass Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c904-3890-7851-9792-dcdecb1e77d3' }
  let(:pass_url) { "#{graph}/users/#{user_id}/authentication/temporaryAccessPassMethods" }
  let(:pass_value) { '+drkzqAD' }

  let(:created_pass) do
    {
      '@odata.type' => '#microsoft.graph.temporaryAccessPassAuthenticationMethod',
      id: '6f1967b7-15e8-4935-ac26-d50770ed07a7', temporaryAccessPass: pass_value,
      createdDateTime: '2026-11-11T16:21:09Z', startDateTime: '2026-11-12T10:00:00Z', lifetimeInMinutes: 60,
      isUsableOnce: true, isUsable: false, methodUsabilityReason: 'NotYetValid',
    }
  end

  def stub_create(status: 201, body: created_pass.to_json)
    stub_request(:post, pass_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'requires the user id and limits the lifetime to the shortest and longest pass lifetime' do
      schema = action.input_schema
      expect(schema.field(:user_id).required).to be_truthy
      expect(schema.field(:lifetime_in_minutes).min).to eq(MsEntraConnector::MIN_TAP_LIFETIME_MINUTES)
      expect(schema.field(:lifetime_in_minutes).max).to eq(MsEntraConnector::MAX_TAP_LIFETIME_MINUTES)
    end
  end

  describe 'output_schema' do
    it 'returns the pass as a required secret string' do
      field = action.output_schema.first.field(:temporary_access_pass)
      expect(field.type).to eq(:secret_string)
      expect(field.required).to be_truthy
    end
  end

  describe 'run' do
    it 'posts an empty object when no option is set, and returns the pass as a secret string on 201' do
      stub_create
      output = run_action({ user_id: user_id })
      expect(@sent).to eq({})
      expect(output[:temporary_access_pass]).to be_a(IPaaS::Encryption::SecretString)
      expect(output[:temporary_access_pass].to_s).not_to eq(pass_value)
      expect(action.decrypt_secret_string(output[:temporary_access_pass])).to eq(pass_value)
      expect(output.except(:temporary_access_pass)).to include(
        'method_id' => '6f1967b7-15e8-4935-ac26-d50770ed07a7', 'lifetime_in_minutes' => 60,
        'is_usable_once' => true, 'is_usable' => false, 'method_usability_reason' => 'NotYetValid'
      )
    end

    it 'sends the lifetime, the one-use flag and the start time when they are set' do
      stub_create
      run_action({ user_id: user_id, lifetime_in_minutes: 60, is_usable_once: 'true',
                   start_date_time: '2026-11-12T10:00:00Z', })
      expect(@sent).to eq('lifetimeInMinutes' => 60, 'isUsableOnce' => true,
                          'startDateTime' => '2026-11-12T10:00:00+00:00')
    end

    it 'fails when Graph answers 201 without a pass' do
      stub_create(body: created_pass.except(:temporaryAccessPass).to_json)
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Error, 'Microsoft Graph returned no Temporary Access Pass')
    end

    it 'leaves the passcode out of the message when a 201 reply is cut short' do
      full_reply = created_pass.to_json
      cut_reply = full_reply[0, full_reply.index(pass_value) + pass_value.length]
      stub_create(body: cut_reply)
      expect(cut_reply).to include(pass_value)
      expect { run_action({ user_id: user_id }) }.to raise_error(
        IPaaS::Job::FailJob,
        'Microsoft Graph returned a reply that is not JSON: the reply is not shown because it can hold the ' \
        'Temporary Access Pass.'
      ) { |error| expect(error.message).not_to include(pass_value) }
    end

    it 'leaves the passcode out of the message when Graph answers 200 where 201 is expected' do
      stub_create(status: 200)
      expect { run_action({ user_id: user_id }) }.to raise_error(
        IPaaS::Job::FailJob,
        'Microsoft Graph returned HTTP 200 : the reply is not shown because it can hold the Temporary Access Pass'
      ) { |error| expect(error.message).not_to include(pass_value) }
    end

    it 'fails the job on 503 instead of retrying, because the pass may already exist' do
      stub = stub_create(status: 503, body: graph_error('serviceNotAvailable', 'Service unavailable'))
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 503 serviceNotAvailable: Service unavailable')
      expect(stub).to have_been_requested.once
    end

    it 'names UserAuthMethod-TAP.ReadWrite.All on 403' do
      stub_create(status: 403, body: access_denied.to_json)
      expect { run_action({ user_id: user_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: UserAuthMethod-TAP.ReadWrite.All. ' \
                                'Admin consent is required.'))
    end
  end
end
