class LansweeperConnector < IPaaS::Connector::Definition
  # Lansweeper Integration constants
  LS_INTEGRATION_ID = 'a561a72d-aa5e-4c52-af6d-084129ab5f09'.freeze
  LS_INTEGRATION_VERSION = '1.0'.freeze
  API_BASE_URL = 'https://api.lansweeper.com/api'.freeze
  OAUTH_URL = "#{API_BASE_URL}/integrations/oauth".freeze
  GRAPHQL_URL = "#{API_BASE_URL}/v2/graphql".freeze
  DEFAULT_PAGE_SIZE = 100
  DEFAULT_CUTOFF_DAYS = 30

  connector '019b22da-f781-7c72-b3c6-5e796a404308' do
    name 'Lansweeper Connector'
    avatar '/assets/icons/lansweeper.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Connects to [Lansweeper](https://www.lansweeper.com/) via the Lansweeper GraphQL Data API to read sites, sources, asset types, and assets from your Lansweeper environment.

      ## Prerequisites
      - A Lansweeper account with API access.
      - An OAuth application registered in Lansweeper. See the [Quickstart guide](https://developer.lansweeper.com/docs/data-api/get-started/quickstart/) for setup instructions. Use the **Get OAuth Refresh Token** action to obtain the Refresh Token.

      ## Authentication
      Uses OAuth 2.0 refresh token flow. Configure the connection with the **Client ID**, **Client Secret**, and **Refresh Token** from your Lansweeper OAuth application.

      ## Triggers
      None. Outbound only.

      ## Actions

      ### Get OAuth Refresh Token

      Exchanges an OAuth 2.0 authorization code for access and refresh tokens.

      **Input**:
      - `client_id` (required) — OAuth application client ID
      - `client_secret` (required) — OAuth application client secret
      - `callback_url` (required) — redirect URI used in the authorization request
      - `authorization_code` (required) — authorization code received from Lansweeper

      **Output**:
      - `response` (required) — full HTTP response from the token endpoint
        - `status` — HTTP status code (200 for success, 400/401 for errors)
        - `body` — raw response body (JSON-encoded token response)
        - `headers` — response headers as `{ name, value }` entries
      - `refresh_token` — refresh token from the response body; empty string if the request failed

      **Use case**: obtain the long-lived refresh token used to configure a Lansweeper connection.

      **Example Output: success**:
      ```json
      {
        "response": {
          "status": 200,
          "body": "{"access_token":"eyJhbGciOi...","token_type":"Bearer","expires_in":3600,"refresh_token":"def502..."}",
          "headers": [
            {"name": "content-type", "value": "application/json"},
            {"name": "x-rate-limit", "value": "100"}
          ]
        },
        "refresh_token": "def502..."
      }
      ```

      **Example Output: error**:
      ```json
      {
        "response": {
          "status": 400,
          "body": "{"error":"invalid_grant","error_description":"Invalid authorization code"}",
          "headers": [
            {"name": "content-type", "value": "application/json"}
          ]
        },
        "refresh_token": ""
      }
      ```

      ### Get Sites

      Returns all sites your OAuth application can access.

      **Input**: None.

      **Output**: List of sites, each with `site_id` and `site_name`.

      **Use case**: discover available sites or validate access.

      ### Get Sources

      Returns all sources for a specified site. Each source is a Lansweeper data source (e.g. a scanning server or cloud connector).

      **Input**:
      - `site_id` (required) — unique identifier of the site

      **Output**: List of sources with ID, name, type, lifecycle state, and sync timestamps.

      **Use case**: discover sources within a site, or scope asset queries by source.

      **Example Input**:
      ```json
      {
        "site_id": "12345678-1234-1234-1234-123456789012"
      }
      ```

      **Example Output**:
      ```json
      {
        "total": 1,
        "sources": [
          {
            "source_id": "11111111-1111-1111-1111-111111111111",
            "site_id": "12345678-1234-1234-1234-123456789012",
            "name": "Main Server",
            "type": "IT",
            "external_id": "abc-123",
            "created_at": "2024-01-15T10:00:00Z",
            "state": "ACTIVE",
            "unlinked_on_date": null,
            "deleted_on_date": null,
            "first_sync_completed_on": "2024-01-15T11:30:00Z"
          }
        ]
      }
      ```

      ### Get Asset Types

      Returns all asset type names for a site (e.g. `Computer`, `Printer`, `Network Device`).

      **Input**:
      - `site_id` (required) — unique identifier of the site

      **Output**: Array of asset type name strings.

      **Use case**: discover available asset types, or scope **Get Assets** by type.

      **Example Input**:
      ```json
      {
        "site_id": "12345678-1234-1234-1234-123456789012"
      }
      ```

      **Example Output**:
      ```json
      {
        "asset_types": ["Computer", "Printer", "Network Device", "Mobile Device"]
      }
      ```

      ### Get Assets

      Returns paginated assets for a site, with filtering by asset type, source, IP address presence, and last-seen date.

      **Input**:
      - `site_id` (required) — unique identifier of the site
      - `import_type` (optional, default: `all`) — `all`, `ip_only`, or `selected_types_only`
      - `asset_types` (conditional) — asset type names to filter by; required when `import_type` is `selected_types_only`
      - `source_handling` (optional, default: `all`) — `all` or `selected_only`
      - `source_ids` (conditional) — source IDs to filter by; required when `source_handling` is `selected_only`
      - `cutoff_time` (optional) — return assets last seen after this time; defaults to 30 days ago

      **Output**: Paginated list of assets including name, type, IP address, last-seen timestamps, manufacturer, model, OS, installed software, hardware specs, and user associations (encrypted).

      **Use case**: asset inventory, device discovery, compliance monitoring, or ITSM integration.

      **Example Input — defaults**:
      ```json
      {
        "site_id": "12345678-1234-1234-1234-123456789012"
      }
      ```

      **Example Input — selected sources**:
      ```json
      {
        "site_id": "12345678-1234-1234-1234-123456789012",
        "import_type": "all",
        "source_handling": "selected_only",
        "source_ids": ["11111111-1111-1111-1111-111111111111"]
      }
      ```

      **Example Input — selected asset types**:
      ```json
      {
        "site_id": "12345678-1234-1234-1234-123456789012",
        "import_type": "selected_types_only",
        "asset_types": ["Computer", "Server", "Laptop"]
      }
      ```

      **Example Input — custom cutoff time**:
      ```json
      {
        "site_id": "12345678-1234-1234-1234-123456789012",
        "cutoff_time": "2024-01-01T00:00:00Z"
      }
      ```

      ## Rate Limiting
      Lansweeper enforces these limits on Data API queries (see [API restrictions](https://developer.lansweeper.com/docs/data-api/get-started/restrictions/)):
      - Up to **150 requests per minute**; exceeding this triggers a one-minute cooldown.
      - Up to **2000 synchronous requests per hour**.
      - Up to **30 element paths** per `assetResources` query.
      - Up to **100 filter conditions** per query.
      - Up to **4 MB** response size per page.

      | HTTP status | Connector behaviour |
      |---|---|
      | 429 Too Many Requests | Retry after `Retry-After` seconds (60 s default if header absent) |
      | 503 Service Unavailable | Retry with backoff |
      | 401 / 403 | Fail immediately; credential or permission issue |
      | Other 4xx | Fail immediately with error from Lansweeper |

      ## Best Practices
      - **Incremental syncs**: Set `cutoff_time` on **Get Assets** to the timestamp of your last successful sync. Use the max `last_seen` from that run as the next `cutoff_time`.
      - **Narrow by asset type**: Use `import_type = selected_types_only` with `asset_types = [...]` to reduce payload and GraphQL query cost.
      - **Narrow by source**: In multi-source environments, call **Get Sources** first, then pass selected IDs via `source_handling = selected_only` + `source_ids` on **Get Assets**.
      - **Discover IDs at runbook start**: Call **Get Sites** → **Get Sources** → **Get Asset Types** early. Avoid hard-coding site or source GUIDs.
      - **Refresh token**: Run **Get OAuth Refresh Token** once during connection setup; store the token in the connection's **Refresh Token** field.

      ## Common Use Cases
      - **CMDB sync**: mirror Lansweeper assets into Xurrent's CMDB on a schedule.
      - **Incident enrichment**: on incident creation, look up the affected host's asset details (IP, OS, installed software, hardware model).
      - **Licensing audit**: pull `softwares` arrays across all assets to reconcile installed vs. licensed software.
      - **Hardware lifecycle**: filter by `warranty_date` or `os_end_of_support_date` to identify assets due for refresh.
      - **Change management**: route change approvals using `state_name` and `manufacturer`/`model`.

      ## References
      - [Lansweeper](https://www.lansweeper.com/)
      - [Lansweeper Developer Portal](https://developer.lansweeper.com/)
      - [GraphQL API introduction](https://developer.lansweeper.com/docs/data-api/get-started/intro-to-graphql/)
      - [API endpoint & authentication](https://developer.lansweeper.com/docs/data-api/get-started/endpoint/)
      - [Quickstart guide](https://developer.lansweeper.com/docs/data-api/get-started/quickstart/)
      - [API restrictions](https://developer.lansweeper.com/docs/data-api/get-started/restrictions/)
    END_OF_DESCRIPTION

    outbound_connection do
      config_schema do
        field :credentials, 'Credentials', :nested,
              required: true do
          field :client_id, 'Client ID', :string,
                required: true
          field :client_secret, 'Client secret', :secret_string,
                required: true
          field :refresh_token, 'Refresh Token', :secret_string,
                required: true
        end
      end

      authenticate do |request|
        credentials_config = config[:credentials]
        body = {
          client_id: credentials_config[:client_id],
          client_secret: decrypt_secret_string(credentials_config[:client_secret]),
          grant_type: 'refresh_token',
          refresh_token: decrypt_secret_string(credentials_config[:refresh_token]),
        }

        request.headers['Authorization'] = oauth2_authorization_header("#{OAUTH_URL}/token", body)
        request.headers['Content-Type'] = 'application/json'
        request.headers['x-ls-integration-id'] = LS_INTEGRATION_ID
        request.headers['x-ls-integration-version'] = LS_INTEGRATION_VERSION
      end
    end

    action '019b22da-f782-7c72-b3c6-5e796a404308' do
      name 'Get OAuth Refresh Token'
      avatar '/assets/icons/lansweeper.svg'
      description <<~END_OF_DESCRIPTION
        Exchanges an OAuth 2.0 authorization code for access and refresh tokens.

        **Use case**: obtain the long-lived refresh token used to configure a Lansweeper connection.

        ### Input Parameters

        | Parameter | Type | Required | Description |
        |-----------|------|----------|-------------|
        | `client_id` | String | Yes | OAuth application client ID |
        | `client_secret` | Secret String | Yes | OAuth application client secret |
        | `callback_url` | String | Yes | Redirect URI used in the authorization request |
        | `authorization_code` | String | Yes | Authorization code received from Lansweeper |

        ### Example Input

        ```json
        {
          "client_id": "your-client-id",
          "client_secret": "your-client-secret",
          "callback_url": "https://your-app.example.com/oauth/callback",
          "authorization_code": "auth-code-from-lansweeper"
        }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `response` | Object | Full HTTP response from the token endpoint; see **Response object fields** below |
        | `refresh_token` | Secret String | Refresh token from the response body; empty string if the request failed |

        #### Response object fields

        | Field Name | Type | Description |
        |---|---|---|
        | `status` | Integer | HTTP status code (200 for success, 400/401 for errors) |
        | `body` | Secret String | Raw response body (JSON-encoded token response) |
        | `headers` | Array | Response headers as `{ name, value }` entries |

        ### Example Output: success

        ```json
        {
          "response": {
            "status": 200,
            "body": "{"access_token":"eyJhbGciOi...","token_type":"Bearer","expires_in":3600,"refresh_token":"def502..."}",
            "headers": [
              {"name": "content-type", "value": "application/json"},
              {"name": "x-rate-limit", "value": "100"}
            ]
          },
          "refresh_token": "def502..."
        }
        ```

        ### Example Output: error

        ```json
        {
          "response": {
            "status": 400,
            "body": "{"error":"invalid_grant","error_description":"Invalid authorization code"}",
            "headers": [
              {"name": "content-type", "value": "application/json"}
            ]
          },
          "refresh_token": ""
        }
        ```

        ### Best Practices
        - Run this action **once per connection setup.** The refresh token is long-lived; store it in the connection's **Refresh Token** field.
        - The `callback_url` must match the **Allowed callback URL** on your Lansweeper OAuth application; mismatches produce `invalid_grant`.
        - The authorization code is single-use and expires quickly; exchange it immediately after receiving it from Lansweeper.
      END_OF_DESCRIPTION

      input_schema do
        field :client_id, 'Client ID', :string, required: true
        field :client_secret, 'Client Secret', :secret_string, required: true
        field :callback_url, 'Callback URL', :string, required: true
        field :authorization_code, 'Authorization Code', :string, required: true
      end

      output_schema do
        field :response, 'Response', :nested, required: true do
          field :status, 'Status', :integer, required: true
          field :body, 'Body', :string, required: true
          field :headers, 'Headers', [:nested], default: [] do
            field :name, 'Name', :string, required: true
            field :value, 'Value', :string, required: true
          end
        end
        field :refresh_token, 'Refresh Token', :secret_string
      end

      run do
        client_secret = decrypt_secret_string(input[:client_secret])

        result = helpers.exchange_code_for_token(input[:client_id], client_secret, input[:authorization_code],
                                                 input[:callback_url])

        [{
          output: {
            response: result['response'],
            refresh_token: result['refresh_token'],
          },
        }]
      end
    end

    action '019b22db-f781-7c72-b3c6-5e796a404308' do
      name 'Get Sites'
      avatar '/assets/icons/lansweeper.svg'
      description <<~END_OF_DESCRIPTION
        Returns all sites your OAuth application can access.

        **Use case**: discover available sites or validate access.

        ### Input Parameters
        None.

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `sites` | Array | One object per site: `site_id`, `site_name` |

        ### Example Output

        ```json
        {
          "sites": [
            {
              "site_id": "12345678-1234-1234-1234-123456789012",
              "site_name": "Main Site"
            },
            {
              "site_id": "87654321-4321-4321-4321-210987654321",
              "site_name": "Remote Office"
            }
          ]
        }
        ```

        ### Best Practices
        - Call once at the start of a runbook; cache the result since site IDs rarely change.
        - If this action returns "Not authorized for any sites", review the OAuth application's permissions in Lansweeper.
      END_OF_DESCRIPTION

      output_schema do
        field :sites, 'Sites', :nested,
              array: true do
          field :site_id, 'Site ID', :string, required: true
          field :site_name, 'Site Name', :string, required: true
        end
      end

      run do
        query = '{ authorizedSites { sites { id name } } }'
        result = helpers.graphql_query(query)

        fail_job!("Unable to query accessible Lansweeper sites: #{result[:error]}") if result[:error]

        fail_job!('No authorizedSites in Lansweeper response') unless result['authorizedSites']

        sites = result.dig('authorizedSites', 'sites') || []
        fail_job!('Not authorized for any sites') if sites.empty?

        sites_data = sites.map { |site| { site_id: site['id'], site_name: site['name'] } }

        [{ output: { sites: sites_data } }]
      end
    end

    action '019b22dc-f781-7c72-b3c6-5e796a404308' do
      name 'Get Sources'
      avatar '/assets/icons/lansweeper.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Returns all sources for a site. Each source is a Lansweeper data source (e.g. a scanning server or cloud connector).

        **Use case**: discover sources within a site, or scope asset queries by source.

        ### Input Parameters

        | Parameter | Type | Required | Description |
        |-----------|------|----------|-------------|
        | `site_id` | String | Yes | Unique identifier of the site |
        | `page_size` | Integer | No | Sources fetched per page (default 100, max 100). Mainly useful for testing; the action paginates through all sources regardless. |

        ### Example Input

        ```json
        {
          "site_id": "12345678-1234-1234-1234-123456789012"
        }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `total` | Integer | Total number of sources returned by the source query |
        | `sources` | Array | One object per source; see **Source object fields** below |

        #### Source object fields

        | Field Name | Type | Description |
        |---|---|---|
        | `source_id` | String | Unique identifier |
        | `site_id` | String | Parent site ID |
        | `name` | String | Display name |
        | `type` | String | Source type (e.g. `IT`, `OT`, `IT_AGENT`, `CLOUD`, `NETWORK_DISCOVERY`, `MANUAL`) |
        | `external_id` | String | External identifier from the underlying data source |
        | `created_at` | DateTime | When the source was created |
        | `state` | String | Current lifecycle state (e.g. `ACTIVE`) |
        | `unlinked_on_date` | DateTime | When the source was unlinked (null if still linked) |
        | `deleted_on_date` | DateTime | When the source was deleted (null if active) |
        | `first_sync_completed_on` | DateTime | When the first sync completed |

        ### Example Output

        ```json
        {
          "total": 1,
          "sources": [
            {
              "source_id": "11111111-1111-1111-1111-111111111111",
              "site_id": "12345678-1234-1234-1234-123456789012",
              "name": "Main Server",
              "type": "IT",
              "external_id": "abc-123",
              "created_at": "2024-01-15T10:00:00Z",
              "state": "ACTIVE",
              "unlinked_on_date": null,
              "deleted_on_date": null,
              "first_sync_completed_on": "2024-01-15T11:30:00Z"
            }
          ]
        }
        ```

        ### Best Practices
        - Call after **Get Sites** to discover sources for the target site.
        - Pass them to **Get Assets** as `source_ids` to limit results to those sources.
      END_OF_DESCRIPTION

      input_schema do
        field :site_id, 'Site ID', :string, required: true
        field :page_size, 'Page Size', :integer,
              min: 1, max: 100,
              visibility: 'optional',
              default: DEFAULT_PAGE_SIZE,
              hint: 'Number of sources to retrieve per page (1-100). Defaults to 100. ' \
                    'The action paginates through all sources regardless.'
      end

      output_schema 'page' do
        field :total, 'Total', :integer
        field :has_next_page, 'Has next page', :boolean, required: true
        field :sources, 'Sources', :nested,
              array: true do
          field :source_id, 'Source ID', :string, required: true
          field :site_id, 'Site ID', :string
          field :name, 'Name', :string, required: true
          field :type, 'Type', :string
          field :external_id, 'External ID', :string
          field :created_at, 'Created At', :date_time
          field :state, 'State', :string
          field :unlinked_on_date, 'Unlinked On Date', :date_time
          field :deleted_on_date, 'Deleted On Date', :date_time
          field :first_sync_completed_on, 'First Sync Completed On', :date_time
        end
      end

      iteration_state_schema do
        field :next_cursor, 'Next cursor', :string, required: true
      end

      run do
        state = helpers.initialize_sources_state(input)
        query = helpers.build_sources_query(state)
        result = helpers.graphql_query(query, { siteId: state[:site_id] })

        fail_job!("Unable to query sources : #{result[:error]}") if result[:error]

        sources = result.dig('site', 'sources') || {}
        next_cursor = sources.dig('pagination', 'next')
        sources_data = helpers.transform_sources(sources['items'] || [])

        helpers.store_sources_iteration_state(next_cursor)

        [{
          output: { total: sources['total'] || sources_data.length, has_next_page: next_cursor.present?,
                    sources: sources_data, }, schema_reference: 'page',
        }]
      end
    end

    action '019b22dd-f781-7c72-b3c6-5e796a404308' do
      name 'Get Asset Types'
      avatar '/assets/icons/lansweeper.svg'
      description <<~END_OF_DESCRIPTION
        Returns all asset type names for a site (e.g. `Computer`, `Printer`, `Network Device`).

        **Use case**: discover available asset types, or scope **Get Assets** by type.

        ### Input Parameters

        | Parameter | Type | Required | Description |
        |-----------|------|----------|-------------|
        | `site_id` | String | Yes | Unique identifier of the site |

        ### Example Input

        ```json
        {
          "site_id": "12345678-1234-1234-1234-123456789012"
        }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `asset_types` | Array of String | Asset type names available for the site |

        ### Example Output

        ```json
        {
          "asset_types": ["Computer", "Printer", "Network Device", "Mobile Device"]
        }
        ```

        ### Best Practices
        - Validate `asset_types` values here before calling **Get Assets** with `import_type = selected_types_only`.
        - Asset-type names are case-sensitive. Copy values verbatim from this action's output.
      END_OF_DESCRIPTION

      input_schema do
        field :site_id, 'Site ID', :string, required: true
      end

      output_schema do
        field :asset_types, 'Asset Types', :string, array: true
      end

      run do
        query = <<~GRAPHQL
          query getAssetTypes($siteId: ID!) {
            site(id: $siteId) {
              id
              assetTypes
            }
          }
        GRAPHQL

        result = helpers.graphql_query(query, { siteId: input[:site_id] })

        fail_job!("Unable to query asset types: #{result[:error]}") if result[:error]

        asset_types = result.dig('site', 'assetTypes') || []

        [{ output: { asset_types: asset_types } }]
      end
    end

    action '019b22de-f781-7c72-b3c6-5e796a404308' do
      name 'Get Assets'
      avatar '/assets/icons/lansweeper.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Retrieves assets from a Lansweeper site with filtering and pagination support.

        **Use case**: asset inventory, device discovery, compliance monitoring, or ITSM integration.

        > The platform encrypts user-identifying fields (`user_name`, `users.name`, `users.email`, `users.full_name`) and returns them as secret strings.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | `site_id` | String | Yes | – | Unique identifier of the site |
        | `import_type` | String | No | `all` | `all`, `ip_only`, or `selected_types_only` |
        | `asset_types` | Array of String | Conditional | – | Asset-type names to filter by. Required when `import_type` is `selected_types_only` |
        | `source_handling` | String | No | `all` | `all` or `selected_only` |
        | `source_ids` | Array of String | Conditional | – | Source IDs to filter by. Required when `source_handling` is `selected_only` |
        | `cutoff_time` | DateTime | No | 30 days ago | Return assets last seen after this time |

        ### Example Input: defaults

        ```json
        {
          "site_id": "12345678-1234-1234-1234-123456789012"
        }
        ```

        ### Example Input: selected sources

        ```json
        {
          "site_id": "12345678-1234-1234-1234-123456789012",
          "import_type": "all",
          "source_handling": "selected_only",
          "source_ids": ["11111111-1111-1111-1111-111111111111"]
        }
        ```

        ### Example Input: selected asset types

        ```json
        {
          "site_id": "12345678-1234-1234-1234-123456789012",
          "import_type": "selected_types_only",
          "asset_types": ["Computer", "Server", "Laptop"]
        }
        ```

        ### Example Input: custom cutoff time

        ```json
        {
          "site_id": "12345678-1234-1234-1234-123456789012",
          "cutoff_time": "2024-01-01T00:00:00Z"
        }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `total` | Integer | Total matching assets; populated on the first page only |
        | `has_next_page` | Boolean | `true` while more pages remain |
        | `assets` | Array | One object per asset; see **Asset object fields** below |

        #### Asset object fields

        | Field Name | Type | Description |
        |---|---|---|
        | `key` | String | Lansweeper asset key |
        | `url` | String | Lansweeper UI URL for the asset |
        | `name` | String | Asset name |
        | `type` | String | Asset type (e.g. `Windows`, `Printer`) |
        | `description` | String | Free-text description |
        | `ip_address` | String | IP address |
        | `first_seen` | DateTime | When the asset was first discovered |
        | `last_seen` | DateTime | When the asset was last observed |
        | `last_changed` | DateTime | When the asset last changed |
        | `user_name` | Secret String | Primary user name (encrypted) |
        | `user_domain` | String | Primary user domain |
        | `manufacturer` | String | Asset manufacturer |
        | `model` | String | Asset model |
        | `serial_number` | String | Serial number |
        | `state_name` | String | Custom state name |
        | `purchase_date` | DateTime | Purchase date |
        | `warranty_date` | DateTime | Warranty end date |
        | `sku` | String | SKU |
        | `operating_system` | String | OS name |
        | `os_end_of_support_date` | Date | OS end-of-support date |
        | `users` | Array | Logged-in users; see **User object fields** below |
        | `softwares` | Array | Installed software: `[{ name }]` |
        | `processors` | Array | Processor details: `[{ number_of_cores }]` |
        | `memory_modules` | Array | Memory modules: `[{ size }]` (bytes) |

        #### User object fields

        | Field Name | Type | Description |
        |---|---|---|
        | `name` | Secret String | Username (encrypted) |
        | `email` | Secret String | User email (encrypted) |
        | `full_name` | Secret String | Full name (encrypted) |

        ### Example Output

        ```json
        {
          "total": 1,
          "has_next_page": false,
          "assets": [
            {
              "key": "asset-key-0001",
              "url": "https://app.lansweeper.com/site/asset/asset-key-0001",
              "name": "WKS-001",
              "type": "Windows",
              "description": "Engineering workstation",
              "ip_address": "192.168.1.100",
              "first_seen": "2024-03-01T08:15:00Z",
              "last_seen": "2025-11-10T14:22:00Z",
              "last_changed": "2025-11-10T14:22:00Z",
              "user_name": "[ENCRYPTED]",
              "user_domain": "CORP",
              "manufacturer": "Dell Inc.",
              "model": "OptiPlex 7090",
              "serial_number": "ABC123XYZ",
              "state_name": "Active",
              "purchase_date": "2023-06-15T00:00:00Z",
              "warranty_date": "2026-06-15T00:00:00Z",
              "sku": "OP7090-I7-16GB",
              "operating_system": "Windows 11 Pro",
              "os_end_of_support_date": "2031-10-14",
              "users": [
                { "name": "[ENCRYPTED]", "email": "[ENCRYPTED]", "full_name": "[ENCRYPTED]" }
              ],
              "softwares": [
                { "name": "Microsoft Office 365" },
                { "name": "Google Chrome" }
              ],
              "processors": [
                { "number_of_cores": 8 }
              ],
              "memory_modules": [
                { "size": 17179869184 },
                { "size": 17179869184 }
              ]
            }
          ]
        }
        ```

        ### Error Handling

        | Condition | Behaviour |
        |-----------|-----------|
        | GraphQL error (e.g. unauthorized site) | Fail immediately |
        | Non-200 HTTP response | Fail immediately |
        | Missing required conditional input (e.g. `asset_types` when `import_type = selected_types_only`) | Fail with descriptive message |
        | 429 Too Many Requests | Retry after `Retry-After` seconds |
        | 503 Service Unavailable | Retry with backoff |

        ### Best Practices
        - **Incremental syncs**: Set `cutoff_time` to the timestamp of your last successful sync. Use the max `last_seen` from this run as the next `cutoff_time`.
        - **Reduce payload**: Use `import_type = selected_types_only` with `asset_types = [...]` to pull only the device categories you need.
        - **Scope to sources**: In multi-source sites, set `source_handling = selected_only` and pass `source_ids` discovered via **Get Sources**.
        - **Pagination is automatic.** The platform re-invokes this action until all pages are consumed; `has_next_page` is informational.
        - **Use `total` as a progress signal**: It's returned on the first page only; persist it if you need to display progress across pages.
      END_OF_DESCRIPTION

      input_schema do
        field :site_id, 'Site ID', :string, required: true
        field :import_type, 'Import Type', :string,
              visibility: 'optional',
              default: 'all',
              enumeration: [
                { value: 'all', label: 'All Assets', id: 'all' },
                { value: 'ip_only', label: 'Only Assets With IP Address', id: 'ip_only' },
                { value: 'selected_types_only', label: 'Only Selected Asset Types', id: 'selected_types_only' },
              ]
        field :source_handling, 'Source Handling', :string,
              visibility: 'optional',
              default: 'all',
              enumeration: [
                { value: 'all', label: 'All Sources', id: 'all' },
                { value: 'selected_only', label: 'Only Selected Sources', id: 'selected_only' },
              ]
        field :source_ids, 'Source IDs', :string, array: true, visibility: 'optional'
        field :asset_types, 'Asset Types', :string, array: true, visibility: 'optional'
        field :cutoff_time, 'Cutoff Time', :date_time, visibility: 'optional'
      end

      output_schema 'page' do
        field :total, 'Total', :integer
        field :has_next_page, 'Has next page', :boolean, required: true
        field :assets, 'Assets', :nested,
              array: true do
          field :key, 'Key', :string, required: true
          field :url, 'URL', :string

          field :name, 'Name', :string
          field :type, 'Type', :string
          field :description, 'Description', :string
          field :ip_address, 'IP Address', :string
          field :first_seen, 'First Seen', :date_time
          field :last_seen, 'Last Seen', :date_time
          field :last_changed, 'Last Changed', :date_time
          field :user_name, 'User Name', :secret_string
          field :user_domain, 'User Domain', :string

          field :manufacturer, 'Manufacturer', :string
          field :model, 'Model', :string
          field :serial_number, 'Serial Number', :string
          field :state_name, 'State Name', :string
          field :purchase_date, 'Purchase Date', :date_time
          field :warranty_date, 'Warranty Date', :date_time
          field :sku, 'SKU', :string

          field :operating_system, 'Operating System', :string
          field :os_end_of_support_date, 'OS End of Support Date', :date

          field :users, 'Users', :nested, array: true do
            field :name, 'Name', :secret_string
            field :email, 'Email', :secret_string
            field :full_name, 'Full Name', :secret_string
          end

          field :softwares, 'Softwares', :nested, array: true do
            field :name, 'Name', :string
          end

          field :processors, 'Processors', :nested, array: true do
            field :number_of_cores, 'Number of Cores', :integer
          end

          field :memory_modules, 'Memory Modules', :nested, array: true do
            field :size, 'Size', :integer
          end
        end
      end

      iteration_state_schema do
        field :next_cursor, 'Next cursor', :string, required: true
        field :site_id, 'Site ID', :string, required: true
        field :source_ids, 'Source IDs', :string, array: true
        field :asset_types, 'Asset Types', :string, array: true
        field :import_type, 'Import Type', :string
        field :source_handling, 'Source Handling', :string
        field :last_seen_after, 'Last Seen After', :date_time
        field :page_size, 'Page size', :integer, required: true
      end

      run do
        import_type = input[:import_type] || 'all'
        source_handling = input[:source_handling] || 'all'

        helpers.validate_asset_inputs(import_type, source_handling, input)

        state = helpers.initialize_asset_state(input, import_type, source_handling)
        query = helpers.build_assets_query(state)
        result = helpers.graphql_query(query[:query], query[:variables])

        helpers.validate_asset_response(result)

        response_data = helpers.extract_asset_response_data(result)
        assets_data = helpers.transform_assets(response_data[:items])

        helpers.store_asset_iteration_state(response_data[:next_cursor], state)

        [{
          output: { total: response_data[:total], has_next_page: response_data[:next_cursor].present?,
                    assets: assets_data, }, schema_reference: 'page',
        }]
      end
    end

    helper :validate_asset_inputs do |import_type, source_handling, input|
      if import_type == 'selected_types_only' && input[:asset_types].blank?
        fail_job!('Asset Types is required when Import Type is "selected_types_only". ' \
                  'Please provide at least one asset type.')
      end

      if source_handling == 'selected_only' && input[:source_ids].blank?
        fail_job!('Source IDs is required when Source Handling is "selected_only". ' \
                  'Please provide at least one source ID.')
      end
    end

    helper :initialize_asset_state do |input, import_type, source_handling|
      {
        next_cursor: iteration_state_value(:next_cursor),
        site_id: input[:site_id],
        source_ids: source_handling == 'selected_only' ? input[:source_ids] : nil,
        asset_types: input[:asset_types],
        import_type: import_type,
        source_handling: source_handling,
        last_seen_after: input[:cutoff_time] || iteration_state_value(:last_seen_after) ||
          DEFAULT_CUTOFF_DAYS.days.ago.to_datetime,
        page_size: iteration_state_value(:page_size) || DEFAULT_PAGE_SIZE,
      }
    end

    helper :build_assets_query do |state|
      is_first_page = state[:next_cursor].blank?
      pagination = { limit: state[:page_size], page: is_first_page ? 'FIRST' : 'NEXT' }
      pagination[:cursor] = state[:next_cursor] if state[:next_cursor].present?

      filters = helpers.build_asset_filters(
        import_type: state[:import_type],
        last_seen_after: state[:last_seen_after],
        source_ids: state[:source_ids],
        asset_types: state[:asset_types]
      )

      total_field = is_first_page ? 'total' : ''
      query = <<~GRAPHQL
        query getAssetResources($siteId: ID!, $pagination: AssetsPaginationInputValidated, $fields: [String!]!) {
          site(id: $siteId) {
            assetResources(assetPagination: $pagination, fields: $fields, filters: #{filters}) {
              #{total_field}
              pagination { next }
              items
            }
          }
        }
      GRAPHQL

      { query: query,
        variables: { siteId: state[:site_id], pagination: pagination, fields: helpers.build_asset_fields_list }, }
    end

    helper :validate_asset_response do |result|
      fail_job!("Unable to query assets: #{result[:error]}") if result[:error]
      fail_job!('No site data in Lansweeper response') unless result['site']
    end

    helper :extract_asset_response_data do |result|
      asset_resources = result.dig('site', 'assetResources') || {}
      items = asset_resources['items'] || []
      {
        items: items,
        total: asset_resources['total'],
        next_cursor: asset_resources.dig('pagination', 'next'),
      }
    end

    helper :transform_assets do |items|
      items.map { |item| helpers.transform_single_asset(item) }
    end

    helper :transform_single_asset do |item|
      basic_info = item['assetBasicInfo'] || {}
      custom_info = item['assetCustom'] || {}
      os_info = item['operatingSystem'] || {}
      os_metadata = item.dig('recognitionInfo', 'osMetadata') || {}

      {
        key: item['key'],
        url: item['url'],
        name: basic_info['name'],
        type: basic_info['type'],
        description: basic_info['description'],
        ip_address: basic_info['ipAddress'],
        first_seen: basic_info['firstSeen'],
        last_seen: basic_info['lastSeen'],
        last_changed: basic_info['lastChanged'],
        user_name: basic_info['userName'].to_s,
        user_domain: basic_info['userDomain'],
        manufacturer: custom_info['manufacturer'],
        model: custom_info['model'],
        serial_number: custom_info['serialNumber'],
        state_name: custom_info['stateName'],
        purchase_date: custom_info['purchaseDate'],
        warranty_date: custom_info['warrantyDate'],
        sku: custom_info['sku'],
        operating_system: os_info['name'],
        os_end_of_support_date: os_metadata['endOfSupportDate'],
        **helpers.transform_asset_collections(item),
      }
    end

    helper :transform_asset_collections do |item|
      {
        users: (item['users'] || []).map do |u|
          { name: u['name'].to_s, email: u['email'].to_s, full_name: u['fullName'].to_s }
        end,
        softwares: (item['softwares'] || []).map { |s| { name: s['name'] } },
        processors: (item['processors'] || []).map { |p| { number_of_cores: p['numberOfCores'] } },
        memory_modules: (item['memoryModules'] || []).map { |m| { size: m['size'] } },
      }
    end

    helper :store_asset_iteration_state do |next_cursor, state|
      next self.iteration_state_value = nil unless next_cursor.present?

      self.iteration_state_value = {
        next_cursor: next_cursor,
        site_id: state[:site_id],
        source_ids: state[:source_ids],
        asset_types: state[:asset_types],
        import_type: state[:import_type],
        source_handling: state[:source_handling],
        last_seen_after: state[:last_seen_after],
        page_size: state[:page_size],
      }
    end

    helper :initialize_sources_state do |input|
      {
        next_cursor: iteration_state_value(:next_cursor),
        site_id: input[:site_id],
        page_size: input[:page_size] || DEFAULT_PAGE_SIZE,
      }
    end

    helper :build_sources_query do |state|
      pagination = if state[:next_cursor].present?
                     %(pagination: { limit: #{state[:page_size]}, page: NEXT, cursor: "#{state[:next_cursor]}" })
                   else
                     "pagination: { limit: #{state[:page_size]}, page: FIRST }"
                   end

      <<~GRAPHQL
        query listSources($siteId: ID!) {
          site(id: $siteId) {
            sources(
              #{pagination}
              filters: {
                conjunction: AND
                groups: [
                  {
                    conditions: [
                      { operator: EXISTS, path: "id", value: "true" }
                    ]
                    conjunction: AND
                  }
                ]
              }
            ) {
              total
              pagination { next }
              items {
                id
                type
                state {
                  value
                  unlinkedOnDate
                  deletedOnDate
                  firstSyncCompletedOn
                }
                siteId
                createdAt
                externalId
                displayName
              }
            }
          }
        }
      GRAPHQL
    end

    helper :transform_sources do |items|
      items.map do |inst|
        lifecycle = inst['state'] || {}
        {
          source_id: inst['id'],
          site_id: inst['siteId'],
          name: inst['displayName'] || inst['id'],
          type: inst['type'],
          external_id: inst['externalId'],
          created_at: inst['createdAt'],
          state: lifecycle['value'],
          unlinked_on_date: lifecycle['unlinkedOnDate'],
          deleted_on_date: lifecycle['deletedOnDate'],
          first_sync_completed_on: lifecycle['firstSyncCompletedOn'],
        }
      end
    end

    helper :store_sources_iteration_state do |next_cursor|
      next self.iteration_state_value = nil unless next_cursor.present?

      self.iteration_state_value = { next_cursor: next_cursor }
    end

    helper :exchange_code_for_token do |client_id, client_secret, auth_code, callback_url|
      token_request_body = {
        client_id: client_id,
        client_secret: client_secret,
        grant_type: 'authorization_code',
        code: auth_code,
        redirect_uri: callback_url,
      }

      response = http_post("#{OAUTH_URL}/token", token_request_body.to_json, { 'Content-Type' => 'application/json' },
                           skip_authentication: true)

      backoff_if_needed(response, api_name: 'Lansweeper')
      body = parse_json_response(response.body,
                                 error_message: "Lansweeper GraphQL API response was not JSON: '#{response.body}'")

      {
        'refresh_token' => body['refresh_token'].to_s,
        'response' => {
          'status' => response.status,
          'body' => response.body,
          'headers' => response.headers.map { |h, v| { 'name' => h, 'value' => v } },
        },
      }
    end

    helper :graphql_query do |query, variables = {}|
      request_body = { query: query }
      request_body[:variables] = variables if variables.any?
      response = http_post(GRAPHQL_URL, request_body.to_json, { 'Content-Type' => 'application/json' })

      backoff_if_needed(response, api_name: 'Lansweeper')

      unless response.status == 200
        fail_job!("HTTP error from Lansweeper GraphQL API: #{response.status} '#{response.body}'")
      end

      body = parse_json_response(response.body,
                                 error_message: "Lansweeper GraphQL API response was not JSON: '#{response.body}'")

      if body['errors']
        { error: "GraphQL errors: #{body['errors'].to_json}" }
      elsif !body['data']
        fail_job!("No data in Lansweeper GraphQL response: '#{response.body}'")
      else
        body['data']
      end
    end

    helper :build_asset_filters do |import_type:, last_seen_after:, source_ids:, asset_types:|
      filters = [
        helpers.build_asset_type_filter(asset_types),
        helpers.build_ip_filter(import_type, asset_types),
        helpers.build_last_seen_filter(last_seen_after),
        helpers.build_source_filter(source_ids),
      ].compact

      filters.any? ? "{ conjunction: AND\n groups: [ #{filters.join(",\n")} ]\n}" : '{ conjunction: AND groups: [] }'
    end

    helper :build_asset_type_filter do |asset_types|
      next nil unless asset_types.present?
      regex_values = helpers.get_asset_type_regexs(asset_types)
      conditions = regex_values.map { |regex| %({ operator: REGEXP, path: "assetBasicInfo.type", value: "#{regex}" }) }
      helpers.create_conjunction('OR', *conditions)
    end

    helper :build_ip_filter do |import_type, asset_types|
      if asset_types.present? || import_type == 'all'
        nil
      elsif import_type == 'ip_only'
        helpers.create_conjunction('AND', %({ operator: EXISTS, path: "assetBasicInfo.ipAddress", value: "true" }))
      end
    end

    helper :build_last_seen_filter do |last_seen_after|
      next nil unless last_seen_after.present?
      cutoff_iso = last_seen_after.to_datetime.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')
      helpers.create_conjunction(
        'OR',
        %({ operator: GREATER_THAN, path: "assetBasicInfo.lastSeen", value: "#{cutoff_iso}" }),
        '{ operator: EXISTS, path: "assetBasicInfo.lastSeen", value: "false" }'
      )
    end

    helper :build_source_filter do |source_ids|
      next nil unless source_ids.present?
      # Lansweeper's assetResources filter still uses the "installationId" path; a source's `id` is the
      # value to pass here. Switch this path to "sourceId" once Lansweeper exposes it on assetResources.
      conditions = source_ids.map { |id| %({ operator: EQUAL, path: "installationId", value: "#{id}" }) }
      helpers.create_conjunction('OR', *conditions)
    end

    helper :build_asset_fields_list do
      [
        '_id', 'key', 'url',
        *helpers.prefix_fields('assetBasicInfo',
                               %w[name type description ipAddress firstSeen lastSeen lastChanged userName userDomain]),
        *helpers.prefix_fields('assetCustom',
                               %w[model manufacturer stateName purchaseDate warrantyDate serialNumber sku]),
        'operatingSystem.name',
        *helpers.prefix_fields('recognitionInfo.osMetadata', %w[name endOfSupportDate]),
        *helpers.prefix_fields('users', %w[name email fullName]),
        'softwares.name',
        'memoryModules.size',
        'processors.numberOfCores',
      ]
    end

    helper :prefix_fields do |prefix, fields|
      fields.map { |field| "#{prefix}.#{field}" }
    end

    helper :get_asset_type_regexs do |asset_types|
      valid_types = (asset_types || []).compact
      next [] if valid_types.empty?
      first_regex, remaining = helpers.first_regex_value(valid_types)
      regexs = [first_regex]
      regexs += helpers.get_asset_type_regexs(remaining) if remaining.present?
      regexs
    end

    helper :first_regex_value do |asset_types|
      max_length = 100
      selected = []

      asset_types.each do |type|
        next if type.length > max_length
        test_regex = helpers.array_to_regex_value(selected + [type])
        break if test_regex.length > max_length
        selected << type
      end

      [helpers.array_to_regex_value(selected), asset_types[selected.length..]]
    end

    helper :array_to_regex_value do |values|
      values.map { |v| "^#{helpers.regex_escape(v)}$" }.join('|')
    end

    helper :regex_escape do |value|
      value.gsub(/[.*+?^${}()|\[\]\\]/, '\\\\\&')
    end

    helper :create_conjunction do |operator, *conditions|
      <<~CONJUNCTION
        { conjunction: #{operator}
          conditions: [ #{conditions.join(",\n")} ]
        }
      CONJUNCTION
    end
  end
end
