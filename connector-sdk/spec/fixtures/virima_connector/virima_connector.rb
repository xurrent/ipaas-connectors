class VirimaConnector < IPaaS::Connector::Definition
  connector '019b91f0-cfe4-7648-9d97-3854c4c0e0f0' do
    name 'Virima Connector'
    avatar '/assets/icons/virima.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Connects to [Virima](https://virima.com/) to read devices and configuration items, and create matching Configuration Items in Xurrent's CMDB.

      ## Prerequisites
      - A Virima account with API access enabled.
      - An **API Key** generated from the Virima admin panel.
      - Your **Tenant ID** from Virima.

      ## Authentication
      Uses your **API Key** and **Tenant ID** to authenticate

      ## Triggers
      None — this connector is outbound only.

      ## Actions

      ### Fetch devices

      Retrieves all devices from Virima with pagination support using the Get Devices API. Records are sorted by last modified time (newest first); archived devices and CI parts are filtered out.

      **Use case**: populate or refresh the list of Virima-managed devices in Xurrent's CMDB. Use the **Last sync at** field to fetch only devices modified after a specific time, which is useful for incremental CMDB updates.

      > Virima's API does not support filtering by modification time on its
      > side, so the **Last sync at** cutoff is applied by the connector.
      > Because devices come back newest-first, pagination stops as soon as
      > a device older than the cutoff is reached.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |-----------|------|----------|---------|-------------|
      | last_sync_at | DateTime | No | - | Only fetch devices modified after this time. Leave blank to fetch all devices |
      | page_size | Integer | No | 100 | Number of devices per page (1-1000) |

      #### Example Input

      ```json
      {
        "last_sync_at": "2025-11-12T10:00:00Z",
        "page_size": 100
      }
      ```

      #### Output

      | Field Name | Type | Description |
      |---|---|---|
      | `total` | Integer | Total devices in Virima |
      | `has_next_page` | Boolean | `true` while more pages remain |
      | `devices` | Array | One object per device — see **Device object fields** below |

      ##### Device object fields

      | Field Name | Type | Description |
      |---|---|---|
      | `id` | Integer | Virima device ID |
      | `record_id` | String | Unique record identifier |
      | `is_processing` | Boolean | Whether the device is currently being processed |
      | `pattern_scan_running` | Boolean | Whether a pattern scan is running |
      | `is_changed` | Boolean | Whether the device has been changed |
      | `is_aws_import` | Boolean | Whether the device was imported from AWS |
      | `is_editable` | Boolean | Whether the device is editable |
      | `has_change_request` | Boolean | Whether the device has an open change request |
      | `created_on` | DateTime | When the device record was created |
      | `last_modified_on` | DateTime | When the device was last modified |
      | `blueprint` | Object | Device blueprint — `id`, `name`, `icon`, `component`, `configure_main_page` |
      | `private_property_visibility` | Boolean | Whether private properties are visible |
      | `is_temporary_access_given` | Boolean | Whether temporary access is granted |
      | `hardware_asset` | Object | Hardware asset information |
      | `last_seen` | DateTime | When the device was last seen |
      | `missing_components` | Boolean | Whether the device has missing components |
      | `is_moved` | String | Whether the device has been moved |
      | `cherwell_sync` | String | Cherwell sync status |
      | `jira_sync` | String | Jira sync status |
      | `properties` | Array | Device properties — see **Property object fields** below |
      | `selected_cis` | Array | Selected Configuration Items |
      | `groups` | Array | Device groups |

      ##### Property object fields

      | Field Name | Type | Description |
      |---|---|---|
      | `property_name` | String | Field name (e.g. "Asset Name", "Host Name", "IP Address", "Asset ID") |
      | `property_value` | String | Field value |
      | `group_name` | String | Property group (e.g. "Asset Primary Information", "Hardware and Network", "Device Details") |
      | `mandatory` | String | Whether the property is mandatory |
      | `type` | String | Data type (e.g. "text", "bigint") |
      | `private_property` | Boolean | Whether the property is private |

      #### Example Output

      ```json
      {
        "total": 1,
        "has_next_page": false,
        "devices": [
          {
            "id": 1,
            "record_id": "3d778a6a-a75f-4cd7-995f-07d5fc037087",
            "is_processing": false,
            "pattern_scan_running": false,
            "is_changed": false,
            "is_aws_import": false,
            "is_editable": false,
            "has_change_request": false,
            "created_on": "1970-01-01T00:00:00Z",
            "last_modified_on": "2025-11-12T10:12:34Z",
            "blueprint": {
              "id": 11,
              "name": "Windows Server",
              "icon": "windows-server.png",
              "component": false,
              "configure_main_page": "[]"
            },
            "private_property_visibility": false,
            "is_temporary_access_given": false,
            "hardware_asset": {
              "stringobj": ""
            },
            "last_seen": "1970-01-01T00:00:00Z",
            "missing_components": false,
            "is_moved": "False",
            "cherwell_sync": "False",
            "jira_sync": "False",
            "properties": [
              {
                "group_name": "Asset Primary Information",
                "property_name": "Asset Name",
                "property_value": "ADSERVERLD @ 10.14.80.36",
                "mandatory": "true",
                "type": "text",
                "private_property": false
              },
              {
                "group_name": "Asset Primary Information",
                "property_name": "Host Name",
                "property_value": "ADSERVERLD Test1",
                "mandatory": "true",
                "type": "text",
                "private_property": false
              },
              {
                "group_name": "Hardware and Network",
                "property_name": "IP Address",
                "property_value": "10.14.80.36",
                "mandatory": "true",
                "type": "text",
                "private_property": false
              },
              {
                "group_name": "Asset Primary Information",
                "property_name": "Asset ID",
                "property_value": "AST000001",
                "mandatory": "",
                "type": "text",
                "private_property": false
              }
            ],
            "selected_cis": [],
            "groups": []
          }
        ]
      }
      ```

      #### Error Handling
      The job fails immediately on 400 / 401 / 403 responses (invalid input or credential/permission issue — Virima error codes starting with `ERRUSR` or `ERRPMT` also map here). On 429 (rate limited) or 503 (service unavailable) responses, the connector waits for the time in `Retry-After` and retries automatically. See [Virima error codes](https://poc.virima.com/www_em/errorcodes.html) for the full list.

      ## Rate Limiting
      Virima applies rate limits on API requests. The connector automatically waits and retries when it hits the limit or when Virima is temporarily unavailable.

      | HTTP status | Connector behaviour |
      |---|---|
      | 429 Too Many Requests | Retry after `Retry-After` seconds (60 s default if header absent) |
      | 503 Service Unavailable | Retry with backoff |
      | 401 / 403 | Fail immediately — credential or permission issue |
      | 400 | Fail immediately — invalid input |

      ## References
      - [Virima](https://virima.com/)
      - [Virima API documentation](https://poc.virima.com/www_em/home.html)
      - [Virima API error codes](https://poc.virima.com/www_em/errorcodes.html)
    END_OF_DESCRIPTION

    outbound_connection do
      config_schema do
        field :credentials, 'Credentials', :nested,
              required: true,
              hint: 'API credentials for Virima access' do
          field :api_key, 'API Key', :secret_string,
                required: true,
                hint: 'Virima API Key (keep secure)'
          field :tenant_id, 'Tenant ID', :string,
                required: true,
                hint: 'Virima Tenant ID'
        end
        field :api_endpoint, 'API Endpoint', :uri,
              visibility: 'optional',
              default: 'https://login.virima.com',
              hint: 'Base URL for Virima API'
      end

      authenticate do |request|
        credentials = config[:credentials]
        api_key = decrypt_secret_string(credentials[:api_key])
        tenant_id = credentials[:tenant_id]

        request.headers['Api-Key'] = api_key
        request.headers['Tenant-Id'] = tenant_id
        request.headers['Content-Type'] = 'application/json'
      end
    end

    action '019b91f1-7f30-7861-8c1a-b055f865f89a' do
      name 'Fetch devices'
      avatar '/assets/icons/virima.svg'
      nested true

      description <<~END_OF_DESCRIPTION
        Retrieves all devices from Virima with pagination support using the Get Devices API. Records are sorted by last modified time (newest first); archived devices and CI parts are filtered out.

        **Use case**: populate or refresh the list of Virima-managed devices in Xurrent's CMDB. Use the **Last sync at** field to fetch only devices modified after a specific time, which is useful for incremental CMDB updates.

        > Virima's API does not support filtering by modification time on its
        > side, so the **Last sync at** cutoff is applied by the connector.
        > Because devices come back newest-first, pagination stops as soon as
        > a device older than the cutoff is reached.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | last_sync_at | DateTime | No | - | Only fetch devices modified after this time. Leave blank to fetch all devices |
        | page_size | Integer | No | 100 | Number of devices per page (1-1000) |

        ### Example Input

        ```json
        {
          "last_sync_at": "2025-11-12T10:00:00Z",
          "page_size": 100
        }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `total` | Integer | Total devices in Virima |
        | `has_next_page` | Boolean | `true` while more pages remain |
        | `devices` | Array | One object per device — see **Device object fields** below |

        #### Device object fields

        | Field Name | Type | Description |
        |---|---|---|
        | `id` | Integer | Virima device ID |
        | `record_id` | String | Unique record identifier |
        | `is_processing` | Boolean | Whether the device is currently being processed |
        | `pattern_scan_running` | Boolean | Whether a pattern scan is running |
        | `is_changed` | Boolean | Whether the device has been changed |
        | `is_aws_import` | Boolean | Whether the device was imported from AWS |
        | `is_editable` | Boolean | Whether the device is editable |
        | `has_change_request` | Boolean | Whether the device has an open change request |
        | `created_on` | DateTime | When the device record was created |
        | `last_modified_on` | DateTime | When the device was last modified |
        | `blueprint` | Object | Device blueprint — `id`, `name`, `icon`, `component`, `configure_main_page` |
        | `private_property_visibility` | Boolean | Whether private properties are visible |
        | `is_temporary_access_given` | Boolean | Whether temporary access is granted |
        | `hardware_asset` | Object | Hardware asset information |
        | `last_seen` | DateTime | When the device was last seen |
        | `missing_components` | Boolean | Whether the device has missing components |
        | `is_moved` | String | Whether the device has been moved |
        | `cherwell_sync` | String | Cherwell sync status |
        | `jira_sync` | String | Jira sync status |
        | `properties` | Array | Device properties — see **Property object fields** below |
        | `selected_cis` | Array | Selected Configuration Items |
        | `groups` | Array | Device groups |

        #### Property object fields

        | Field Name | Type | Description |
        |---|---|---|
        | `property_name` | String | Field name (e.g. "Asset Name", "Host Name", "IP Address", "Asset ID") |
        | `property_value` | String | Field value |
        | `group_name` | String | Property group (e.g. "Asset Primary Information", "Hardware and Network", "Device Details") |
        | `mandatory` | String | Whether the property is mandatory |
        | `type` | String | Data type (e.g. "text", "bigint") |
        | `private_property` | Boolean | Whether the property is private |

        ### Example Output

        ```json
        {
          "total": 1,
          "has_next_page": false,
          "devices": [
            {
              "id": 1,
              "record_id": "3d778a6a-a75f-4cd7-995f-07d5fc037087",
              "is_processing": false,
              "pattern_scan_running": false,
              "is_changed": false,
              "is_aws_import": false,
              "is_editable": false,
              "has_change_request": false,
              "created_on": "1970-01-01T00:00:00Z",
              "last_modified_on": "2025-11-12T10:12:34Z",
              "blueprint": {
                "id": 11,
                "name": "Windows Server",
                "icon": "windows-server.png",
                "component": false,
                "configure_main_page": "[]"
              },
              "private_property_visibility": false,
              "is_temporary_access_given": false,
              "hardware_asset": {
                "stringobj": ""
              },
              "last_seen": "1970-01-01T00:00:00Z",
              "missing_components": false,
              "is_moved": "False",
              "cherwell_sync": "False",
              "jira_sync": "False",
              "properties": [
                {
                  "group_name": "Asset Primary Information",
                  "property_name": "Asset Name",
                  "property_value": "ADSERVERLD @ 10.14.80.36",
                  "mandatory": "true",
                  "type": "text",
                  "private_property": false
                },
                {
                  "group_name": "Asset Primary Information",
                  "property_name": "Host Name",
                  "property_value": "ADSERVERLD Test1",
                  "mandatory": "true",
                  "type": "text",
                  "private_property": false
                },
                {
                  "group_name": "Hardware and Network",
                  "property_name": "IP Address",
                  "property_value": "10.14.80.36",
                  "mandatory": "true",
                  "type": "text",
                  "private_property": false
                },
                {
                  "group_name": "Asset Primary Information",
                  "property_name": "Asset ID",
                  "property_value": "AST000001",
                  "mandatory": "",
                  "type": "text",
                  "private_property": false
                }
              ],
              "selected_cis": [],
              "groups": []
            }
          ]
        }
        ```

        ### Error Handling
        The job fails immediately on 400 / 401 / 403 responses (invalid input or credential/permission issue — Virima error codes starting with `ERRUSR` or `ERRPMT` also map here). On 429 (rate limited) or 503 (service unavailable) responses, the connector waits for the time in `Retry-After` and retries automatically. See [Virima error codes](https://poc.virima.com/www_em/errorcodes.html) for the full list.
      END_OF_DESCRIPTION

      input_schema do
        field :last_sync_at, 'Last sync at', :date_time,
              hint: 'Only fetch devices modified after this time. Leave blank to fetch all devices.'
        field :page_size, 'Page size', :integer,
              min: 1,
              max: 1000,
              visibility: 'optional',
              default: 100,
              hint: 'Number of devices per page (max 1000)'
      end

      output_schema 'page' do
        field :total, 'Total', :integer,
              hint: 'Total number of devices'
        field :has_next_page, 'Has next page', :boolean, required: true
        field :devices, 'Devices', :nested, array: true do
          field :id, 'ID', :integer, required: true
          field :record_id, 'Record ID', :string, required: true
          field :is_processing, 'Is processing', :boolean
          field :pattern_scan_running, 'Pattern scan running', :boolean
          field :is_changed, 'Is changed', :boolean
          field :is_aws_import, 'Is AWS import', :boolean
          field :is_editable, 'Is editable', :boolean
          field :has_change_request, 'Has change request', :boolean
          field :created_on, 'Created on', :date_time
          field :last_modified_on, 'Last modified on', :date_time
          field :blueprint, 'Blueprint', :nested do
            field :id, 'ID', :integer
            field :name, 'Name', :string
            field :icon, 'Icon', :string
            field :component, 'Component', :boolean
            field :configure_main_page, 'Configure main page', :string
          end
          field :private_property_visibility, 'Private property visibility', :boolean
          field :is_temporary_access_given, 'Is temporary access given', :boolean
          field :hardware_asset, 'Hardware asset', :nested do
            field :stringobj, 'String object', :string
          end
          field :last_seen, 'Last seen', :date_time
          field :missing_components, 'Missing components', :boolean
          field :is_moved, 'Is moved', :string
          field :cherwell_sync, 'Cherwell sync', :string
          field :jira_sync, 'Jira sync', :string
          field :properties, 'Properties', :nested, array: true do
            field :group_name, 'Group name', :string
            field :property_name, 'Property name', :string
            field :property_value, 'Property value', :string
            field :mandatory, 'Mandatory', :string
            field :type, 'Type', :string
            field :private_property, 'Private property', :boolean
          end
          field :selected_cis, 'Selected CIs', :nested, array: true
          field :groups, 'Groups', :nested, array: true
        end
      end

      iteration_state_schema do
        field :page, 'Page', :integer, required: true, default: 0
      end

      run do
        page = iteration_state_value(:page) || 0
        page_size = input[:page_size]&.to_i

        url = "#{helpers.api_endpoint}/www_em/rest/get-records/get-all/#{page}/#{page_size}"
        headers = { 'Content-Type': 'application/json', accept: 'application/json' }
        response = http_post(url, helpers.request_body.to_json, headers)

        backoff_if_needed(response, api_name: 'Virima')
        result = helpers.parse_response(response)

        total_results = result[:totalResults] || 0
        response_list_json_string = result[:responseList]

        fail_job!('responseList is missing from the API response') if response_list_json_string.blank?

        devices = begin
          parsed = JSON.parse(response_list_json_string)
          if parsed.is_a?(Array)
            parsed.map(&:with_indifferent_access)
          else
            fail_job!("Failed to parse responseList: Not an Array \n#{parsed}")
          end
        rescue JSON::ParserError => e
          fail_job!("Failed to parse responseList: #{e.message}")
        end

        has_more = devices.size == page_size && ((page * page_size) + devices.size) < total_results

        if input[:last_sync_at].present?
          last_sync_at = input[:last_sync_at]
          cutoff_index = devices.index { |d| helpers.to_datetime(d[:lastModifiedOn]) < last_sync_at }
          if cutoff_index
            devices = devices[0...cutoff_index]
            has_more = false
          end
        end

        self.iteration_state_value = has_more ? { page: page + 1 } : nil

        [{
          output: {
            total: total_results,
            has_next_page: has_more,
            devices: helpers.transform(devices),
          },
          schema_reference: 'page',
        }]
      end
    end

    helper :api_endpoint do
      env_config = outbound_connection.config
      endpoint = env_config[:api_endpoint].presence
      endpoint || 'https://login.virima.com'
    end

    helper :request_body do
      {
        sort: {
          sortKey: 'lastModifiedOn',
          sortOrder: 'DESC',
        },
        className: 'CmdbCi',
        dbClassName: 'TCI',
        module: 'CmdbCi',
        filters: [
          {
            dbProperty: 'archive',
            dbPropertyType: 'boolean',
            key: 'Archive',
            mapProperty: false,
            possibleValue: 'false',
            type: 'DEFAULT',
            filterKey: 'archive',
            operator: 'eq',
            value1: 'false',
            default: true,
          },
          {
            dbProperty: 'blueprint.isCIPart',
            dbPropertyType: 'boolean',
            key: 'isCiPart',
            mapProperty: false,
            possibleValue: 'false',
            type: 'DEFAULT',
            filterKey: 'blueprint.isCIPart',
            operator: 'eq',
            value1: 'false',
            default: true,
          },
        ],
      }
    end

    helper :parse_response do |response|
      begin
        body = JSON.parse(response.body)
      rescue JSON::ParserError
        fail_job!("HTTP error: #{response.status} '#{response.body}'")
      end

      if body['code'].present?
        error_code = body['code']
        error_text = body['message'] || 'Unknown error'

        auth_error_prefixes = %w[ERRUSR ERRPMT]
        is_auth_error = auth_error_prefixes.any? { |prefix| error_code.start_with?(prefix) }

        if is_auth_error || [401, 403].include?(response.status)
          fail_job!("Virima authentication/permission error [#{error_code}]: #{error_text}. " \
                    'Check your Api-Key and Tenant-Id.')
        end

        fail_job!("Virima API error [#{error_code}]: #{error_text}")
      end

      fail_job!("HTTP error: #{response.status} '#{response.body}'") unless response.status == 200
      body.with_indifferent_access
    end

    helper :transform do |devices|
      camel_to_snake(devices).map do |device|
        device.merge(
          created_on: helpers.to_datetime(device[:created_on]),
          last_modified_on: helpers.to_datetime(device[:last_modified_on]),
          last_seen: helpers.to_datetime(device[:last_seen])
        )
      end
    end

    helper :to_datetime do |timestamp_ms|
      Time.at(timestamp_ms.to_i / 1000.0).utc.to_datetime if timestamp_ms.present?
    end
  end
end
