require 'spec_helper'

describe 'Microsoft Outlook Outbound Connection', :outbound_connection, :microsoft_outlook do
  describe 'validation' do
    it 'is valid with all credentials and a default mailbox provided' do
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'requires tenant_id' do
      outbound_connection_config[:credentials].delete(:tenant_id)
      expect(outbound_connection).not_to be_valid
    end

    it 'requires client_id' do
      outbound_connection_config[:credentials].delete(:client_id)
      expect(outbound_connection).not_to be_valid
    end

    it 'requires client_secret' do
      outbound_connection_config[:credentials].delete(:client_secret)
      expect(outbound_connection).not_to be_valid
    end

    it 'requires default_mailbox' do
      outbound_connection_config.delete(:default_mailbox)
      expect(outbound_connection).not_to be_valid
    end
  end

  describe 'authenticate' do
    let(:request) do
      Faraday::Request.create(:get) do |req|
        req.headers = {}
      end
    end

    it 'requests a token from the tenant-specific endpoint and sets the Authorization header' do
      token_stub = stub_graph_token(access_token: 'abc123')

      outbound_connection.authenticate_request(request)

      expect(request.headers['Authorization']).to eq('Bearer abc123')
      expect(token_stub).to have_been_requested.once
    end

    it 'requests the client credentials scope for Microsoft Graph' do
      token_stub = stub_graph_token
                   .with(body: hash_including('scope' => 'https://graph.microsoft.com/.default',
                                              'grant_type' => 'client_credentials'))

      outbound_connection.authenticate_request(request)

      expect(token_stub).to have_been_requested.once
    end

    it 'raises CustomerCredentialsError when the tenant rejects the client credentials' do
      stub_graph_token(status: 401)

      expect { outbound_connection.authenticate_request(request) }
        .to raise_error(IPaaS::Job::Outbound::CustomerCredentialsError)
    end
  end

  describe 'config_tester' do
    let(:inbox_url) { "https://graph.microsoft.com/v1.0/users/#{default_mailbox}/mailFolders/inbox" }

    it 'returns success when Microsoft Graph accepts the credentials and the mailbox resolves' do
      stub_graph_token
      stub_request(:get, inbox_url).to_return(status: 200, body: { id: 'inbox-id' }.to_json)

      result = outbound_connection.config_tester
      expect(result).to eq(
        { status: :success,
          message: "Connection successful. Default mailbox '#{default_mailbox}' is reachable with Mail.Read access.", },
      )
    end

    it 'returns failed when Microsoft Graph rejects the token' do
      stub_graph_token
      stub_request(:get, inbox_url).to_return(status: 401, body: '')

      result = outbound_connection.config_tester
      expect(result).to eq({ status: :failed, message: 'Microsoft Graph rejected the credentials (HTTP 401).' })
    end

    it 'returns failed when the tenant rejects the client credentials at the token endpoint' do
      stub_graph_token(status: 401)

      result = outbound_connection.config_tester
      expect(result[:status]).to eq(:failed)
    end

    it 'returns failed when the default mailbox is not found' do
      stub_graph_token
      stub_request(:get, inbox_url).to_return(status: 404, body: '')

      result = outbound_connection.config_tester
      expect(result).to eq(
        { status: :failed, message: "Mailbox '#{default_mailbox}' was not found. Check the Default mailbox address." },
      )
    end

    it 'returns error on unexpected responses' do
      stub_graph_token
      stub_request(:get, inbox_url).to_return(status: 500, body: 'boom')

      result = outbound_connection.config_tester
      expect(result).to eq({ status: :error, message: "Unable to reach Microsoft Graph (HTTP 500): 'boom'" })
    end

    it 'returns error when an unexpected exception is raised' do
      stub_graph_token
      allow(outbound_connection).to receive(:http_get).and_raise(StandardError, 'kaboom')

      result = outbound_connection.config_tester
      expect(result).to eq({ status: :error, message: 'kaboom' })
    end
  end
end
