def graphql_request_body(query, variables: nil, operation_name: nil, squeeze_query_whitespace: true)
  query_to_send = query
  if squeeze_query_whitespace
    query_to_send = query_to_send.gsub(/\s+/, ' ').strip
  end
  { query: query_to_send }.tap do |body|
    body[:variables] = variables if variables.present?
    body[:operationName] = operation_name if operation_name.present?
  end
end
