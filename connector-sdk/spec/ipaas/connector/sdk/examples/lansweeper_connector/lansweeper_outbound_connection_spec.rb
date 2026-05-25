require 'spec_helper'

describe 'Lansweeper Connection', :outbound_connection do
  let(:connector_id) { '019b22da-f781-7c72-b3c6-5e796a404308' }

  let(:outbound_connection_config) do
    {
      credentials: {
        client_id: 'test-client-id',
        client_secret: make_secret_string('test-secret'),
        refresh_token: make_secret_string('test-refresh-token'),
      },
    }
  end

  describe 'validation' do
    it 'client_id is required' do
      outbound_connection_config[:credentials].delete(:client_id)
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
    end

    it 'client_secret is required' do
      outbound_connection_config[:credentials].delete(:client_secret)
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
    end

    it 'refresh_token is required' do
      outbound_connection_config[:credentials].delete(:refresh_token)
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
    end
  end
end
