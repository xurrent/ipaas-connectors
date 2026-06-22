class XurrentGraphqlConnector < IPaaS::Connector::Definition
  connector '01962529-c8eb-7a89-a682-73d6f09541d6' do
    name 'Xurrent GraphQL Connector'
    avatar '/assets/icons/x-logo-webhook.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Direct access to the Xurrent GraphQL API. Exposes a generic GraphQL query action plus three higher-level helpers for paginated record retrieval and CMDB lookups (people and software). Use it when you need to read data from Xurrent that the dedicated **Xurrent** connector's typed actions do not cover, or when you need to drive your own paginated queries from a runbook.

      ## Prerequisites
      - A Xurrent account with API access.
      - Either an **OAuth Application** (Client credentials grant) configured from the Settings console in Xurrent, or a **Personal Access Token** generated from My Profile.

      ## Authentication
      Configure one of two credential modes on the outbound connection:

      ### OAuth2 Client Credentials
      Server-to-server. Create an OAuth Application from the Settings console in Xurrent (Client credentials grant), and paste the **Client ID** and **Client secret** into the connection.

      ### Personal Access Token
      Quick setup. Generate a token from **My Profile > Personal Access Tokens** in Xurrent and paste it as the **Personal Access Token** field. The token inherits the permissions of the user that created it. When set, PAT takes precedence and the OAuth client fields are not required.

      An optional **Account ID** overrides the iPaaS account when you need to target a different Xurrent account from the same connection. The connector sends it as the `x-xurrent-account` header.

      ## Triggers
      None. This connector is outbound only.

      ## Actions

      ### Xurrent GraphQL Query
      Minimal wrapper around the Xurrent GraphQL API. Send a raw query (with optional variables and operation name) and receive the raw `data` payload along with the rate-limit and cost-limit metadata returned by Xurrent.

      Use case: any read or mutation that is not covered by the higher-level actions — e.g. ad-hoc reporting queries, deep field selections, mutations driven by runbook input.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `query` | String | Yes | - | The GraphQL query or mutation document. |
      | `variables` | Hash | No | - | GraphQL variables. Secret-string values inside the hash are decrypted before the request is sent. |
      | `operation_name` | String | No | - | Operation name to execute when the document defines multiple. |

      #### Example Input

      ```json
      {
        "query": "query($id: ID!) { node(nodeID: $id) { ... on Person { id name primaryEmail } } }",
        "variables": { "id": "5C5jO0e..." },
        "operation_name": null
      }
      ```

      #### Output

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `data` | Hash | Yes | The GraphQL `data` payload returned by Xurrent. |
      | `ratelimit.limit` | Integer | No | Maximum requests permitted in the rate-limit window (`x-ratelimit-limit`). |
      | `ratelimit.remaining` | Integer | No | Requests remaining in the current window (`x-ratelimit-remaining`). |
      | `ratelimit.reset` | Integer | No | UTC epoch seconds when the rate-limit window resets (`x-ratelimit-reset`). |
      | `costlimit.limit` | Integer | No | Maximum cost points permitted in the 60-minute window (`x-costlimit-limit`). |
      | `costlimit.cost` | Integer | No | Cost of the current request (`x-costlimit-cost`). |
      | `costlimit.remaining` | Integer | No | Cost points remaining in the current window (`x-costlimit-remaining`). |
      | `costlimit.reset` | Integer | No | UTC epoch seconds when the cost window resets (`x-costlimit-reset`). |
      | `request_id` | String | No | The `x-request-id` header from the Xurrent API response. |

      #### Example Output

      ```json
      {
        "data": { "node": { "id": "5C5jO0e...", "name": "Ada Lovelace", "primaryEmail": "ada@example.com" } },
        "ratelimit": { "limit": 7200, "remaining": 7188, "reset": 1714492800 },
        "costlimit": { "limit": 5000, "cost": 12, "remaining": 4988, "reset": 1714492800 },
        "request_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      }
      ```

      #### Error Handling
      - **HTTP error** — the action fails the job with `HTTP error from Xurrent GraphQL API: <status> '<body>'` for any non-200 response that is not 429 or 503.
      - **GraphQL errors** — when the response body contains an `errors` array, the action fails the job with `Errors from Xurrent GraphQL API: <errors json>`.
      - **Empty data** — a 200 response with no `data` payload fails the job with `No data from Xurrent GraphQL API`.
      - **Rate limit (429)** / **Service unavailable (503)** — the action backs off for the duration in `Retry-After` (numeric seconds or HTTP-date) or 60 seconds when the header is missing or unparseable.

      ### Retrieve Xurrent Records
      This action retrieves all records of a certain type using the Xurrent GraphQL API. It builds a `connection(first, view, filter, order, after) { pageInfo, totalCount, nodes }` query, drives the cursor across pages via the iteration state, and emits one page per run.

      Use case: bulk export of a record type into a downstream CMDB or report; backfilling a system that needs the full set of Xurrent records of a given type.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `connection` | String | Yes | - | The GraphQL connection name (e.g. `people`, `requests`, `configurationItems`). Must match `[A-Za-z0-9]+`. |
      | `node_fields` | String | No | - | Additional fields to select on each node (e.g. `name primaryEmail`). `id` is always included. |
      | `filter` | Array of `{field, value}` | No | `[]` | Each entry becomes a `field: value` clause inside `filter: { … }`. `field` must match `[A-Za-z0-9]+`. `value` is inlined verbatim — quote string literals yourself (e.g. `""foo""`). |
      | `view` | String | No | - | View enum literal inlined as `view: <value>`. Each connection has its own view enum — e.g. `PersonView` accepts `all`, `all_with_roles`, `archive`, `current_account`, `trash`; `ConfigurationItemView` accepts `all`, `archive`, `current_account`, `spare_cis`, `supported_by_my_teams`, `trash`. Defaults to `current_account` when omitted. |
      | `order` | Array of `{field, direction}` | No | `[]` | Each entry becomes `{ field: <field>, direction: <asc|desc> }` inside `order: [ … ]`. |
      | `page_size` | Integer | No | `100` | Records per page, 1–100. |

      #### Example Input

      ```json
      {
        "connection": "people",
        "node_fields": "name primaryEmail",
        "filter": [{ "field": "disabled", "value": "false" }],
        "view": "all",
        "order": [{ "field": "name", "direction": "asc" }],
        "page_size": 50
      }
      ```

      #### Output

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `total_count` | Integer | Yes | `totalCount` returned by the connection. |
      | `has_next_page` | Boolean | Yes | `true` when another page is available — the iteration state captures `endCursor`. |
      | `nodes` | Array of Hash | Yes | Records on this page; each contains `id` plus any fields requested in `node_fields`. |
      | `ratelimit` | Nested | No | Same fields as **Xurrent GraphQL Query**. |
      | `costlimit` | Nested | No | Same fields as **Xurrent GraphQL Query**. |
      | `request_id` | String | No | The `x-request-id` header from the Xurrent API response. |

      #### Example Output

      ```json
      {
        "total_count": 412,
        "has_next_page": true,
        "nodes": [
          { "id": "5C5jO0e...", "name": "Ada Lovelace", "primaryEmail": "ada@example.com" }
        ],
        "costlimit": { "limit": 5000, "cost": 18, "remaining": 4970, "reset": 1714492800 }
      }
      ```

      #### Error Handling
      - **Empty connection result** — when the connection name returns no payload (e.g. an unknown connection or one the credentials cannot read), the action fails the job with `Content for connection`.
      - All HTTP, GraphQL, rate-limit, and cost-limit failure modes match **Xurrent GraphQL Query**.

      ### Fetch People from Xurrent for CMDB
      Fetch people by searching across multiple identifier fields (`authenticationID`, `primaryEmail`, `sourceID`, `employeeID`, `supportID`). Returns a hash keyed by the input identifier with person data (`id` and any requested node fields). Identifiers are accepted as `secret_string` so they round-trip through the platform encrypted; the action decrypts them only when building the GraphQL request.

      Use case: CMDB synchronisation where the source system supplies a list of user identifiers (emails, employee IDs) and the runbook needs to resolve each one to a Xurrent person record.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `identifiers` | Array of Secret string | Yes | - | Identifiers to resolve. Encrypted at rest for GDPR; decrypted only at request time. |
      | `identifier_fields` | Array of String | No | `["authenticationID", "primaryEmail", "sourceID", "employeeID", "supportID"]` | Person fields to search. The action issues one `people` query per field, all aliased into a single GraphQL request. |
      | `node_fields` | String | No | - | Additional Person fields to return on each record (e.g. `name jobTitle disabled`). `id` is always included. |
      | `page_size` | Integer | No | `100` | Identifiers per batch, 1–100. The action paginates over the input list, one batch per run. |

      #### Example Input

      ```json
      {
        "identifiers": ["ada@example.com", "alan@example.com"],
        "identifier_fields": ["primaryEmail"],
        "node_fields": "name jobTitle",
        "page_size": 100
      }
      ```

      #### Output

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `identifier_map` | Hash | Yes | Map keyed by the original (encrypted) identifier. Values are the matched person record. |
      | `records` | Array of Hash | Yes | Deduplicated person records found in this batch. Each contains `id` plus the requested `node_fields`. |
      | `has_next_page` | Boolean | Yes | `true` while more batches of input identifiers remain. |
      | `stats.total_found` | Integer | No | Number of distinct persons returned for this batch. |
      | `stats.total_searched` | Integer | No | Number of identifiers in the current batch. |
      | `stats.batches_processed` | Integer | No | Always `1` — emitted per page rather than as a running total. |
      | `ratelimit` | Nested | No | Same fields as **Xurrent GraphQL Query**. |
      | `costlimit` | Nested | No | Same fields as **Xurrent GraphQL Query**. |
      | `request_id` | String | No | The `x-request-id` header from the Xurrent API response. |

      #### Example Output

      ```json
      {
        "identifier_map": {
          "ada@example.com": { "id": "5C5jO0e...", "name": "Ada Lovelace", "jobTitle": "Engineer" },
          "alan@example.com": { "id": "9HpQ2k8...", "name": "Alan Turing", "jobTitle": "Researcher" }
        },
        "records": [
          { "id": "5C5jO0e...", "name": "Ada Lovelace", "jobTitle": "Engineer" },
          { "id": "9HpQ2k8...", "name": "Alan Turing", "jobTitle": "Researcher" }
        ],
        "has_next_page": false,
        "stats": { "total_found": 2, "total_searched": 2, "batches_processed": 1 }
      }
      ```

      #### Error Handling
      - All HTTP, GraphQL, rate-limit, and cost-limit failure modes match **Xurrent GraphQL Query**.
      - Identifiers that resolve to no person are absent from `identifier_map`. The runbook treats missing keys as "not found in Xurrent".
      - Each `identifier_fields` query is capped at 100 matches by the underlying `people(first: 100)` clause; if a single identifier matches more than 100 persons the extras are dropped.

      ### Fetch Software from Xurrent for CMDB
      Fetch configuration items (software) by searching across `name` and `alternateName` fields. Returns an array of software records and a hash keyed by the input software name with CI data. Defaults to CI statuses `reserved`, `being_built`, `installed`, `being_tested`, `standby_for_continuity`, and `in_production`.

      Use case: CMDB synchronisation where the source system reports installed software names and the runbook needs to map each to a Xurrent CI.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |---|---|---|---|---|
      | `software_names` | Array of String | Yes | - | Software names to resolve to Xurrent CIs. |
      | `statuses` | Array of String | No | `["reserved", "being_built", "installed", "being_tested", "standby_for_continuity", "in_production"]` | CI statuses to include. Values are Xurrent `CiStatus` enum members. |
      | `filter_fields` | Array of String | No | `["name", "alternateName"]` | Configuration-item fields to search across. The action issues one `configurationItems` query per field, aliased into a single GraphQL request. |
      | `node_fields` | String | No | - | Additional CI fields to return on each record. Inlined verbatim into the GraphQL `nodes { … }` selection set, so nested selections are supported (e.g. `label status product { brand model supplier { name } }`). `id`, `name`, and `alternateNames` are always included. |
      | `page_size` | Integer | No | `100` | Names per batch, 1–100. The action paginates over the input list, one batch per run. |

      #### Example Input

      ```json
      {
        "software_names": ["Slack", "Zoom"],
        "statuses": ["installed", "in_production"],
        "filter_fields": ["name", "alternateName"],
        "node_fields": "label status product { brand model }",
        "page_size": 100
      }
      ```

      #### Output

      | Field | Type | Required | Description |
      |---|---|---|---|
      | `records` | Array of Hash | Yes | Deduplicated CI records found in this batch. Each contains `id`, `name`, `alternateNames`, plus the requested `node_fields`. |
      | `name_to_record_map` | Hash | Yes | Map keyed by the input software name (and any of its alternate names that appear in the input). |
      | `has_next_page` | Boolean | Yes | `true` while more batches of input names remain. |
      | `stats.total_found` | Integer | No | Number of distinct CIs returned for this batch. |
      | `stats.total_searched` | Integer | No | Number of names in the current batch. |
      | `ratelimit` | Nested | No | Same fields as **Xurrent GraphQL Query**. |
      | `costlimit` | Nested | No | Same fields as **Xurrent GraphQL Query**. |
      | `request_id` | String | No | The `x-request-id` header from the Xurrent API response. |

      #### Example Output

      ```json
      {
        "records": [
          {
            "id": "C1abc...",
            "name": "Slack",
            "alternateNames": ["Slack Desktop"],
            "label": "Slack 4.40.0",
            "status": "in_production",
            "product": { "brand": "Slack Technologies", "model": "Slack Desktop" }
          }
        ],
        "name_to_record_map": {
          "Slack": {
            "id": "C1abc...",
            "name": "Slack",
            "alternateNames": ["Slack Desktop"],
            "label": "Slack 4.40.0",
            "status": "in_production",
            "product": { "brand": "Slack Technologies", "model": "Slack Desktop" }
          }
        },
        "has_next_page": false,
        "stats": { "total_found": 1, "total_searched": 2 }
      }
      ```

      #### Error Handling
      - All HTTP, GraphQL, rate-limit, and cost-limit failure modes match **Xurrent GraphQL Query**.
      - Names that match no CI are absent from `name_to_record_map`. The runbook treats missing keys as "not found in Xurrent".
      - Each `filter_fields` query is capped at 100 matches by the underlying `configurationItems(first: 100)` clause; if a single name matches more than 100 CIs the extras are dropped.

      ## Best Practices
      - Prefer the dedicated **Xurrent** connector (`Xurrent Query` / `Xurrent Mutation`) when its typed, schema-introspected actions cover your use case. Reach for **Xurrent GraphQL Connector** for queries that need raw control or high-volume pagination.
      - Set `node_fields` to the minimum set of fields the runbook actually consumes. Over-selecting inflates `costlimit` consumption and slows pagination.
      - On long-running iterations, branch on `has_next_page` and `costlimit.remaining` to schedule work — the connector backs off automatically on 429, but spreading load avoids hitting the wall in the first place.
      - Use **Personal Access Token** for one-off integrations and short-lived prototypes; switch to **OAuth2 Client Credentials** once the integration is owned by a service rather than a person, so it survives staff changes.
      - For CMDB sync flows, pass identifiers as encrypted secret strings where applicable (the **Fetch People from Xurrent for CMDB** action requires it). This keeps PII out of plain runbook logs.

      ## Common Use Cases
      - **Bulk CMDB seeding** — **Retrieve Xurrent Records** with `connection: "configurationItems"` and a `view`/`filter` matching the CIs to ingest, fed into the downstream CMDB writer.
      - **Person reconciliation** — source system emits a list of user emails; **Fetch People from Xurrent for CMDB** resolves each to a Xurrent person; the runbook updates the source system with Xurrent IDs.
      - **Software inventory mapping** — endpoint-management agent reports installed software names; **Fetch Software from Xurrent for CMDB** resolves each to a Xurrent CI; the runbook links discovered installations to their CIs.
      - **Custom export** — **Xurrent GraphQL Query** with a hand-tuned query and `operation_name`, used for reporting feeds that don't fit the paginated record shape.

      ## References
      - [Xurrent GraphQL API documentation](https://developer.xurrent.com/graphql/)
      - [Xurrent GraphQL service quotas](https://developer.xurrent.com/graphql/#service-quotas)
      - [GraphQL specification](https://spec.graphql.org/)
      - [RFC 6749: OAuth 2.0](https://www.rfc-editor.org/rfc/rfc6749)
      - [RFC 6750: Bearer Token Usage](https://www.rfc-editor.org/rfc/rfc6750)
    END_OF_DESCRIPTION

    outbound_connection do
      config_schema do
        field :credentials, 'Credentials', :nested,
              required: true do
          field :account_id, 'Account ID', :string,
                visibility: 'optional',
                hint: 'The Xurrent account identifier. Leave blank to use the current iPaaS account.'
          field :client_id, 'Client ID', :string,
                required: true
          field :client_secret, 'Client secret', :secret_string,
                required: true
          field :personal_access_token, 'Personal Access Token', :secret_string,
                visibility: 'optional',
                hint: 'When set, authenticates with a Personal Access Token instead of OAuth2 client credentials.'
        end

        env_validator = ->(value) do
          return true if value.blank?
          return true if value[:graphql_endpoint].present? && value[:oauth2_endpoint].present?

          value[:stage].present?
        end
        field :environment, 'Environment', :nested,
              visibility: 'optional',
              validator: env_validator do
          field :stage, 'Stage', :string,
                enumeration: %w[Demo QA Prod]
          field :region, 'Region', :string,
                enumeration: %w[au ch uk us]
          field :oauth2_endpoint, 'OAuth2 Endpoint', :uri,
                visibility: 'optional'
          field :graphql_endpoint, 'GraphQL Endpoint', :uri,
                visibility: 'optional'
        end

        # Make OAuth2 client credentials optional when a Personal Access Token is provided,
        # since PAT takes precedence in the authenticate block.
        after_update do |fields, new_values|
          credentials_field = fields.detect { |f| f.id == :credentials }
          pat_provided = new_values.dig(:credentials, :personal_access_token).present?
          credentials_field.fields.detect { |f| f.id == :client_id }.required = !pat_provided
          credentials_field.fields.detect { |f| f.id == :client_secret }.required = !pat_provided
          fields
        end
      end

      authenticate do |request|
        credentials_config = config[:credentials] || {}
        account_id = credentials_config[:account_id].presence || helpers.system_account_id
        request.headers['X-Xurrent-Account'] = account_id

        if credentials_config[:personal_access_token].present?
          token = decrypt_secret_string(credentials_config[:personal_access_token])
          request.headers['Authorization'] = "Bearer #{token}"
        else
          body = oauth2_client_credentials_body(credentials_config[:client_id],
                                                decrypt_secret_string(credentials_config[:client_secret]))
          request.headers['Authorization'] = oauth2_authorization_header(helpers.oauth_endpoint,
                                                                         body,
                                                                         account_id: account_id)
        end
      end

      config_tester do
        response = http_get(helpers.introspect_endpoint, nil, nil, open_timeout: 1, timeout: 2)
        if response.status == 200
          parsed = helpers.parse_introspection_response(response)
          scopes = Array(parsed['scopes'])
          if scopes.any?
            { status: :success, message: "Connection successful. Token scopes: #{scopes.join(', ')}." }
          else
            { status: :failed, message: 'Token is valid but has no scopes.' }
          end
        elsif [401, 403].include?(response.status)
          { status: :failed, message: "Xurrent rejected the credentials (HTTP #{response.status})." }
        elsif response.status == 400
          parsed = helpers.parse_introspection_response(response)
          { status: :failed, message: parsed['message'].presence || 'Xurrent rejected the request (HTTP 400).' }
        else
          {
            status: :error,
            message: "Token introspection failed (HTTP #{response.status}): '#{response.body}'",
          }
        end
      rescue IPaaS::Job::Outbound::CustomerCredentialsError => e
        { status: :failed, message: e.message }
      rescue JSON::ParserError
        { status: :error, message: "Token introspection returned an unparseable response (HTTP #{response.status})." }
      end

      helper :parse_introspection_response do |response|
        parsed = JSON.parse(response.body)
        raise JSON::ParserError unless parsed.is_a?(Hash)
        parsed
      end

      # Introspect lives on the oauth host; rebuild from the resolved oauth endpoint
      # so stage/region/custom-endpoint resolution is reused.
      helper :introspect_endpoint do
        uri = URI.parse(helpers.oauth_endpoint)
        port = uri.port == uri.default_port ? '' : ":#{uri.port}"
        "#{uri.scheme}://#{uri.host}#{port}/introspect"
      end
    end

    action '019320e9-e159-7bbf-983d-a861da9de712' do
      name 'Xurrent GraphQL Query'
      description 'Minimal wrapper around Xurrent GraphQL API.'
      avatar '/assets/icons/x-logo-graphql.svg'

      input_schema do
        field :query, 'Query', :string,
              required: true
        field :variables, 'Variables', :hash
        field :operation_name, 'Operation name', :string,
              visibility: 'optional'
      end

      output_schema do
        field :data, 'Query result',
              :hash

        field :ratelimit, 'Rate limit', :nested,
              visibility: 'optional' do
          field :limit,
                'Limit',
                :integer
          field :remaining,
                'Remaining',
                :integer
          field :reset,
                'Reset',
                :integer
        end

        field :costlimit, 'Cost limit', :nested,
              visibility: 'optional' do
          field :limit,
                'Limit',
                :integer
          field :cost,
                'Cost',
                :integer
          field :remaining,
                'Remaining',
                :integer
          field :reset,
                'Reset',
                :integer
        end

        field :request_id, 'Request ID', :string,
              visibility: 'optional'
      end

      run do
        output = helpers.graphql_call(input[:query], input[:variables], input[:operation_name])

        [{ output: output }]
      end
    end

    action '01961a26-09f7-78e4-b6d9-7b61f43a949a' do
      name 'Retrieve Xurrent Records'
      description 'This action retrieves all records of a certain type using the Xurrent GraphQL API.'
      avatar '/assets/icons/x-logo-graphql.svg'
      nested true

      input_schema do
        field :connection, 'Connection', :string,
              pattern: /\A[A-Za-z0-9]+\z/,
              required: true
        field :node_fields, 'Node fields', :string
        field :filter, 'Filter',
              [:nested],
              visibility: 'optional',
              default: [] do
          field :field, 'Field', :string,
                pattern: /\A[A-Za-z0-9]+\z/,
                required: true
          field :value, 'Filter value', :string,
                required: true
        end
        field :view, 'View', :string,
              visibility: 'optional'
        field :order, 'Order',
              [:nested],
              visibility: 'optional',
              default: [] do
          field :field, 'Field', :string,
                pattern: /\A[A-Za-z0-9]+\z/,
                required: true
          field :direction, 'Direction', :string,
                default: 'asc',
                enumeration: [
                  { id: 'asc', label: 'Ascending' },
                  { id: 'desc', label: 'Descending' },
                ]
        end
        field :page_size, 'Page size', :integer,
              min: 1, max: 100,
              visibility: 'optional',
              default: 100
      end

      output_schema 'page' do
        field :total_count, 'Total count', :integer
        field :has_next_page, 'Has next page', :boolean

        field :nodes, 'Records',
              :hash,
              array: true

        field :ratelimit, 'Rate limit', :nested,
              visibility: 'optional' do
          field :limit,
                'Limit',
                :integer
          field :remaining,
                'Remaining',
                :integer
          field :reset,
                'Reset',
                :integer
        end

        field :costlimit, 'Cost limit', :nested,
              visibility: 'optional' do
          field :limit,
                'Limit',
                :integer
          field :cost,
                'Cost',
                :integer
          field :remaining,
                'Remaining',
                :integer
          field :reset,
                'Reset',
                :integer
        end

        field :request_id, 'Request ID', :string,
              visibility: 'optional'
      end

      iteration_state_schema do
        field :end_cursor, 'End cursor', :string, required: true
      end

      run do
        query = <<~GRAPHQL
          { #{input[:connection]}(
              first: #{input[:page_size]}
              #{helpers.prepare_view_clause(input[:view])}
              #{helpers.prepare_filter_clause(input[:filter])}
              #{helpers.prepare_order_clause(input[:order])}
              #{helpers.prepare_after_clause(iteration_state_value(:end_cursor))}
            ) {
              pageInfo { hasNextPage endCursor }
              totalCount
              nodes { id
                #{input[:node_fields]}
              }
            } }
        GRAPHQL

        output = helpers.graphql_call(query)
        data = output[:data]
        query_result = data[input[:connection]]
        fail_job!('Content for connection') if query_result.blank?
        self.iteration_state_value = helpers.extract_next_iteration_state_value(query_result)

        page = output.except(:data)
        page[:total_count] = query_result['totalCount']
        page[:has_next_page] = iteration_state_value.present?
        page[:nodes] = query_result['nodes'] || []

        [{ output: page, schema_reference: 'page' }]
      end

      helper :prepare_filter_clause do |filter_input|
        next '' if filter_input.blank?

        filters = filter_input.map do |filter_expr|
          "#{filter_expr[:field]}: #{filter_expr[:value]}"
        end
        "filter: {#{filters.join(', ')}}"
      end

      helper :prepare_view_clause do |view_input|
        if view_input.blank?
          ''
        else
          "view: #{view_input}"
        end
      end

      helper :prepare_order_clause do |order_input|
        next '' if order_input.blank?

        orders = order_input.map do |order_expr|
          "{ field: #{order_expr[:field]}, direction: #{order_expr[:direction]} }"
        end
        "order: [#{orders.join(', ')}]"
      end

      helper :prepare_after_clause do |end_cursor|
        next '' if end_cursor.blank?

        %(after: "#{end_cursor}")
      end

      helper :extract_next_iteration_state_value do |query_result|
        end_cursor = query_result.dig('pageInfo', 'endCursor')
        if end_cursor.present? && query_result.dig('pageInfo', 'hasNextPage')&.to_s == 'true'
          { end_cursor: end_cursor }
        else
          nil
        end
      end
    end

    action '01973456-abcd-7890-b1c2-d3e4f5a6b7c8' do
      name 'Fetch People from Xurrent for CMDB'
      description 'Fetch people by searching across multiple identifier fields ' \
                  '(authenticationID, primaryEmail, sourceID, employeeID, supportID). ' \
                  'Returns a hash keyed by the input identifier with person data (id and any requested node fields).'
      avatar '/assets/icons/x-logo-graphql.svg'
      nested true

      input_schema do
        field :identifiers, 'Identifiers', [:secret_string],
              required: true,
              hint: 'Array of identifiers to search for (e.g., email addresses, employee IDs). ' \
                    'Values are encrypted for GDPR compliance.'
        field :identifier_fields, 'Identifier fields', [:string],
              visibility: 'optional',
              default: %w[authenticationID primaryEmail sourceID employeeID supportID]
        field :node_fields, 'Node fields', :string,
              visibility: 'optional'
        field :page_size, 'Page size', :integer,
              min: 1, max: 100,
              visibility: 'optional',
              default: 100
      end

      output_schema 'page' do
        field :identifier_map, 'Identifier map', :hash
        field :records, 'Person records', :hash, array: true
        field :has_next_page, 'Has next page', :boolean
        field :stats, 'Statistics', :nested,
              visibility: 'optional' do
          field :total_found, 'Total found', :integer
          field :total_searched, 'Total searched', :integer
          field :batches_processed, 'Batches processed', :integer
        end
        field :ratelimit, 'Rate limit', :nested,
              visibility: 'optional' do
          field :limit, 'Limit', :integer
          field :remaining, 'Remaining', :integer
          field :reset, 'Reset', :integer
        end
        field :costlimit, 'Cost limit', :nested,
              visibility: 'optional' do
          field :limit, 'Limit', :integer
          field :cost, 'Cost', :integer
          field :remaining, 'Remaining', :integer
          field :reset, 'Reset', :integer
        end
        field :request_id, 'Request ID', :string,
              visibility: 'optional'
      end

      iteration_state_schema do
        field :batch_index, 'Batch index', :integer, required: true
      end

      run do
        identifiers = input[:identifiers]
        page_size = input[:page_size]
        current_batch_index = iteration_state_value(:batch_index) || 0

        current_batch = helpers.extract_current_batch(identifiers, page_size, current_batch_index)
        query = helpers.build_people_search_query(input[:identifier_fields], input[:node_fields])

        identifier_map = {}
        records = []
        graphql_output = {}

        if current_batch.any?
          graphql_output = helpers.graphql_call(query, { values: current_batch }, nil)
          all_nodes = graphql_output[:data].values.flat_map { |field_result| field_result['nodes'] || [] }.compact
          identifier_lookup = helpers.build_identifier_lookup(current_batch)

          identifier_map = helpers.build_identifier_map(all_nodes, identifier_lookup)
          records = all_nodes.uniq { |p| p['nodeID'] }.map { |person| helpers.transform_person_node(person) }
        end

        total_batches = (identifiers.length.to_f / page_size).ceil
        has_next_page = (current_batch_index + 1) < total_batches
        self.iteration_state_value = has_next_page ? { batch_index: current_batch_index + 1 } : nil

        page_output = helpers.build_page_output(
          identifier_map: identifier_map,
          records: records,
          has_next_page: has_next_page,
          current_batch: current_batch,
          graphql_output: graphql_output
        )

        [{ output: page_output, schema_reference: 'page' }]
      end

      helper :extract_current_batch do |identifiers, page_size, batch_index|
        batch_start = batch_index * page_size
        batch_end = batch_start + page_size
        identifiers[batch_start...batch_end] || []
      end

      helper :build_identifier_lookup do |identifiers|
        identifiers.each_with_object({}) do |id, lookup|
          plain_id = id.is_a?(IPaaS::Encryption::SecretString) ? decrypt_secret_string(id) : id.to_s
          lookup[plain_id.downcase] = true
        end
      end

      helper :build_identifier_map do |all_nodes, identifier_lookup|
        all_nodes.each_with_object({}) do |person, result_hash|
          external_identifier = person['externalIdentifier']
          next unless external_identifier.present?

          key = external_identifier.to_s.downcase
          next unless identifier_lookup[key]

          result_hash[make_secret_string(key)] = helpers.transform_person_node(person)
        end
      end

      helper :transform_person_node do |person|
        person.except('externalIdentifier', 'nodeID').merge('id' => person['nodeID'])
      end

      helper :build_page_output do |identifier_map:, records:, has_next_page:, current_batch:, graphql_output:|
        page = {
          identifier_map: identifier_map,
          records: records,
          has_next_page: has_next_page,
          stats: {
            total_found: records.length,
            total_searched: current_batch.length,
            batches_processed: 1,
          },
        }

        page[:ratelimit] = graphql_output[:ratelimit] if graphql_output[:ratelimit]
        page[:costlimit] = graphql_output[:costlimit] if graphql_output[:costlimit]
        page[:request_id] = graphql_output[:request_id] if graphql_output[:request_id]

        page
      end

      helper :build_people_search_query do |identifier_fields, node_fields|
        query_parts = identifier_fields.map do |field|
          <<~GRAPHQL
            #{field}: people(first: 100 view: all filter: { #{field}: { values: $values }, disabled: false }) {
              nodes {
                externalIdentifier: #{field}
                nodeID: id
                #{node_fields}
              }
            }
          GRAPHQL
        end

        <<~GRAPHQL
          query ($values: [String!]!) {
            #{query_parts.join("\n")}
          }
        GRAPHQL
      end
    end

    action '01973456-abcd-7890-b1c2-d3e4f5a6b7c9' do
      name 'Fetch Software from Xurrent for CMDB'
      description 'Fetch configuration items (software) by searching across name and alternateName fields. ' \
                  'Returns an array of software records and a hash keyed by the input software name with CI data.'
      avatar '/assets/icons/x-logo-graphql.svg'
      nested true

      input_schema do
        field :software_names, 'Software Names', [:string],
              required: true
        field :statuses, 'CI Statuses', [:string],
              visibility: 'optional',
              default: %w[reserved being_built installed being_tested standby_for_continuity in_production]
        field :filter_fields, 'Filter fields', [:string],
              visibility: 'optional',
              default: %w[name alternateName],
              hint: 'Fields to filter on (e.g., ["name", "alternateName"])'
        field :node_fields, 'Node fields', :string,
              visibility: 'optional',
              hint: 'Additional GraphQL fields to retrieve (e.g., "version vendor description")'
        field :page_size, 'Page size', :integer,
              min: 1, max: 100,
              visibility: 'optional',
              default: 100
      end

      output_schema 'page' do
        field :records, 'Software records', :hash, array: true
        field :name_to_record_map, 'Name to record map', :hash,
              hint: 'Hash mapping software names (including alternate names) to their corresponding records'
        field :has_next_page, 'Has next page', :boolean
        field :stats, 'Statistics', :nested,
              visibility: 'optional' do
          field :total_found, 'Total found', :integer
          field :total_searched, 'Total searched', :integer
        end
        field :ratelimit, 'Rate limit', :nested,
              visibility: 'optional' do
          field :limit, 'Limit', :integer
          field :remaining, 'Remaining', :integer
          field :reset, 'Reset', :integer
        end
        field :costlimit, 'Cost limit', :nested,
              visibility: 'optional' do
          field :limit, 'Limit', :integer
          field :cost, 'Cost', :integer
          field :remaining, 'Remaining', :integer
          field :reset, 'Reset', :integer
        end
        field :request_id, 'Request ID', :string,
              visibility: 'optional'
      end

      iteration_state_schema do
        field :batch_index, 'Batch index', :integer, required: true
      end

      run do
        batch_index = iteration_state_value(:batch_index) || 0

        current_batch = helpers.extract_current_batch(input[:software_names], input[:page_size], batch_index)

        name_to_record_map = {}
        records = []
        graphql_output = {}

        if current_batch.any?
          query = helpers.build_software_search_query(input[:filter_fields], input[:node_fields])
          graphql_output = helpers.graphql_call(query, { statuses: input[:statuses], names: current_batch }, nil)

          records = graphql_output[:data].values.flat_map { |result| result['nodes'] || [] }.uniq { |node| node['id'] }
          name_to_record_map = helpers.build_name_to_record_map(records, current_batch)
        end

        total_batches = (input[:software_names].length.to_f / input[:page_size]).ceil
        has_next_page = (batch_index + 1) < total_batches
        self.iteration_state_value = has_next_page ? { batch_index: batch_index + 1 } : nil

        page_output = helpers.build_page_output(records, name_to_record_map, has_next_page, current_batch,
                                                graphql_output)

        [{ output: page_output, schema_reference: 'page' }]
      end

      helper :extract_current_batch do |software_names, page_size, batch_index|
        start_idx = batch_index * page_size
        software_names[start_idx, page_size] || []
      end

      helper :build_name_to_record_map do |all_nodes, current_batch|
        all_entries = all_nodes.each_with_object({}) do |node, hash|
          hash[node['name'].to_s] = node if node['name'].present?
          node['alternateNames']&.each { |alt_name| hash[alt_name] = node }
        end

        all_entries.slice(*current_batch.map(&:to_s))
      end

      helper :build_page_output do |records, name_to_record_map, has_next_page, current_batch, graphql_output|
        {
          records: records,
          name_to_record_map: name_to_record_map,
          has_next_page: has_next_page,
          stats: {
            total_found: records.length,
            total_searched: current_batch.length,
          },
          ratelimit: graphql_output[:ratelimit],
          costlimit: graphql_output[:costlimit],
          request_id: graphql_output[:request_id],
        }.compact
      end

      helper :build_software_search_query do |filter_fields, node_fields|
        query_parts = filter_fields.map do |field|
          <<~GRAPHQL
            #{field}: configurationItems(
              first: 100,
              filter: {
                ruleSet: { values: [software] },
                status: { values: $statuses },
                #{field}: { values: $names }
              }
            ) {
              nodes {
                id
                name
                alternateNames
                #{node_fields}
              }
            }
          GRAPHQL
        end

        <<~GRAPHQL
          query ($statuses: [CiStatus!]!, $names: [String]!) {
            #{query_parts.join("\n")}
          }
        GRAPHQL
      end
    end

    helper :graphql_call do |query, variables, operation_name|
      request_body = { query: query.gsub(/\s+/, ' ').strip }
      request_body[:variables] = helpers.decrypt_secret_strings_in_variables(variables) if variables.present?
      request_body[:operationName] = operation_name if operation_name.present?

      response = http_post(helpers.graphql_uri, request_body.to_json, { 'content-type' => 'application/json' })
      helpers.backoff_if_needed(response)

      {}.tap do |output|
        output[:data] = helpers.extract_data_from_graphql_response(response)
        output[:request_id] = response.headers['x-request-id']
        output[:ratelimit] = helpers.extract_ratelimit(response)
        output[:costlimit] = helpers.extract_costlimit(response)
      end
    end

    helper :decrypt_secret_strings_in_variables do |value|
      case value
      when Hash
        value.transform_values { |v| helpers.decrypt_secret_strings_in_variables(v) }
      when Array
        value.map { |v| helpers.decrypt_secret_strings_in_variables(v) }
      when IPaaS::Encryption::SecretString
        decrypt_secret_string(value)
      else
        value
      end
    end

    helper :extract_data_from_graphql_response do |response|
      fail_job!("HTTP error from Xurrent GraphQL API: #{response.status} '#{response.body}'") if response.status != 200

      body = JSON.parse(response.body)
      fail_job!("Errors from Xurrent GraphQL API: #{body['errors'].to_json}") if body['errors'].present?

      data = body['data']
      fail_job!('No data from Xurrent GraphQL API') if data.blank?

      data
    end

    helper :extract_ratelimit do |response|
      {
        limit: response.headers['x-ratelimit-limit'],
        remaining: response.headers['x-ratelimit-remaining'],
        reset: response.headers['x-ratelimit-reset'],
      }
    end

    helper :extract_costlimit do |response|
      {
        limit: response.headers['x-costlimit-limit'],
        cost: response.headers['x-costlimit-cost'],
        remaining: response.headers['x-costlimit-remaining'],
        reset: response.headers['x-costlimit-reset'],
      }
    end

    helper :backoff_if_needed do |response|
      retry_after = response.headers['Retry-After']
      if retry_after.present?
        retry_after_msg = " (retry after: #{retry_after})"
        if /^\d+$/.match(retry_after) && retry_after.to_i > 0
          retry_after = retry_after.to_i
        else
          begin
            parsed_retry = Time.parse(retry_after)
            retry_after = if parsed_retry > Time.current
                            parsed_retry - Time.current
                          else
                            nil
                          end
          rescue StandardError
            retry_after = nil
          end
        end
      end
      retry_after ||= 60.seconds
      if response.status == 429
        backoff("Xurrent rate limit hit#{retry_after_msg}. '#{response.body}'",
                retry_after: retry_after)
      end
      if response.status == 503
        backoff("Xurrent not available#{retry_after_msg}. '#{response.body}'",
                retry_after: retry_after)
      end
    end

    helper :oauth_endpoint do
      env_config = outbound_connection.config[:environment] || {}
      env_config[:oauth2_endpoint].presence ||
        if env_config[:stage].present?
          "https://oauth.#{helpers.xurrent_domain}/token"
        else
          helpers.system_oauth_endpoint || "https://oauth.#{helpers.xurrent_domain}/token"
        end
    end

    helper :graphql_uri do
      env_config = outbound_connection.config[:environment] || {}
      endpoint = env_config[:graphql_endpoint].presence
      endpoint ||= if env_config[:stage].present?
                     "https://graphql.#{helpers.xurrent_domain}"
                   else
                     helpers.system_graphql_endpoint || "https://graphql.#{helpers.xurrent_domain}"
                   end
      URI.parse(endpoint)
    end

    helper :xurrent_domain do
      env_config = outbound_connection.config[:environment] || {}
      stage = env_config[:stage]
      stage_domain = case stage
                     when 'Demo'
                       'xurrent-demo.com'
                     when 'QA'
                       'xurrent.qa'
                     else
                       'xurrent.com'
                     end
      region = env_config[:region]
      if stage != 'Demo' && region
        "#{region}.#{stage_domain}"
      else
        stage_domain
      end
    end

    helper :system_account_id do
      environment[:xurrent_ipaas_account_id]
    end

    helper :system_oauth_endpoint do
      environment[:xurrent_ipaas_oauth_endpoint]
    end

    helper :system_graphql_endpoint do
      environment[:xurrent_ipaas_graphql_endpoint]
    end
  end
end
