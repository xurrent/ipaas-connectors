class CheckmkConnector < IPaaS::Connector::Definition
  DEFAULT_BATCH_SIZE = 50
  GET_HOSTS_API_ROUTE = '/api/1.0/domain-types/host_config/collections/all'.freeze
  GET_HOST_INVENTORY_TIMESTAMPS_API_ROUTE = '/api/1.0/domain-types/host/collections/all'.freeze

  connector '019d1f4e-7837-7a72-a0b5-df0ba9a5d44f' do
    name 'Checkmk Connector'
    avatar '/assets/icons/checkmk.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview

      This connector integrates with Checkmk to retrieve hosts and hardware/software inventory data
      for synchronizing Configuration Items into the Xurrent CMDB.

      ## Prerequisites

      To use this connector, you need:
      * A Checkmk 2.4+ server with the REST API enabled
      * A Checkmk user with read access to hosts and HW/SW inventory
      * Site access for every site whose hosts you plan to sync

      ## Authentication

      Uses your **Username** and **Password** to authenticate. Additionally, provide
      your **Domain** (e.g. `myserver.example.com`) and **Site name** (e.g. `mysite`)
      to locate your Checkmk instance.

      ## Triggers

      None — this connector is outbound only.

      ## Actions

      ### Get hosts

      Retrieves hosts from Checkmk with optional filters for hostnames, site, field selection,
      effective attributes, and links. Returns each host with its folder, attributes, and optional
      members metadata.

      **Use case**: Fetch the host inventory before retrieving detailed HW/SW inventory, or refresh
      host metadata for CMDB tagging and grouping.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |-----------|------|----------|---------|-------------|
      | effective_attributes | Boolean | No | false | Show all effective attributes including inherited from parent folders |
      | include_links | Boolean | No | false | Include HATEOAS links in the response |
      | fields | String | No | - | Field selection expression to trim the response (e.g. `(value(id,title,extensions))`) |
      | hostnames | Array[String] | No | - | Filter results by specific host names |
      | site | String | No | - | Filter results by a specific monitoring site |

      #### Example Input

      ```json
      {
        "effective_attributes": false,
        "include_links": false,
        "fields": "(value(id,title,extensions))",
        "hostnames": ["web-server-01"],
        "site": "mysite"
      }
      ```

      #### Output

      | Field | Type | Description |
      |-------|------|-------------|
      | domain_type | String | Checkmk domain type (e.g. `host_config`) |
      | id | String | Response collection identifier |
      | title | String | Response collection title |
      | extensions | Object | Additional top-level metadata returned by Checkmk |
      | hosts | Array[Host] | List of hosts matching the filters |

      ##### Host fields

      | Field | Type | Description |
      |-------|------|-------------|
      | id | String | Host identifier (required) |
      | title | String | Host title as shown in Checkmk |
      | domain_type | String | Always `host_config` for this endpoint |
      | members | Object | Nested members metadata (folder_config, move); present when returned by Checkmk |
      | links | Array | HATEOAS links; present only when `include_links = true` |
      | extensions | Object | Host-level details — see `Host extensions` fields |

      ##### Host extensions fields

      | Field | Type | Description |
      |-------|------|-------------|
      | folder | String | Checkmk folder path (e.g. `/`, `/production`) |
      | is_cluster | Boolean | Whether the host is a cluster node container |
      | is_offline | Boolean | Whether the host is marked offline |
      | cluster_nodes | Array[String] | Node host IDs when `is_cluster = true` |
      | effective_attributes | Object | Merged attributes including folder inheritance; populated when `effective_attributes = true` |
      | attributes | Object | Raw host attributes — see `Host attributes` fields |

      ##### Host attributes fields

      | Field | Type | Description |
      |-------|------|-------------|
      | alias | String | Host alias |
      | site | String | Monitoring site owning this host |
      | ipaddress | String | Primary IPv4 address |
      | ipv6address | String | Primary IPv6 address |
      | additional_ipv4addresses | Array[String] | Secondary IPv4 addresses |
      | additional_ipv6addresses | Array[String] | Secondary IPv6 addresses |
      | parents | Array[String] | Parent host IDs for topology |
      | tag_address_family | String | Address family tag (`ip-v4-only`, `ip-v6-only`, `ip-v4v6`, `no-ip`) |
      | tag_agent | String | Agent tag (e.g. `cmk-agent`, `no-agent`) |
      | tag_snmp_ds | String | SNMP data source tag |
      | tag_piggyback | String | Piggyback tag |
      | tag_criticality | String | Criticality tag |
      | tag_networking | String | Networking tag (e.g. `lan`, `wan`, `dmz`) |
      | cmk_agent_connection | String | Agent connection mode |
      | labels | Object | Arbitrary key/value labels attached to the host |
      | meta_data | Object | `{ created_at, updated_at, created_by }` audit trail |
      | contactgroups | Object | `{ groups, use, use_for_services, recurse_use, recurse_perms }` contact assignment |
      | locked_by | Object | `{ site_id, program_id, instance_id }` if the host is programmatically locked |
      | locked_attributes | Array[String] | Attribute names locked from UI edits |

      #### Example Output

      ```json
      {
        "domain_type": "host_config",
        "id": "host_config",
        "title": "All hosts",
        "extensions": {},
        "hosts": [
          {
            "id": "monitoring-container",
            "title": "monitoring-container",
            "domain_type": "host_config",
            "extensions": {
              "folder": "/",
              "attributes": {
                "ipaddress": "127.0.0.1",
                "meta_data": { "created_at": "2026-02-19T07:18:24Z" }
              }
            }
          },
          {
            "id": "web-server-01",
            "title": "Web Server 01",
            "domain_type": "host_config",
            "extensions": {
              "folder": "/production",
              "attributes": {
                "ipaddress": "10.0.1.5",
                "meta_data": { "created_at": "2026-03-01T12:00:00Z" }
              }
            }
          }
        ]
      }
      ```

      #### Error Handling

      | Condition | Behavior |
      |-----------|----------|
      | 401 / 403 | Fail immediately with `Checkmk authentication error: <status>` |
      | 429 or 503 | Retry, respecting `Retry-After` (default 60s) |
      | Other 4xx / 5xx (400, 404, 500, 502, 504) | Fail with `Checkmk HTTP error: <status>` |
      | Non-JSON body | Fail with `Checkmk response was not valid JSON` |

      #### Best Practices

      * Use the `fields` filter — e.g. `(value(id,title,extensions~folder,extensions~attributes))` —
        to drop members and links from the wire when only host identity + attributes are needed.
      * Combine `hostnames` with `site` to narrow queries on multi-site Checkmk deployments.
      * Call **Get hosts** before **Get host inventory timestamps** so you have the canonical host
        list to diff timestamps against.

      ### Get host inventory timestamps

      Retrieves the `mk_inventory_last` Unix timestamp for every host in one lightweight call.
      Returns `0` for hosts that have never been inventoried.

      **Use case**: Drive incremental inventory syncs — compare each host's `mk_inventory_last`
      against the watermark stored from the previous sync, and pass only the changed subset to
      **Get host inventory**.

      #### Input Parameters

      None.

      #### Example Input

      ```json
      {}
      ```

      #### Output

      | Field | Type | Description |
      |-------|------|-------------|
      | domain_type | String | Checkmk domain type (e.g. `host`) |
      | id | String | Response collection identifier |
      | hosts | Array[Host] | One entry per host — see `Host fields` |

      ##### Host fields

      | Field | Type | Description |
      |-------|------|-------------|
      | name | String | Host name (required) |
      | mk_inventory_last | Integer | Unix timestamp of the last HW/SW inventory run; `0` means never inventoried |

      #### Example Output

      ```json
      {
        "domain_type": "host",
        "id": "host",
        "hosts": [
          { "name": "cmk", "mk_inventory_last": 0 },
          { "name": "mysite", "mk_inventory_last": 1776179669 }
        ]
      }
      ```

      #### Error Handling

      | Condition | Behavior |
      |-----------|----------|
      | 401 / 403 | Fail immediately with `Checkmk authentication error: <status>` |
      | 429 or 503 | Retry, respecting `Retry-After` (default 60s) |
      | Other 4xx / 5xx (400, 404, 500, 502, 504) | Fail with `Checkmk HTTP error: <status>` |
      | Non-JSON body | Fail with `Checkmk response was not valid JSON` |

      #### Best Practices

      * Call this before **Get host inventory** to filter the `host_names` input down to only hosts
        whose `mk_inventory_last` changed since the previous sync.
      * Persist each host's `mk_inventory_last` as the watermark for the next run.
      * Skip hosts where `mk_inventory_last = 0` if your sync only cares about inventoried hosts.

      ### Get host inventory

      Retrieves detailed hardware, software, and networking inventory for a batch of hosts.
      The action paginates internally — it emits one page per batch and drains the full
      `host_names` list across successive iterations.

      **Use case**: Fetch device inventory (manufacturer, model, serial, CPU, memory, OS,
      applications, network interfaces) for CMDB synchronization.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |-----------|------|----------|---------|-------------|
      | host_names | Array[String] | Yes | - | Host names to fetch inventory for (typically the changed subset from **Get host inventory timestamps**) |
      | batch_size | Integer | No | 50 | Number of hosts per request (min 1, max 50) |

      #### Example Input

      ```json
      {
        "host_names": ["host1", "host2"],
        "batch_size": 50
      }
      ```

      #### Output

      | Field | Type | Description |
      |-------|------|-------------|
      | has_next_page | Boolean | `true` if more host_names remain after this batch |
      | hosts | Array[Host] | One entry per host in the current batch — see `Host fields` |

      ##### Host fields

      | Field | Type | Description |
      |-------|------|-------------|
      | hostname | String | Host name (required) |
      | inventory | Object | Inventory tree — see `Inventory fields` |

      ##### Inventory fields

      The `inventory` object mirrors Checkmk's HW/SW inventory tree with snake-cased keys.
      Each node carries `attributes` (with a `pairs` object of scalar facts), optional `nodes`
      (child sub-trees), and optional `table` (rows of tabular data such as interfaces).

      | Path | Type | Description |
      |------|------|-------------|
      | nodes.hardware.nodes.system.attributes.pairs | Object | `{ manufacturer, model, serial, product, family, uuid }` |
      | nodes.hardware.nodes.cpu.attributes.pairs | Object | `{ cores, threads, model, arch, cpus, max_speed, cache_size }` |
      | nodes.hardware.nodes.memory.attributes.pairs | Object | `{ total_ram_usable, total_swap, total_vmalloc }` in bytes |
      | nodes.software.nodes.os.attributes.pairs | Object | `{ name, version, type, vendor, arch, build, service_pack, kernel_version, install_date }` |
      | nodes.software.nodes.applications.nodes.check_mk | Object | Checkmk-specific application info (cluster, sites, versions) |
      | nodes.networking.attributes.pairs | Object | `{ hostname, domain_name, default_gateway, available_ethernet_ports, total_ethernet_ports, total_interfaces }` |
      | nodes.networking.nodes.interfaces.table | Object | `{ key_columns, rows[] }` — one row per NIC with `alias`, `description`, `index`, `oper_status`, `phys_address`, `port_type`, `speed`, `available` |

      #### Example Output

      ```json
      {
        "has_next_page": false,
        "hosts": [
          {
            "hostname": "host1",
            "inventory": {
              "attributes": {},
              "table": {},
              "nodes": {
                "hardware": {
                  "attributes": {},
                  "table": {},
                  "nodes": {
                    "system": {
                      "attributes": {
                        "pairs": { "manufacturer": "Amazon EC2", "model": "m5a.2xlarge" }
                      },
                      "nodes": {},
                      "table": {}
                    },
                    "cpu": {
                      "attributes": { "pairs": { "cores": 4 } },
                      "nodes": {},
                      "table": {}
                    },
                    "memory": {
                      "attributes": { "pairs": { "total_ram_usable": 33688150016 } },
                      "nodes": {},
                      "table": {}
                    }
                  }
                },
                "software": {
                  "attributes": {},
                  "table": {},
                  "nodes": {
                    "os": {
                      "attributes": {
                        "pairs": { "name": "Microsoft Windows Server 2019 Datacenter" }
                      },
                      "nodes": {},
                      "table": {}
                    }
                  }
                },
                "networking": {
                  "attributes": {
                    "pairs": { "hostname": "host1", "total_interfaces": 2 }
                  },
                  "table": {},
                  "nodes": {
                    "interfaces": {
                      "attributes": {},
                      "nodes": {},
                      "table": {
                        "key_columns": ["index"],
                        "rows": [
                          {
                            "index": 1,
                            "description": "eth0",
                            "alias": "Primary",
                            "speed": 10000000000,
                            "oper_status": 1,
                            "phys_address": "00:11:22:33:44:55",
                            "port_type": 6,
                            "available": true
                          }
                        ]
                      }
                    }
                  }
                }
              }
            }
          }
        ]
      }
      ```

      #### Error Handling

      | Condition | Behavior |
      |-----------|----------|
      | 401 / 403 | Fail immediately with `Checkmk authentication error: <status>` |
      | 429 or 503 | Retry, respecting `Retry-After` (default 60s) |
      | Other 4xx / 5xx (400, 404, 500, 502, 504) | Fail with `Checkmk HTTP error: <status>` |
      | Inventory `result_code != 0` | Fail with `Checkmk inventory API error [result_code=N]: <message>` |
      | Non-JSON body | Fail with `Checkmk response was not valid JSON` |

      #### Best Practices

      * Keep `batch_size` at its documented maximum (50) to minimize round-trips.
      * Feed `host_names` from the diffed output of **Get host inventory timestamps** — do not
        re-fetch inventory for hosts whose `mk_inventory_last` is unchanged.
      * Let the action drain its internal pagination across iterations rather than slicing
        `host_names` manually at the caller.

      ## Rate Limiting

      | HTTP Status | Connector Behavior |
      |-------------|--------------------|
      | 200 | Success |
      | 401 / 403 | Fail immediately with `Checkmk authentication error: <status>` |
      | 429 | Retry, respecting `Retry-After` header (default 60s) |
      | 503 | Retry, respecting `Retry-After` header (default 60s) |
      | 400, 404, other 4xx | Fail with `Checkmk HTTP error: <status>` |
      | 500, 502, 504 | Fail with `Checkmk HTTP error: <status>` |
      | Invalid JSON body | Fail with `Checkmk response was not valid JSON` |
      | Inventory `result_code != 0` | Fail with `Checkmk inventory API error [result_code=N]` |

      ## Best Practices

      * Run **Get host inventory timestamps** first, diff `mk_inventory_last` against your stored
        watermark, then pass only the changed subset as `host_names` to **Get host inventory**.
        This avoids re-fetching heavy inventory trees for unchanged hosts.
      * Keep `batch_size` on **Get host inventory** at its maximum (50).
      * Use the `fields` filter on **Get hosts** — e.g.
        `(value(id,title,extensions~folder,extensions~attributes))` — to drop members and links
        from the wire when only hosts plus attributes are needed.
      * Narrow **Get hosts** with `site` when your Checkmk is multi-site.
      * Persist each host's `mk_inventory_last` in Xurrent as the watermark for the next run.

      ## Common Use Cases

      * Initial CMDB import → **Get hosts** → **Get host inventory** for all hostnames.
      * Incremental sync → **Get host inventory timestamps** → diff against stored watermark →
        **Get host inventory** with the changed subset.
      * Host list refresh for tagging and grouping → **Get hosts** with a `fields` filter.
      * Troubleshoot a single host → **Get hosts** with `hostnames=[name]` →
        **Get host inventory** with `host_names=[name]`.

      ## References

      * Checkmk REST API documentation: https://docs.checkmk.com/latest/en/rest_api.html
      * Endpoints used by this connector:
        * `GET /api/1.0/domain-types/host_config/collections/all` — Get hosts
        * `POST /api/1.0/domain-types/host/collections/all` — Get host inventory timestamps (livestatus-backed host columns)
        * `GET /host_inv_api.py` — Get host inventory (HW/SW inventory over Web API)
    END_OF_DESCRIPTION

    outbound_connection do
      config_schema do
        field :domain, 'Domain', :string,
              required: true,
              hint: 'Checkmk server domain (e.g. myserver.example.com)'
        field :site_name, 'Site name', :string,
              required: true,
              hint: 'Checkmk site name (e.g. mysite)'
        field :username, 'Username', :string,
              required: true,
              hint: 'Checkmk user with API access'
        field :password, 'Password', :secret_string,
              required: true,
              hint: 'Checkmk user password'
      end

      authenticate do |request|
        username = config[:username]
        password = decrypt_secret_string(config[:password])
        encoded_auth = Base64.strict_encode64("#{username}:#{password}")
        request.headers['Authorization'] = "Basic #{encoded_auth}"
      end
    end

    action '019d1f4e-7837-7a35-bf23-ad7603241aca' do
      name 'Get hosts'
      avatar '/assets/icons/checkmk.svg'
      description <<~END_OF_DESCRIPTION
        Retrieves hosts from Checkmk with optional filters for hostnames, site, field selection,
        effective attributes, and links. Returns each host with its folder, attributes, and
        optional members metadata.

        **Use case**: Fetch the host inventory before retrieving detailed HW/SW inventory, or
        refresh host metadata for CMDB tagging and grouping.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | effective_attributes | Boolean | No | false | Show all effective attributes including inherited from parent folders |
        | include_links | Boolean | No | false | Include HATEOAS links in the response |
        | fields | String | No | - | Field selection expression to trim the response (e.g. `(value(id,title,extensions))`) |
        | hostnames | Array[String] | No | - | Filter results by specific host names |
        | site | String | No | - | Filter results by a specific monitoring site |

        ### Example Input

        ```json
        {
          "effective_attributes": false,
          "include_links": false,
          "fields": "(value(id,title,extensions))",
          "hostnames": ["web-server-01"],
          "site": "mysite"
        }
        ```

        ### Output

        | Field | Type | Description |
        |-------|------|-------------|
        | domain_type | String | Checkmk domain type (e.g. `host_config`) |
        | id | String | Response collection identifier |
        | title | String | Response collection title |
        | extensions | Object | Additional top-level metadata returned by Checkmk |
        | hosts | Array[Host] | List of hosts matching the filters |

        #### Host fields

        | Field | Type | Description |
        |-------|------|-------------|
        | id | String | Host identifier (required) |
        | title | String | Host title as shown in Checkmk |
        | domain_type | String | Always `host_config` for this endpoint |
        | members | Object | Nested members metadata (folder_config, move); present when returned by Checkmk |
        | links | Array | HATEOAS links; present only when `include_links = true` |
        | extensions | Object | Host-level details — see `Host extensions` fields |

        #### Host extensions fields

        | Field | Type | Description |
        |-------|------|-------------|
        | folder | String | Checkmk folder path (e.g. `/`, `/production`) |
        | is_cluster | Boolean | Whether the host is a cluster node container |
        | is_offline | Boolean | Whether the host is marked offline |
        | cluster_nodes | Array[String] | Node host IDs when `is_cluster = true` |
        | effective_attributes | Object | Merged attributes including folder inheritance; populated when `effective_attributes = true` |
        | attributes | Object | Raw host attributes — see `Host attributes` fields |

        #### Host attributes fields

        | Field | Type | Description |
        |-------|------|-------------|
        | alias | String | Host alias |
        | site | String | Monitoring site owning this host |
        | ipaddress | String | Primary IPv4 address |
        | ipv6address | String | Primary IPv6 address |
        | additional_ipv4addresses | Array[String] | Secondary IPv4 addresses |
        | additional_ipv6addresses | Array[String] | Secondary IPv6 addresses |
        | parents | Array[String] | Parent host IDs for topology |
        | tag_address_family | String | Address family tag (`ip-v4-only`, `ip-v6-only`, `ip-v4v6`, `no-ip`) |
        | tag_agent | String | Agent tag (e.g. `cmk-agent`, `no-agent`) |
        | tag_snmp_ds | String | SNMP data source tag |
        | tag_piggyback | String | Piggyback tag |
        | tag_criticality | String | Criticality tag |
        | tag_networking | String | Networking tag (e.g. `lan`, `wan`, `dmz`) |
        | cmk_agent_connection | String | Agent connection mode |
        | labels | Object | Arbitrary key/value labels attached to the host |
        | meta_data | Object | `{ created_at, updated_at, created_by }` audit trail |
        | contactgroups | Object | `{ groups, use, use_for_services, recurse_use, recurse_perms }` contact assignment |
        | locked_by | Object | `{ site_id, program_id, instance_id }` if the host is programmatically locked |
        | locked_attributes | Array[String] | Attribute names locked from UI edits |

        ### Example Output

        ```json
        {
          "domain_type": "host_config",
          "id": "host_config",
          "title": "All hosts",
          "extensions": {},
          "hosts": [
            {
              "id": "monitoring-container",
              "title": "monitoring-container",
              "domain_type": "host_config",
              "extensions": {
                "folder": "/",
                "attributes": {
                  "ipaddress": "127.0.0.1",
                  "meta_data": { "created_at": "2026-02-19T07:18:24Z" }
                }
              }
            },
            {
              "id": "web-server-01",
              "title": "Web Server 01",
              "domain_type": "host_config",
              "extensions": {
                "folder": "/production",
                "attributes": {
                  "ipaddress": "10.0.1.5",
                  "meta_data": { "created_at": "2026-03-01T12:00:00Z" }
                }
              }
            }
          ]
        }
        ```

        ### Error Handling

        | Condition | Behavior |
        |-----------|----------|
        | 401 / 403 | Fail immediately with `Checkmk authentication error: <status>` |
        | 429 or 503 | Retry, respecting `Retry-After` (default 60s) |
        | Other 4xx / 5xx (400, 404, 500, 502, 504) | Fail with `Checkmk HTTP error: <status>` |
        | Non-JSON body | Fail with `Checkmk response was not valid JSON` |

        ### Best Practices

        * Use the `fields` filter — e.g. `(value(id,title,extensions~folder,extensions~attributes))` —
          to drop members and links from the wire when only host identity + attributes are needed.
        * Combine `hostnames` with `site` to narrow queries on multi-site Checkmk deployments.
        * Call **Get hosts** before **Get host inventory timestamps** so you have the canonical host
          list to diff timestamps against.
      END_OF_DESCRIPTION

      input_schema do
        field :effective_attributes, 'Effective attributes', :boolean,
              visibility: 'optional',
              default: false,
              hint: 'Show all effective attributes including inherited from parent folders'
        field :include_links, 'Include links', :boolean,
              visibility: 'optional',
              default: false,
              hint: 'Include HATEOAS links in the response'
        field :fields, 'Fields filter', :string,
              visibility: 'optional',
              hint: 'Field selection expression to filter response fields (e.g. "(value(id,title,extensions))")'
        field :hostnames, 'Hostnames', :string,
              array: true,
              visibility: 'optional',
              hint: 'Filter results by specific host names'
        field :site, 'Site', :string,
              visibility: 'optional',
              hint: 'Filter results by a specific monitoring site'
      end

      output_schema do
        field :domain_type, 'Domain type', :string
        field :id, 'ID', :string
        field :title, 'Title', :string
        field :extensions, 'Extensions', :hash
        field :hosts, 'Hosts', :nested, array: true do
          field :domain_type, 'Domain type', :string
          field :links, 'Links', :nested, array: true do
            field :domain_type, 'Domain type', :string
            field :rel, 'Rel', :string
            field :href, 'Href', :string
            field :method, 'Method', :string
            field :type, 'Type', :string
            field :title, 'Title', :string
            field :body_params, 'Body params', :hash
          end
          field :id, 'ID', :string, required: true
          field :title, 'Title', :string
          field :members, 'Members', :nested do
            field :folder_config, 'Folder config', :nested do
              field :domain_type, 'Domain type', :string
              field :id, 'ID', :string
              field :title, 'Title', :string
              field :links, 'Links', :nested, array: true do
                field :domain_type, 'Domain type', :string
                field :rel, 'Rel', :string
                field :href, 'Href', :string
                field :method, 'Method', :string
                field :type, 'Type', :string
                field :title, 'Title', :string
                field :body_params, 'Body params', :hash
              end
              field :members, 'Members', :nested do
                field :hosts, 'Hosts', :nested do
                  field :links, 'Links', :nested, array: true do
                    field :domain_type, 'Domain type', :string
                    field :rel, 'Rel', :string
                    field :href, 'Href', :string
                    field :method, 'Method', :string
                    field :type, 'Type', :string
                    field :title, 'Title', :string
                    field :body_params, 'Body params', :hash
                  end
                  field :id, 'ID', :string
                  field :disabled_reason, 'Disabled reason', :string
                  field :invalid_reason, 'Invalid reason', :string
                  field :member_type, 'Member type', :string
                  field :value, 'Value', :nested, array: true do
                    field :domain_type, 'Domain type', :string
                    field :rel, 'Rel', :string
                    field :href, 'Href', :string
                    field :method, 'Method', :string
                    field :type, 'Type', :string
                    field :title, 'Title', :string
                    field :body_params, 'Body params', :hash
                  end
                  field :name, 'Name', :string
                  field :title, 'Title', :string
                end
                field :move, 'Move', :nested do
                  field :links, 'Links', :nested, array: true do
                    field :domain_type, 'Domain type', :string
                    field :rel, 'Rel', :string
                    field :href, 'Href', :string
                    field :method, 'Method', :string
                    field :type, 'Type', :string
                    field :title, 'Title', :string
                    field :body_params, 'Body params', :hash
                  end
                  field :id, 'ID', :string
                  field :disabled_reason, 'Disabled reason', :string
                  field :invalid_reason, 'Invalid reason', :string
                  field :member_type, 'Member type', :string
                  field :parameters, 'Parameters', :hash
                  field :name, 'Name', :string
                  field :title, 'Title', :string
                end
              end
              field :extensions, 'Extensions', :nested do
                field :path, 'Path', :string
                field :attributes, 'Attributes', :hash
              end
            end
          end
          field :extensions, 'Extensions', :nested do
            field :folder, 'Folder', :string
            field :is_cluster, 'Is cluster', :boolean
            field :is_offline, 'Is offline', :boolean
            field :cluster_nodes, 'Cluster nodes', :string, array: true
            field :effective_attributes, 'Effective attributes', :hash
            field :attributes, 'Attributes', :nested, remove_unmapped_fields: false do
              field :alias, 'Alias', :string
              field :site, 'Site', :string
              field :ipaddress, 'IP address', :string
              field :ipv6address, 'IPv6 address', :string
              field :additional_ipv4addresses, 'Additional IPv4 addresses', :string, array: true
              field :additional_ipv6addresses, 'Additional IPv6 addresses', :string, array: true
              field :parents, 'Parents', :string, array: true
              field :tag_address_family, 'Tag address family', :string
              field :tag_agent, 'Tag agent', :string
              field :tag_snmp_ds, 'Tag SNMP DS', :string
              field :tag_piggyback, 'Tag piggyback', :string
              field :tag_criticality, 'Tag criticality', :string
              field :tag_networking, 'Tag networking', :string
              field :cmk_agent_connection, 'Agent connection', :string
              field :bake_agent_package, 'Bake agent package', :boolean
              field :snmp_community, 'SNMP community', :hash
              field :labels, 'Labels', :hash
              field :waiting_for_discovery, 'Waiting for discovery', :boolean
              field :management_protocol, 'Management protocol', :string
              field :management_address, 'Management address', :string
              field :management_snmp_community, 'Management SNMP community', :hash
              field :management_ipmi_credentials, 'Management IPMI credentials', :nested do
                field :username, 'Username', :string
                field :password, 'Password', :secret_string
              end
              field :inventory_failed, 'Inventory failed', :boolean
              field :locked_by, 'Locked by', :nested do
                field :site_id, 'Site ID', :string
                field :program_id, 'Program ID', :string
                field :instance_id, 'Instance ID', :string
              end
              field :locked_attributes, 'Locked attributes', :string, array: true
              field :network_scan, 'Network scan', :hash
              field :network_scan_result, 'Network scan result', :nested do
                field :start, 'Start', :date_time
                field :end, 'End', :date_time
                field :state, 'State', :string
                field :output, 'Output', :string
              end
              field :contactgroups, 'Contact groups', :nested do
                field :groups, 'Groups', :string, array: true
                field :use, 'Use', :boolean
                field :use_for_services, 'Use for services', :boolean
                field :recurse_use, 'Recurse use', :boolean
                field :recurse_perms, 'Recurse perms', :boolean
              end
              field :meta_data, 'Meta data', :nested do
                field :created_at, 'Created at', :date_time
                field :updated_at, 'Updated at', :date_time
                field :created_by, 'Created by', :string
              end
            end
          end
        end
      end

      run do
        url = "#{helpers.checkmk_base_url}#{GET_HOSTS_API_ROUTE}"
        params = {}
        params[:effective_attributes] = input[:effective_attributes].to_s if input.key?(:effective_attributes)
        params[:include_links] = input[:include_links].to_s if input.key?(:include_links)
        params[:fields] = input[:fields] if input[:fields].present?
        params[:site] = input[:site] if input[:site].present?

        if input[:hostnames].present?
          conn = http_connection(url)
          conn.options[:params_encoder] = Faraday::FlatParamsEncoder
          response = conn.get do |request|
            request.params = params if params.present?
            request.params['hostnames'] = input[:hostnames]
          end
        else
          response = http_get(url, params.presence)
        end

        backoff_if_needed(response, api_name: 'Checkmk')
        result = helpers.parse_checkmk_response(response)
        normalized = camel_to_snake(result)

        [{ output: {
          domain_type: normalized[:domain_type],
          id: normalized[:id],
          title: normalized[:title],
          extensions: normalized[:extensions],
          hosts: normalized[:value] || [],
        } }]
      end
    end

    action '019d1f4e-7837-73ad-8dc1-67280058d2c5' do
      name 'Get host inventory'
      avatar '/assets/icons/checkmk.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Retrieves detailed hardware, software, and networking inventory for a batch of hosts.
        The action paginates internally — it emits one page per batch and drains the full
        `host_names` list across successive iterations.

        **Use case**: Fetch device inventory (manufacturer, model, serial, CPU, memory, OS,
        applications, network interfaces) for CMDB synchronization.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | host_names | Array[String] | Yes | - | Host names to fetch inventory for (typically the changed subset from **Get host inventory timestamps**) |
        | batch_size | Integer | No | 50 | Number of hosts per request (min 1, max 50) |

        ### Example Input

        ```json
        {
          "host_names": ["host1", "host2"],
          "batch_size": 50
        }
        ```

        ### Output

        | Field | Type | Description |
        |-------|------|-------------|
        | has_next_page | Boolean | `true` if more host_names remain after this batch |
        | hosts | Array[Host] | One entry per host in the current batch — see `Host fields` |

        #### Host fields

        | Field | Type | Description |
        |-------|------|-------------|
        | hostname | String | Host name (required) |
        | inventory | Object | Inventory tree — see `Inventory fields` |

        #### Inventory fields

        The `inventory` object mirrors Checkmk's HW/SW inventory tree with snake-cased keys.
        Each node carries `attributes` (with a `pairs` object of scalar facts), optional `nodes`
        (child sub-trees), and optional `table` (rows of tabular data such as interfaces).

        | Path | Type | Description |
        |------|------|-------------|
        | nodes.hardware.nodes.system.attributes.pairs | Object | `{ manufacturer, model, serial, product, family, uuid }` |
        | nodes.hardware.nodes.cpu.attributes.pairs | Object | `{ cores, threads, model, arch, cpus, max_speed, cache_size }` |
        | nodes.hardware.nodes.memory.attributes.pairs | Object | `{ total_ram_usable, total_swap, total_vmalloc }` in bytes |
        | nodes.software.nodes.os.attributes.pairs | Object | `{ name, version, type, vendor, arch, build, service_pack, kernel_version, install_date }` |
        | nodes.software.nodes.applications.nodes.check_mk | Object | Checkmk-specific application info (cluster, sites, versions) |
        | nodes.networking.attributes.pairs | Object | `{ hostname, domain_name, default_gateway, available_ethernet_ports, total_ethernet_ports, total_interfaces }` |
        | nodes.networking.nodes.interfaces.table | Object | `{ key_columns, rows[] }` — one row per NIC with `alias`, `description`, `index`, `oper_status`, `phys_address`, `port_type`, `speed`, `available` |

        ### Example Output

        ```json
        {
          "has_next_page": false,
          "hosts": [
            {
              "hostname": "host1",
              "inventory": {
                "attributes": {},
                "table": {},
                "nodes": {
                  "hardware": {
                    "attributes": {},
                    "table": {},
                    "nodes": {
                      "system": {
                        "attributes": {
                          "pairs": { "manufacturer": "Amazon EC2", "model": "m5a.2xlarge" }
                        },
                        "nodes": {},
                        "table": {}
                      },
                      "cpu": {
                        "attributes": { "pairs": { "cores": 4 } },
                        "nodes": {},
                        "table": {}
                      },
                      "memory": {
                        "attributes": { "pairs": { "total_ram_usable": 33688150016 } },
                        "nodes": {},
                        "table": {}
                      }
                    }
                  },
                  "software": {
                    "attributes": {},
                    "table": {},
                    "nodes": {
                      "os": {
                        "attributes": {
                          "pairs": { "name": "Microsoft Windows Server 2019 Datacenter" }
                        },
                        "nodes": {},
                        "table": {}
                      }
                    }
                  },
                  "networking": {
                    "attributes": {
                      "pairs": { "hostname": "host1", "total_interfaces": 2 }
                    },
                    "table": {},
                    "nodes": {
                      "interfaces": {
                        "attributes": {},
                        "nodes": {},
                        "table": {
                          "key_columns": ["index"],
                          "rows": [
                            {
                              "index": 1,
                              "description": "eth0",
                              "alias": "Primary",
                              "speed": 10000000000,
                              "oper_status": 1,
                              "phys_address": "00:11:22:33:44:55",
                              "port_type": 6,
                              "available": true
                            }
                          ]
                        }
                      }
                    }
                  }
                }
              }
            }
          ]
        }
        ```

        ### Error Handling

        | Condition | Behavior |
        |-----------|----------|
        | 401 / 403 | Fail immediately with `Checkmk authentication error: <status>` |
        | 429 or 503 | Retry, respecting `Retry-After` (default 60s) |
        | Other 4xx / 5xx (400, 404, 500, 502, 504) | Fail with `Checkmk HTTP error: <status>` |
        | Inventory `result_code != 0` | Fail with `Checkmk inventory API error [result_code=N]: <message>` |
        | Non-JSON body | Fail with `Checkmk response was not valid JSON` |

        ### Best Practices

        * Keep `batch_size` at its documented maximum (50) to minimize round-trips.
        * Feed `host_names` from the diffed output of **Get host inventory timestamps** — do not
          re-fetch inventory for hosts whose `mk_inventory_last` is unchanged.
        * Let the action drain its internal pagination across iterations rather than slicing
          `host_names` manually at the caller.
      END_OF_DESCRIPTION

      input_schema do
        field :host_names, 'Host names', :string,
              array: true,
              required: true,
              hint: 'List of host names to fetch inventory for (from Get Hosts action)'
        field :batch_size, 'Batch size', :integer,
              min: 1, max: 50,
              visibility: 'optional',
              default: 50,
              hint: 'Number of hosts per inventory request (max 50)'
      end

      output_schema 'page' do
        field :has_next_page, 'Has next page', :boolean, required: true
        field :hosts, 'Hosts', :nested, array: true do
          field :hostname, 'Hostname', :string, required: true
          field :inventory, 'Inventory', :nested do
            field :attributes, 'Attributes', :hash
            field :nodes, 'Nodes', :nested, remove_unmapped_fields: false do
              field :hardware, 'Hardware', :nested do
                field :attributes, 'Attributes', :hash
                field :nodes, 'Nodes', :nested, remove_unmapped_fields: false do
                  field :system, 'System', :nested do
                    field :attributes, 'Attributes', :nested do
                      field :pairs, 'Pairs', :nested, remove_unmapped_fields: false do
                        field :manufacturer, 'Manufacturer', :string
                        field :model, 'Model', :string
                        field :serial, 'Serial', :string
                        field :product, 'Product', :string
                        field :family, 'Family', :string
                        field :uuid, 'UUID', :string
                      end
                    end
                    field :nodes, 'Nodes', :hash
                    field :table, 'Table', :hash
                  end
                  field :cpu, 'CPU', :nested do
                    field :attributes, 'Attributes', :nested do
                      field :pairs, 'Pairs', :nested, remove_unmapped_fields: false do
                        field :cores, 'Cores', :integer
                        field :threads, 'Threads', :integer
                        field :model, 'Model', :string
                        field :arch, 'Architecture', :string
                        field :cpus, 'CPUs', :integer
                        field :max_speed, 'Max speed', :float
                        field :cache_size, 'Cache size', :integer
                      end
                    end
                    field :nodes, 'Nodes', :hash
                    field :table, 'Table', :hash
                  end
                  field :memory, 'Memory', :nested do
                    field :attributes, 'Attributes', :nested do
                      field :pairs, 'Pairs', :nested, remove_unmapped_fields: false do
                        field :total_ram_usable, 'Total RAM usable', :integer
                        field :total_swap, 'Total swap', :integer
                        field :total_vmalloc, 'Total vmalloc', :integer
                      end
                    end
                    field :nodes, 'Nodes', :hash
                    field :table, 'Table', :hash
                  end
                end
                field :table, 'Table', :hash
              end
              field :software, 'Software', :nested do
                field :attributes, 'Attributes', :hash
                field :nodes, 'Nodes', :nested, remove_unmapped_fields: false do
                  field :os, 'OS', :nested do
                    field :attributes, 'Attributes', :nested do
                      field :pairs, 'Pairs', :nested, remove_unmapped_fields: false do
                        field :name, 'Name', :string
                        field :version, 'Version', :string
                        field :type, 'Type', :string
                        field :vendor, 'Vendor', :string
                        field :arch, 'Architecture', :string
                        field :build, 'Build', :string
                        field :service_pack, 'Service pack', :string
                        field :kernel_version, 'Kernel version', :string
                        field :install_date, 'Install date', :string
                      end
                    end
                    field :nodes, 'Nodes', :hash
                    field :table, 'Table', :hash
                  end
                  field :applications, 'Applications', :nested do
                    field :attributes, 'Attributes', :hash
                    field :nodes, 'Nodes', :nested, remove_unmapped_fields: false do
                      field :check_mk, 'Check MK', :nested do
                        field :attributes, 'Attributes', :nested do
                          field :pairs, 'Pairs', :nested, remove_unmapped_fields: false do
                            field :num_sites, 'Num sites', :integer
                            field :num_versions, 'Num versions', :integer
                          end
                        end
                        field :nodes, 'Nodes', :nested, remove_unmapped_fields: false do
                          field :cluster, 'Cluster', :nested do
                            field :attributes, 'Attributes', :nested do
                              field :pairs, 'Pairs', :nested, remove_unmapped_fields: false do
                                field :is_cluster, 'Is cluster', :boolean
                              end
                            end
                            field :nodes, 'Nodes', :hash
                            field :table, 'Table', :hash
                          end
                          field :sites, 'Sites', :nested do
                            field :attributes, 'Attributes', :hash
                            field :nodes, 'Nodes', :hash
                            field :table, 'Table', :nested do
                              field :key_columns, 'Key columns', :string, array: true
                              field :rows, 'Rows', :nested, array: true, remove_unmapped_fields: false do
                                field :site, 'Site', :string
                                field :used_version, 'Used version', :string
                                field :autostart, 'Autostart', :boolean
                                field :num_hosts, 'Num hosts', :string
                                field :num_services, 'Num services', :string
                                field :apache, 'Apache', :string
                                field :cmc, 'CMC', :string
                                field :crontab, 'Crontab', :string
                                field :dcd, 'DCD', :string
                                field :liveproxyd, 'Liveproxyd', :string
                                field :livestatus_usage, 'Livestatus usage', :float
                                field :mkeventd, 'Mkeventd', :string
                                field :mknotifyd, 'Mknotifyd', :string
                                field :rrdcached, 'Rrdcached', :string
                                field :stunnel, 'Stunnel', :string
                                field :xinetd, 'Xinetd', :string
                                field :check_helper_usage, 'Check helper usage', :float
                                field :checker_helper_usage, 'Checker helper usage', :float
                                field :fetcher_helper_usage, 'Fetcher helper usage', :float
                              end
                            end
                          end
                          field :versions, 'Versions', :nested do
                            field :attributes, 'Attributes', :hash
                            field :nodes, 'Nodes', :hash
                            field :table, 'Table', :nested do
                              field :key_columns, 'Key columns', :string, array: true
                              field :rows, 'Rows', :nested, array: true, remove_unmapped_fields: false do
                                field :version, 'Version', :string
                                field :number, 'Number', :string
                                field :edition, 'Edition', :string
                                field :num_sites, 'Num sites', :integer
                                field :demo, 'Demo', :boolean
                              end
                            end
                          end
                        end
                        field :table, 'Table', :hash
                      end
                      field :checkmk_agent, 'Checkmk agent', :nested do
                        field :attributes, 'Attributes', :nested do
                          field :pairs, 'Pairs', :nested, remove_unmapped_fields: false do
                            field :agent_directory, 'Agent directory', :string
                            field :data_directory, 'Data directory', :string
                            field :local_directory, 'Local directory', :string
                            field :plugins_directory, 'Plugins directory', :string
                            field :spool_directory, 'Spool directory', :string
                            field :version, 'Version', :string
                          end
                        end
                        field :nodes, 'Nodes', :hash
                        field :table, 'Table', :hash
                      end
                    end
                    field :table, 'Table', :hash
                  end
                end
                field :table, 'Table', :hash
              end
              field :networking, 'Networking', :nested do
                field :attributes, 'Attributes', :nested do
                  field :pairs, 'Pairs', :nested, remove_unmapped_fields: false do
                    field :hostname, 'Hostname', :string
                    field :domain_name, 'Domain name', :string
                    field :default_gateway, 'Default gateway', :string
                    field :available_ethernet_ports, 'Available ethernet ports', :integer
                    field :total_ethernet_ports, 'Total ethernet ports', :integer
                    field :total_interfaces, 'Total interfaces', :integer
                  end
                end
                field :nodes, 'Nodes', :nested, remove_unmapped_fields: false do
                  field :interfaces, 'Interfaces', :nested do
                    field :attributes, 'Attributes', :hash
                    field :nodes, 'Nodes', :hash
                    field :table, 'Table', :nested do
                      field :key_columns, 'Key columns', :string, array: true
                      field :rows, 'Rows', :nested, array: true, remove_unmapped_fields: false do
                        field :alias, 'Alias', :string
                        field :available, 'Available', :boolean
                        field :description, 'Description', :string
                        field :index, 'Index', :integer
                        field :oper_status, 'Oper status', :integer
                        field :phys_address, 'Phys address', :string
                        field :port_type, 'Port type', :integer
                        field :speed, 'Speed', :integer
                      end
                    end
                  end
                end
                field :table, 'Table', :hash
              end
            end
            field :table, 'Table', :hash
          end
        end
      end

      iteration_state_schema do
        field :offset, 'Offset', :integer, required: true, default: 0
      end

      run do
        offset = iteration_state_value(:offset) || 0
        batch_size = input[:batch_size]&.to_i || DEFAULT_BATCH_SIZE
        all_host_names = input[:host_names] || []

        batch = all_host_names[offset, batch_size] || []

        if batch.empty?
          self.iteration_state_value = nil
          next [{ output: { has_next_page: false, hosts: [] }, schema_reference: 'page' }]
        end

        request_param = { hosts: batch }.to_json
        url = "#{helpers.checkmk_base_url}/host_inv_api.py"
        response = http_get(url, { request: request_param, output_format: 'json' })
        backoff_if_needed(response, api_name: 'Checkmk')
        result = helpers.parse_checkmk_response(response)
        helpers.validate_inventory_result(result)

        inventory_data = result[:result] || {}
        hosts = batch.map do |hostname|
          host_data = inventory_data[hostname] || {}
          { hostname: hostname, inventory: camel_to_snake(host_data) }
        end

        next_offset = offset + batch.size
        has_more = next_offset < all_host_names.size
        self.iteration_state_value = has_more ? { offset: next_offset } : nil

        [{ output: { has_next_page: has_more, hosts: hosts }, schema_reference: 'page' }]
      end
    end

    action '019db8d6-ceef-7783-b275-c6ee6a60662a' do
      name 'Get host inventory timestamps'
      avatar '/assets/icons/checkmk.svg'
      description <<~END_OF_DESCRIPTION
        Retrieves the `mk_inventory_last` Unix timestamp for every host in one lightweight call.
        Returns `0` for hosts that have never been inventoried.

        **Use case**: Drive incremental inventory syncs — compare each host's `mk_inventory_last`
        against the watermark stored from the previous sync, and pass only the changed subset to
        **Get host inventory**.

        ### Input Parameters

        None.

        ### Example Input

        ```json
        {}
        ```

        ### Output

        | Field | Type | Description |
        |-------|------|-------------|
        | domain_type | String | Checkmk domain type (e.g. `host`) |
        | id | String | Response collection identifier |
        | hosts | Array[Host] | One entry per host — see `Host fields` |

        #### Host fields

        | Field | Type | Description |
        |-------|------|-------------|
        | name | String | Host name (required) |
        | mk_inventory_last | Integer | Unix timestamp of the last HW/SW inventory run; `0` means never inventoried |

        ### Example Output

        ```json
        {
          "domain_type": "host",
          "id": "host",
          "hosts": [
            { "name": "cmk", "mk_inventory_last": 0 },
            { "name": "mysite", "mk_inventory_last": 1776179669 }
          ]
        }
        ```

        ### Error Handling

        | Condition | Behavior |
        |-----------|----------|
        | 401 / 403 | Fail immediately with `Checkmk authentication error: <status>` |
        | 429 or 503 | Retry, respecting `Retry-After` (default 60s) |
        | Other 4xx / 5xx (400, 404, 500, 502, 504) | Fail with `Checkmk HTTP error: <status>` |
        | Non-JSON body | Fail with `Checkmk response was not valid JSON` |

        ### Best Practices

        * Call this before **Get host inventory** to filter the `host_names` input down to only
          hosts whose `mk_inventory_last` changed since the previous sync.
        * Persist each host's `mk_inventory_last` as the watermark for the next run.
        * Skip hosts where `mk_inventory_last = 0` if your sync only cares about inventoried hosts.
      END_OF_DESCRIPTION

      input_schema do
      end

      output_schema do
        field :domain_type, 'Domain type', :string
        field :id, 'ID', :string
        field :hosts, 'Hosts', :nested, array: true do
          field :name, 'Name', :string, required: true
          field :mk_inventory_last, 'Last inventory timestamp', :integer,
                hint: 'Unix timestamp of the last HW/SW inventory run; 0 means never inventoried'
        end
      end

      run do
        url = "#{helpers.checkmk_base_url}#{GET_HOST_INVENTORY_TIMESTAMPS_API_ROUTE}"
        body = { columns: %w[name mk_inventory_last] }.to_json
        response = http_post(url, body) do |request|
          request.headers['Content-Type'] = 'application/json'
        end
        backoff_if_needed(response, api_name: 'Checkmk')
        result = helpers.parse_checkmk_response(response)
        normalized = camel_to_snake(result)

        hosts = (normalized[:value] || []).map do |entry|
          extensions = entry[:extensions] || {}
          { name: extensions[:name], mk_inventory_last: extensions[:mk_inventory_last] }
        end

        [{ output: {
          domain_type: normalized[:domain_type],
          id: normalized[:id],
          hosts: hosts,
        } }]
      end
    end

    helper :checkmk_base_url do
      domain = outbound_connection.config[:domain]
      site_name = outbound_connection.config[:site_name]
      "https://#{domain}/#{site_name}/check_mk"
    end

    helper :parse_checkmk_response do |response|
      if [401, 403].include?(response.status)
        fail_job!("Checkmk authentication error: #{response.status} #{helpers.format_error_body(response)}")
      end
      unless response.status == 200
        fail_job!("Checkmk HTTP error: #{response.status} #{helpers.format_error_body(response)}")
      end

      parse_json_response(
        response.body,
        error_message: "Checkmk response was not valid JSON: '#{response.body}'"
      ).with_indifferent_access
    end

    helper :format_error_body do |response|
      content_type = response.headers['Content-Type'].to_s
      if content_type.include?('application/problem+json')
        parsed = JSON.parse(response.body)
        parts = []
        parts << parsed['title'] if parsed['title'].present?
        parts << parsed['detail'] if parsed['detail'].present?
        next parts.join(' - ') if parts.any?
      end
      "'#{response.body}'"
    rescue JSON::ParserError
      "'#{response.body}'"
    end

    helper :validate_inventory_result do |result|
      result_code = result[:result_code]
      if result_code && result_code != 0
        fail_job!("Checkmk inventory API error [result_code=#{result_code}]: #{result[:result]}")
      end
    end
  end
end
