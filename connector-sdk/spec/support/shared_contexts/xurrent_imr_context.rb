shared_context 'xurrent_imr', :xurrent_imr do
  let(:connector_id) { '019d6d9a-3230-7355-9268-3ec5c9ce502c' }
  let(:outbound_connection_config) do
    {
      credentials: {
        api_key: make_secret_string('test-api-key'),
      },
    }
  end
  let(:base_url) { 'https://www.zenduty.com' }
end
