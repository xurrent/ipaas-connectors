module XurrentIntrospectionHelper
  def xurrent_graphql_endpoint
    'https://graphql.xurrent-demo.com'
  end

  def xurrent_outbound_connection_config
    {
      credentials: {
        account_id: 'test-account',
        personal_access_token: make_secret_string('test-api-key'),
      },
      environment: { stage: 'Demo' },
    }
  end

  def graphql_response_headers
    {
      'content-type' => 'application/json',
      'x-request-id' => 'req-test-123',
      'x-ratelimit-limit' => '3600',
      'x-ratelimit-remaining' => '3599',
      'x-ratelimit-reset' => '60',
      'x-costlimit-limit' => '5000',
      'x-costlimit-cost' => '12',
      'x-costlimit-remaining' => '4988',
      'x-costlimit-reset' => '60',
    }
  end

  def stub_introspection(endpoint: xurrent_graphql_endpoint)
    stub_request(:post, endpoint)
      .with { |req| req.body.include?('__schema') }
      .to_return(
        status: 200,
        body: { data: { __schema: introspection_schema } }.to_json,
        headers: graphql_response_headers,
      )
  end

  def stub_graphql_query(query_pattern, response_data, endpoint: xurrent_graphql_endpoint, headers: graphql_response_headers)
    stub_request(:post, endpoint)
      .with { |req| !req.body.include?('__schema') && req.body.match?(query_pattern) }
      .to_return(
        status: 200,
        body: { data: response_data }.to_json,
        headers: headers,
      )
  end

  def introspection_schema
    {
      'queryType' => { 'name' => 'Query' },
      'mutationType' => { 'name' => 'Mutation' },
      'types' => [
        query_type_def,
        mutation_type_def,
        person_connection_type_def,
        person_type_def,
        skill_connection_type_def,
        skill_type_def,
        request_type_def,
        page_info_type_def,
        organization_type_def,
        request_create_payload_type_def,
        request_create_input_type_def,
        custom_field_input_type_def,
        person_update_payload_type_def,
        person_update_input_type_def,
        mutation_error_type_def,
        request_category_enum_type_def,
        person_view_enum_type_def,
        person_filter_input_type_def,
        person_order_input_type_def,
        person_order_field_enum_type_def,
        order_direction_enum_type_def,
      ],
    }
  end

  def query_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'Query',
      'description' => nil,
      'fields' => [
        {
          'name' => 'people',
          'description' => 'List of people',
          'type' => { 'kind' => 'OBJECT', 'name' => 'PersonConnection', 'ofType' => nil },
          'args' => [
            { 'name' => 'first', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'Int', 'ofType' => nil }, 'defaultValue' => nil },
            { 'name' => 'after', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil },
            { 'name' => 'view', 'description' => nil, 'type' => { 'kind' => 'ENUM', 'name' => 'PersonView', 'ofType' => nil }, 'defaultValue' => nil },
            { 'name' => 'filter', 'description' => nil, 'type' => { 'kind' => 'INPUT_OBJECT', 'name' => 'PersonFilter', 'ofType' => nil }, 'defaultValue' => nil },
            { 'name' => 'order', 'description' => nil, 'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'INPUT_OBJECT', 'name' => 'PersonOrder', 'ofType' => nil } } }, 'defaultValue' => nil },
          ],
        },
        {
          'name' => 'me',
          'description' => 'Current user',
          'type' => { 'kind' => 'OBJECT', 'name' => 'Person', 'ofType' => nil },
          'args' => [],
        },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def mutation_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'Mutation',
      'description' => nil,
      'fields' => [
        {
          'name' => 'requestCreate',
          'description' => 'Create a request',
          'type' => { 'kind' => 'OBJECT', 'name' => 'RequestCreatePayload', 'ofType' => nil },
          'args' => [
            {
              'name' => 'input',
              'description' => nil,
              'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'INPUT_OBJECT', 'name' => 'RequestCreateInput', 'ofType' => nil } },
              'defaultValue' => nil,
            },
          ],
        },
        {
          'name' => 'personUpdate',
          'description' => 'Update a person',
          'type' => { 'kind' => 'OBJECT', 'name' => 'PersonUpdatePayload', 'ofType' => nil },
          'args' => [
            {
              'name' => 'input',
              'description' => nil,
              'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'INPUT_OBJECT', 'name' => 'PersonUpdateInput', 'ofType' => nil } },
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

  def person_connection_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'PersonConnection',
      'description' => nil,
      'fields' => [
        { 'name' => 'nodes', 'description' => nil, 'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'OBJECT', 'name' => 'Person', 'ofType' => nil } }, 'args' => [] },
        { 'name' => 'totalCount', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'Int', 'ofType' => nil }, 'args' => [] },
        { 'name' => 'pageInfo', 'description' => nil, 'type' => { 'kind' => 'OBJECT', 'name' => 'PageInfo', 'ofType' => nil }, 'args' => [] },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def person_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'Person',
      'description' => nil,
      'fields' => [
        { 'name' => 'id', 'description' => 'Unique identifier of the person.', 'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'ID', 'ofType' => nil } }, 'args' => [] },
        { 'name' => 'name', 'description' => 'Full name of the person.', 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [] },
        { 'name' => 'primaryEmail', 'description' => 'Primary email address.', 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [] },
        { 'name' => 'disabled', 'description' => 'Whether the person is disabled.', 'type' => { 'kind' => 'SCALAR', 'name' => 'Boolean', 'ofType' => nil }, 'args' => [] },
        { 'name' => 'organization', 'description' => 'Organization the person belongs to.', 'type' => { 'kind' => 'OBJECT', 'name' => 'Organization', 'ofType' => nil }, 'args' => [] },
        { 'name' => 'skills', 'description' => 'Skills of the person.', 'type' => { 'kind' => 'OBJECT', 'name' => 'SkillConnection', 'ofType' => nil }, 'args' => [] },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  # totalCount keeps the connection type realistic (connection detection is
  # based on the presence of a nodes field among others); the generated query
  # selects only nodes.
  def skill_connection_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'SkillConnection',
      'description' => nil,
      'fields' => [
        { 'name' => 'nodes', 'description' => nil, 'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'OBJECT', 'name' => 'Skill', 'ofType' => nil } }, 'args' => [] },
        { 'name' => 'totalCount', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'Int', 'ofType' => nil }, 'args' => [] },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def skill_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'Skill',
      'description' => nil,
      'fields' => [
        { 'name' => 'id', 'description' => nil, 'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'ID', 'ofType' => nil } }, 'args' => [] },
        { 'name' => 'name', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [] },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def request_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'Request',
      'description' => nil,
      'fields' => [
        { 'name' => 'id', 'description' => 'Request ID.', 'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'ID', 'ofType' => nil } }, 'args' => [] },
        { 'name' => 'subject', 'description' => 'Subject of the request.', 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [] },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def page_info_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'PageInfo',
      'description' => nil,
      'fields' => [
        { 'name' => 'hasNextPage', 'description' => nil, 'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'Boolean', 'ofType' => nil } }, 'args' => [] },
        { 'name' => 'endCursor', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [] },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def organization_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'Organization',
      'description' => nil,
      'fields' => [
        { 'name' => 'id', 'description' => nil, 'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'ID', 'ofType' => nil } }, 'args' => [] },
        { 'name' => 'name', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [] },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def request_create_payload_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'RequestCreatePayload',
      'description' => nil,
      'fields' => [
        { 'name' => 'request', 'description' => nil, 'type' => { 'kind' => 'OBJECT', 'name' => 'Request', 'ofType' => nil }, 'args' => [] },
        { 'name' => 'errors', 'description' => nil, 'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'OBJECT', 'name' => 'MutationError', 'ofType' => nil } }, 'args' => [] },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def request_create_input_type_def
    {
      'kind' => 'INPUT_OBJECT',
      'name' => 'RequestCreateInput',
      'description' => nil,
      'fields' => nil,
      'inputFields' => [
        { 'name' => 'subject', 'description' => nil, 'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil } }, 'defaultValue' => nil },
        { 'name' => 'category', 'description' => nil, 'type' => { 'kind' => 'ENUM', 'name' => 'RequestCategory', 'ofType' => nil }, 'defaultValue' => nil },
        { 'name' => 'source', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil },
        { 'name' => 'sourceID', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil },
        { 'name' => 'customFields', 'description' => nil, 'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'INPUT_OBJECT', 'name' => 'CustomFieldInput', 'ofType' => nil } } }, 'defaultValue' => nil },
      ],
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def person_update_payload_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'PersonUpdatePayload',
      'description' => nil,
      'fields' => [
        { 'name' => 'person', 'description' => nil, 'type' => { 'kind' => 'OBJECT', 'name' => 'Person', 'ofType' => nil }, 'args' => [] },
        { 'name' => 'errors', 'description' => nil, 'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'OBJECT', 'name' => 'MutationError', 'ofType' => nil } }, 'args' => [] },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def person_update_input_type_def
    {
      'kind' => 'INPUT_OBJECT',
      'name' => 'PersonUpdateInput',
      'description' => nil,
      'fields' => nil,
      'inputFields' => [
        { 'name' => 'id', 'description' => nil, 'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'ID', 'ofType' => nil } }, 'defaultValue' => nil },
        { 'name' => 'name', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil },
        { 'name' => 'primaryEmail', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil },
        { 'name' => 'disabled', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'Boolean', 'ofType' => nil }, 'defaultValue' => nil },
        { 'name' => 'clientMutationId', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil },
      ],
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def custom_field_input_type_def
    {
      'kind' => 'INPUT_OBJECT',
      'name' => 'CustomFieldInput',
      'description' => nil,
      'fields' => nil,
      'inputFields' => [
        { 'name' => 'id', 'description' => nil, 'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil } }, 'defaultValue' => nil },
        { 'name' => 'value', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil },
      ],
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def mutation_error_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'MutationError',
      'description' => nil,
      'fields' => [
        { 'name' => 'message', 'description' => nil, 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [] },
        { 'name' => 'path', 'description' => nil, 'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil } }, 'args' => [] },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def request_category_enum_type_def
    {
      'kind' => 'ENUM',
      'name' => 'RequestCategory',
      'description' => 'Request category',
      'fields' => nil,
      'inputFields' => nil,
      'enumValues' => [
        { 'name' => 'incident', 'description' => nil },
        { 'name' => 'rfc', 'description' => nil },
        { 'name' => 'rfi', 'description' => nil },
        { 'name' => 'complaint', 'description' => nil },
      ],
      'possibleTypes' => nil,
    }
  end

  def person_view_enum_type_def
    {
      'kind' => 'ENUM',
      'name' => 'PersonView',
      'description' => 'Person view',
      'fields' => nil,
      'inputFields' => nil,
      'enumValues' => [
        { 'name' => 'all', 'description' => 'All people' },
        { 'name' => 'disabled', 'description' => 'Disabled people' },
        { 'name' => 'internal', 'description' => 'Internal people' },
        { 'name' => 'directory', 'description' => 'Directory' },
        { 'name' => 'supportDomain', 'description' => 'Support domain' },
      ],
      'possibleTypes' => nil,
    }
  end

  def person_filter_input_type_def
    {
      'kind' => 'INPUT_OBJECT',
      'name' => 'PersonFilter',
      'description' => 'Filter for people',
      'fields' => nil,
      'inputFields' => [
        { 'name' => 'query', 'description' => 'Search by keyword', 'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil },
        { 'name' => 'disabled', 'description' => 'Filter by disabled', 'type' => { 'kind' => 'SCALAR', 'name' => 'Boolean', 'ofType' => nil }, 'defaultValue' => nil },
        { 'name' => 'name', 'description' => 'Filter by name', 'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil } }, 'defaultValue' => nil },
        { 'name' => 'primaryEmail', 'description' => 'Filter by email', 'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil } }, 'defaultValue' => nil },
        { 'name' => 'createdAt', 'description' => 'Filter by creation date', 'type' => { 'kind' => 'SCALAR', 'name' => 'ISO8601DateTime', 'ofType' => nil }, 'defaultValue' => nil },
      ],
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def person_order_input_type_def
    {
      'kind' => 'INPUT_OBJECT',
      'name' => 'PersonOrder',
      'description' => 'Order for people',
      'fields' => nil,
      'inputFields' => [
        { 'name' => 'field', 'description' => 'Field to order by', 'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'ENUM', 'name' => 'PersonOrderField', 'ofType' => nil } }, 'defaultValue' => nil },
        { 'name' => 'direction', 'description' => 'Order direction', 'type' => { 'kind' => 'ENUM', 'name' => 'OrderDirection', 'ofType' => nil }, 'defaultValue' => nil },
      ],
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def person_order_field_enum_type_def
    {
      'kind' => 'ENUM',
      'name' => 'PersonOrderField',
      'description' => 'Fields to order people by',
      'fields' => nil,
      'inputFields' => nil,
      'enumValues' => [
        { 'name' => 'name', 'description' => nil },
        { 'name' => 'createdAt', 'description' => nil },
        { 'name' => 'updatedAt', 'description' => nil },
      ],
      'possibleTypes' => nil,
    }
  end

  def order_direction_enum_type_def
    {
      'kind' => 'ENUM',
      'name' => 'OrderDirection',
      'description' => 'Order direction',
      'fields' => nil,
      'inputFields' => nil,
      'enumValues' => [
        { 'name' => 'asc', 'description' => 'Ascending' },
        { 'name' => 'desc', 'description' => 'Descending' },
      ],
      'possibleTypes' => nil,
    }
  end
end
