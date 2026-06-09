# Small introspection schema with a nested connection:
# Query.requests -> RequestConnection -> Request.notes -> NoteConnection -> Note,
# plus a simple object query, a list query, and a mutation whose payload also
# contains the notes connection. Include after GraphqlIntrospectionHelper to
# override its schema (PageInfo is reused from there).
module GraphqlNestedConnectionHelper
  def graphql_connector_introspection_schema
    {
      'queryType' => { 'name' => 'Query' },
      'mutationType' => { 'name' => 'Mutation' },
      'types' => [
        gql_nested_query_type_def,
        gql_nested_mutation_type_def,
        gql_request_update_input_type_def,
        gql_request_update_payload_type_def,
        gql_request_connection_type_def,
        gql_request_type_def,
        gql_note_connection_type_def,
        gql_note_type_def,
        gql_page_info_type_def,
      ],
    }
  end

  def gql_nested_query_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'Query',
      'description' => nil,
      'fields' => [
        {
          'name' => 'requests',
          'description' => 'List of requests',
          'type' => { 'kind' => 'OBJECT', 'name' => 'RequestConnection', 'ofType' => nil },
          'args' => [
            { 'name' => 'first', 'description' => nil,
              'type' => { 'kind' => 'SCALAR', 'name' => 'Int', 'ofType' => nil }, 'defaultValue' => nil, },
            { 'name' => 'after', 'description' => nil,
              'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil, },
          ],
        },
        {
          'name' => 'firstRequest',
          'description' => 'A single request',
          'type' => { 'kind' => 'OBJECT', 'name' => 'Request', 'ofType' => nil },
          'args' => [],
        },
        {
          'name' => 'recentRequests',
          'description' => 'Recently updated requests',
          'type' => { 'kind' => 'LIST', 'name' => nil,
                      'ofType' => { 'kind' => 'OBJECT', 'name' => 'Request', 'ofType' => nil }, },
          'args' => [],
        },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_nested_mutation_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'Mutation',
      'description' => nil,
      'fields' => [
        {
          'name' => 'requestUpdate',
          'description' => 'Update a request',
          'type' => { 'kind' => 'OBJECT', 'name' => 'RequestUpdatePayload', 'ofType' => nil },
          'args' => [
            { 'name' => 'input', 'description' => nil,
              'type' => { 'kind' => 'NON_NULL', 'name' => nil,
                          'ofType' => { 'kind' => 'INPUT_OBJECT', 'name' => 'RequestUpdateInput', 'ofType' => nil }, },
              'defaultValue' => nil, },
          ],
        },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_request_update_input_type_def
    {
      'kind' => 'INPUT_OBJECT',
      'name' => 'RequestUpdateInput',
      'description' => nil,
      'fields' => nil,
      'inputFields' => [
        { 'name' => 'subject', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil, },
      ],
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  # The payload carries the notes connection directly, so the mutation action
  # auto-includes it as a top-level nested payload field.
  def gql_request_update_payload_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'RequestUpdatePayload',
      'description' => nil,
      'fields' => [
        { 'name' => 'subject', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [], },
        { 'name' => 'notes', 'description' => nil,
          'type' => { 'kind' => 'OBJECT', 'name' => 'NoteConnection', 'ofType' => nil }, 'args' => [], },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_request_connection_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'RequestConnection',
      'description' => nil,
      'fields' => [
        { 'name' => 'nodes', 'description' => nil,
          'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'OBJECT', 'name' => 'Request', 'ofType' => nil } }, 'args' => [], },
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

  def gql_request_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'Request',
      'description' => nil,
      'fields' => [
        { 'name' => 'id', 'description' => nil,
          'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'ID', 'ofType' => nil } }, 'args' => [], },
        { 'name' => 'subject', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [], },
        { 'name' => 'notes', 'description' => 'Notes of the request',
          'type' => { 'kind' => 'OBJECT', 'name' => 'NoteConnection', 'ofType' => nil }, 'args' => [], },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  # totalCount keeps the connection type realistic (connection detection is
  # based on the presence of a nodes field among others); the generated query
  # selects only nodes.
  def gql_note_connection_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'NoteConnection',
      'description' => nil,
      'fields' => [
        { 'name' => 'nodes', 'description' => nil,
          'type' => { 'kind' => 'LIST', 'name' => nil, 'ofType' => { 'kind' => 'OBJECT', 'name' => 'Note', 'ofType' => nil } }, 'args' => [], },
        { 'name' => 'totalCount', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'Int', 'ofType' => nil }, 'args' => [], },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end

  def gql_note_type_def
    {
      'kind' => 'OBJECT',
      'name' => 'Note',
      'description' => nil,
      'fields' => [
        { 'name' => 'id', 'description' => nil,
          'type' => { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => { 'kind' => 'SCALAR', 'name' => 'ID', 'ofType' => nil } }, 'args' => [], },
        { 'name' => 'text', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'args' => [], },
        { 'name' => 'internal', 'description' => nil,
          'type' => { 'kind' => 'SCALAR', 'name' => 'Boolean', 'ofType' => nil }, 'args' => [], },
      ],
      'inputFields' => nil,
      'enumValues' => nil,
      'possibleTypes' => nil,
    }
  end
end
