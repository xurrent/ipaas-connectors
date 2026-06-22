class MsEntraIntuneConnector < IPaaS::Connector::Definition
  DEVICE_ODATA_TYPE = '#microsoft.graph.device'.freeze

  connector '01983ca8-546f-7610-93c9-c6cc164300fc' do
    name 'Microsoft Entra and Intune Connector'
    avatar '/assets/icons/microsoft-intune.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Connects to [Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/) and [Microsoft Intune](https://learn.microsoft.com/en-us/mem/intune/) via the [Microsoft Graph API](https://learn.microsoft.com/en-us/graph/) to read groups, group members, and managed devices into Xurrent.

      ## Prerequisites
      - A Microsoft Entra ID (formerly Azure AD) tenant.
      - An app registration in Microsoft Entra. Obtain:
        - **Tenant ID**: GUID visible in **Microsoft Entra → Overview → Tenant ID**.
        - **Client ID**: visible on the app registration's **Overview** page.
        - **Client Secret**: created under the app registration's **Certificates & secrets**. Copy the value at creation time; it is not shown again.
      - API permissions granted on the app registration (type: Application):
        - `Device.Read.All` (Microsoft Graph API) With API Permission type : Application.
        - `GroupMember.Read.All`: used by the group lookup and group members actions.
        - `DeviceManagementManagedDevices.Read.All`: used by the Intune managed devices action.

      ## Authentication
      The connector uses the OAuth 2.0 client credentials flow against `https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token` and requests the `https://graph.microsoft.com/.default` scope. The Tenant ID, Client ID, and Client Secret obtained in **Prerequisites** are passed as:
      - `tenant_id`: substituted into the OAuth2 token endpoint URL.
      - `client_id` and `client_secret`: sent in the token request body as form-encoded credentials.

      ## Triggers
      None. This connector is outbound only.

      ## Actions

      ### Entra group ID from name
      Retrieves Microsoft Entra group IDs for a list of display names in a single request via Microsoft Graph's [group list API](https://learn.microsoft.com/en-us/graph/api/group-list).

      **Use case**: convert human-readable group names to their IDs before calling other actions (e.g. **Retrieve Entra group members**). Also useful to validate that a group exists in the tenant.

      **Permissions required**: `GroupMember.Read.All`

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |-----------|------|----------|---------|-------------|
      | group_names | String[] | Yes | - | Up to 10 Entra group display names to look up |

      #### Example Input

      ```json
      {
        "group_names": ["IT Administrators", "Sales Team", "Marketing Department"]
      }
      ```

      #### Output

      | Field Name | Type | Description |
      |---|---|---|
      | `results` | Object[] | One object per matched group. See **Result object fields** below. |

      ##### Result object fields

      | Field Name | Type | Description |
      |---|---|---|
      | `display_name` | String | Group display name as stored in Entra |
      | `group_id` | String | Entra group object ID (GUID) |

      #### Example Output

      ```json
      {
        "results": [
          {
            "display_name": "IT Administrators",
            "group_id": "12345678-1234-1234-1234-123456789012"
          }
        ]
      }
      ```

      #### Error Handling
      The job fails without retry on 400 / 401 / 403 responses (invalid input or credential / permission issue). On 429 (rate limited) or 503 (service unavailable), the connector waits for the time in `Retry-After` and retries the request.

      #### Operational notes
      - Call at the start of runbooks that operate on groups by name. Pass the returned IDs to **Retrieve Entra group members** or other group actions.
      - Group display names are case-sensitive and must match the value stored in Entra (e.g. `it administrators` will not match a group named `IT Administrators`).
      - The connector deduplicates `group_names` before calling Microsoft Graph, so input length minus distinct-output length is the count of misses.
      - Groups not found in Entra are omitted from the results.

      ### Retrieve Entra group members
      Retrieves all members of a Microsoft Entra ID group with pagination support via Microsoft Graph's [group members API](https://learn.microsoft.com/en-us/graph/api/group-list-members). Members may be users, devices, or other directory objects.

      **Use case**: audit group memberships, synchronize group data with other systems, or process group members in workflows that need user or device information. Pair with **Entra group ID from name** to resolve the `group_id` from a friendly name first.

      **Permissions required**: `GroupMember.Read.All`

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |-----------|------|----------|---------|-------------|
      | group_id | String | Yes | - | Entra group ID (obtained from the **Entra group ID from name** action) |
      | page_size | Integer | No | 100 | Number of members per page (1-999) |

      #### Example Input

      ```json
      {
        "group_id": "12345678-1234-1234-1234-123456789012",
        "page_size": 50
      }
      ```

      #### Output

      | Field Name | Type | Description |
      |---|---|---|
      | `odata_count` | Integer | Total members in the group. Microsoft Graph only populates this when the request includes `$count=true` and `ConsistencyLevel: eventual`; expect `null` otherwise. |
      | `has_next_page` | Boolean | `true` while more pages remain. Re-invoke the action until `false`. |
      | `members` | Object[] | One object per member. See **Member object fields** below. |

      ##### Member object fields

      | Field Name | Type | Description |
      |---|---|---|
      | `member_id` | String | Entra object ID of the member (user, device, etc.) |
      | `device_id` | String | Entra device ID (the AAD-side `deviceId`). Populated only when the member is a device. Distinct from the Intune managed-device ID returned by **Managed devices from Intune**. |
      | `odata_type` | String | Microsoft Graph type of the member (e.g. `#microsoft.graph.user`, `#microsoft.graph.device`) |

      #### Example Output

      ```json
      {
        "members": [
          {
            "member_id": "87654321-4321-4321-4321-210987654321",
            "device_id": null,
            "odata_type": "#microsoft.graph.user"
          },
          {
            "member_id": "98765432-5432-5432-5432-321098765432",
            "device_id": "device123",
            "odata_type": "#microsoft.graph.device"
          }
        ]
      }
      ```

      #### Error Handling
      The job fails without retry on 400 / 401 / 403 responses (invalid input or credential / permission issue), or when a member's required fields are missing. On 429 (rate limited) or 503 (service unavailable), the connector waits for the time in `Retry-After` and retries the request.

      #### Limitations
      - Microsoft Graph v1.0 does not return service principals as members ([known issue](https://learn.microsoft.com/en-us/graph/known-issues#get-groupsidmembers-doesnt-return-service-principals-in-v10)). If your runbook depends on service principal membership, follow the workaround in the linked doc.

      #### Operational notes
      - Pair with **Entra group ID from name** to resolve `group_id` from a friendly group name.
      - Paginate to completion: call until `has_next_page` is `false`.
      - Branch on `odata_type` to detect member kind, not on `device_id` presence (`#microsoft.graph.user` vs. `#microsoft.graph.device`).
      - For large groups, raise `page_size` toward the max (999) to reduce round-trips.

      ### Managed devices from Intune
      Retrieves devices managed through Microsoft Intune with pagination support via Microsoft Graph's [managed devices API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-list). Returns device identity, hardware, operating system, user association, compliance, and enrollment details.

      **Use case**: populate or refresh the list of Intune-managed devices in Xurrent's CMDB for inventory, compliance monitoring, user-device mapping, or security audits. For incremental updates, set **Last sync** to fetch only devices whose `lastSyncDateTime` is at or after the given time.

      **Permissions required**: `DeviceManagementManagedDevices.Read.All`

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |-----------|------|----------|---------|-------------|
      | last_sync | DateTime | No | - | Only fetch devices whose `lastSyncDateTime` is at or after this time. Leave blank to fetch all devices |
      | page_size | Integer | No | 100 | Number of devices per page (1-999) |

      #### Example Input

      ```json
      {
        "last_sync": "2024-01-01T00:00:00Z",
        "page_size": 50
      }
      ```

      #### Output

      | Field Name | Type | Description |
      |---|---|---|
      | `odata_count` | Integer | Total devices matching the query. Microsoft Graph only populates this when the request includes `$count=true`; expect `null` otherwise. |
      | `has_next_page` | Boolean | `true` while more pages remain. Re-invoke the action until `false`. |
      | `devices` | Object[] | One object per device. See **Device object fields** below. |

      ##### Device object fields

      | Field Name | Type | Description |
      |---|---|---|
      | `device_id` | String | Intune device ID |
      | `manufacturer` | String | Hardware manufacturer |
      | `model` | String | Hardware model |
      | `device_name` | String | Device display name |
      | `serial_number` | String | Device serial number |
      | `last_sync_date_time` | DateTime | Last time the device checked in with Intune |
      | `operating_system` | String | OS family (e.g. `Windows`, `iOS`, `macOS`) |
      | `os_version` | String | OS version string |
      | `user_id` | String | Entra object ID of the primary user |
      | `email_address` | String | Primary user's email (stored as secret) |
      | `physical_memory_in_bytes` | Integer | Installed RAM in bytes |
      | `azure_ad_registered` | Boolean | Whether the device is registered with Entra |
      | `azure_ad_device_id` | String | Entra device ID |
      | `jail_broken` | String | Jailbreak/root status. Free-form string (typically `Unknown`, `True`, `False`, `Pending`, or empty) |
      | `enrolled_date_time` | DateTime | When the device was enrolled in Intune |
      | `device_enrollment_type` | String | Enrollment type. See [deviceEnrollmentType enum](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-deviceenrollmenttype) for all 13 values |
      | `managed_device_owner_type` | String | One of: `unknown`, `company`, `personal` |
      | `is_encrypted` | Boolean | Whether the device is encrypted |
      | `compliance_state` | String | One of: `unknown`, `compliant`, `noncompliant`, `conflict`, `error`, `inGracePeriod`, `configManager` |
      | `user_principal_name` | String | Primary user's UPN (stored as secret) |
      | `phone_number` | String | Device phone number |
      | `wi_fi_mac_address` | String | Wi-Fi MAC address |
      | `ethernet_mac_address` | String | Ethernet MAC address |
      | `total_storage_space_in_bytes` | Integer | Total storage in bytes |
      | `free_storage_space_in_bytes` | Integer | Free storage in bytes |

      #### Example Output

      ```json
      {
        "has_next_page": true,
        "devices": [
          {
            "device_id": "12345678-1234-1234-1234-123456789012",
            "manufacturer": "Microsoft",
            "model": "Surface Pro 8",
            "device_name": "SURFACE-JOHN-01",
            "serial_number": "X123456789",
            "last_sync_date_time": "2024-01-15T10:30:00Z",
            "operating_system": "Windows",
            "os_version": "10.0.19045.3803",
            "user_id": "98765432-9876-9876-9876-987654321098",
            "email_address": "[REDACTED]",
            "physical_memory_in_bytes": 17179869184,
            "azure_ad_registered": true,
            "azure_ad_device_id": "87654321-8765-8765-8765-876543210987",
            "jail_broken": "Unknown",
            "enrolled_date_time": "2023-01-01T00:00:00Z",
            "device_enrollment_type": "windowsAzureADJoin",
            "managed_device_owner_type": "company",
            "is_encrypted": true,
            "compliance_state": "compliant",
            "user_principal_name": "[REDACTED]",
            "phone_number": "+********4703",
            "wi_fi_mac_address": "00:1F:5A:9D:44:21",
            "ethernet_mac_address": "A4:9C:3F:12:6B:8E",
            "total_storage_space_in_bytes": 256000000000,
            "free_storage_space_in_bytes": 68021125120
          }
        ]
      }
      ```

      #### Error Handling
      The job fails without retry on 400 / 401 / 403 responses (invalid input or credential / permission issue). On 429 (rate limited) or 503 (service unavailable), the connector waits for the time in `Retry-After` and retries the request.

      #### Operational notes
      - **Incremental syncs**: Set `last_sync` to the start time (UTC) of your previous run. Storing the max `last_sync_date_time` observed in this run can miss devices whose timestamp advances between page fetches.
      - **Filter downstream**: Branch on `compliance_state` for security audits, or on `managed_device_owner_type` for BYOD vs. corporate fleets.
      - **Paginate to completion**: call until `has_next_page` is `false`.
      - **Treat user fields as PII**: `email_address` and `user_principal_name` are secret strings. Don't log them in plain text.

      ## Rate Limiting
      Microsoft Graph throttles requests per tenant and per app and returns `429 Too Many Requests` with a `Retry-After` header when the threshold is exceeded ([reference](https://learn.microsoft.com/en-us/graph/throttling)). The connector retries on 429 and 503 responses.

      | HTTP status | Connector behavior |
      |---|---|
      | 429 Too Many Requests | Wait for the value of the `Retry-After` header (seconds or HTTP date), then retry. If the header is absent, the connector applies a default backoff. |
      | 503 Service Unavailable | Retry with backoff. |
      | 401 / 403 | Fail without retry. Credential or API-permission issue. |
      | 400 | Fail without retry. Invalid input. |

      Notes:
      - Microsoft's [throttling guidance](https://learn.microsoft.com/en-us/graph/throttling#best-practices-to-handle-throttling) recommends exponential backoff when `Retry-After` is absent.
      - 503 is treated as a transient error; it is not part of Microsoft Graph's [documented throttling contract](https://learn.microsoft.com/en-us/graph/throttling#what-happens-when-throttling-occurs).

      ## Best Practices
      - **Resolve IDs at runbook start**: Call **Entra group ID from name** to convert friendly group names into IDs. Don't hard-code GUIDs that may change.
      - **Incremental device syncs**: Use `last_sync` on **Managed devices from Intune** with the timestamp of your last successful sync. Store the max `last_sync_date_time` to use next time.
      - **Paginate to completion**: **Retrieve Entra group members** and **Managed devices from Intune** are iterator actions. Call until `has_next_page` is `false`.
      - **Scope permissions minimally**: Grant only `GroupMember.Read.All` and `DeviceManagementManagedDevices.Read.All` on the app registration. Don't grant broader scopes.
      - **Protect PII**: Device records include user email and UPN as secret strings. Don't log them in plain text.

      ## Common Use Cases
      - **CMDB sync**: **Managed devices from Intune** → upsert into Xurrent's CMDB keyed on `device_id`. Use `last_sync` for incremental runs.
      - **Security compliance**: **Managed devices from Intune** → branch on `compliance_state` → route non-compliant devices into remediation workflows.
      - **Group-based access workflows**: **Entra group ID from name** → **Retrieve Entra group members** → provision or revoke Xurrent access based on membership changes.
      - **BYOD vs. corporate inventory**: **Managed devices from Intune** → segment by `managed_device_owner_type` for separate reporting pipelines.
      - **Lifecycle management**: **Managed devices from Intune** → filter by `enrolled_date_time` and `device_enrollment_type` to identify devices due for refresh or compliance review.

      ## References

      ### API Reference
      - [Microsoft Graph REST API (v1.0)](https://learn.microsoft.com/en-us/graph/api/overview)
      - [List groups (Microsoft Graph API)](https://learn.microsoft.com/en-us/graph/api/group-list)
      - [List group members (Microsoft Graph API)](https://learn.microsoft.com/en-us/graph/api/group-list-members)
      - [List managedDevices (Microsoft Graph Intune API)](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-list)
      - [managedDevice resource type](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-manageddevice)

      ### Concepts
      - [Advanced query capabilities on directory objects](https://learn.microsoft.com/en-us/graph/aad-advanced-queries)
      - [Microsoft Graph throttling](https://learn.microsoft.com/en-us/graph/throttling)
      - [OAuth 2.0 client credentials flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow)
      - [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference)

      ### Setup
      - [Register an application with Microsoft Entra](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)
    END_OF_DESCRIPTION

    outbound_connection do
      config_schema do
        field :credentials, 'Credentials', :nested,
              required: true do
          field :tenant_id, 'Tenant ID', :string,
                required: true
          field :client_id, 'Client ID', :string,
                required: true
          field :client_secret, 'Client secret', :secret_string,
                required: true
        end

        field :environment, 'Environment', :nested,
              visibility: 'optional' do
          field :oauth2_endpoint, 'OAuth2 endpoint', :uri,
                default: 'https://login.microsoftonline.com'
          field :graph_endpoint, 'Graph API endpoint', :uri,
                default: 'https://graph.microsoft.com/v1.0'
        end
      end

      authenticate do |request|
        credentials_config = config[:credentials]
        body = oauth2_client_credentials_body(credentials_config[:client_id],
                                              decrypt_secret_string(credentials_config[:client_secret]))
        body[:scope] = 'https://graph.microsoft.com/.default'
        request.headers['Authorization'] = oauth2_authorization_header(helpers.oauth_endpoint, body)
      end
    end

    action '01983cb0-b8c0-7d91-a381-79e30c4d572e' do
      name 'Entra group ID from name'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Retrieves Microsoft Entra group IDs for a list of display names in a single request via Microsoft Graph's [group list API](https://learn.microsoft.com/en-us/graph/api/group-list).

        **Use case**: convert human-readable group names to their IDs before calling other actions (e.g. **Retrieve Entra group members**). Also useful to validate that a group exists in the tenant.

        **Permissions required**: `GroupMember.Read.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | group_names | String[] | Yes | - | Up to 10 Entra group display names to look up |

        ### Example Input

        ```json
        {
          "group_names": ["IT Administrators", "Sales Team", "Marketing Department"]
        }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `results` | Object[] | One object per matched group. See **Result object fields** below. |

        #### Result object fields

        | Field Name | Type | Description |
        |---|---|---|
        | `display_name` | String | Group display name as stored in Entra |
        | `group_id` | String | Entra group object ID (GUID) |

        ### Example Output

        ```json
        {
          "results": [
            {
              "display_name": "IT Administrators",
              "group_id": "12345678-1234-1234-1234-123456789012"
            }
          ]
        }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 responses (invalid input or credential / permission issue). On 429 (rate limited) or 503 (service unavailable), the connector waits for the time in `Retry-After` and retries the request.

        ### Operational notes
        - Call at the start of runbooks that operate on groups by name. Pass the returned IDs to **Retrieve Entra group members** or other group actions.
        - Group display names are case-sensitive and must match the value stored in Entra (e.g. `it administrators` will not match a group named `IT Administrators`).
        - The connector deduplicates `group_names` before calling Microsoft Graph, so input length minus distinct-output length is the count of misses.
        - Groups not found in Entra are omitted from the results.
      END_OF_DESCRIPTION

      input_schema do
        field :group_names, 'Group display names', :string,
              array: true,
              max_length: 10,
              required: true
      end

      output_schema do
        field :results, 'Results', :nested,
              array: true do
          field :display_name, 'Display name', :string, required: true
          field :group_id, 'Group ID', :string, required: true
        end
      end

      run do
        url = "#{helpers.graph_endpoint}/groups"
        names = (input[:group_names] || [])
                .uniq
                .select(&:present?)

        results = []
        if names.present?
          names_expr = names.map { |name| "'#{name}'" }
                            .join(',')
          graph_result = helpers.graph_call(url,
                                            {
                                              '$filter': "displayName in (#{names_expr})",
                                              '$select': 'id,displayName',
                                            })

          results = graph_result[:value].map do |v|
            display_name = v['displayName']
            group_id = v['id']
            unless display_name.present? && group_id.present?
              fail_job!("Not all values have displayName and id: #{graph_result[:value].to_json}")
            end

            { display_name: display_name, group_id: group_id }
          end
        end

        [{ output: { results: results } }]
      end
    end

    action '01983cb4-b1b5-75fa-8320-b9350012a886' do
      name 'Retrieve Entra group members'
      avatar '/assets/icons/microsoft-entra.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Retrieves all members of a Microsoft Entra ID group with pagination support via Microsoft Graph's [group members API](https://learn.microsoft.com/en-us/graph/api/group-list-members). Members may be users, devices, or other directory objects.

        **Use case**: audit group memberships, synchronize group data with other systems, or process group members in workflows that need user or device information. Pair with **Entra group ID from name** to resolve the `group_id` from a friendly name first.

        **Permissions required**: `GroupMember.Read.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | group_id | String | Yes | - | Entra group ID (obtained from the **Entra group ID from name** action) |
        | page_size | Integer | No | 100 | Number of members per page (1-999) |

        ### Example Input

        ```json
        {
          "group_id": "12345678-1234-1234-1234-123456789012",
          "page_size": 50
        }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `odata_count` | Integer | Total members in the group. Microsoft Graph only populates this when the request includes `$count=true` and `ConsistencyLevel: eventual`; expect `null` otherwise. |
        | `has_next_page` | Boolean | `true` while more pages remain. Re-invoke the action until `false`. |
        | `members` | Object[] | One object per member. See **Member object fields** below. |

        #### Member object fields

        | Field Name | Type | Description |
        |---|---|---|
        | `member_id` | String | Entra object ID of the member (user, device, etc.) |
        | `device_id` | String | Entra device ID (the AAD-side `deviceId`). Populated only when the member is a device. Distinct from the Intune managed-device ID returned by **Managed devices from Intune**. |
        | `odata_type` | String | Microsoft Graph type of the member (e.g. `#microsoft.graph.user`, `#microsoft.graph.device`) |

        ### Example Output

        ```json
        {
          "members": [
            {
              "member_id": "87654321-4321-4321-4321-210987654321",
              "device_id": null,
              "odata_type": "#microsoft.graph.user"
            },
            {
              "member_id": "98765432-5432-5432-5432-321098765432",
              "device_id": "device123",
              "odata_type": "#microsoft.graph.device"
            }
          ]
        }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 responses (invalid input or credential / permission issue), or when a member's required fields are missing. On 429 (rate limited) or 503 (service unavailable), the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Microsoft Graph v1.0 does not return service principals as members ([known issue](https://learn.microsoft.com/en-us/graph/known-issues#get-groupsidmembers-doesnt-return-service-principals-in-v10)). If your runbook depends on service principal membership, follow the workaround in the linked doc.

        ### Operational notes
        - Pair with **Entra group ID from name** to resolve `group_id` from a friendly group name.
        - Paginate to completion: call until `has_next_page` is `false`.
        - Branch on `odata_type` to detect member kind, not on `device_id` presence (`#microsoft.graph.user` vs. `#microsoft.graph.device`).
        - For large groups, raise `page_size` toward the max (999) to reduce round-trips.
      END_OF_DESCRIPTION

      input_schema do
        field :group_id, 'Group ID', :string, required: true
        field :page_size, 'Page size', :integer,
              min: 1, max: 999,
              visibility: 'optional',
              default: 100
      end

      output_schema 'page' do
        field :odata_count, 'OData count', :integer
        field :has_next_page, 'Has next page', :boolean, required: true

        field :members, 'Members', :nested,
              array: true do
          field :member_id, 'Member ID', :string, required: true
          field :device_id, 'Device ID', :string
          field :odata_type, 'OData type', :string,
                visibility: 'optional'
        end
      end

      iteration_state_schema do
        field :odata_nextLink, 'OData next link', :string, required: true
      end

      run do
        url = "#{helpers.graph_endpoint}/groups/#{input[:group_id]}/members"
        parameters = { '$top': input[:page_size]&.to_s || '100', '$select': 'id,deviceId' }
        graph_result = helpers.graph_fetch_page(url, parameters)

        members = graph_result[:value].map do |v|
          member_id = v['id']
          device_id = v['deviceId']

          fail_job!("Not all values have id: #{graph_result[:value].to_json}") unless member_id.present?
          if v['@odata.type'] == DEVICE_ODATA_TYPE && !device_id.present?
            fail_job!("Not all devices have deviceId: #{graph_result[:value].to_json}")
          end

          { member_id: member_id, device_id: device_id, odata_type: v['@odata.type'] }
        end

        helpers.build_graph_page(graph_result, :members, members)
      end
    end

    action '01983cb5-865f-7219-9799-67d526948e7c' do
      name 'Managed devices from Intune'
      avatar '/assets/icons/microsoft-intune.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Retrieves devices managed through Microsoft Intune with pagination support via Microsoft Graph's [managed devices API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-list). Returns device identity, hardware, operating system, user association, compliance, and enrollment details.

        **Use case**: populate or refresh the list of Intune-managed devices in Xurrent's CMDB for inventory, compliance monitoring, user-device mapping, or security audits. For incremental updates, set **Last sync** to fetch only devices whose `lastSyncDateTime` is at or after the given time.

        **Permissions required**: `DeviceManagementManagedDevices.Read.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | last_sync | DateTime | No | - | Only fetch devices whose `lastSyncDateTime` is at or after this time. Leave blank to fetch all devices |
        | page_size | Integer | No | 100 | Number of devices per page (1-999) |

        ### Example Input

        ```json
        {
          "last_sync": "2024-01-01T00:00:00Z",
          "page_size": 50
        }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `odata_count` | Integer | Total devices matching the query. Microsoft Graph only populates this when the request includes `$count=true`; expect `null` otherwise. |
        | `has_next_page` | Boolean | `true` while more pages remain. Re-invoke the action until `false`. |
        | `devices` | Object[] | One object per device. See **Device object fields** below. |

        #### Device object fields

        | Field Name | Type | Description |
        |---|---|---|
        | `device_id` | String | Intune device ID |
        | `manufacturer` | String | Hardware manufacturer |
        | `model` | String | Hardware model |
        | `device_name` | String | Device display name |
        | `serial_number` | String | Device serial number |
        | `last_sync_date_time` | DateTime | Last time the device checked in with Intune |
        | `operating_system` | String | OS family (e.g. `Windows`, `iOS`, `macOS`) |
        | `os_version` | String | OS version string |
        | `user_id` | String | Entra object ID of the primary user |
        | `email_address` | String | Primary user's email (stored as secret) |
        | `physical_memory_in_bytes` | Integer | Installed RAM in bytes |
        | `azure_ad_registered` | Boolean | Whether the device is registered with Entra |
        | `azure_ad_device_id` | String | Entra device ID |
        | `jail_broken` | String | Jailbreak/root status. Free-form string (typically `Unknown`, `True`, `False`, `Pending`, or empty) |
        | `enrolled_date_time` | DateTime | When the device was enrolled in Intune |
        | `device_enrollment_type` | String | Enrollment type. See [deviceEnrollmentType enum](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-deviceenrollmenttype) for all 13 values |
        | `managed_device_owner_type` | String | One of: `unknown`, `company`, `personal` |
        | `is_encrypted` | Boolean | Whether the device is encrypted |
        | `compliance_state` | String | One of: `unknown`, `compliant`, `noncompliant`, `conflict`, `error`, `inGracePeriod`, `configManager` |
        | `user_principal_name` | String | Primary user's UPN (stored as secret) |
        | `phone_number` | String | Device phone number |
        | `wi_fi_mac_address` | String | Wi-Fi MAC address |
        | `ethernet_mac_address` | String | Ethernet MAC address |
        | `total_storage_space_in_bytes` | Integer | Total storage in bytes |
        | `free_storage_space_in_bytes` | Integer | Free storage in bytes |

        ### Example Output

        ```json
        {
          "has_next_page": true,
          "devices": [
            {
              "device_id": "12345678-1234-1234-1234-123456789012",
              "manufacturer": "Microsoft",
              "model": "Surface Pro 8",
              "device_name": "SURFACE-JOHN-01",
              "serial_number": "X123456789",
              "last_sync_date_time": "2024-01-15T10:30:00Z",
              "operating_system": "Windows",
              "os_version": "10.0.19045.3803",
              "user_id": "98765432-9876-9876-9876-987654321098",
              "email_address": "[REDACTED]",
              "physical_memory_in_bytes": 17179869184,
              "azure_ad_registered": true,
              "azure_ad_device_id": "87654321-8765-8765-8765-876543210987",
              "jail_broken": "Unknown",
              "enrolled_date_time": "2023-01-01T00:00:00Z",
              "device_enrollment_type": "windowsAzureADJoin",
              "managed_device_owner_type": "company",
              "is_encrypted": true,
              "compliance_state": "compliant",
              "user_principal_name": "[REDACTED]",
              "phone_number": "+********4703",
              "wi_fi_mac_address": "00:1F:5A:9D:44:21",
              "ethernet_mac_address": "A4:9C:3F:12:6B:8E",
              "total_storage_space_in_bytes": 256000000000,
              "free_storage_space_in_bytes": 68021125120
            }
          ]
        }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 responses (invalid input or credential / permission issue). On 429 (rate limited) or 503 (service unavailable), the connector waits for the time in `Retry-After` and retries the request.

        ### Operational notes
        - **Incremental syncs**: Set `last_sync` to the start time (UTC) of your previous run. Storing the max `last_sync_date_time` observed in this run can miss devices whose timestamp advances between page fetches.
        - **Filter downstream**: Branch on `compliance_state` for security audits, or on `managed_device_owner_type` for BYOD vs. corporate fleets.
        - **Paginate to completion**: call until `has_next_page` is `false`.
        - **Treat user fields as PII**: `email_address` and `user_principal_name` are secret strings. Don't log them in plain text.
      END_OF_DESCRIPTION

      input_schema do
        field :last_sync, 'Last sync', :date_time
        field :page_size, 'Page size', :integer,
              min: 1, max: 999,
              visibility: 'optional',
              default: 100
      end

      output_schema 'page' do
        field :odata_count, 'OData count', :integer
        field :has_next_page, 'Has next page', :boolean, required: true

        field :devices, 'Devices', :nested,
              array: true do
          field :device_id, 'Device ID', :string, required: true
          field :manufacturer, 'Manufacturer', :string
          field :model, 'Model', :string
          field :device_name, 'Device name', :string
          field :serial_number, 'Serial number', :string
          field :last_sync_date_time, 'Last sync date time', :date_time
          field :operating_system, 'Operating system', :string
          field :os_version, 'Operating system version', :string
          field :user_id, 'User ID', :string
          field :email_address, 'Email address', :secret_string
          field :physical_memory_in_bytes, 'Physical memory in bytes', :integer
          field :azure_ad_registered, 'Azure AD registered', :boolean
          field :azure_ad_device_id, 'Azure AD device ID', :string
          field :jail_broken, 'Jail broken', :string
          field :enrolled_date_time, 'Enrolled date time', :date_time
          field :device_enrollment_type, 'Device enrollment type', :string
          field :managed_device_owner_type, 'Managed device owner type', :string
          field :is_encrypted, 'Is encrypted', :boolean
          field :compliance_state, 'Compliance state', :string
          field :user_principal_name, 'User Principal Name', :secret_string
          field :phone_number, 'Phone Number', :string
          field :wi_fi_mac_address, 'WiFi Mac Address', :string
          field :ethernet_mac_address, 'Ethernet Mac Address', :string
          field :total_storage_space_in_bytes, 'Total Storage Space In Bytes', :integer
          field :free_storage_space_in_bytes, 'Free Storage Space In Bytes', :integer
        end
      end

      iteration_state_schema do
        field :odata_nextLink, 'OData next link', :string, required: true
      end

      run do
        device_schema_fields = action.output_schema('page').field(:devices).fields

        all_fields = %w[
          userId operatingSystem osVersion manufacturer model deviceName serialNumber azureADDeviceId
          lastSyncDateTime emailAddress physicalMemoryInBytes azureADRegistered jailBroken
          enrolledDateTime deviceEnrollmentType managedDeviceOwnerType isEncrypted complianceState
          userPrincipalName phoneNumber wiFiMacAddress ethernetMacAddress totalStorageSpaceInBytes
          freeStorageSpaceInBytes
        ]

        url = "#{helpers.graph_endpoint}/deviceManagement/managedDevices"
        parameters = {
          '$top': input[:page_size]&.to_s || '100',
          '$select': "id,#{all_fields.join(',')}",
        }
        if input[:last_sync].present?
          last_sync = input[:last_sync].to_datetime.utc.iso8601(3)
          parameters[:$filter] = "lastSyncDateTime ge #{last_sync}"
        end

        graph_result = helpers.graph_fetch_page(url, parameters)

        devices = graph_result[:value].map do |v|
          helpers.map_device_fields(v, all_fields, device_schema_fields)
        end

        helpers.build_graph_page(graph_result, :devices, devices)
      end
    end

    helper :graph_fetch_page do |initial_url, parameters|
      url = iteration_state_value(:odata_nextLink)
      params = nil
      unless url.present?
        url = initial_url
        params = parameters
      end
      helpers.graph_call(url, params)
    end

    helper :build_graph_page do |graph_result, items_key, items|
      next_link = graph_result[:odata_nextLink]
      self.iteration_state_value = next_link ? { odata_nextLink: next_link } : nil

      page = {}
      page[:odata_count] = graph_result[:odata_count]
      page[:has_next_page] = iteration_state_value.present?
      page[items_key] = items.presence || []
      [{ output: page, schema_reference: 'page' }]
    end

    helper :map_device_fields do |device_hash, all_fields, device_schema_fields|
      device_id = device_hash['id']
      fail_job!("Not all values have id: #{device_hash.to_json}") unless device_id.present?

      { device_id: device_id }.tap do |h|
        all_fields.each do |field|
          field_schema = device_schema_fields.detect { |fs| fs.id.to_s.underscore == field.underscore }
          value = field_schema.type == :secret_string ? device_hash[field].to_s : device_hash[field].presence
          h[field.underscore.to_sym] = value
        end
      end
    end

    helper :graph_call do |url, parameters|
      response = http_get(url, parameters)
      backoff_if_needed(response, api_name: 'Microsoft')

      parsed_body = helpers.parse_graph_response(response)
      {}.tap do |output|
        output[:value] = helpers.extract_value_from_graph_response(parsed_body, response)
        output[:odata_context] = parsed_body['@odata.context'].presence
        output[:odata_nextLink] = parsed_body['@odata.nextLink'].presence
        output[:odata_count] = parsed_body['@odata.count']&.to_i
      end
    end

    helper :parse_graph_response do |response|
      fail_job!("HTTP error from Microsoft Graph API: #{response.status} '#{response.body}'") if response.status != 200

      body = parse_json_response(
        response.body,
        error_message: "Microsoft Graph API response was not JSON: '#{response.body}'"
      )
      fail_job!("Error from Microsoft Graph API: #{body['error'].to_json}") if body['error'].present?

      body
    end

    helper :extract_value_from_graph_response do |parsed_body, response|
      fail_job!("No value in Microsoft Graph API response: '#{response.body}'") unless parsed_body.key?('value')

      parsed_body['value']
    end

    helper :oauth_endpoint do
      tenant_id = outbound_connection.config[:credentials][:tenant_id]
      endpoint_base = helpers.env_config_value(:oauth2_endpoint, 'https://login.microsoftonline.com')
      "#{endpoint_base}/#{tenant_id}/oauth2/v2.0/token"
    end

    helper :graph_endpoint do
      helpers.env_config_value(:graph_endpoint, 'https://graph.microsoft.com/v1.0')
    end

    helper :env_config_value do |key, default|
      env_config = outbound_connection.config[:environment] || {}
      env_config[key].presence || default
    end
  end
end
