class DatadogConnector < IPaaS::Connector::Definition
  connector '019ccf8a-e9c0-70ea-980c-ee7ed4fa2e80' do
    name 'Datadog Connector'
    avatar '/assets/icons/datadog.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Connects to [Datadog](https://www.datadoghq.com/) to fetch monitored hosts for syncing into Xurrent's CMDB.

      ## Prerequisites
      - A Datadog account on any [supported site](https://docs.datadoghq.com/getting_started/site/).
      - An **API key** from **Organization Settings → API Keys** ([docs](https://docs.datadoghq.com/account_management/api-app-keys/)).
      - An **Application key** from **Organization Settings → Application Keys** that carries the `hosts_read` scope.

      ## Authentication
      Header-based. Each outbound request carries `DD-API-KEY` and `DD-APPLICATION-KEY`, populated from the connection's **API Key** and **Application Key** credential fields. No OAuth flow is involved.

      ## Configuration
      Pick a **Region** matching your Datadog site. The connector routes all calls to the region's API host:

      | Region | API base URL |
      |---|---|
      | US1 | `api.datadoghq.com` |
      | US3 | `api.us3.datadoghq.com` |
      | US5 | `api.us5.datadoghq.com` |
      | EU1 | `api.datadoghq.eu` |
      | US1-FED | `api.ddog-gov.com` |
      | AP1 | `api.ap1.datadoghq.com` |
      | AP2 | `api.ap2.datadoghq.com` |

      ## Triggers
      None — this connector is outbound only.

      ## Actions
      ### Fetch hosts
      Retrieves all hosts from Datadog with pagination support using the [Hosts API (v1)](https://docs.datadoghq.com/api/latest/hosts/).

      **Use case**: populate or refresh the list of Datadog-monitored hosts in Xurrent's CMDB. Use the **From** field to fetch only hosts reported at or after a specific time, which is useful for incremental CMDB updates.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |-----------|------|----------|---------|-------------|
      | page_size | Integer | No | 100 | Number of hosts per page (1-1000) |
      | from | Integer | No | - | Epoch seconds for incremental sync |
      | filter | String | No | - | String to filter search results |
      | sort_field | String | No | - | Field to sort hosts by |
      | sort_dir | String | No | - | Sort direction (asc or desc) |
      | include_muted_hosts_data | Boolean | No | - | Include muted hosts data |
      | include_hosts_metadata | Boolean | No | - | Include additional metadata |

      #### Example Input

      ```json
      {
        "page_size": 100,
        "from": 1771410150,
        "filter": "my-host",
        "sort_dir": "asc"
      }
      ```

      #### Output

      | Field Name | Type | Description |
      |---|---|---|
      | `total_matching` | Integer | Total hosts matching the query |
      | `total_returned` | Integer | Hosts returned in this page |
      | `has_next_page` | Boolean | `true` while more pages remain |
      | `host_list` | Array | One object per host — see **Host object fields** below |

      ##### Host object fields

      | Field Name | Type | Description |
      |---|---|---|
      | `id` | Integer | Datadog host ID. For Amazon EC2 hosts this field is replaced by `aws_id` |
      | `aws_id` | Integer | AWS host ID. Returned in place of `id` when the host is an Amazon EC2 instance |
      | `name` | String | Host display name |
      | `host_name` | String | Hostname reported by the agent |
      | `aliases` | Array | Host aliases |
      | `apps` | Array | Applications running on the host |
      | `aws_name` | String | AWS name (when available) |
      | `sources` | Array | Data sources reporting this host |
      | `up` | Boolean | Whether the host is currently reporting |
      | `is_muted` | Boolean | Whether the host is muted |
      | `mute_timeout` | Integer | Mute timeout (timestamp in seconds) |
      | `last_reported_time` | Integer | Last report time (timestamp in seconds) |
      | `tags_by_source` | Object | Tags grouped by source |
      | `meta` | Object | Agent, OS, and Gohai metadata (when **Include hosts metadata** is on) |
      | `metrics` | Object | Basic metrics — `cpu`, `iowait`, `load` |

      #### Example Output

      ```json
      {
        "total_matching": 1,
        "total_returned": 1,
        "has_next_page": false,
        "host_list": [
          {
            "id": 123145537712914,
            "name": "Xurrent-FNX2Y3Q7FK",
            "host_name": "Xurrent-FNX2Y3Q7FK",
            "aliases": ["Xurrent-FNX2Y3Q7FK"],
            "apps": ["agent", "ntp"],
            "sources": ["agent"],
            "up": true,
            "is_muted": false,
            "mute_timeout": null,
            "last_reported_time": 1770967634,
            "tags_by_source": {
              "Datadog": ["host:Xurrent-FNX2Y3Q7FK"]
            },
            "meta": {
              "cpu_cores": 12,
              "agent_version": "7.75.3",
              "timezones": ["IST"],
              "platform": "darwin",
              "machine": "arm64",
              "processor": "Apple M4 Pro",
              "install_method": {
                "installer_version": null,
                "tool": null,
                "tool_version": "install_script_mac"
              },
              "logs_agent": {
                "transport": ""
              },
              "agent_flavor": "agent",
              "host_id": 123145537712914,
              "gohai": {
                "cpu": { "cpu_cores": "12", "model_name": "Apple M4 Pro" },
                "memory": { "swap_total": "2097152kB", "total": "25769803776" }
              }
            },
            "metrics": {
              "cpu": 8.087143,
              "iowait": 0,
              "load": 0.1817419
            }
          }
        ]
      }
      ```

      #### Error Handling
      The job fails immediately on 400 / 401 / 403 responses (invalid input or credential/scope issue). On 429 (rate limited) or 5xx server errors, the connector waits for the time in `X-RateLimit-Reset` and retries automatically.

      #### Best Practices
      - **Incremental**: Use `from` set to the epoch-seconds of your last successful sync; store the max `last_reported_time` seen in this run for the next run's `from`.
      - **Full metadata off by default**: Set `include_hosts_metadata = true` only when you need agent / OS / Gohai details — otherwise leave it off to reduce payload.
      - **Deterministic paging**: Set `sort_field = "name"` and `sort_dir = "asc"` to page through hosts in a stable order across runs.
      - **Paginate to completion**: Call until `has_next_page = false` — the connector manages the cursor internally.

      ## Rate Limiting
      Datadog applies per-endpoint rate limits that vary by site and plan, surfaced on rate-limited endpoints via `X-RateLimit-*` headers ([reference](https://docs.datadoghq.com/api/latest/rate-limits/)). The connector reads the limit off those headers and backs off automatically. Higher limits can be requested through a Datadog support ticket.

      | HTTP status | Connector behaviour |
      |---|---|
      | 429 Too Many Requests | Retry after `X-RateLimit-Reset` seconds (60 s default if header absent) |
      | 5xx Server errors | Retry after `X-RateLimit-Reset` seconds if present, otherwise 60 s default |
      | 401 / 403 | Fail immediately — credential or scope issue |
      | 400 | Fail immediately — invalid input |

      ## Best Practices
      - **Incremental syncs**: Set the `from` input on **Fetch hosts** to the epoch-seconds timestamp of your last sync — returns only hosts that have reported since then.
      - **Track sync state**: Store the max `last_reported_time` seen in this run and use it as the next `from` input.
      - **Filter noise**: Use the `filter` input (free-text match) or combine with `sort_field` / `sort_dir` to narrow results when you don't need the full host list.
      - **Scope metadata**: Leave `include_hosts_metadata = false` unless you specifically need the `meta` field (agent / OS / Gohai details) — it's a larger payload per host.
      - **Match Region to your Datadog site**: Set the connection's **Region** to match your Datadog account's site. API keys are scoped to a single site, so a mismatched region returns 403 Forbidden.

      ## Common Use Cases
      - **CMDB sync** — mirror Datadog-monitored hosts into Xurrent's CMDB as Configuration Items.
      - **Incident enrichment** — on incident creation, look up the affected host's agent version, OS, and last-reported time.
      - **Fleet inventory** — periodic pull of all hosts with `up`, `is_muted`, and `metrics` for monitoring dashboards.
      - **Compliance reporting** — track reporting vs. non-reporting hosts by filtering on `up` and `last_reported_time`.

      ## References
      - [Datadog Hosts API (v1)](https://docs.datadoghq.com/api/latest/hosts/)
      - [Rate limits](https://docs.datadoghq.com/api/latest/rate-limits/)
      - [Sites and URLs](https://docs.datadoghq.com/getting_started/site/)
      - [API and application keys](https://docs.datadoghq.com/account_management/api-app-keys/)
    END_OF_DESCRIPTION

    REGIONS = {
      'us1' => { url: 'https://api.datadoghq.com', label: 'US1 (datadoghq.com)' },
      'us3' => { url: 'https://api.us3.datadoghq.com', label: 'US3 (us3.datadoghq.com)' },
      'us5' => { url: 'https://api.us5.datadoghq.com', label: 'US5 (us5.datadoghq.com)' },
      'eu1' => { url: 'https://api.datadoghq.eu', label: 'EU1 (datadoghq.eu)' },
      'us1-fed' => { url: 'https://api.ddog-gov.com', label: 'US1-FED (ddog-gov.com)' },
      'ap1' => { url: 'https://api.ap1.datadoghq.com', label: 'AP1 (ap1.datadoghq.com)' },
      'ap2' => { url: 'https://api.ap2.datadoghq.com', label: 'AP2 (ap2.datadoghq.com)' },
    }.freeze

    outbound_connection do
      config_schema do
        field :credentials, 'Credentials', :nested,
              required: true,
              hint: 'API credentials for Datadog access' do
          field :api_key, 'API Key', :secret_string,
                required: true,
                hint: 'Datadog API Key (keep secure)'
          field :application_key, 'Application Key', :secret_string,
                required: true,
                hint: 'Datadog Application Key (keep secure)'
        end
        field :region, 'Region', :string,
              required: true,
              hint: 'Datadog site/region for API access',
              enumeration: REGIONS.map { |id, info| { id: id, label: info[:label] } }
      end

      authenticate do |request|
        credentials = config[:credentials]
        api_key = decrypt_secret_string(credentials[:api_key])
        application_key = decrypt_secret_string(credentials[:application_key])

        request.headers['DD-API-KEY'] = api_key
        request.headers['DD-APPLICATION-KEY'] = application_key
        request.headers['Content-Type'] = 'application/json'
      end
    end

    action '019ccf8a-e9c0-7284-a577-29862f618496' do
      name 'Fetch hosts'
      avatar '/assets/icons/datadog.svg'
      nested true

      description <<~END_OF_DESCRIPTION
        Retrieves all hosts from Datadog with pagination support using the [Hosts API (v1)](https://docs.datadoghq.com/api/latest/hosts/).

        **Use case**: populate or refresh the list of Datadog-monitored hosts in Xurrent's CMDB. Use the **From** field to fetch only hosts reported at or after a specific time, which is useful for incremental CMDB updates.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | page_size | Integer | No | 100 | Number of hosts per page (1-1000) |
        | from | Integer | No | - | Epoch seconds for incremental sync |
        | filter | String | No | - | String to filter search results |
        | sort_field | String | No | - | Field to sort hosts by |
        | sort_dir | String | No | - | Sort direction (asc or desc) |
        | include_muted_hosts_data | Boolean | No | - | Include muted hosts data |
        | include_hosts_metadata | Boolean | No | - | Include additional metadata |

        ### Example Input

        ```json
        {
          "page_size": 100,
          "from": 1771410150,
          "filter": "my-host",
          "sort_dir": "asc"
        }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `total_matching` | Integer | Total hosts matching the query |
        | `total_returned` | Integer | Hosts returned in this page |
        | `has_next_page` | Boolean | `true` while more pages remain |
        | `host_list` | Array | One object per host — see **Host object fields** below |

        #### Host object fields

        | Field Name | Type | Description |
        |---|---|---|
        | `id` | Integer | Datadog host ID. For Amazon EC2 hosts this field is replaced by `aws_id` |
        | `aws_id` | Integer | AWS host ID. Returned in place of `id` when the host is an Amazon EC2 instance |
        | `name` | String | Host display name |
        | `host_name` | String | Hostname reported by the agent |
        | `aliases` | Array | Host aliases |
        | `apps` | Array | Applications running on the host |
        | `aws_name` | String | AWS name (when available) |
        | `sources` | Array | Data sources reporting this host |
        | `up` | Boolean | Whether the host is currently reporting |
        | `is_muted` | Boolean | Whether the host is muted |
        | `mute_timeout` | Integer | Mute timeout (timestamp in seconds) |
        | `last_reported_time` | Integer | Last report time (timestamp in seconds) |
        | `tags_by_source` | Object | Tags grouped by source |
        | `meta` | Object | Agent, OS, and Gohai metadata (when **Include hosts metadata** is on) |
        | `metrics` | Object | Basic metrics — `cpu`, `iowait`, `load` |

        ### Example Output

        ```json
        {
          "total_matching": 1,
          "total_returned": 1,
          "has_next_page": false,
          "host_list": [
            {
              "id": 123145537712914,
              "name": "Xurrent-FNX2Y3Q7FK",
              "host_name": "Xurrent-FNX2Y3Q7FK",
              "aliases": ["Xurrent-FNX2Y3Q7FK"],
              "apps": ["agent", "ntp"],
              "sources": ["agent"],
              "up": true,
              "is_muted": false,
              "mute_timeout": null,
              "last_reported_time": 1770967634,
              "tags_by_source": {
                "Datadog": ["host:Xurrent-FNX2Y3Q7FK"]
              },
              "meta": {
                "cpu_cores": 12,
                "agent_version": "7.75.3",
                "timezones": ["IST"],
                "platform": "darwin",
                "machine": "arm64",
                "processor": "Apple M4 Pro",
                "install_method": {
                  "installer_version": null,
                  "tool": null,
                  "tool_version": "install_script_mac"
                },
                "logs_agent": {
                  "transport": ""
                },
                "agent_flavor": "agent",
                "host_id": 123145537712914,
                "gohai": {
                  "cpu": { "cpu_cores": "12", "model_name": "Apple M4 Pro" },
                  "memory": { "swap_total": "2097152kB", "total": "25769803776" }
                }
              },
              "metrics": {
                "cpu": 8.087143,
                "iowait": 0,
                "load": 0.1817419
              }
            }
          ]
        }
        ```

        ### Error Handling
        The job fails immediately on 400 / 401 / 403 responses (invalid input or credential/scope issue). On 429 (rate limited) or 5xx server errors, the connector waits for the time in `X-RateLimit-Reset` and retries automatically.

        ### Best Practices
        - **Incremental**: Use `from` set to the epoch-seconds of your last successful sync; store the max `last_reported_time` seen in this run for the next run's `from`.
        - **Full metadata off by default**: Set `include_hosts_metadata = true` only when you need agent / OS / Gohai details — otherwise leave it off to reduce payload.
        - **Deterministic paging**: Set `sort_field = "name"` and `sort_dir = "asc"` to page through hosts in a stable order across runs.
        - **Paginate to completion**: Call until `has_next_page = false` — the connector manages the cursor internally.
      END_OF_DESCRIPTION

      input_schema do
        field :page_size, 'Page size', :integer,
              min: 1,
              max: 1000,
              visibility: 'optional',
              default: 100,
              hint: 'Number of hosts per page (max 1000)'
        field :from, 'From', :integer,
              visibility: 'optional',
              hint: 'Epoch seconds for incremental sync'
        field :filter, 'Filter', :string,
              visibility: 'optional',
              hint: 'String to filter search results'
        field :sort_field, 'Sort field', :string,
              visibility: 'optional',
              hint: 'Field to sort hosts by'
        field :sort_dir, 'Sort direction', :string,
              visibility: 'optional',
              hint: 'Sort direction',
              enumeration: [
                { id: 'asc', label: 'Ascending' },
                { id: 'desc', label: 'Descending' },
              ]
        field :include_muted_hosts_data, 'Include muted hosts data', :boolean,
              visibility: 'optional',
              hint: 'Include muted hosts timeout and muting information'
        field :include_hosts_metadata, 'Include hosts metadata', :boolean,
              visibility: 'optional',
              hint: 'Include additional metadata (agent_version, machine, platform, processor, etc.)'
      end

      output_schema 'page' do
        field :total_matching, 'Total matching', :integer,
              required: true,
              hint: 'Total number of matching hosts'
        field :total_returned, 'Total returned', :integer,
              required: true,
              hint: 'Number of hosts returned in this page'
        field :has_next_page, 'Has next page', :boolean, required: true
        field :host_list, 'Host list', :nested, array: true do
          field :id, 'ID', :integer
          field :aws_id, 'AWS ID', :integer
          field :name, 'Name', :string
          field :host_name, 'Host name', :string
          field :aliases, 'Aliases', :string, array: true
          field :apps, 'Apps', :string, array: true
          field :aws_name, 'AWS name', :string
          field :sources, 'Sources', :string, array: true
          field :up, 'Up', :boolean
          field :is_muted, 'Is muted', :boolean
          field :mute_timeout, 'Mute timeout', :integer
          field :last_reported_time, 'Last reported time', :integer
          field :tags_by_source, 'Tags by source', :hash
          field :meta, 'Meta', :nested do
            field :agent_checks, 'Agent checks', :any_item_type, array: true
            field :agent_flavor, 'Agent flavor', :string
            field :agent_version, 'Agent version', :string
            field :cpu_cores, 'CPU cores', :integer
            field :fbsd_v, 'FreeBSD versions', :string, array: true
            field :host_id, 'Host ID', :integer
            field :logs_agent, 'Logs agent', :nested do
              field :auto_multi_line_detection_enabled, 'Auto multi-line detection enabled', :boolean
              field :transport, 'Transport', :string
            end
            field :mac_v, 'Mac versions', :any_item_type, array: true
            field :python_v, 'Python version', :string
            field :machine, 'Machine', :string
            field :network, 'Network', :nested do
              field :network_id, 'Network ID', :string
              field :public_ipv4, 'Public IPv4', :string
            end
            field :nix_v, 'Unix versions', :string, array: true
            field :platform, 'Platform', :string
            field :processor, 'Processor', :string
            field :socket_hostname, 'Socket hostname', :string
            field :socket_fqdn, 'Socket FQDN', :string
            field :timezones, 'Timezones', :string, array: true
            field :win_v, 'Windows versions', :string, array: true
            field :install_method, 'Install method', :nested do
              field :installer_version, 'Installer version', :string
              field :tool, 'Tool', :string
              field :tool_version, 'Tool version', :string
            end
            field :gohai, 'Gohai', :nested do
              field :cpu, 'CPU', :nested do
                field :cache_size, 'Cache size', :string
                field :cpu_cores, 'CPU cores', :string
                field :cpu_logical_processors, 'CPU logical processors', :string
                field :family, 'Family', :string
                field :mhz, 'MHz', :string
                field :model, 'Model', :string
                field :model_name, 'Model name', :string
                field :stepping, 'Stepping', :string
                field :vendor_id, 'Vendor ID', :string
              end
              field :filesystem, 'Filesystem', :nested, array: true do
                field :kb_size, 'KB size', :string
                field :mounted_on, 'Mounted on', :string
                field :name, 'Name', :string
              end
              field :memory, 'Memory', :nested do
                field :swap_total, 'Swap total', :string
                field :total, 'Total', :string
              end
              field :network, 'Network', :nested do
                field :interfaces, 'Interfaces', :nested, array: true do
                  field :ipv4, 'IPv4', :any_value_type
                  field :ipv4_network, 'IPv4 network', :string
                  field :ipv6, 'IPv6', :any_value_type
                  field :ipv6_network, 'IPv6 network', :string
                  field :macaddress, 'MAC address', :string
                  field :name, 'Name', :string
                end
                field :ipaddress, 'IP address', :string
                field :ipaddressv6, 'IPv6 address', :string
                field :macaddress, 'MAC address', :string
              end
              field :platform, 'Platform', :nested do
                field :gooarch, 'GOOARCH', :string
                field :goos, 'GOOS', :string
                field :go_v, 'Go version', :string
                field :hardware_platform, 'Hardware platform', :string
                field :hostname, 'Hostname', :string
                field :kernel_name, 'Kernel name', :string
                field :kernel_release, 'Kernel release', :string
                field :kernel_version, 'Kernel version', :string
                field :machine, 'Machine', :string
                field :os, 'Operating system', :string
                field :processor, 'Processor', :string
                field :python_v, 'Python version', :string
              end
            end
          end
          field :metrics, 'Metrics', :nested do
            field :cpu, 'CPU', :float
            field :iowait, 'IO wait', :float
            field :load, 'Load', :float
          end
        end
      end

      iteration_state_schema do
        field :offset, 'Offset', :integer, required: true, default: 0
      end

      run do
        offset = iteration_state_value(:offset) || 0
        page_size = input[:page_size]

        query_params = { start: offset.to_s, count: page_size.to_s }
        query_params[:from] = input[:from].to_s if input[:from].present?
        query_params[:filter] = input[:filter] if input[:filter].present?
        query_params[:sort_field] = input[:sort_field] if input[:sort_field].present?
        query_params[:sort_dir] = input[:sort_dir] if input[:sort_dir].present?
        if input.key?(:include_muted_hosts_data)
          query_params[:include_muted_hosts_data] = input[:include_muted_hosts_data].to_s
        end
        if input.key?(:include_hosts_metadata)
          query_params[:include_hosts_metadata] = input[:include_hosts_metadata].to_s
        end

        url = "#{helpers.api_endpoint}/api/v1/hosts"
        response = http_get(url, query_params)

        backoff_if_needed(response,
                          api_name: 'Datadog',
                          header_name: 'X-RateLimit-Reset',
                          server_error_statuses: (500...600).to_a)
        result = helpers.parse_response(response)

        host_list = result[:host_list]
        total_matching = result[:total_matching]
        total_returned = result[:total_returned]

        has_more = (offset + host_list.size) < total_matching
        next_offset = has_more ? offset + host_list.size : nil

        self.iteration_state_value = next_offset ? { offset: next_offset } : nil

        [{
          output: {
            total_matching: total_matching,
            total_returned: total_returned,
            has_next_page: has_more,
            host_list: helpers.transform(host_list),
          },
          schema_reference: 'page',
        }]
      end
    end

    helper :api_endpoint do
      region = outbound_connection.config[:region]
      REGIONS.dig(region, :url)
    end

    helper :parse_response do |response|
      body = JSON.parse(response.body)

      if body['errors'].is_a?(Array) && body['errors'].any?
        error_message = body['errors'].join(', ')

        fail_job!("Datadog authentication error: #{error_message}") if response.status == 401
        fail_job!("Datadog forbidden error: #{error_message}") if response.status == 403

        fail_job!("Datadog API error: #{error_message}")
      end

      fail_job!("HTTP error: #{response.status} '#{response.body}'") unless response.status == 200
      body.with_indifferent_access
    rescue JSON::ParserError
      fail_job!("HTTP error: #{response.status} '#{response.body}'")
    end

    helper :transform do |host_list|
      host_list.map do |host|
        host = camel_to_snake(host, [:tags_by_source]).with_indifferent_access

        meta = host[:meta]
        next host unless meta.is_a?(Hash)

        gohai = meta[:gohai]
        next host unless gohai.is_a?(String)

        parsed_gohai = camel_to_snake(JSON.parse(gohai)).with_indifferent_access

        host.merge(meta: meta.merge(gohai: parsed_gohai))
      rescue JSON::ParserError
        fail_job!("Failed to parse gohai JSON for host '#{host[:name]}'")
      end
    end
  end
end
