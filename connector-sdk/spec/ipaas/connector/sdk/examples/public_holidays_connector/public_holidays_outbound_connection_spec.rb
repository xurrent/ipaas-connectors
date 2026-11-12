require 'spec_helper'

describe 'Public Holidays Outbound Connection', :outbound_connection, :public_holidays do
  let(:countries_url) { "#{base_url}/api/v3/AvailableCountries" }

  describe 'config_schema' do
    it 'requires a Base URL that defaults to Nager.Date' do
      field = outbound_connection.config_schema.field(:base_url)
      expect([field.type, field.required, field.default]).to eq([:uri, true, 'https://date.nager.at'])
    end

    it 'accepts the Base URL' do
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'refuses a Base URL without a scheme' do
      outbound_connection_config[:base_url] = 'date.nager.at'
      expect(outbound_connection).not_to be_valid
    end
  end

  describe 'config_tester' do
    it 'counts the available countries' do
      stub_request(:get, countries_url).to_return(
        status: 200,
        body: [{ countryCode: 'NL', name: 'Netherlands' }, { countryCode: 'US', name: 'United States' }].to_json
      )
      expect(outbound_connection.config_tester)
        .to eq({ status: :success, message: 'Connected to Nager.Date: 2 countries available.' })
    end

    it 'reports any other status as error with the response body' do
      stub_request(:get, countries_url).to_return(status: 502, body: 'Bad Gateway')
      expect(outbound_connection.config_tester)
        .to eq({ status: :error, message: 'Nager.Date connection check failed (HTTP 502): Bad Gateway' })
    end

    it 'strips trailing slashes from the Base URL' do
      outbound_connection_config[:base_url] = 'https://date.nager.at//'
      stub = stub_request(:get, countries_url).to_return(status: 200, body: '[]')
      outbound_connection.config_tester
      expect(stub).to have_been_requested
    end
  end
end
