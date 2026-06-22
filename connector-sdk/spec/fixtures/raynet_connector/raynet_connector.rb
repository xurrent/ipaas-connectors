class RaynetConnector < IPaaS::Connector::Definition
  DEFAULT_DEVICES_PAGE_SIZE = 100
  MAX_DEVICES_PAGE_SIZE = 1000
  DEFAULT_OS_PAGE_SIZE = 100
  MAX_OS_PAGE_SIZE = 1000
  DEVICES_BY_INVENTORY_API_ROUTE = '/Devices/by-inventory'.freeze
  OPERATING_SYSTEMS_BY_MANY_DEVICE_IDS_API_ROUTE = '/OperatingSystems/ByManyDeviceIds'.freeze

  connector '019e2b9d-de23-7092-94c3-1125dfc31d59' do
    name 'Raynet Connector'
    avatar '/assets/icons/raynet.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview

      This connector integrates with [Raynet](https://raynet.de/) to retrieve device inventory and operating system data for synchronizing Configuration Items into the Xurrent CMDB.

      ## Prerequisites

      To use this connector, you need:
      * A Raynet tenant (e.g. `xurrent-demo-01.raynetone.com`)
      * A Raynet **API key** with read access to the Devices and OperatingSystems endpoints

      ## Authentication

      Header-based. Each outbound request carries an `ApiKey` header populated from the connection's **API key** field. No OAuth flow is involved. Provide the **Instance** (e.g. `xurrent-demo-01`) so the connector can compose the base URL `https://<instance>.raynetone.com/api/v1`.

      ## Triggers

      None — this connector is outbound only.

      ## Actions

      ### Fetch devices

      Retrieves devices from `GET /api/v1/Devices/by-inventory` with optional incremental-sync filter. Paginates internally using Raynet's `lastId` cursor — one page is emitted per iteration, and the action drains the full result set across successive iterations.

      **Use case**: populate or refresh the device inventory in Xurrent's CMDB. Pass `inventory_date_later_then` (ISO 8601) to fetch only devices whose inventory was updated at or after a specific time for incremental sync; omit it for a full sync.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |-----------|------|----------|---------|-------------|
      | inventory_date_later_then | DateTime | No | - | ISO 8601 timestamp — return only devices whose inventory was updated at or after this time |
      | count | Integer | No | 100 | Page size (1-1000) |

      #### Example Input

      ```json
      {
        "inventory_date_later_then": "2026-05-14T00:00:00Z",
        "count": 100
      }
      ```

      #### Output

      | Field | Type | Description |
      |-------|------|-------------|
      | has_next_page | Boolean | `true` while more pages remain |
      | devices | Array[Device] | One entry per device in the current page — see `Device fields` |

      ##### Device fields

      | Field | Type | Description |
      |-------|------|-------------|
      | id | String | Raynet device id (UUID v7). Primary key and cursor for pagination |
      | name | String | Hostname assigned to the device |
      | creation_date | DateTime | When the device was first discovered |
      | tag | String | Device tag |
      | domain | String | Active Directory or DNS domain the device belongs to |
      | model | String | Hardware model (e.g. `VMware Virtual Platform`) |
      | manufacturer | String | Hardware manufacturer (e.g. `VMware, Inc.`) |
      | number_of_logical_processors | Integer | Logical CPU count |
      | number_of_processors | Integer | Physical CPU count |
      | total_physical_memory | Integer | Total physical memory in bytes |
      | physical_memory | Integer | Reported physical memory in bytes |
      | uuid | String | SMBIOS hardware UUID — distinct from `id` and may be absent |
      | user_name | String | Last logged-in user (when populated) |
      | comment | String | Free-form comment |
      | corporate_asset_class | String | Corporate asset classification |
      | corporate_identifier | String | Corporate asset identifier |
      | corporate_state | String | Corporate lifecycle state |
      | ad_last_logon | DateTime | Last Active Directory logon timestamp |
      | custom_import_id | String | Identifier from a custom import source |
      | custom_source | String | Free-form custom source label |
      | corporate_ownership | Boolean | Whether the device is corporate-owned |
      | detected_os_type | String | OS family (`None`, `Windows`, `Unix`, `MacOs`) |
      | last_sucessful_inventory_run | DateTime | Timestamp of the last successful inventory run. **Note**: the misspelling `Sucessful` is preserved verbatim from the Raynet API |
      | is_virtual | Boolean | Whether the device is reported as virtual |
      | source | String | Comma-separated list of discovery sources (e.g. `MECM,ActiveDirectory`) |

      #### Example Output

      ```json
      {
        "has_next_page": true,
        "devices": [
          {
            "id": "019aee57-6d0f-7eef-9ca9-504d44b78630",
            "name": "srv_4cb1f",
            "creation_date": "2025-12-05T11:48:18.319Z",
            "model": "VMware Virtual Platform",
            "manufacturer": "VMware, Inc.",
            "number_of_logical_processors": 6,
            "number_of_processors": 6,
            "total_physical_memory": 17179869184,
            "physical_memory": 17179869184,
            "uuid": "2c983a42-2b40-4890-22b0-7fc24b314822",
            "detected_os_type": "Windows",
            "last_sucessful_inventory_run": "2025-12-04T00:02:17.639Z",
            "is_virtual": false,
            "source": "MECM,ActiveDirectory"
          }
        ]
      }
      ```

      #### Error Handling

      | Condition | Behavior |
      |-----------|----------|
      | 401 / 403 | Fail immediately with `Raynet authentication error: <status>` |
      | 404 (no results) | Return empty result; not an error. Raynet returns 404 with `application/problem+json` when zero records match. |
      | 429 or 503 | Retry, respecting `Retry-After` (default 60s) |
      | Other 4xx / 5xx (400, 500, 502, 504) | Fail with `Raynet HTTP error: <status>` |
      | Non-JSON body | Fail with `Raynet response was not valid JSON` |

      #### Best Practices

      * Pass `inventory_date_later_then` set to the start of the previous successful run for incremental sync — do not derive the watermark from per-device `last_sucessful_inventory_run`.
      * Keep `count` at its documented maximum (1000) to minimize round-trips on large tenants.
      * Let the action drain its internal pagination across iterations rather than slicing pages manually.

      ### Fetch operating systems by device IDs

      Retrieves operating system records in bulk for a batch of device IDs from `POST /api/v1/OperatingSystems/ByManyDeviceIds`. The action paginates internally — it emits one page per batch and drains the full `device_ids` list across successive iterations.

      **Use case**: enrich device records with detailed OS information (caption, edition, version, architecture, install date) for CMDB synchronization. Feed `device_ids` from the output of **Fetch devices**.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |-----------|------|----------|---------|-------------|
      | device_ids | Array[String] | Yes | - | Device IDs to fetch OS data for (UUIDs from **Fetch devices** `id`) |
      | count | Integer | No | 100 | Page size (1-1000) |

      #### Example Input

      ```json
      {
        "device_ids": [
          "019aee57-6d0f-7eef-9ca9-504d44b78630",
          "019aee57-4e37-7857-bcea-77aa4dc83e8e"
        ],
        "count": 100
      }
      ```

      #### Output

      | Field | Type | Description |
      |-------|------|-------------|
      | has_next_page | Boolean | `true` while more pages remain |
      | operating_systems | Array[OperatingSystem] | One entry per device that has an OS record — see `OperatingSystem fields`. Devices without an OS record are silently omitted by the API |

      ##### OperatingSystem fields

      | Field | Type | Description |
      |-------|------|-------------|
      | id | String | OS record id (UUID) |
      | device_id | String | Device id this OS record belongs to — pairs with `Fetch devices.id` |
      | name | String | OS short name (e.g. `Windows Server 2016`) |
      | caption | String | OS full caption (e.g. `Microsoft Windows Server 2016 Standard`) |
      | service_pack | String | Service pack identifier |
      | manufacturer | String | OS vendor (e.g. `Microsoft Corporation`) |
      | build_number | String | OS build number |
      | architecture | String | OS architecture (e.g. `64-bit`) |
      | codename | String | OS codename |
      | edition | String | OS edition (e.g. `Standard`) |
      | os_language | String | Locale id (e.g. `1033`) |
      | os_language_name | String | Locale name |
      | version | String | OS version (e.g. `10.0.14393`) |
      | version_internal | String | Internal version identifier |
      | type | String | OS family (`Windows`, `Linux`, `MacOs`) |
      | system_directory | String | OS system directory path |
      | serial_number | String | OS license serial number |
      | install_date | DateTime | When the OS was installed |

      #### Example Output

      ```json
      {
        "has_next_page": false,
        "operating_systems": [
          {
            "id": "019aee70-db5d-78a7-a392-9bcf2814a923",
            "device_id": "019aee57-6d0f-7eef-9ca9-504d44b78630",
            "name": "Windows Server 2016",
            "caption": "Windows Server 2016",
            "manufacturer": "Microsoft Corporation",
            "architecture": "64-bit",
            "edition": "Standard",
            "os_language": "1033",
            "version": "10.0.14393",
            "type": "Windows",
            "system_directory": "C:\\WINDOWS\\system32",
            "serial_number": "00377-60000-00000-AA934"
          }
        ]
      }
      ```

      #### Error Handling

      | Condition | Behavior |
      |-----------|----------|
      | 401 / 403 | Fail immediately with `Raynet authentication error: <status>` |
      | 404 (no results) | Return empty result; not an error. Raynet returns 404 with `application/problem+json` when zero records match. |
      | 429 or 503 | Retry, respecting `Retry-After` (default 60s) |
      | Other 4xx / 5xx (400, 500, 502, 504) | Fail with `Raynet HTTP error: <status>` |
      | Non-JSON body | Fail with `Raynet response was not valid JSON` |

      #### Best Practices

      * `count` defaults to 100 and can go up to 1000 — set it near the max to minimize round-trips on large device lists.
      * Feed `device_ids` from **Fetch devices** rather than maintaining a separate list.

      ## Rate Limiting

      | HTTP Status | Connector Behavior |
      |-------------|--------------------|
      | 200 | Success |
      | 401 / 403 | Fail immediately with `Raynet authentication error: <status>` |
      | 404 (no results) | Return empty result; not an error. Raynet returns 404 with `application/problem+json` when zero records match — e.g. paginating past the last device, or asking for OS records for stub devices that have none. |
      | 429 | Retry, respecting `Retry-After` header (default 60s) |
      | 503 | Retry, respecting `Retry-After` header (default 60s) |
      | 400, other 4xx | Fail with `Raynet HTTP error: <status>` |
      | 500, 502, 504 | Fail with `Raynet HTTP error: <status>` |
      | Invalid JSON body | Fail with `Raynet response was not valid JSON` |

      ## Best Practices

      * Run **Fetch devices** before **Fetch operating systems by device IDs** — the latter consumes the `id` field from the former.
      * Use `inventory_date_later_then` for incremental syncs after the first full sync to keep page counts small.
      * Treat `last_sucessful_inventory_run` as a per-device value, not a global high-watermark — persist the run's start timestamp for the next `inventory_date_later_then` value.
      * Stub devices (devices with no `model` / `manufacturer` / `uuid`) are returned alongside fully-populated devices — the connector returns them as-is so the runbook can filter them out.

      ## Common Use Cases

      * Initial CMDB import → **Fetch devices** (without `inventory_date_later_then`) → **Fetch operating systems by device IDs** for all returned device ids.
      * Incremental sync → **Fetch devices** with `inventory_date_later_then` set to the previous run's start timestamp → **Fetch operating systems by device IDs** for the changed subset.
      * OS enrichment refresh → **Fetch operating systems by device IDs** with a known device id list.

      ## References

      * Raynet API documentation: https://docs.raynet.de/raynet-one/cloud/2026.1-u3/api-v1/en/index.html
      * Endpoints used by this connector:
        * `GET /api/v1/Devices/by-inventory` — Fetch devices (cursor pagination via `lastId`, incremental filter via `inventoryDateLaterThen`)
        * `POST /api/v1/OperatingSystems/ByManyDeviceIds` — Fetch operating systems by device IDs
    END_OF_DESCRIPTION

    outbound_connection do
      config_schema do
        field :instance, 'Instance', :string,
              required: true,
              hint: 'Raynet tenant — paste the subdomain (xurrent-demo-01), the full host ' \
                    '(xurrent-demo-01.raynetone.com), or the full URL ' \
                    '(https://xurrent-demo-01.raynetone.com); the connector normalizes all three'
        field :api_key, 'API key', :secret_string,
              required: true,
              hint: 'Raynet API key with read access to Devices and OperatingSystems'
      end

      authenticate do |request|
        request.headers['ApiKey'] = decrypt_secret_string(config[:api_key])
        request.headers['Content-Type'] = 'application/json'
      end
    end

    action '019e2b9d-de23-7917-a4de-3f30b50fd211' do
      name 'Fetch devices'
      avatar '/assets/icons/raynet.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Retrieves devices from `GET /api/v1/Devices/by-inventory` with optional incremental-sync filter. Paginates internally using Raynet's `lastId` cursor — one page is emitted per iteration, and the action drains the full result set across successive iterations.

        **Use case**: populate or refresh the device inventory in Xurrent's CMDB. Pass `inventory_date_later_then` (ISO 8601) to fetch only devices whose inventory was updated at or after a specific time for incremental sync; omit it for a full sync.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | inventory_date_later_then | DateTime | No | - | ISO 8601 timestamp — return only devices whose inventory was updated at or after this time |
        | count | Integer | No | 100 | Page size (1-1000) |

        ### Example Input

        ```json
        {
          "inventory_date_later_then": "2026-05-14T00:00:00Z",
          "count": 100
        }
        ```

        ### Output

        | Field | Type | Description |
        |-------|------|-------------|
        | has_next_page | Boolean | `true` while more pages remain |
        | devices | Array[Device] | One entry per device in the current page — see `Device fields` |

        #### Device fields

        | Field | Type | Description |
        |-------|------|-------------|
        | id | String | Raynet device id (UUID v7). Primary key and cursor for pagination |
        | name | String | Hostname assigned to the device |
        | creation_date | DateTime | When the device was first discovered |
        | tag | String | Device tag |
        | domain | String | Active Directory or DNS domain the device belongs to |
        | model | String | Hardware model |
        | manufacturer | String | Hardware manufacturer |
        | number_of_logical_processors | Integer | Logical CPU count |
        | number_of_processors | Integer | Physical CPU count |
        | total_physical_memory | Integer | Total physical memory in bytes |
        | physical_memory | Integer | Reported physical memory in bytes |
        | uuid | String | SMBIOS hardware UUID — distinct from `id` and may be absent |
        | user_name | String | Last logged-in user (when populated) |
        | comment | String | Free-form comment |
        | corporate_asset_class | String | Corporate asset classification |
        | corporate_identifier | String | Corporate asset identifier |
        | corporate_state | String | Corporate lifecycle state |
        | ad_last_logon | DateTime | Last Active Directory logon timestamp |
        | custom_import_id | String | Identifier from a custom import source |
        | custom_source | String | Free-form custom source label |
        | corporate_ownership | Boolean | Whether the device is corporate-owned |
        | detected_os_type | String | OS family (`None`, `Windows`, `Unix`, `MacOs`) |
        | last_sucessful_inventory_run | DateTime | Timestamp of the last successful inventory run. The misspelling `Sucessful` is preserved verbatim from the Raynet API |
        | is_virtual | Boolean | Whether the device is reported as virtual |
        | source | String | Comma-separated list of discovery sources (e.g. `MECM,ActiveDirectory`) |

        ### Example Output

        ```json
        {
          "has_next_page": true,
          "devices": [
            {
              "id": "019aee57-6d0f-7eef-9ca9-504d44b78630",
              "name": "srv_4cb1f",
              "creation_date": "2025-12-05T11:48:18.319Z",
              "model": "VMware Virtual Platform",
              "manufacturer": "VMware, Inc.",
              "number_of_logical_processors": 6,
              "number_of_processors": 6,
              "total_physical_memory": 17179869184,
              "physical_memory": 17179869184,
              "uuid": "2c983a42-2b40-4890-22b0-7fc24b314822",
              "detected_os_type": "Windows",
              "last_sucessful_inventory_run": "2025-12-04T00:02:17.639Z",
              "is_virtual": false,
              "source": "MECM,ActiveDirectory"
            }
          ]
        }
        ```

        ### Error Handling

        | Condition | Behavior |
        |-----------|----------|
        | 401 / 403 | Fail immediately with `Raynet authentication error: <status>` |
        | 404 (no results) | Return empty result; not an error. Raynet returns 404 with `application/problem+json` when zero records match. |
        | 429 or 503 | Retry, respecting `Retry-After` (default 60s) |
        | Other 4xx / 5xx (400, 500, 502, 504) | Fail with `Raynet HTTP error: <status>` |
        | Non-JSON body | Fail with `Raynet response was not valid JSON` |

        ### Best Practices

        * Pass `inventory_date_later_then` set to the start of the previous successful run for incremental sync.
        * Keep `count` at its documented maximum (1000) to minimize round-trips on large tenants.
        * Let the action drain its internal pagination across iterations rather than slicing pages manually.
      END_OF_DESCRIPTION

      input_schema do
        field :inventory_date_later_then, 'Inventory date later then', :date_time,
              visibility: 'optional',
              hint: 'Return only devices whose inventory was updated at or after this time'
        field :count, 'Count', :integer,
              min: 1, max: MAX_DEVICES_PAGE_SIZE,
              visibility: 'optional',
              default: DEFAULT_DEVICES_PAGE_SIZE,
              hint: 'Page size (1-1000)'
      end

      output_schema 'page' do
        field :has_next_page, 'Has next page', :boolean, required: true
        field :devices, 'Devices', :nested, array: true do
          field :id, 'ID', :string, required: true
          field :name, 'Name', :string
          field :creation_date, 'Creation date', :date_time
          field :tag, 'Tag', :string
          field :domain, 'Domain', :string
          field :model, 'Model', :string
          field :manufacturer, 'Manufacturer', :string
          field :number_of_logical_processors, 'Number of logical processors', :integer
          field :number_of_processors, 'Number of processors', :integer
          field :total_physical_memory, 'Total physical memory', :integer
          field :physical_memory, 'Physical memory', :integer
          field :uuid, 'UUID', :string
          field :user_name, 'User name', :string
          field :comment, 'Comment', :string
          field :corporate_asset_class, 'Corporate asset class', :string
          field :corporate_identifier, 'Corporate identifier', :string
          field :corporate_state, 'Corporate state', :string
          field :ad_last_logon, 'AD last logon', :date_time
          field :custom_import_id, 'Custom import ID', :string
          field :custom_source, 'Custom source', :string
          field :corporate_ownership, 'Corporate ownership', :boolean
          field :detected_os_type, 'Detected OS type', :string
          field :last_sucessful_inventory_run, 'Last successful inventory run', :date_time,
                hint: 'Misspelling Sucessful is preserved verbatim from the Raynet API'
          field :is_virtual, 'Is virtual', :boolean
          field :source, 'Source', :string
        end
      end

      iteration_state_schema do
        field :last_id, 'Last ID', :string
      end

      run do
        page_size = input[:count]&.to_i || DEFAULT_DEVICES_PAGE_SIZE
        last_id = iteration_state_value(:last_id)

        inventory_date = input[:inventory_date_later_then]
        params = { count: page_size.to_s }
        params[:lastId] = last_id if last_id.present?
        params[:inventoryDateLaterThen] = inventory_date.to_datetime.utc.iso8601 if inventory_date.present?

        url = "#{helpers.raynet_base_url}#{DEVICES_BY_INVENTORY_API_ROUTE}"
        response = http_get(url, params)
        backoff_if_needed(response, api_name: 'Raynet')
        result = helpers.parse_raynet_response(response)

        devices = result.is_a?(Array) ? result : []
        devices = camel_to_snake(devices.map { |d| d.except('$id') })

        has_more = devices.size == page_size
        self.iteration_state_value = has_more ? { last_id: devices.last[:id] } : nil

        [{ output: { has_next_page: has_more, devices: devices }, schema_reference: 'page' }]
      end
    end

    action '019e2b9d-de23-755d-bac7-0f52597c1bd1' do
      name 'Fetch operating systems by device IDs'
      avatar '/assets/icons/raynet.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Retrieves operating system records in bulk for a batch of device IDs from `POST /api/v1/OperatingSystems/ByManyDeviceIds`. The action paginates internally — it emits one page per batch and drains the full `device_ids` list across successive iterations.

        **Use case**: enrich device records with detailed OS information (caption, edition, version, architecture, install date) for CMDB synchronization. Feed `device_ids` from the output of **Fetch devices**.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_ids | Array[String] | Yes | - | Device IDs to fetch OS data for (UUIDs from **Fetch devices** `id`) |
        | count | Integer | No | 100 | Page size (1-1000) |

        ### Example Input

        ```json
        {
          "device_ids": [
            "019aee57-6d0f-7eef-9ca9-504d44b78630",
            "019aee57-4e37-7857-bcea-77aa4dc83e8e"
          ],
          "count": 100
        }
        ```

        ### Output

        | Field | Type | Description |
        |-------|------|-------------|
        | has_next_page | Boolean | `true` while more pages remain |
        | operating_systems | Array[OperatingSystem] | One entry per device that has an OS record — see `OperatingSystem fields`. Devices without an OS record are silently omitted by the API |

        #### OperatingSystem fields

        | Field | Type | Description |
        |-------|------|-------------|
        | id | String | OS record id (UUID) |
        | device_id | String | Device id this OS record belongs to — pairs with `Fetch devices.id` |
        | name | String | OS short name |
        | caption | String | OS full caption |
        | service_pack | String | Service pack identifier |
        | manufacturer | String | OS vendor |
        | build_number | String | OS build number |
        | architecture | String | OS architecture |
        | codename | String | OS codename |
        | edition | String | OS edition |
        | os_language | String | Locale id |
        | os_language_name | String | Locale name |
        | version | String | OS version |
        | version_internal | String | Internal version identifier |
        | type | String | OS family |
        | system_directory | String | OS system directory path |
        | serial_number | String | OS license serial number |
        | install_date | DateTime | When the OS was installed |

        ### Example Output

        ```json
        {
          "has_next_page": false,
          "operating_systems": [
            {
              "id": "019aee70-db5d-78a7-a392-9bcf2814a923",
              "device_id": "019aee57-6d0f-7eef-9ca9-504d44b78630",
              "name": "Windows Server 2016",
              "caption": "Windows Server 2016",
              "manufacturer": "Microsoft Corporation",
              "architecture": "64-bit",
              "edition": "Standard",
              "os_language": "1033",
              "version": "10.0.14393",
              "type": "Windows",
              "system_directory": "C:\\WINDOWS\\system32",
              "serial_number": "00377-60000-00000-AA934"
            }
          ]
        }
        ```

        ### Error Handling

        | Condition | Behavior |
        |-----------|----------|
        | 401 / 403 | Fail immediately with `Raynet authentication error: <status>` |
        | 404 (no results) | Return empty result; not an error. Raynet returns 404 with `application/problem+json` when zero records match. |
        | 429 or 503 | Retry, respecting `Retry-After` (default 60s) |
        | Other 4xx / 5xx (400, 500, 502, 504) | Fail with `Raynet HTTP error: <status>` |
        | Non-JSON body | Fail with `Raynet response was not valid JSON` |

        ### Best Practices

        * `count` defaults to 100 and can go up to 1000 — set it near the max to minimize round-trips on large device lists.
        * Feed `device_ids` from **Fetch devices** rather than maintaining a separate list.
      END_OF_DESCRIPTION

      input_schema do
        field :device_ids, 'Device IDs', :string,
              array: true,
              required: true,
              hint: 'List of device IDs (UUIDs) to fetch OS data for'
        field :count, 'Count', :integer,
              min: 1, max: MAX_OS_PAGE_SIZE,
              visibility: 'optional',
              default: DEFAULT_OS_PAGE_SIZE,
              hint: 'Page size (1-1000)'
      end

      output_schema 'page' do
        field :has_next_page, 'Has next page', :boolean, required: true
        field :operating_systems, 'Operating systems', :nested, array: true do
          field :id, 'ID', :string, required: true
          field :device_id, 'Device ID', :string, required: true
          field :name, 'Name', :string
          field :caption, 'Caption', :string
          field :service_pack, 'Service pack', :string
          field :manufacturer, 'Manufacturer', :string
          field :build_number, 'Build number', :string
          field :architecture, 'Architecture', :string
          field :codename, 'Codename', :string
          field :edition, 'Edition', :string
          field :os_language, 'OS language', :string
          field :os_language_name, 'OS language name', :string
          field :version, 'Version', :string
          field :version_internal, 'Version internal', :string
          field :type, 'Type', :string
          field :system_directory, 'System directory', :string
          field :serial_number, 'Serial number', :string
          field :install_date, 'Install date', :date_time
        end
      end

      iteration_state_schema do
        field :last_id, 'Last ID', :string
      end

      run do
        page_size = input[:count]&.to_i || DEFAULT_OS_PAGE_SIZE
        last_id = iteration_state_value(:last_id)

        query = { count: page_size.to_s }
        query[:LastId] = last_id if last_id.present?
        base = "#{helpers.raynet_base_url}#{OPERATING_SYSTEMS_BY_MANY_DEVICE_IDS_API_ROUTE}"
        url = "#{base}?#{URI.encode_www_form(query)}"

        response = http_post(url, { guids: input[:device_ids] }.to_json)
        backoff_if_needed(response, api_name: 'Raynet')
        result = helpers.parse_raynet_response(response)
        operating_systems = result.is_a?(Array) ? camel_to_snake(result.map { |r| r.except('$id') }) : []

        has_more = operating_systems.size == page_size
        self.iteration_state_value = has_more ? { last_id: operating_systems.last[:id] } : nil

        [{ output: { has_next_page: has_more, operating_systems: operating_systems }, schema_reference: 'page' }]
      end
    end

    helper :raynet_base_url do
      raw = outbound_connection.config[:instance].to_s.strip
      instance = raw.sub(%r{\Ahttps?://}i, '').sub(/\.raynetone\.com.*\z/i, '').sub(%r{/.*\z}, '')
      "https://#{instance}.raynetone.com/api/v1"
    end

    helper :parse_raynet_response do |response|
      if [401, 403].include?(response.status)
        fail_job!("Raynet authentication error: #{response.status} #{helpers.format_error_body(response)}")
      end
      next [] if response.status == 404
      unless response.status == 200
        fail_job!("Raynet HTTP error: #{response.status} #{helpers.format_error_body(response)}")
      end

      parse_json_response(
        response.body,
        error_message: "Raynet response was not valid JSON: '#{response.body}'"
      )
    end

    helper :format_error_body do |response|
      content_type = response.headers['Content-Type'].to_s
      if content_type.include?('application/problem+json')
        parsed = JSON.parse(response.body)
        parts = []
        parts << parsed['title']  if parsed['title'].present?
        parts << parsed['detail'] if parsed['detail'].present?
        next parts.join(' - ') if parts.any?
      end
      "'#{response.body}'"
    rescue JSON::ParserError
      "'#{response.body}'"
    end
  end
end
