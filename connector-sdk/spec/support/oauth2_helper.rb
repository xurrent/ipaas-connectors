def stub_xurrent_oauth2_token(outbound_connection_config)
  url = outbound_connection_config[:environment][:oauth2_endpoint]
  if !url && outbound_connection_config[:environment][:stage] == 'Demo'
    url = 'https://oauth.xurrent-demo.com/token'
  elsif !url && outbound_connection_config[:environment][:stage] == 'QA'
    url = 'https://oauth.xurrent.qa/token'
  end

  body = {
    client_id: outbound_connection_config[:credentials][:client_id],
    client_secret: encryptor.decrypt(outbound_connection_config[:credentials][:client_secret]),
    grant_type: 'client_credentials',
  }
  store_oauth2_header(url, body, account_id: outbound_connection_config[:credentials][:account_id])
end

def store_oauth2_header(url, body, token: 'abc', **extra_params)
  cache_key = outbound_connection.send(:create_cache_key, url, body, **extra_params)
  outbound_connection.cache_write(cache_key,
                                  "Bearer #{token}",
                                  10_000_000)
end
