class GraphqlConnector < IPaaS::Connector::Definition
  GqlSchema = IPaaS::Job::GraphQL::Schema
  GqlQuery = IPaaS::Job::GraphQL::QueryBuilder
  GqlFields = IPaaS::Job::GraphQL::FieldBuilder
  GqlResult = IPaaS::Job::GraphQL::Result
  Humanize = IPaaS::Job::Humanize
  CompactHash = IPaaS::Job::CompactHash

  INTROSPECTION_FAILURE_TTL = 10.minutes # configuration errors cached for 10 minutes
  INTROSPECTION_TRANSIENT_FAILURE_TTL = 30.seconds # transient errors cached for 30 seconds
  INTROSPECTION_FAILURE_MESSAGE_LIMIT = 200 # cap on the length of the error message

  connector 'd5bbb2a2-4a95-4b49-b490-56711e4455f8' do
    name 'GraphQL Connector'
    avatar '/assets/icons/graphql.svg'
    description <<~DESC
      Generic connector for integrating with any GraphQL API using dynamic schema introspection.

      # Outbound Connection
      An outbound connection is required for the query and mutation actions. It supports three authentication methods: **Bearer Token**, **API Key Header**, and **OAuth2 Client Credentials**.

      Provide the GraphQL endpoint URL and optionally a URL to the GraphQL schema (introspection endpoint) or paste the full schema JSON directly. When a schema URL is provided, the schema is downloaded and stored in the full schema field automatically.

      # GraphQL Query Action
      Dynamically queries records from the GraphQL API. Select a query object and the input arguments and output fields are automatically generated from the GraphQL schema via introspection.

      ## How it works
      1. Select a **query object** from the available queries in the schema. The available objects are loaded from the GraphQL schema once the outbound connection is configured.
      2. The input fields (arguments) and output fields are automatically generated based on the selected query object via schema introspection.
      3. Use **Include nested fields** to select which related objects to include in the query result.
      4. Optionally set a **Max results** limit to cap the number of records retrieved.

      This action is **nested**: for connection-type queries (with pagination), it iterates over all matching records and executes the successor action once per page.

      ## Clearing the schema cache
      The GraphQL schema is cached after the first introspection. Check the **Refresh schema** option to force a refresh.

      # GraphQL Mutation Action
      Executes a GraphQL mutation. Select a mutation and the input and output schemas are automatically generated from the schema.

      ## How it works
      1. Select a **mutation** from the available mutations in the schema. The available mutations are loaded from the GraphQL schema once the outbound connection is configured.
      2. The input fields and output fields are automatically generated based on the selected mutation.
      3. Provide the mutation input either by mapping individual fields or as a **JSON object**.

      ## Clearing the schema cache
      The GraphQL schema is cached after the first introspection. Check the **Refresh schema** option to force a refresh.
    DESC

    # ──────────────────────────────────────────────
    # Outbound Connection (API authentication)
    # ──────────────────────────────────────────────

    outbound_connection do
      config_schema do
        field :graphql_endpoint, 'GraphQL Endpoint', :uri,
              hint: 'The URL of the GraphQL API endpoint (e.g. https://api.example.com/graphql).',
              required: true

        field :auth_type, 'Authentication type', :string,
              hint: <<~HINT.strip,
                Select how to authenticate with the GraphQL API.

                # Bearer Token
                Use a static bearer token (e.g. a personal access token or API token).
                The token is sent as `Authorization: Bearer <token>` header.

                # API Key Header
                Send an API key as a custom HTTP header.
                Configure the header name and value.

                # OAuth2 Client Credentials
                Use the OAuth2 client credentials grant for server-to-server authentication.
                Requires a token endpoint URL, client ID, and client secret.

                # No Authentication
                Connect without authentication. Useful for public GraphQL APIs.
              HINT
              enumeration: [
                { id: 'bearer_token', label: 'Bearer Token' },
                { id: 'api_key_header', label: 'API Key Header' },
                { id: 'oauth2', label: 'OAuth2 Client Credentials' },
                { id: 'none', label: 'No Authentication' },
              ],
              required: true

        field :bearer_token, 'Bearer Token', :nested,
              visibility: 'hidden' do
          field :token, 'Token', :secret_string,
                hint: 'The bearer token to send in the Authorization header.',
                required: true
        end

        field :api_key_header, 'API Key Header', :nested,
              visibility: 'hidden' do
          field :header_name, 'Header name', :string,
                hint: 'The name of the HTTP header to send (e.g. X-API-Key, Authorization).',
                required: true
          field :header_value, 'Header value', :secret_string,
                hint: 'The value of the HTTP header.',
                required: true
        end

        field :oauth2, 'OAuth2 Credentials', :nested,
              visibility: 'hidden' do
          field :token_endpoint, 'Token endpoint', :uri,
                hint: 'The OAuth2 token endpoint URL.',
                required: true
          field :client_id, 'Client ID', :string,
                hint: 'The OAuth2 client ID.',
                required: true
          field :client_secret, 'Client secret', :secret_string,
                hint: 'The OAuth2 client secret.',
                required: true
          field :scope, 'Scope', :string,
                hint: 'Optional OAuth2 scope(s), space-separated.',
                visibility: 'optional'
        end

        field :custom_headers, 'Custom headers', :nested,
              array: true,
              hint: 'Additional HTTP headers to send with every request.',
              visibility: 'optional' do
          field :name, 'Header name', :string, required: true
          field :value, 'Header value', :string, required: true
        end

        after_update do |fields, new_values|
          auth_type = new_values[:auth_type]
          bearer_field = fields.detect { |f| f.id == :bearer_token }
          api_key_field = fields.detect { |f| f.id == :api_key_header }
          oauth2_field = fields.detect { |f| f.id == :oauth2 }

          bearer_field.visibility = auth_type == 'bearer_token' ? 'visible' : 'hidden'
          api_key_field.visibility = auth_type == 'api_key_header' ? 'visible' : 'hidden'
          oauth2_field.visibility = auth_type == 'oauth2' ? 'visible' : 'hidden'

          fields
        end

        field :schema_source, 'Schema source', :string,
              hint: <<~HINT.strip,
                Choose how to provide the GraphQL schema for dynamic field generation.

                # Introspection (default)
                The schema is fetched from the GraphQL endpoint using the standard introspection
                query. This works with most GraphQL APIs that have introspection enabled.

                # Manual
                Paste the full introspection schema JSON directly into the schema field.
                Useful when the API does not support introspection.
              HINT
              enumeration: [
                { id: 'introspection', label: 'Introspection (from endpoint)' },
                { id: 'manual', label: 'Manual (paste schema JSON)' },
              ],
              default: 'introspection'

        field :full_schema, 'Full schema', :string,
              hint: 'The full GraphQL introspection schema as JSON. ' \
                    'Populated automatically when using introspection. ' \
                    'Paste the schema JSON here when using manual mode.',
              visibility: 'hidden'

        after_update do |fields, new_values|
          schema_source = new_values[:schema_source]
          full_schema_field = fields.detect { |f| f.id == :full_schema }

          full_schema_field.visibility = schema_source == 'manual' ? 'visible' : 'optional'

          fields
        end
      end

      authenticate do |request|
        case config[:auth_type]
        when 'bearer_token'
          token = decrypt_secret_string(config[:bearer_token][:token])
          request.headers['Authorization'] = "Bearer #{token}"
        when 'api_key_header'
          api_key_config = config[:api_key_header]
          request.headers[api_key_config[:header_name]] = decrypt_secret_string(api_key_config[:header_value])
        when 'oauth2'
          oauth2_config = config[:oauth2]
          body = oauth2_client_credentials_body(oauth2_config[:client_id],
                                                decrypt_secret_string(oauth2_config[:client_secret]))
          body[:scope] = oauth2_config[:scope] if oauth2_config[:scope].present?
          request.headers['Authorization'] = oauth2_authorization_header(oauth2_config[:token_endpoint], body)
        end

        config[:custom_headers]&.each do |header|
          request.headers[header[:name]] = header[:value]
        end
      end
    end

    # ──────────────────────────────────────────────
    # Action: Dynamic GraphQL Query
    # ──────────────────────────────────────────────

    action 'eb80d943-e0a3-44c7-97aa-640e243f9320' do
      name 'GraphQL Query'
      description <<~DESC
        Query records from a GraphQL API with dynamically generated input and output fields.

        # How it works
        1. Select a **query object** from the available queries in the schema. The available objects are loaded from the GraphQL schema once the outbound connection is configured.
        2. The input fields (arguments) and output fields are automatically generated based on the selected query object via schema introspection.
        3. Use **Include nested fields** to select which related objects to include in the query result.
        4. Optionally set a **Max results** limit to cap the number of records retrieved.

        This action is **nested**: for connection-type queries (with pagination), it iterates over all matching records and executes the successor action once per page.

        # Clearing the schema cache
        The GraphQL schema is cached after the first introspection. Check the **Refresh schema** option to force a refresh.
      DESC
      avatar '/assets/icons/graphql.svg'
      nested true

      # Defined before input_schema (which runs eagerly at connector load) so the
      # helper is registered when first called. schema_data stays local to this
      # helper and is never captured by the after_update closure (on the cached Schema).
      helper :build_query_input_fields do |schema|
        object_name = action.input&.[](:object)
        schema_data = cache_read('gql_schema')
        query_options = schema_data.present? ? GqlSchema.gql_list_root_fields(schema_data, 'query') : []

        if query_options.any?
          schema.field :object, 'Query object', :string,
                       enumeration: query_options,
                       required: true
        else
          schema.field :object, 'Query object', :string,
                       hint: 'The GraphQL query field name.',
                       notice: 'Outbound Connection is not configured correctly.',
                       notice_type: 'error',
                       notice_action: 'edit_connection',
                       pattern: /\A[A-Za-z][A-Za-z0-9]*\z/,
                       required: true
        end

        schema.field :include_fields, 'Include nested fields', :nested

        if schema_data.present? && object_name.present?
          helpers.add_input_fields_from_schema_data(schema, schema_data, object_name)
        end

        schema.field :page_size, 'Page size', :integer,
                     min: 1, max: 100,
                     visibility: 'optional',
                     default: 100,
                     hint: 'Number of records to retrieve per page (1-100). Defaults to 100.'
        schema.field :max_results, 'Max results', :integer,
                     min: 1,
                     visibility: 'optional',
                     hint: 'Maximum total number of records to retrieve. Leave empty to retrieve all records.'
        schema.field :refresh_schema, 'Refresh schema', :boolean,
                     hint: 'Check to clear the cached GraphQL schema and re-fetch it. ' \
                           'Useful after schema changes in the GraphQL API.',
                     visibility: 'optional',
                     default: false
      end

      input_schema do
        # Built in a helper so the parsed schema_data stays local to it and is never
        # captured by the after_update closure below (stored on the cached Schema).
        helpers.build_query_input_fields(self)
        after_update do |_fields|
          helpers.refresh_dynamic_schemas(self, :object, 'query_result')
        end
      end

      output_schema 'query_result' do
        object_name = action.input&.[](:object)

        if object_name.present?
          schema_data = cache_read('gql_schema')
          helpers.add_query_fields_from_schema_data(self, schema_data, object_name) if schema_data.present?
        end

        field :request_id, 'Request ID', :string,
              visibility: 'optional'
      end

      iteration_state_schema do
        field :end_cursor, 'End cursor', :string, required: true
        field :fetched_count, 'Fetched count', :integer
      end

      run do
        schema_data = helpers.ensure_schema_cached
        object_name = input[:object]
        node_type_name = GqlSchema.gql_resolve_connection_node_type(schema_data, 'query', object_name)
        is_connection = node_type_name.present?
        is_list = !is_connection && helpers.list_return_type?(schema_data, object_name)

        gql_output = if is_connection
                       helpers.run_connection_query(schema_data, object_name, node_type_name)
                     else
                       helpers.run_simple_query(schema_data, object_name)
                     end

        data = gql_output[:data]
        result = gql_output.except(:data)

        if is_connection
          helpers.process_connection_result(data, object_name, result)
        else
          object_data = data[object_name]
          fail_job!("No data returned for '#{object_name}'") if object_data.blank?

          # flatten nested connections so the data matches the generated schema
          if is_list
            result[:nodes] = GqlResult.gql_flatten_nodes(object_data)
          elsif object_data.is_a?(Hash)
            # connection-shaped results route to process_connection_result,
            # so the flattened value is still a hash here
            result.merge!(GqlResult.gql_flatten_nodes(object_data))
          end
        end

        [{ output: result, schema_reference: 'query_result' }]
      end

      helper :add_input_fields_from_schema_data do |schema, schema_data, object_name|
        root_field = GqlSchema.gql_find_root_field(schema_data, 'query', object_name)
        gql_args = root_field&.[]('args') || []

        gql_args.each do |arg|
          arg_name = arg['name']
          next if %w[first last before after].include?(arg_name)

          type_info = GqlSchema.gql_unwrap_type(arg['type'])

          if type_info[:kind] == 'ENUM'
            enum_type = GqlSchema.gql_find_type(schema_data, type_info[:name])
            enum_values = enum_type&.[]('enumValues')&.map do |e|
              { id: e['name'], label: Humanize.humanize_field_name(e['name']) }
            end || []
            schema.field arg_name.to_sym, Humanize.humanize_field_name(arg_name), :string,
                         enumeration: enum_values
          elsif type_info[:kind] == 'INPUT_OBJECT'
            schema.field arg_name.to_sym, Humanize.humanize_field_name(arg_name), :nested
            GqlFields.gql_add_dynamic_input_fields(
              schema.field(arg_name.to_sym), schema_data, type_info[:name], 0,
              sort: true,
              visibility: ->(_name, _is_required, _depth) { 'optional' },
            )
          else
            ipaas_type = GqlSchema.gql_to_ipaas_type(type_info)
            opts = {}
            opts[:array] = true if type_info[:list]
            opts[:required] = true if type_info[:required]
            schema.field arg_name.to_sym, Humanize.humanize_field_name(arg_name), ipaas_type, **opts
          end
        end

        # Include fields — update with proper enumeration and sub-sections
        node_type_name = GqlSchema.gql_resolve_connection_node_type(schema_data, 'query', object_name)
        target_type = node_type_name || GqlSchema.gql_resolve_return_type_name(schema_data, 'query', object_name)
        if target_type.present?
          GqlFields.gql_update_include_fields_input(schema, schema_data, target_type, action.input, 0)
        end
      end

      helper :add_query_fields_from_schema_data do |schema, schema_data, object_name|
        node_type_name = GqlSchema.gql_resolve_connection_node_type(schema_data, 'query', object_name)
        if node_type_name.present?
          schema.field :total_count, 'Total count', :integer
          schema.field :has_next_page, 'Has next page', :boolean
          schema.field :nodes, 'Records', :nested, array: true
          GqlFields.gql_add_dynamic_fields(schema.field(:nodes), schema_data, node_type_name, 0,
                                           include_data: action.input)
        else
          return_type_name = GqlSchema.gql_resolve_return_type_name(schema_data, 'query', object_name)
          next if return_type_name.blank?

          if helpers.list_return_type?(schema_data, object_name)
            schema.field :nodes, 'Records', :nested, array: true
            GqlFields.gql_add_dynamic_fields(schema.field(:nodes), schema_data, return_type_name, 0,
                                             include_data: action.input)
          else
            GqlFields.gql_add_dynamic_fields(schema, schema_data, return_type_name, 0, include_data: action.input)
          end
        end
      end

      helper :effective_page_size do
        page_size = input[:page_size]
        max_results = input[:max_results]
        if max_results.present?
          fetched_count = iteration_state_value(:fetched_count).to_i
          remaining = max_results - fetched_count
          page_size = [page_size, remaining].min
        end
        page_size
      end

      helper :run_connection_query do |schema_data, object_name, node_type_name|
        root_field = GqlSchema.gql_find_root_field(schema_data, 'query', object_name)
        gql_args = root_field&.[]('args') || []
        field_selection = GqlQuery.gql_build_field_selection(schema_data, node_type_name, 0, include_data: input)

        var_defs = []
        query_params = ["first: #{helpers.effective_page_size}"]
        variables = {}

        cursor = iteration_state_value(:end_cursor)
        query_params << %(after: "#{cursor}") if cursor.present?

        gql_args.each do |arg|
          arg_name = arg['name']
          next if %w[first last before after].include?(arg_name)
          next if input[arg_name.to_sym].blank?

          arg_value = input[arg_name.to_sym]
          arg_value = CompactHash.compact_hash(arg_value) if arg_value.is_a?(Hash)
          next if arg_value.blank?

          var_defs << "$#{arg_name}: #{GqlQuery.gql_type_ref_string(arg['type'])}"
          query_params << "#{arg_name}: $#{arg_name}"
          variables[arg_name] = arg_value
        end

        var_clause = var_defs.any? ? "(#{var_defs.join(', ')})" : ''
        query = <<~GRAPHQL
          query#{var_clause} { #{object_name}(#{query_params.join(', ')}) {
              pageInfo { hasNextPage endCursor }
              totalCount
              nodes { #{field_selection} }
            } }
        GRAPHQL

        helpers.graphql_call(query, variables.presence)
      end

      helper :run_simple_query do |schema_data, object_name|
        return_type_name = GqlSchema.gql_resolve_return_type_name(schema_data, 'query', object_name)
        field_selection = GqlQuery.gql_build_field_selection(schema_data, return_type_name, 0, include_data: input)

        root_field = GqlSchema.gql_find_root_field(schema_data, 'query', object_name)
        gql_args = root_field&.[]('args') || []

        var_defs = []
        query_params = []
        variables = {}

        gql_args.each do |arg|
          arg_name = arg['name']
          next if %w[first last before after skip].include?(arg_name)
          next if input[arg_name.to_sym].blank?

          arg_value = input[arg_name.to_sym]
          arg_value = CompactHash.compact_hash(arg_value) if arg_value.is_a?(Hash)
          next if arg_value.blank?

          var_defs << "$#{arg_name}: #{GqlQuery.gql_type_ref_string(arg['type'])}"
          query_params << "#{arg_name}: $#{arg_name}"
          variables[arg_name] = arg_value
        end

        var_clause = var_defs.any? ? "(#{var_defs.join(', ')})" : ''
        args_clause = query_params.any? ? "(#{query_params.join(', ')})" : ''
        query = "query#{var_clause} { #{object_name}#{args_clause} { #{field_selection} } }"
        helpers.graphql_call(query, variables.presence)
      end

      helper :process_connection_result do |data, object_name, result|
        max_results = input[:max_results]
        fetched_count = iteration_state_value(:fetched_count).to_i

        query_result = data[object_name]
        fail_job!("No data returned for '#{object_name}'") if query_result.blank?

        nodes = query_result['nodes'] || []
        new_fetched_count = fetched_count + nodes.length

        next_state = helpers.extract_next_iteration_state_value(query_result)
        if next_state && (!max_results || new_fetched_count < max_results)
          next_state[:fetched_count] = new_fetched_count if max_results
          self.iteration_state_value = next_state
        else
          self.iteration_state_value = nil
        end

        result[:total_count] = query_result['totalCount']
        result[:has_next_page] = iteration_state_value.present?
        # flatten nested connections so the records match the generated schema
        result[:nodes] = GqlResult.gql_flatten_nodes(nodes)
      end

      helper :extract_next_iteration_state_value do |query_result|
        end_cursor = query_result.dig('pageInfo', 'endCursor')
        { end_cursor: end_cursor } if end_cursor.present? && query_result.dig('pageInfo', 'hasNextPage')&.to_s == 'true'
      end

      helper :list_return_type? do |schema_data, object_name|
        root_field = GqlSchema.gql_find_root_field(schema_data, 'query', object_name)
        return false if root_field.blank?

        GqlSchema.gql_unwrap_type(root_field['type'])[:list]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Dynamic GraphQL Mutation
    # ──────────────────────────────────────────────

    action 'f7d7f36f-4746-460a-ba28-30f817be3698' do
      name 'GraphQL Mutation'
      description <<~DESC
        Execute a GraphQL mutation with dynamically generated input and output fields.

        # How it works
        1. Select a **mutation** from the available mutations in the schema. The available mutations are loaded from the GraphQL schema once the outbound connection is configured.
        2. The input fields and output fields are automatically generated based on the selected mutation.
        3. Provide the mutation input either by mapping individual fields or as a **JSON object**.

        # Clearing the schema cache
        The GraphQL schema is cached after the first introspection. Check the **Refresh schema** option to force a refresh.
      DESC
      avatar '/assets/icons/graphql.svg'

      # Defined before input_schema (which runs eagerly at connector load) so the
      # helper is registered when first called. schema_data stays local to this
      # helper and is never captured by the after_update closure (on the cached Schema).
      helper :build_mutation_input_fields do |schema|
        mutation_name = action.input&.[](:mutation)
        schema_data = cache_read('gql_schema')
        mutation_options = schema_data.present? ? GqlSchema.gql_list_root_fields(schema_data, 'mutation') : []

        if mutation_options.any?
          schema.field :mutation, 'Mutation', :string,
                       enumeration: mutation_options,
                       required: true
        else
          schema.field :mutation, 'Mutation', :string,
                       hint: 'The GraphQL mutation name.',
                       notice: 'Outbound Connection is not configured correctly.',
                       notice_type: 'error',
                       notice_action: 'edit_connection',
                       pattern: /\A[A-Za-z][A-Za-z0-9]*\z/,
                       required: true
        end

        schema.field :include_fields, 'Include nested fields', :nested

        if schema_data.present? && mutation_name.present?
          helpers.add_mutation_input_fields(schema, schema_data, mutation_name)
        else
          schema.field :input, 'Input', :hash,
                       hint: 'The mutation input variables as a JSON object.',
                       required: true
        end

        schema.field :refresh_schema, 'Refresh schema', :boolean,
                     hint: 'Check to clear the cached GraphQL schema and re-fetch it. ' \
                           'Useful after schema changes in the GraphQL API.',
                     visibility: 'optional',
                     default: false
      end

      input_schema do
        # See build_query_input_fields above: building in a helper keeps schema_data
        # out of the after_update closure's binding (which lives on the cached Schema).
        helpers.build_mutation_input_fields(self)
        after_update do |_fields|
          helpers.refresh_dynamic_schemas(self, :mutation, 'mutation_result')
        end
      end

      output_schema 'mutation_result' do
        mutation_name = action.input&.[](:mutation)

        if mutation_name.present?
          schema_data = cache_read('gql_schema')
          helpers.add_mutation_output_fields(self, schema_data, mutation_name) if schema_data.present?
        end

        field :request_id, 'Request ID', :string,
              visibility: 'optional'
      end

      run do
        mutation_name = input[:mutation]
        gql_output = helpers.run_mutation_query(mutation_name)
        mutation_data = gql_output.delete(:data)[mutation_name]
        fail_job!("No data returned for mutation '#{mutation_name}'") if mutation_data.blank?

        if mutation_data['errors'].is_a?(Array) && mutation_data['errors'].any?
          messages = mutation_data['errors'].filter_map { |e| e['message'] }
          fail_job!("Mutation error: #{messages.join('; ')}") if messages.any?
        end

        # flatten nested connections so the payload matches the generated schema
        # (mutation payloads are object types, so the flattened value stays a hash)
        result = gql_output.merge!(GqlResult.gql_flatten_nodes(mutation_data))
        [{ output: result, schema_reference: 'mutation_result' }]
      end

      helper :add_mutation_input_fields do |schema, schema_data, mutation_name|
        input_type_name = GqlSchema.gql_mutation_input_type_name(schema_data, mutation_name)
        input_type = GqlSchema.gql_find_type(schema_data, input_type_name)
        if input_type.present? && input_type['inputFields'].present?
          schema.field :input, 'Input', :nested, required: true
          GqlFields.gql_add_dynamic_input_fields(
            schema.field(:input), schema_data, input_type_name, 0,
            visibility: ->(_, is_required, depth) {
              next if depth > 0 || is_required

              'optional'
            },
          )
        else
          schema.field :input, 'Input', :hash,
                       hint: 'The mutation input variables as a JSON object.', required: true
        end

        return_type_name = GqlSchema.gql_resolve_return_type_name(schema_data, 'mutation', mutation_name)
        if return_type_name.present?
          GqlFields.gql_update_include_fields_input(schema, schema_data, return_type_name, action.input, 0)
        end
      end

      helper :add_mutation_output_fields do |schema, schema_data, mutation_name|
        return_type_name = GqlSchema.gql_resolve_return_type_name(schema_data, 'mutation', mutation_name)
        next if return_type_name.blank?

        include_data = helpers.mutation_include_data(schema_data, return_type_name)
        GqlFields.gql_add_dynamic_fields(schema, schema_data, return_type_name, 0,
                                         include_data: include_data)

        unless schema.field(:errors)
          schema.field :errors, 'Errors', :nested, array: true, visibility: 'optional' do
            schema.field :message, 'Message', :string
            schema.field :path, 'Path', :string, array: true
          end
        end
      end

      helper :run_mutation_query do |mutation_name|
        schema_data = helpers.ensure_schema_cached
        return_type_name = GqlSchema.gql_resolve_return_type_name(schema_data, 'mutation', mutation_name)
        input_type_name = GqlSchema.gql_mutation_input_type_name(schema_data, mutation_name)

        include_data = helpers.mutation_include_data(schema_data, return_type_name)
        field_selection = GqlQuery.gql_build_field_selection(
          schema_data, return_type_name, 0,
          include_data: include_data
        )

        mutation = "mutation($input: #{input_type_name}!) { #{mutation_name}(input: $input) { #{field_selection} } }"
        helpers.graphql_call(mutation, { input: input[:input] })
      end

      helper :mutation_include_data do |schema_data, return_type_name|
        payload_fields = GqlSchema.gql_collect_fields(schema_data, return_type_name)
        top_level = payload_fields.filter_map do |f|
          type_info = GqlSchema.gql_unwrap_type(f['type'])
          f['name'] if GqlSchema.gql_to_ipaas_type(type_info) == :nested
        end

        user_includes = input[:include_fields]
        user_includes = {} unless user_includes.is_a?(Hash)
        merged = user_includes.to_hash
        top_level.each { |name| merged[name.to_sym] = true unless merged.key?(name.to_sym) }

        input.to_hash.merge(include_fields: merged)
      end
    end

    # ──────────────────────────────────────────────
    # Connector-level Helpers: Schema Introspection
    # ──────────────────────────────────────────────

    helper :refresh_dynamic_schemas do |context, selection_field, output_schema_ref|
      if action.input&.[](:refresh_schema)
        cache_clear('gql_schema')
        cache_clear('_schema_present')
        cache_clear(helpers.introspection_failure_cache_key)
      end
      begin
        helpers.ensure_schema_cached
      rescue StandardError => e
        log("Schema introspection failed: #{e.message}")
      end
      context.regenerate_schema(context.output_schema(output_schema_ref)) if action.input&.[](selection_field).present?
      context.regenerate_schema(context.input_schema)
    end

    helper :ensure_schema_cached do
      next cache_read('gql_schema') if cache_read('_schema_present') == true

      cached = cache_read('gql_schema')
      if cached.present?
        cache_write('_schema_present', true, 3600)
        next cached
      end

      schema_data = helpers.fetch_schema
      fail_job!('No schema data available. Configure a schema source in the outbound connection.') if schema_data.blank?

      cache_write('gql_schema', schema_data, 3600)
      cache_write('_schema_present', true, 3600)
      schema_data
    end

    helper :fetch_schema do
      schema_source = outbound_connection.config[:schema_source] || 'introspection'

      case schema_source
      when 'manual'
        helpers.parse_schema_json(outbound_connection.config[:full_schema])
      else
        helpers.fetch_schema_via_introspection
      end
    end

    # Performs the introspection HTTP call and, on failure, records a negative
    # cache entry. The negative cache is consulted only on this path; manual
    # schema mode makes no HTTP call and is never suppressed by a cached failure.
    helper :fetch_schema_via_introspection do
      # failures are cached to limit the number of API calls
      cached_failure = cache_read(helpers.introspection_failure_cache_key)
      fail_job!(cached_failure) if cached_failure.present?

      response = begin
        helpers.graphql_call_impl(GqlSchema::INTROSPECTION_QUERY)
      rescue IPaaS::Job::RescheduleJob
        # A backoff (429/503) is a transient signal raised upstream, not cached.
        raise
      rescue IPaaS::Job::Outbound::CustomerCredentialsError => e
        # OAuth credential rejection (401/403/known-400) raises before any GraphQL
        # response. Deterministic config failure; server's responsibility that message is credential-free.
        helpers.record_introspection_failure(e.message, INTROSPECTION_FAILURE_TTL)
      rescue IPaaS::Error => e
        # Other auth errors (e.g. a 5xx from the OAuth token endpoint) are transient.
        helpers.record_introspection_failure(e.message, INTROSPECTION_TRANSIENT_FAILURE_TTL)
      end

      if response.status != 200
        # Bearer/api-key/no-auth connections make no token call, so a bad credential
        # surfaces as a non-200 response. 4xx is deterministic; 5xx is transient.
        deterministic = response.status >= 400 && response.status < 500
        ttl = deterministic ? INTROSPECTION_FAILURE_TTL : INTROSPECTION_TRANSIENT_FAILURE_TTL
        helpers.record_introspection_failure("HTTP error from GraphQL API: #{response.status} " \
                                             "'#{response.body}'", ttl)
      end

      schema_data = helpers.extract_data_from_graphql_response(response)['__schema']
      fail_job!('No schema data from introspection') if schema_data.blank?
      schema_data
    end

    # Writes the bounded failure message to the negative cache keyed by the auth
    # tuple and fails the job with it. The message is capped because it is
    # re-logged on every cache hit for the TTL; the message never contains credentials.
    helper :record_introspection_failure do |message, ttl|
      bounded = message.to_s[0, INTROSPECTION_FAILURE_MESSAGE_LIMIT]
      cache_write(helpers.introspection_failure_cache_key, bounded, ttl)
      fail_job!(bounded)
    end

    # Builds a stable, secret-safe negative-cache key from the elements that
    # determine whether introspection is authorized for the active auth type.
    # Secrets contribute only to the SHA256 input, never to the returned string.
    helper :introspection_failure_cache_key do
      config = outbound_connection.config
      auth_type = config[:auth_type]
      base = [
        config[:graphql_endpoint], # the introspection target
        auth_type,
      ]
      # custom headers can carry auth, so a change must re-attempt
      tuple = base + helpers.auth_key_elements(config, auth_type) + helpers.custom_header_key_elements(config)
      "introspection_failure_#{Digest::SHA256.hexdigest(tuple.join("\n"))}"
    end

    # The authorization determinants for the active auth type. A change to any of
    # these must re-attempt introspection rather than reuse a cached failure.
    helper :auth_key_elements do |config, auth_type|
      case auth_type
      when 'bearer_token'
        bearer = config[:bearer_token] || {}
        [helpers.decrypt_present(bearer[:token])]
      when 'api_key_header'
        api_key = config[:api_key_header] || {}
        [api_key[:header_name], helpers.decrypt_present(api_key[:header_value])]
      when 'oauth2'
        oauth2 = config[:oauth2] || {}
        [
          oauth2[:token_endpoint], # where the client-credential token is obtained
          oauth2[:client_id],
          helpers.decrypt_present(oauth2[:client_secret]),
          oauth2[:scope],
        ]
      else
        [] # 'none' adds nothing beyond endpoint + auth_type
      end
    end

    # Flattens the optional custom headers into name/value pairs for the key.
    helper :custom_header_key_elements do |config|
      headers = config[:custom_headers] || []
      headers.flat_map { |header| [header[:name], header[:value]] }
    end

    # Decrypts a secret string for use in the key input, tolerating a blank value.
    helper :decrypt_present do |secret|
      secret.present? ? decrypt_secret_string(secret) : ''
    end

    helper :parse_schema_json do |json_string|
      return nil if json_string.blank?

      parsed = begin
        JSON.parse(json_string)
      rescue JSON::ParserError => e
        fail_job!("Invalid schema JSON: #{e.message}")
      end

      # Support both raw __schema and wrapped { data: { __schema: ... } } formats
      if parsed.is_a?(Hash) && parsed['data'].is_a?(Hash) && parsed['data']['__schema'].present?
        parsed['data']['__schema']
      elsif parsed.is_a?(Hash) && parsed['__schema'].present?
        parsed['__schema']
      elsif parsed.is_a?(Hash) && parsed['types'].present?
        parsed
      else
        fail_job!('Unrecognized schema format. Expected introspection result with __schema or types.')
      end
    end

    # ──────────────────────────────────────────────
    # Connector-level Helpers: GraphQL Execution
    # ──────────────────────────────────────────────

    helper :graphql_call do |query, variables = nil, operation_name = nil|
      request_body = { query: query.gsub(/\s+/, ' ').strip }
      request_body[:variables] = helpers.decrypt_secret_strings_in_variables(variables) if variables.present?
      request_body[:operationName] = operation_name if operation_name.present?

      response = helpers.graphql_call_impl(request_body.to_json)

      {}.tap do |output|
        output[:data] = helpers.extract_data_from_graphql_response(response)
        output[:request_id] = response.headers['x-request-id']
      end
    end

    helper :graphql_call_impl do |request_body|
      endpoint = outbound_connection.config[:graphql_endpoint]
      response = http_post(endpoint, request_body, { 'content-type' => 'application/json' })
      backoff_if_needed(response, api_name: 'GraphQL')
      response
    end

    helper :decrypt_secret_strings_in_variables do |value|
      case value
      when Hash
        value.to_hash.transform_values { |v| helpers.decrypt_secret_strings_in_variables(v) }
      when Array
        value.map { |v| helpers.decrypt_secret_strings_in_variables(v) }
      when IPaaS::Encryption::SecretString
        decrypt_secret_string(value)
      else
        value
      end
    end

    helper :extract_data_from_graphql_response do |response|
      fail_job!("HTTP error from GraphQL API: #{response.status} '#{response.body}'") if response.status != 200

      body = JSON.parse(response.body)
      fail_job!("Errors from GraphQL API: #{body['errors'].to_json}") if body['errors'].present?

      data = body['data']
      fail_job!('No data from GraphQL API') if data.blank?
      data
    end
  end
end
