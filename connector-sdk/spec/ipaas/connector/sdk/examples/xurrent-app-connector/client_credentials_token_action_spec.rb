require 'spec_helper'

describe 'Client Credentials Token Action', :action do
  let(:action_template_id) { '01946f7d-f7bd-789b-b718-4db4c8d71764' }

  let(:outbound_connection_config) do
    {
      credentials: {
        account_id: 'wdc',
        client_id: 'abc',
        client_secret: make_secret_string('def'),
      },
      environment: {
        stage: 'Demo',
        graphql_endpoint: 'https://graphql.example.com/graphql',
      },
    }
  end

  let(:sample_token) do
    {
      'oauth_application_nodeID' => 'dGVzdC5ob3N0L09hdXRoQXBwbGljYXRpb24vMQ',
      'client_id' => 'H3lzcY6Zgi80BbjIUbtyuzcI5j3wKmGavfDcOiS6vNiPbuxY',
      'client_secret' => make_secret_string('7IocHHKQKXiGIy'),
    }
  end

  def store_client_credentials_token(app_reference: 'weu_it_phone')
    customer_key = "customer_client_credentials_token/wdc/#{app_reference}"
    action.outbound_connection.store.write(customer_key, sample_token.to_json)
  end

  context 'using trigger output' do
    let(:action_input) { {} }

    before(:each) do
      store_client_credentials_token
      allow(runbook).to receive(:trigger_output).and_return(
        {
          customer_account_id: 'wdc',
          app_reference: 'weu_it_phone',
        }
      )
    end

    it 'should retrieve the client credentials token' do
      output = run_action
      expect(output[:oauth_application_nodeID]).to eq(sample_token['oauth_application_nodeID'])
      expect(output[:client_id]).to eq(sample_token['client_id'])
      expect(action.decrypt_secret_string(output[:client_secret])).to eq('7IocHHKQKXiGIy')
    end
  end

  context 'using action input' do
    let(:action_input) do
      {
        customer_account_id: 'wdc',
        app_reference: 'xurrent_sync',
      }
    end

    it 'should retrieve the client credentials token' do
      store_client_credentials_token(app_reference: action_input[:app_reference])
      output = run_action
      expect(output[:oauth_application_nodeID]).to eq(sample_token['oauth_application_nodeID'])
      expect(output[:client_id]).to eq(sample_token['client_id'])
      expect(action.decrypt_secret_string(output[:client_secret])).to eq('7IocHHKQKXiGIy')
    end
  end

  context 'using unknown app' do
    let(:action_input) do
      {
        customer_account_id: 'wdc',
        app_reference: 'foo_bar',
      }
    end

    it 'should return empty values when token is not stored' do
      output = run_action
      expect(output[:oauth_application_id]).to be_nil
      expect(output[:client_id]).to be_nil
      expect(output[:client_secret]).to be_nil
    end
  end
end
