module GraphqlIntrospectionHelper
  def graphql_connector_endpoint
    'https://api.example.com/graphql'
  end

  def graphql_connector_outbound_connection_config
    {
      graphql_endpoint: graphql_connector_endpoint,
      auth_type: 'bearer_token',
      bearer_token: { token: make_secret_string('test-token') },
      schema_source: 'introspection',
    }
  end

  def graphql_connector_response_headers
    {
      'content-type' => 'application/json',
      'x-request-id' => 'req-test-456',
    }
  end

  def stub_graphql_connector_introspection(endpoint: graphql_connector_endpoint)
    stub_request(:post, endpoint)
      .with { |req| req.body.include?('__schema') }
      .to_return(
        status: 200,
        body: { data: { __schema: graphql_connector_introspection_schema } }.to_json,
        headers: graphql_connector_response_headers,
      )
  end

  def stub_graphql_connector_query(query_pattern, response_data, endpoint: graphql_connector_endpoint,
                                   headers: graphql_connector_response_headers)
    stub_request(:post, endpoint)
      .with { |req| !req.body.include?('__schema') && req.body.match?(query_pattern) }
      .to_return(
        status: 200,
        body: { data: response_data }.to_json,
        headers: headers,
      )
  end

  def graphql_connector_introspection_schema
    {
      'queryType' => { 'name' => 'Query' },
      'mutationType' => { 'name' => 'Mutation' },
      'types' => [
        gql_query_type_def,
        gql_mutation_type_def,
        gql_user_connection_type_def,
        gql_user_type_def,
        gql_post_type_def,
        gql_page_info_type_def,
        gql_create_post_payload_type_def,
        gql_create_post_input_type_def,
        gql_update_user_payload_type_def,
        gql_update_user_input_type_def,
        gql_mutation_error_type_def,
        gql_user_status_enum_type_def,
      ],
    }
  end

  def gql_query_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'Query',
      'description' => nil,
      'fields' => [
        {
          'name' => 'users',
          'description' => 'List of users',
          'type' => { 'kind' => 'OBJECT', 'name' => 'UserConnection', 'ofType' => nil },
          'args' => [
            { 'name' => 'first', 'description' => nil,
              'type' => { 'kind' => 'SCALAR', 'name' => 'Int', 'ofType' => nil }, 'defaultValue' => nil, },
            { 'name' => 'after', 'description' => nil,
              'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil, },
            { 'name' => 'status', 'description' => nil,
              'type' => { 'kind' => 'ENUM', 'name' => 'UserStatus', 'ofType' => nil }, 'defaultValue' => nil, },
          ],
        },
        {
          'name' => 'viewer',
          'description' => 'Current viewer',
          'type' => { 'kind' => 'OBJECT', 'name' => 'User', 'ofType' => nil },
          'args' => [],
        },
        {
          'name' => 'posts',
          'description' => 'List of posts',
          'type' => { 'kind' => 'LIST', 'name' => nil,
                      'ofType' => { 'kind' => 'NON_NULL', 'name' => nil,
                                    'ofType' => { 'kind' => 'OBJECT', 'name' => 'Post', 'ofType' => nil } } },
          'args' => [
            { 'name' => 'status', 'description' => nil,
              'type' => { 'kind' => 'ENUM', 'name' => 'UserStatus', 'ofType' => nil }, 'defaultValue' => nil, },
          ],
        },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_mutation_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'Mutation',
      'description' => nil,
      'fields' => [
        {
          'name' => 'createPost',
          'description' => 'Create a post',
          'type' => { 'kind' => 'OBJECT', 'name' => 'CreatePostPayload', 'ofType' => nil },
          'args' => [
            {
              'name' => 'input',
              'description' => nil,
              'type' => { 'kind' => 'NON_NULL', 'name' => nil,
                          'ofType' => { 'kind' => 'INPUT_OBJECT', 'name' => 'CreatePostInput', 'ofType' => nil }, },
              'defaultValue' => nil,
            },
          ],
        },
        {
          'name' => 'updateUser',
          'description' => 'Update a user',
          'type' => { 'kind' => 'OBJECT', 'name' => 'UpdateUserPayload', 'ofType' => nil },
          'args' => [
            {
              'name' => 'input',
              'description' => nil,
              'type' => { 'kind' => 'NON_NULL', 'name' => nil,
                          'ofType' => { 'kind' => 'INPUT_OBJECT', 'name' => 'UpdateUserInput', 'ofType' => nil }, },
              'defaultValue' => nil,
            },
          ],
        },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_user_connection_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'UserConnection',
      'description' => nil,
      'fields' => [
        { 'name' => 'nodes', 'description' => nil,
          'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'OBJECT', 'name' => 'User', 'ofType' => nil } }, 'args' => [], },
        { 'name' => 'totalCount', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'Int', 'ofType' => nil }, 'args' => [], },
        { 'name' => 'pageInfo', 'description' => nil,
          'type' => { 'kind' => 'OBJECT', 'name' => 'PageInfo', 'ofType' => nil }, 'args' => [], },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_user_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'User',
      'description' => nil,
      'fields' => [
        { 'name' => 'id', 'description' => 'Unique identifier.',
          'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'ID', 'ofType' => nil } }, 'args' => [], },
        { 'name' => 'name', 'description' => 'Full name.',
          'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [], },
        { 'name' => 'email', 'description' => 'Email address.',
          'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [], },
        { 'name' => 'active', 'description' => 'Whether the user is active.',
          'type' => { 'kind' => 'SCALAR', 'name' => 'Boolean', 'ofType' => nil }, 'args' => [], },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_post_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'Post',
      'description' => nil,
      'fields' => [
        { 'name' => 'id', 'description' => nil,
          'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'ID', 'ofType' => nil } }, 'args' => [], },
        { 'name' => 'title', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [], },
        { 'name' => 'body', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [], },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_page_info_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'PageInfo',
      'description' => nil,
      'fields' => [
        { 'name' => 'hasNextPage', 'description' => nil,
          'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'Boolean', 'ofType' => nil } }, 'args' => [], },
        { 'name' => 'endCursor', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [], },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_create_post_payload_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'CreatePostPayload',
      'description' => nil,
      'fields' => [
        { 'name' => 'post', 'description' => nil, 'type' => { 'kind' => 'OBJECT', 'name' => 'Post', 'ofType' => nil },
          'args' => [], },
        { 'name' => 'errors', 'description' => nil,
          'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'OBJECT', 'name' => 'MutationError', 'ofType' => nil } }, 'args' => [], },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_create_post_input_type_def
    {
      'kind' => 'INPUT_OBJECT',
      'name' => 'CreatePostInput',
      'description' => nil,
      'fields' => nil,
      'inputFields' => [
        { 'name' => 'title', 'description' => nil,
          'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil } }, 'defaultValue' => nil, },
        { 'name' => 'body', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil, },
      ],
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_update_user_payload_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'UpdateUserPayload',
      'description' => nil,
      'fields' => [
        { 'name' => 'user', 'description' => nil, 'type' => { 'kind' => 'OBJECT', 'name' => 'User', 'ofType' => nil },
          'args' => [], },
        { 'name' => 'errors', 'description' => nil,
          'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'OBJECT', 'name' => 'MutationError', 'ofType' => nil } }, 'args' => [], },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_update_user_input_type_def
    {
      'kind' => 'INPUT_OBJECT',
      'name' => 'UpdateUserInput',
      'description' => nil,
      'fields' => nil,
      'inputFields' => [
        { 'name' => 'id', 'description' => nil,
          'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'ID', 'ofType' => nil } }, 'defaultValue' => nil, },
        { 'name' => 'name', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil, },
        { 'name' => 'email', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil, },
      ],
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_mutation_error_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'MutationError',
      'description' => nil,
      'fields' => [
        { 'name' => 'message', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [], },
        { 'name' => 'path', 'description' => nil,
          'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil } }, 'args' => [], },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_user_status_enum_type_def
    {
      'kind' => 'ENUM',
      'name' => 'UserStatus',
      'description' => 'User status',
      'fields' => nil,
      'inputFields' => nil,
      'enumValues' => [
        { 'name' => 'active', 'description' => 'Active users' },
        { 'name' => 'inactive', 'description' => 'Inactive users' },
        { 'name' => 'suspended', 'description' => 'Suspended users' },
      ],
      'possibleTypes' => nil,
    }
  end
end
