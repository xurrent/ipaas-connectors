class GraphqlConnector < IPaaS::Connector::Definition
  GqlSchema = IPaaS::Job::GraphQL::Schema
  GqlQuery = IPaaS::Job::GraphQL::QueryBuilder
  GqlFields = IPaaS::Job::GraphQL::FieldBuilder
  GqlResult = IPaaS::Job::GraphQL::Result
  GqlArtifactCache = IPaaS::Job::GraphQL::ArtifactCache
  Humanize = IPaaS::Job::Humanize
  CompactHash = IPaaS::Job::CompactHash

  INTROSPECTION_FAILURE_TTL = 10.minutes # configuration errors cached for 10 minutes
  INTROSPECTION_TRANSIENT_FAILURE_TTL = 30.seconds # transient errors cached for 30 seconds
  INTROSPECTION_FAILURE_MESSAGE_LIMIT = 200 # cap on the length of the error message

  # Cursor-pagination args the connection run handles positionally (first/after
  # literals); never serialized into arg_type_refs nor passed as a runtime variable.
  # A non-connection list query also drops `skip`, but a connection may still pass it,
  # so `skip` stays in the bundle and the simple-query branch excludes it at run time.
  CONNECTION_PAGINATION_ARGS = %w[first last before after].freeze
  SIMPLE_PAGINATION_ARGS = %w[first last before after skip].freeze

  # The static metadata tail every query/mutation output schema appends; rebuilt by
  # the output block and never serialized into the bundle.
  OUTPUT_STATIC_IDS = [:request_id].freeze

  # Static top-level input fields the builder always rebuilds; never serialized. The
  # query selector + pagination/refresh controls; the mutation selector + refresh. The
  # dynamic remainder (query args + include_fields; mutation input + include_fields) is
  # what collect_dynamic_descriptors captures so the warm input schema is field-identical.
  QUERY_STATIC_INPUT_IDS = [:object, :page_size, :max_results, :refresh_schema].freeze
  MUTATION_STATIC_INPUT_IDS = [:mutation, :refresh_schema].freeze

  # Keys a stored bundle part must carry to be usable; a part missing any (an entry
  # written by an older connector that shaped bundles differently) is ignored so run
  # rebuilds from the schema instead of reading an incompatible shape.
  BUNDLE_REQUIRED_KEYS = {
    [:query, 'in'] => %w[is_connection is_list field_selection arg_type_refs input_fields].freeze,
    [:query, 'out'] => %w[output_fields].freeze,
    [:mutation, 'in'] => %w[input_type_name field_selection input_fields].freeze,
    [:mutation, 'out'] => %w[output_fields].freeze,
  }.freeze

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
    # Connector-level Helpers: Schema Cache Store
    # ──────────────────────────────────────────────
    # Defined before the actions so the eagerly-built input_schema finds them registered.
    # Scoping the cache to the outbound connection lets all actions on it share one schema;
    # a nil store (unconfigured action) no-ops.

    helper :schema_cache_store do
      action&.outbound_connection
    end

    helper :schema_cache_read do |key|
      GqlArtifactCache.gql_cache_read(helpers.schema_cache_store, key)
    end

    helper :schema_cache_write do |key, value, ttl|
      GqlArtifactCache.gql_cache_write(helpers.schema_cache_store, key, value, ttl)
    end

    helper :schema_cache_clear do |key|
      GqlArtifactCache.gql_cache_clear(helpers.schema_cache_store, key)
    end

    # ──────────────────────────────────────────────
    # Connector-level Helpers: Selection Digest Inputs
    # ──────────────────────────────────────────────
    # The bundle is keyed on these RESOLVED values, which is correct for any mapping source: a
    # runtime-varying value just yields a different key (a fresh bundle, never stale), while a
    # stable value reuses one.

    helper :selection_value do |operation|
      action.input&.[](operation == :query ? :object : :mutation)
    end

    # The resolved include_fields hash drives field selection and the include subtree.
    # An explicit false leaf is preserved (the digest distinguishes {a: false} from {}).
    helper :resolved_include_fields do
      value = action.input&.[](:include_fields)
      value.is_a?(Hash) ? value.to_hash : {}
    end

    helper :cacheable_selection? do |operation|
      helpers.selection_value(operation).present?
    end

    # Only a present selection is cacheable; the required keys drive the fail-closed shape check.
    helper :load_bundle do |operation, part|
      next nil unless helpers.cacheable_selection?(operation)

      GqlArtifactCache.gql_load_bundle(
        helpers.schema_cache_store, operation, part,
        selection_name: helpers.selection_value(operation),
        include_fields: helpers.resolved_include_fields,
        required_keys: BUNDLE_REQUIRED_KEYS.fetch([operation, part]),
      )
    end

    # ──────────────────────────────────────────────
    # Connector-level Helpers: Root-Field Options Cache
    # ──────────────────────────────────────────────
    # The selector enumeration is independent of the chosen object/include_fields, so it is
    # shared by every query (resp. mutation) action on a connection, under the same generation.

    helper :read_root_options do |operation|
      GqlArtifactCache.gql_read_root_options(helpers.schema_cache_store, operation)
    end

    helper :write_root_options do |operation, options|
      GqlArtifactCache.gql_write_root_options(helpers.schema_cache_store, operation, options)
    end

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

      # Defined before input_schema (built eagerly at load) so it is registered. schema_data
      # lives only in this frame, so the after_update closure never captures the parsed schema
      # (which would pin the multi-MB blob per solution version and OOM).
      helper :build_query_input_fields do |schema|
        object_name = action.input&.[](:object)
        in_bundle = helpers.load_bundle(:query, 'in')
        root_options = in_bundle && helpers.read_root_options(:query) # fail closed if evicted

        if in_bundle && root_options
          # warm path: we have cached data, no need to read/process the (large) schema
          helpers.build_query_static_object_field(schema, root_options)
          helpers.restore_fields_from_descriptors(schema, in_bundle['input_fields'])
        else
          schema_data = helpers.schema_cache_read('gql_schema')
          # Fall back to the cached root-field options for the selector enumeration when
          # the schema has lapsed (it expires sooner than the bundle), so the dropdown is
          # never served empty while a generation's derived caches are still warm.
          query_options = if schema_data.present?
                            GqlSchema.gql_list_root_fields(schema_data, 'query')
                          else
                            helpers.read_root_options(:query) || []
                          end
          helpers.build_query_static_object_field(schema, query_options.presence)

          # Define include_fields early so its value is resolved in the first pass,
          # making it available in action.input when after_update regenerates the output schema.
          schema.field :include_fields, 'Include nested fields', :nested
          if schema_data.present? && object_name.present?
            helpers.add_input_fields_from_schema_data(schema, schema_data, object_name)
          end
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

        # On a cold cacheable build, write the 'in' bundle (run shape + dynamic input
        # descriptors collected from this just-built schema) and the root options so
        # later builds and runs take the warm path.
        if !(in_bundle && root_options) && object_name.present? &&
           helpers.cacheable_selection?(:query) && helpers.schema_cache_read('gql_schema').present?
          schema_data = helpers.schema_cache_read('gql_schema')
          helpers.write_bundle_part(:query, 'in', helpers.build_query_in_bundle(schema_data, object_name, schema))
          helpers.persist_root_options(schema_data, :query)
        end
      end

      # The object selector is static (never serialized into the bundle): the enum comes
      # from the root-field options on the warm path, the schema on a miss, or the
      # configure-connection notice when neither is available.
      helper :build_query_static_object_field do |schema, options|
        if options.present?
          schema.field :object, 'Query object', :string,
                       enumeration: options,
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
      end

      # The 'in' bundle: the run shape plus the dynamic input descriptors collected from
      # the just-built LIVE input schema. Collecting from the live schema keeps the warm
      # input build structurally identical to the cold one with no rebuild.
      helper :build_query_in_bundle do |schema_data, object_name, input_schema|
        helpers.build_query_bundle_shape(schema_data, object_name).tap do |bundle|
          bundle['input_fields'] = helpers.collect_dynamic_descriptors(input_schema, QUERY_STATIC_INPUT_IDS)
        end
      end

      # The schema-derived run inputs (connection/list shape, type names, field selection,
      # and the type-ref of every non-pagination arg) that run assembles the final query
      # and variables from without re-parsing the schema.
      helper :build_query_bundle_shape do |schema_data, object_name|
        node_type_name = GqlSchema.gql_resolve_connection_node_type(schema_data, 'query', object_name)
        if node_type_name.present?
          {
            'is_connection' => true,
            # Always present so the bundle-shape check can require it; a connection result
            # is flattened by process_connection_result, so run never reads is_list here.
            'is_list' => false,
            'node_type_name' => node_type_name,
            'field_selection' => GqlQuery.gql_build_field_selection(schema_data, node_type_name, 0,
                                                                    include_data: action.input),
            'arg_type_refs' => helpers.collect_arg_type_refs(schema_data, object_name),
          }
        else
          return_type_name = GqlSchema.gql_resolve_return_type_name(schema_data, 'query', object_name)
          {
            'is_connection' => false,
            'is_list' => helpers.list_return_type?(schema_data, object_name),
            'return_type_name' => return_type_name,
            'field_selection' => GqlQuery.gql_build_field_selection(schema_data, return_type_name, 0,
                                                                    include_data: action.input),
            'arg_type_refs' => helpers.collect_arg_type_refs(schema_data, object_name),
          }
        end
      end

      # The type-ref string of every root-field arg except the cursor-pagination args
      # (handled positionally by run), keyed by arg name, so run builds var defs from the
      # bundle. `skip` is kept (a connection may pass it); the simple branch drops it.
      helper :collect_arg_type_refs do |schema_data, object_name|
        gql_args = GqlSchema.gql_find_root_field(schema_data, 'query', object_name)&.[]('args') || []
        gql_args.each_with_object({}) do |arg, refs|
          next if CONNECTION_PAGINATION_ARGS.include?(arg['name'])

          refs[arg['name']] = GqlQuery.gql_type_ref_string(arg['type'])
        end
      end

      input_schema do
        # Built in a helper so schema_data stays out of this block's binding and is never
        # captured by the after_update closure below (stored on the cached Schema).
        helpers.build_query_input_fields(self)
        after_update do |_fields|
          helpers.refresh_dynamic_schemas(self, :object, 'query_result')
        end
      end

      output_schema 'query_result' do
        object_name = action.input&.[](:object)
        out_bundle = object_name.present? ? helpers.load_bundle(:query, 'out') : nil

        if out_bundle
          helpers.restore_fields_from_descriptors(self, out_bundle['output_fields'])
        elsif object_name.present?
          schema_data = helpers.schema_cache_read('gql_schema')
          helpers.add_query_fields_from_schema_data(self, schema_data, object_name) if schema_data.present?
        end

        field :request_id, 'Request ID', :string,
              visibility: 'optional'

        # On a cold cacheable build, write the 'out' bundle (dynamic output descriptors
        # collected from this just-built schema) so later builds and runs restore it.
        if !out_bundle && object_name.present? && helpers.cacheable_selection?(:query) &&
           helpers.schema_cache_read('gql_schema').present?
          helpers.write_bundle_part(:query, 'out',
                                    { 'output_fields' => helpers.collect_dynamic_descriptors(self, OUTPUT_STATIC_IDS) })
        end
      end

      iteration_state_schema do
        field :end_cursor, 'End cursor', :string, required: true
        field :fetched_count, 'Fetched count', :integer
      end

      run do
        object_name = input[:object]
        # Warm path: assemble the query from the 'in' bundle without parsing the schema.
        # Miss / non-cacheable: build from the shared schema and write the bundle.
        bundle = helpers.load_bundle(:query, 'in') || helpers.build_query_run_bundle(object_name)
        is_connection = bundle['is_connection']

        gql_output = if is_connection
                       helpers.run_connection_query(bundle, object_name)
                     else
                       helpers.run_simple_query(bundle, object_name)
                     end

        data = gql_output[:data]
        result = gql_output.except(:data)

        if is_connection
          helpers.process_connection_result(data, object_name, result)
        else
          object_data = data[object_name]
          fail_job!("No data returned for '#{object_name}'") if object_data.blank?

          # flatten nested connections so the data matches the generated schema
          if bundle['is_list']
            result[:nodes] = GqlResult.gql_flatten_nodes(object_data)
          elsif object_data.is_a?(Hash)
            # connection-shaped results route to process_connection_result,
            # so the flattened value is still a hash here
            result.merge!(GqlResult.gql_flatten_nodes(object_data))
          end
        end

        [{ output: result, schema_reference: 'query_result' }]
      end

      # Miss path for run (the schema-regeneration warm-up did not run, e.g. a cold
      # worker whose parse-time introspection failed): introspect, build the shape run
      # needs, and warm the 'in' bundle + root options from the live input schema so
      # later iterations and actions read it without re-parsing.
      helper :build_query_run_bundle do |object_name|
        schema_data = helpers.ensure_schema_cached
        if object_name.present? && helpers.cacheable_selection?(:query)
          # The parse-time build may have run without a schema (a cold worker whose
          # introspection then failed), leaving a degraded input/output schema. Now that
          # the schema is available, regenerate both so they write correct 'in'/'out'
          # bundles and root options, then restore the run shape from the fresh 'in'.
          action.regenerate_schema(action.output_schema('query_result'))
          action.regenerate_schema(action.input_schema)
          bundle = helpers.load_bundle(:query, 'in')
          next bundle if bundle
        end
        helpers.build_query_bundle_shape(schema_data, object_name)
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

      # field_selection and the arg type-refs come from the bundle (built once from the
      # schema); the page_size/cursor literals and the present?/compact_hash variable
      # gates are assembled here from live runtime values.
      helper :run_connection_query do |bundle, object_name|
        field_selection = bundle['field_selection']

        query_params = ["first: #{helpers.effective_page_size}"]
        cursor = iteration_state_value(:end_cursor)
        query_params << %(after: "#{cursor}") if cursor.present?

        var_defs, arg_params, variables = helpers.build_arg_clauses(bundle, CONNECTION_PAGINATION_ARGS)
        arg_params.each { |param| query_params << param }

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

      helper :run_simple_query do |bundle, object_name|
        field_selection = bundle['field_selection']

        var_defs, query_params, variables = helpers.build_arg_clauses(bundle, SIMPLE_PAGINATION_ARGS)

        var_clause = var_defs.any? ? "(#{var_defs.join(', ')})" : ''
        args_clause = query_params.any? ? "(#{query_params.join(', ')})" : ''
        query = "query#{var_clause} { #{object_name}#{args_clause} { #{field_selection} } }"
        helpers.graphql_call(query, variables.presence)
      end

      # Builds [var_defs, query_params, variables] from the bundle's arg_type_refs and the
      # live input values, skipping pagination args and blanks (after compacting hashes).
      helper :build_arg_clauses do |bundle, skip_args|
        var_defs = []
        query_params = []
        variables = {}

        (bundle['arg_type_refs'] || {}).each do |arg_name, type_ref|
          next if skip_args.include?(arg_name)
          next if input[arg_name.to_sym].blank?

          arg_value = input[arg_name.to_sym]
          arg_value = CompactHash.compact_hash(arg_value) if arg_value.is_a?(Hash)
          next if arg_value.blank?

          var_defs << "$#{arg_name}: #{type_ref}"
          query_params << "#{arg_name}: $#{arg_name}"
          variables[arg_name] = arg_value
        end

        [var_defs, query_params, variables]
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

      # Defined before input_schema (which runs eagerly at connector load) so the helper
      # is registered when first called. schema_data and the bundle stay local to this
      # helper and are never captured by the after_update closure (which lives on the
      # cached Schema) — see build_query_input_fields above.
      helper :build_mutation_input_fields do |schema|
        mutation_name = action.input&.[](:mutation)
        in_bundle = helpers.load_bundle(:mutation, 'in')
        root_options = in_bundle && helpers.read_root_options(:mutation) # fail closed if evicted

        if in_bundle && root_options
          # warm path: we have cached data, no need to read/process the (large) schema
          helpers.build_mutation_static_field(schema, root_options)
          helpers.restore_fields_from_descriptors(schema, in_bundle['input_fields'])
        else
          schema_data = helpers.schema_cache_read('gql_schema')
          # Fall back to the cached root-field options for the selector enumeration when
          # the schema has lapsed (it expires sooner than the bundle), so the dropdown is
          # never served empty while a generation's derived caches are still warm.
          mutation_options = if schema_data.present?
                               GqlSchema.gql_list_root_fields(schema_data, 'mutation')
                             else
                               helpers.read_root_options(:mutation) || []
                             end
          helpers.build_mutation_static_field(schema, mutation_options.presence)

          # Define include_fields early so its value is resolved in the first pass
          schema.field :include_fields, 'Include nested fields', :nested
          if schema_data.present? && mutation_name.present?
            helpers.add_mutation_input_fields(schema, schema_data, mutation_name)
          else
            schema.field :input, 'Input', :hash,
                         hint: 'The mutation input variables as a JSON object.',
                         required: true
          end
        end

        schema.field :refresh_schema, 'Refresh schema', :boolean,
                     hint: 'Check to clear the cached GraphQL schema and re-fetch it. ' \
                           'Useful after schema changes in the GraphQL API.',
                     visibility: 'optional',
                     default: false

        # On a cold cacheable build, write the 'in' bundle (run shape + dynamic input
        # descriptors collected from this just-built schema) and the root options.
        if !(in_bundle && root_options) && mutation_name.present? &&
           helpers.cacheable_selection?(:mutation) && helpers.schema_cache_read('gql_schema').present?
          schema_data = helpers.schema_cache_read('gql_schema')
          helpers.write_bundle_part(:mutation, 'in',
                                    helpers.build_mutation_in_bundle(schema_data, mutation_name, schema))
          helpers.persist_root_options(schema_data, :mutation)
        end
      end

      # The mutation selector is static (never serialized into the bundle): the enum comes
      # from the root-field options on the warm path, the schema on a miss, or the
      # configure-connection notice when neither is available.
      helper :build_mutation_static_field do |schema, options|
        if options.present?
          schema.field :mutation, 'Mutation', :string,
                       enumeration: options,
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
      end

      # The 'in' bundle: the run shape (input_type_name + field_selection built from the
      # merged mutation include_data) plus the dynamic input descriptors collected from
      # the just-built LIVE input schema. Collecting from the live schema keeps the warm
      # input build structurally identical to the cold one with no rebuild.
      helper :build_mutation_in_bundle do |schema_data, mutation_name, input_schema|
        return_type_name = GqlSchema.gql_resolve_return_type_name(schema_data, 'mutation', mutation_name)
        include_data = helpers.mutation_include_data(schema_data, return_type_name)
        {
          'input_type_name' => GqlSchema.gql_mutation_input_type_name(schema_data, mutation_name),
          'field_selection' => GqlQuery.gql_build_field_selection(schema_data, return_type_name, 0,
                                                                  include_data: include_data),
          'input_fields' => helpers.collect_dynamic_descriptors(input_schema, MUTATION_STATIC_INPUT_IDS),
        }
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
        out_bundle = mutation_name.present? ? helpers.load_bundle(:mutation, 'out') : nil

        if out_bundle
          helpers.restore_fields_from_descriptors(self, out_bundle['output_fields'])
        elsif mutation_name.present?
          schema_data = helpers.schema_cache_read('gql_schema')
          helpers.add_mutation_output_fields(self, schema_data, mutation_name) if schema_data.present?
        end

        field :request_id, 'Request ID', :string,
              visibility: 'optional'

        # On a cold cacheable build, write the 'out' bundle (dynamic output descriptors
        # collected from this just-built schema, including the always-present errors
        # field) so later builds and runs restore it.
        if !out_bundle && mutation_name.present? && helpers.cacheable_selection?(:mutation) &&
           helpers.schema_cache_read('gql_schema').present?
          helpers.write_bundle_part(:mutation, 'out',
                                    { 'output_fields' => helpers.collect_dynamic_descriptors(self, OUTPUT_STATIC_IDS) })
        end
      end

      run do
        mutation_name = input[:mutation]
        # Warm path: assemble the mutation from the 'in' bundle without parsing the schema.
        # Miss / non-cacheable: build from the shared schema and write the bundle.
        bundle = helpers.load_bundle(:mutation, 'in') || helpers.build_mutation_run_bundle(mutation_name)
        gql_output = helpers.run_mutation_query(mutation_name, bundle)
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

      # Miss path for run (the schema-regeneration warm-up did not run, e.g. a cold worker
      # whose parse-time introspection failed): introspect, build the run shape, and warm
      # the 'in' bundle + root options from the live input schema so later runs and actions
      # read it without re-parsing.
      helper :build_mutation_run_bundle do |mutation_name|
        schema_data = helpers.ensure_schema_cached
        if mutation_name.present? && helpers.cacheable_selection?(:mutation)
          # The parse-time build may have run without a schema (a cold worker whose
          # introspection then failed), leaving a degraded input/output schema. Now that
          # the schema is available, regenerate both so they write correct 'in'/'out'
          # bundles and root options, then restore the run shape from the fresh 'in'.
          action.regenerate_schema(action.output_schema('mutation_result'))
          action.regenerate_schema(action.input_schema)
          bundle = helpers.load_bundle(:mutation, 'in')
          next bundle if bundle
        end
        return_type_name = GqlSchema.gql_resolve_return_type_name(schema_data, 'mutation', mutation_name)
        include_data = helpers.mutation_include_data(schema_data, return_type_name)
        {
          'input_type_name' => GqlSchema.gql_mutation_input_type_name(schema_data, mutation_name),
          'field_selection' => GqlQuery.gql_build_field_selection(schema_data, return_type_name, 0,
                                                                  include_data: include_data),
        }
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

      # input_type_name and field_selection come from the bundle (built once from the
      # schema); the input value is passed as a variable so it never touches the text.
      helper :run_mutation_query do |mutation_name, bundle|
        mutation = "mutation($input: #{bundle['input_type_name']}!) " \
                   "{ #{mutation_name}(input: $input) { #{bundle['field_selection']} } }"
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

    # Whether our current configuration is fully warm, so regeneration can skip the schema fetch.
    helper :warm_for_regeneration? do |operation, selection_field|
      GqlArtifactCache.gql_warm_for_regeneration?(
        helpers.schema_cache_store, operation,
        selection_present: action.input&.[](selection_field).present?,
        selection_name: helpers.selection_value(operation),
        include_fields: helpers.resolved_include_fields,
        required_keys_in: BUNDLE_REQUIRED_KEYS.fetch([operation, 'in']),
        required_keys_out: BUNDLE_REQUIRED_KEYS.fetch([operation, 'out']),
      )
    end

    helper :refresh_dynamic_schemas do |context, selection_field, output_schema_ref|
      if action.input&.[](:refresh_schema)
        GqlArtifactCache.gql_invalidate(helpers.schema_cache_store,
                                        'gql_schema', helpers.introspection_failure_cache_key)
      end
      operation = selection_field == :object ? :query : :mutation
      unless helpers.warm_for_regeneration?(operation, selection_field)
        begin
          helpers.ensure_schema_cached
        rescue StandardError => e
          log("Schema introspection failed: #{e.message}")
        end
      end
      context.regenerate_schema(context.output_schema(output_schema_ref)) if action.input&.[](selection_field).present?
      context.regenerate_schema(context.input_schema)
    end

    # A present gql_schema is the single source of truth; an absent one re-fetches.
    helper :ensure_schema_cached do
      cached = helpers.schema_cache_read('gql_schema')
      next cached if cached.present?

      schema_data = helpers.fetch_schema
      fail_job!('No schema data available. Configure a schema source in the outbound connection.') if schema_data.blank?

      helpers.schema_cache_write('gql_schema', schema_data, 3600)
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
      cached_failure = helpers.schema_cache_read(helpers.introspection_failure_cache_key)
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
      helpers.schema_cache_write(helpers.introspection_failure_cache_key, bounded, ttl)
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
    # Connector-level Helpers: Schema Field Caching
    # ──────────────────────────────────────────────
    # Serialize/restore live in the shared FieldBuilder; the static-id lists stay connector-specific.

    helper :collect_dynamic_descriptors do |schema, static_ids|
      GqlFields.gql_collect_dynamic_descriptors(schema, static_ids)
    end

    helper :restore_fields_from_descriptors do |target, descriptors|
      GqlFields.gql_restore_fields_from_descriptors(target, descriptors)
    end

    # Writes one bundle part ('in' shape+input descriptors, or 'out' output descriptors)
    # under the current generation, establishing the generation when absent. Each schema
    # block writes its own part from its live schema. Returns the bundle.
    helper :write_bundle_part do |operation, part, bundle|
      GqlArtifactCache.gql_write_bundle_part(
        helpers.schema_cache_store, operation, part,
        selection_name: helpers.selection_value(operation),
        include_fields: helpers.resolved_include_fields, bundle: bundle,
      )
    end

    # Records the root-field options (selector enumeration) under the current generation
    # so the warm input-schema build restores the selector without reading the schema.
    helper :persist_root_options do |schema_data, operation|
      helpers.write_root_options(operation, GqlSchema.gql_list_root_fields(schema_data, operation.to_s))
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
