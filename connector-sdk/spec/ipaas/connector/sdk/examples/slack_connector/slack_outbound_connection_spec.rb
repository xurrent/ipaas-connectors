require 'spec_helper'

describe 'Slack Outbound Connection', :outbound_connection do
  let(:connector_id) { '019d6e9d-90c5-724f-840b-13cb467ff342' }

  let(:outbound_connection_config) do
    {
      bearer: {
        bearer_token: make_secret_string('xoxb-test-token'),
      },
    }
  end

  describe 'authenticators' do
    it 'does not also register the shared bearer authenticator' do
      expect(connector.outbound_connection.authenticators).not_to include(:bearer)
    end
  end

  describe 'config_schema' do
    let(:field) { outbound_connection.config_schema.field(:bearer) }

    it 'labels the token group Slack bot token' do
      expect(field.label).to eq('Slack bot token')
    end

    it 'shows the token group on the form instead of behind the optional fields' do
      expect(field.visibility).to eq('visible')
    end

    it 'labels the token Bot token' do
      expect(field.field(:bearer_token).label).to eq('Bot token')
    end
  end

  describe 'validation' do
    it 'requires the Slack bot token' do
      outbound_connection_config.delete(:bearer)
      expect(outbound_connection).not_to be_valid
      expect(outbound_connection.full_error_messages).to include("Field 'bearer' is required")
    end
  end

  describe 'authenticate' do
    let(:request) do
      Faraday::Request.create(:get) do |req|
        req.headers = {}
      end
    end

    before { outbound_connection.authenticate_request(request) }

    it { expect(request.headers['Authorization']).to eq('Bearer xoxb-test-token') }

    context 'with different token' do
      let(:outbound_connection_config) do
        {
          bearer: {
            bearer_token: make_secret_string('xoxb-other-token'),
          },
        }
      end

      it { expect(request.headers['Authorization']).to eq('Bearer xoxb-other-token') }
    end

    context 'with whitespace pasted around the token' do
      let(:outbound_connection_config) do
        {
          bearer: {
            bearer_token: make_secret_string("  xoxb-padded-token \n"),
          },
        }
      end

      it 'sends the token without the whitespace' do
        expect(request.headers['Authorization']).to eq('Bearer xoxb-padded-token')
      end
    end
  end
end
