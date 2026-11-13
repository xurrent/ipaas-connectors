require 'spec_helper'

describe 'endoflife.date outbound connection', :outbound_connection, :endoflife_date do
  describe 'validation' do
    it 'is valid without any configuration, because the API is public' do
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end
  end

  describe 'config_tester' do
    it 'provides the config_tester feature' do
      expect(outbound_connection.config_tester?).to be true
    end

    it 'reports success when the API index answers' do
      stub_eol('/', body: eol_body([], total: 3))
      expect(outbound_connection.config_tester)
        .to eq({ status: :success, message: 'Connection successful. The endoflife.date API is reachable.' })
    end

    it 'reports failed when endoflife.date is rate limiting' do
      stub_eol('/', status: 429)
      expect(outbound_connection.config_tester)
        .to eq({ status: :failed, message: 'endoflife.date is rate limiting requests (HTTP 429). Try again shortly.' })
    end

    it 'reports error on any other status' do
      stub_eol('/', status: 500, body: 'boom')
      expect(outbound_connection.config_tester)
        .to eq({ status: :error, message: 'endoflife.date API check failed (HTTP 500).' })
    end
  end
end
