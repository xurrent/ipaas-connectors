require 'spec_helper'

describe 'N-Central Register PSA User Action', :action do
  let(:action_template_id) { '01970d2a-8760-7251-a9d6-6bfc884d39cd' }

  context 'input_schema' do
    it 'requires user_name' do
      expect(action.input_schema.field(:user_name).required).to be_truthy
    end

    it 'makes psa_generate_ticket_runbook optional' do
      expect(action.input_schema.field(:psa_generate_ticket_runbook).required).to be_falsey
    end
  end

  context 'run' do
    let(:user_name) { 'customer1' }

    context 'without runbook' do
      let(:action_input) do
        {
          user_name: user_name,
        }
      end

      it 'generates and stores credentials' do
        expect(outbound_connection.store).to receive(:write)
          .with("secret##{user_name}", instance_of(IPaaS::Encryption::SecretString))

        output = run_action
        expect(output[:user_name]).to eq(user_name)
        expect(encryptor.decrypt(output[:password]).length).to eq(SecureRandom.uuid.length)
        expect(output[:base_endpoint_url]).to be_nil
        expect(output[:ticketing_endpoint]).to be_nil
      end
    end

    context 'with runbook' do
      let(:psa_generate_ticket_runbook) do
        IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7).tap do |runbook|
          allow(runbook).to receive(:endpoint) { 'https://example.com/inbound/1/abc/def' }
        end
      end

      let(:action_input) do
        {
          user_name: user_name,
          psa_generate_ticket_runbook: psa_generate_ticket_runbook,
        }
      end

      it 'includes endpoint information' do
        expect(outbound_connection.store).to receive(:write)
          .with("secret##{user_name}", instance_of(IPaaS::Encryption::SecretString))

        output = run_action
        expect(output[:user_name]).to eq(user_name)
        expect(encryptor.decrypt(output[:password]).length).to eq(SecureRandom.uuid.length)
        expect(output[:base_endpoint_url]).to eq('https://example.com')
        expect(output[:ticketing_endpoint]).to eq('/inbound/1/abc/def')
      end
    end
  end
end
