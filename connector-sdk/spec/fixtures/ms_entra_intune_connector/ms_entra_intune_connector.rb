class MsEntraIntuneConnector < IPaaS::Connector::Definition
  DEVICE_ODATA_TYPE = '#microsoft.graph.device'.freeze
  DOT_SEGMENTS      = %w[. ..].freeze

  JSON_HEADERS        = { 'Content-Type' => 'application/json' }.freeze
  GUID_PATTERN        = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  EMPTY_GUID          = '00000000-0000-0000-0000-000000000000'.freeze
  OK_STATUS           = 200
  NO_CONTENT_STATUS   = 204
  FORBIDDEN_STATUS    = 403
  NOT_FOUND_STATUS    = 404
  TRAILING_SLASHES    = %r{/+\z}
  V1_SUFFIX           = %r{/v1\.0\z}i
  BETA_SUFFIX         = %r{/beta\z}i
  BETA_PATH           = '/beta'.freeze
  BYTE_VALUES         = 256
  CHARACTER_FORMAT    = '%c'.freeze
  FIRST_SURROGATE     = 0xD800
  LAST_SURROGATE      = 0xDFFF
  OS_VOLUME_TYPE      = 'operatingSystemVolume'.freeze
  VOLUME_TYPE_NAMES   = {
    '1' => 'operatingSystemVolume', '2' => 'fixedDataVolume', '3' => 'removableDataVolume',
  }.freeze
  BITLOCKER_KEYS_PATH = '/informationProtection/bitlocker/recoveryKeys'.freeze

  BITLOCKER_KEY_PAGE_LIMIT     = 10
  NOT_JSON_MESSAGE             = 'Microsoft Graph returned a response that is not JSON.'.freeze
  INTUNE_DEVICE_NOT_FOUND_HINT = 'Check that the ID is the Intune device ID: the id of the managed device, ' \
                                 'which Managed devices from Intune returns as device_id.'.freeze
  ENTRA_DEVICE_NOT_FOUND_HINT  = 'Check that the ID is the Entra device ID: the azureADDeviceId of the managed ' \
                                 'device, which Managed devices from Intune returns as azure_ad_device_id.'.freeze

  ELEVATION_DECISIONS = %w[deny revoke].freeze
  LOG_COLLECTION_TEMPLATE = {
    '@odata.type' => 'microsoft.graph.deviceLogCollectionRequest',
    'templateType' => 'predefined',
  }.freeze
  LOCAL_CREDENTIAL_SELECT = 'id,deviceName,lastBackupDateTime,refreshDateTime,credentials'.freeze
  BITLOCKER_KEY_SELECT    = 'id,createdDateTime,volumeType,deviceId,key'.freeze

  PRIVILEGED_OPERATIONS_PERMISSION = 'DeviceManagementManagedDevices.PrivilegedOperations.All'.freeze
  MANAGED_DEVICE_WRITE_PERMISSION  = 'DeviceManagementManagedDevices.ReadWrite.All'.freeze
  AUTOPILOT_WRITE_PERMISSION       = 'DeviceManagementServiceConfig.ReadWrite.All'.freeze
  ELEVATION_PERMISSION             = 'DeviceManagementConfiguration.ReadWrite.All'.freeze
  LOCAL_CREDENTIAL_PERMISSION      = 'DeviceLocalCredential.Read.All'.freeze
  BITLOCKER_PERMISSION             = 'BitlockerKey.Read.All'.freeze

  connector '01983ca8-546f-7610-93c9-c6cc164300fc' do
    name 'Microsoft Intune'
    avatar '/assets/icons/microsoft-intune.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Connects to [Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/) and [Microsoft Intune](https://learn.microsoft.com/en-us/mem/intune/) via the [Microsoft Graph API](https://learn.microsoft.com/en-us/graph/) to read groups, group members, and managed devices into Xurrent, and to act on Intune devices: sync, restart, lock, reset the passcode, retire, wipe, Fresh Start, run a Defender scan, rename, change the primary user, collect diagnostics, and delete. It also reads local administrator passwords and BitLocker recovery keys, rotates local administrator passwords, assigns Windows Autopilot devices to users, and approves, denies or revokes Endpoint Privilege Management (EPM) elevation requests. To manage Entra users, licenses and groups, or to start workflows when they change, use the **Microsoft Entra** connector.

      To install or uninstall software on a device, or to grant or remove temporary local administrator rights, add or remove a member of the Entra group that the app or the local administrator policy is assigned to, with the **Add member to Entra group** and **Remove member from Entra group** actions of the **Microsoft Entra** connector.

      Actions whose name ends in **(Beta)** use the Microsoft Graph beta API, which Microsoft can change. **Change primary user (Alpha)** uses a call that Microsoft does not document and can change or remove without notice.

      ## Prerequisites
      - A Microsoft Entra ID (formerly Azure AD) tenant with a Microsoft Intune license.
      - An app registration in Microsoft Entra. Obtain:
        - **Tenant ID**: GUID visible in **Microsoft Entra → Overview → Tenant ID**.
        - **Client ID**: visible on the app registration's **Overview** page.
        - **Client Secret**: created under the app registration's **Certificates & secrets**. Copy the value at creation time; it is not shown again.
      - API permissions granted on the app registration (type: Application), with admin consent. Grant only the ones for the actions you use:
        - `GroupMember.Read.All`: used by **Entra group ID from name** and **Retrieve Entra group members**.
        - `Device.Read.All`: lets **Retrieve Entra group members** read the `device_id` of members that are devices. Without it, Microsoft Graph returns no `deviceId` for a device member, and the action fails the job with `Not all devices have deviceId`.
        - `DeviceManagementManagedDevices.Read.All`: used by **Managed devices from Intune**.
        - `DeviceManagementManagedDevices.PrivilegedOperations.All`: used by **Sync Intune device**, **Restart Intune device**, **Remote lock Intune device**, **Reset Intune device passcode**, **Retire Intune device**, **Wipe Intune device**, **Fresh Start Intune device**, **Run Defender scan on Intune device**, **Rename Intune device (Beta)** and **Rotate Intune local admin password (Beta)**.
        - `DeviceManagementManagedDevices.ReadWrite.All`: used by **Delete Intune device record**, **Collect Intune device diagnostics (Beta)** and **Change primary user (Alpha)**. Microsoft does not document which permission **Change primary user (Alpha)** needs. Its own 403 names this one.
        - `DeviceManagementServiceConfig.ReadWrite.All`: used by **Assign Autopilot device to user**.
        - `DeviceManagementConfiguration.ReadWrite.All`: used by **Approve Intune EPM elevation request (Beta)** and **Deny or revoke Intune EPM elevation (Beta)**.
        - `DeviceLocalCredential.Read.All`: used by **Get Intune device local admin password**.
        - `BitlockerKey.Read.All`: used by **Get BitLocker recovery key**.

      ## Authentication
      The connector uses the OAuth 2.0 client credentials flow against `https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token` and requests the `https://graph.microsoft.com/.default` scope. The Tenant ID, Client ID, and Client Secret obtained in **Prerequisites** are passed as:
      - `tenant_id`: substituted into the OAuth2 token endpoint URL.
      - `client_id` and `client_secret`: sent in the token request body as form-encoded credentials.

      ## Triggers
      None. This connector is outbound only.

      ## Best Practices
      - **Resolve IDs at runbook start**: Call **Entra group ID from name** to convert friendly group names into IDs. Don't hard-code GUIDs that may change.
      - **Incremental device syncs**: Use `last_sync` on **Managed devices from Intune** with the start time (UTC) of your previous successful run.
      - **Paginate to completion**: **Retrieve Entra group members** and **Managed devices from Intune** are iterator actions. Call until `has_next_page` is `false`.
      - **Pass the right device ID**: The device actions take the Intune `device_id` from **Managed devices from Intune**. **Get Intune device local admin password** and **Get BitLocker recovery key** take its `azure_ad_device_id` instead.
      - **Approve destructive actions first**: **Wipe Intune device**, **Retire Intune device**, **Fresh Start Intune device** and **Delete Intune device record** cannot be undone. Put an approval step in front of them.
      - **Save secrets before you retire or delete**: Retiring or deleting a Microsoft Entra joined Windows device suspends BitLocker. Read the BitLocker recovery key and the local administrator password first if you still need them.
      - **Rotate after use**: After a technician used the password from **Get Intune device local admin password**, run **Rotate Intune local admin password (Beta)**.
      - **Scope permissions minimally**: Grant only the permissions that **Prerequisites** lists for the actions you use. Don't grant broader scopes.
      - **Protect PII and secrets**: Device records include user email and UPN as secret strings, and the local administrator password and the BitLocker recovery key are secret strings too. Don't log them in plain text.

      ## Common Use Cases
      - **CMDB sync**: **Managed devices from Intune** → upsert into Xurrent's CMDB keyed on `device_id`. Use `last_sync` for incremental runs.
      - **Security compliance**: **Managed devices from Intune** → branch on `compliance_state` → route non-compliant devices into remediation workflows.
      - **Group-based access workflows**: **Entra group ID from name** → **Retrieve Entra group members** → provision or revoke Xurrent access based on membership changes.
      - **BYOD vs. corporate inventory**: **Managed devices from Intune** → segment by `managed_device_owner_type` for separate reporting pipelines.
      - **Lifecycle management**: **Managed devices from Intune** → filter by `enrolled_date_time` and `device_enrollment_type` to identify devices due for refresh or compliance review.
      - **Lost or stolen device**: **Remote lock Intune device** → approval → **Wipe Intune device**, or **Retire Intune device** for a personal device.
      - **Device offboarding**: **Get BitLocker recovery key** → **Retire Intune device** or **Wipe Intune device** → **Delete Intune device record**.
      - **Device hand-over**: **Fresh Start Intune device** → **Change primary user (Alpha)** → **Rename Intune device (Beta)**.
      - **Helpdesk recovery**: **Managed devices from Intune** → **Get BitLocker recovery key** or **Get Intune device local admin password** with its `azure_ad_device_id` → **Rotate Intune local admin password (Beta)** after the support session.
      - **Security response**: **Run Defender scan on Intune device** → **Collect Intune device diagnostics (Beta)** → record the log collection request on the Xurrent request.
      - **New laptop for a named user**: **Assign Autopilot device to user** from the Xurrent request that ordered the device.
      - **Elevation approvals**: a Xurrent approval → **Approve Intune EPM elevation request (Beta)**, or **Deny or revoke Intune EPM elevation (Beta)** when the approval is rejected.
      - **Policy refresh**: change a group assignment → **Sync Intune device** so that the device gets it at once.

      ## References

      ### API Reference
      - [Microsoft Graph REST API (v1.0)](https://learn.microsoft.com/en-us/graph/api/overview)
      - [Microsoft Graph REST API (beta)](https://learn.microsoft.com/en-us/graph/api/overview?view=graph-rest-beta)
      - [List groups (Microsoft Graph API)](https://learn.microsoft.com/en-us/graph/api/group-list)
      - [List group members (Microsoft Graph API)](https://learn.microsoft.com/en-us/graph/api/group-list-members)
      - [List managedDevices (Microsoft Graph Intune API)](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-list)
      - [managedDevice resource type](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-manageddevice)
      - [windowsAutopilotDeviceIdentity resource type](https://learn.microsoft.com/en-us/graph/api/resources/intune-enrollment-windowsautopilotdeviceidentity)
      - [privilegeManagementElevationRequest resource type (beta)](https://learn.microsoft.com/en-us/graph/api/resources/intune-epmgraphapiservice-privilegemanagementelevationrequest?view=graph-rest-beta)
      - [deviceLocalCredentialInfo resource type](https://learn.microsoft.com/en-us/graph/api/resources/devicelocalcredentialinfo)
      - [bitlockerRecoveryKey resource type](https://learn.microsoft.com/en-us/graph/api/resources/bitlockerrecoverykey)
      - [deviceLogCollectionResponse resource type (beta)](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-devicelogcollectionresponse?view=graph-rest-beta)

      ### Concepts
      - [Intune device actions](https://learn.microsoft.com/en-us/intune/device-management/actions/)
      - [Endpoint Privilege Management](https://learn.microsoft.com/en-us/intune/epm/overview)
      - [Windows LAPS](https://learn.microsoft.com/en-us/windows-server/identity/laps/laps-overview)
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
          names_expr = names.map { |name| "'#{name.to_s.gsub("'", "''")}'" }
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
        url = "#{helpers.graph_endpoint}/groups/#{helpers.graph_segment(input[:group_id], 'Group ID')}/members"
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

    action '01a1c8f9-2061-789c-aa75-8f78357ad804' do
      name 'Sync Intune device'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Asks one Intune managed device to check in with Intune now, through Microsoft Graph's [syncDevice API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-syncdevice). The device then gets its latest policies, apps and actions without waiting for its next scheduled check-in.

        **Use case**: apply a policy or app assignment to a device right after a Xurrent request changed it, or refresh a device before you read its compliance state with **Managed devices from Intune**.

        **Permissions required**: `DeviceManagementManagedDevices.PrivilegedOperations.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_id | String | Yes | - | Intune device ID (GUID): the `device_id` returned by **Managed devices from Intune** |

        ### Example Input

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `device_id` | String | The Intune device ID that was asked to sync |

        ### Example Output

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the Intune device ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. A 404 asks you to check that the ID is the Intune device ID. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Microsoft accepts the request before the device acts on it. The device syncs when it is next online.
      END_OF_DESCRIPTION

      input_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      output_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      run do
        device_id = helpers.device_command(input[:device_id], 'syncDevice', PRIVILEGED_OPERATIONS_PERMISSION)
        [{ output: { device_id: device_id } }]
      end
    end

    action '01a1c8f9-20d6-7f70-b5e4-0e0345ad1486' do
      name 'Restart Intune device'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Restarts one Intune managed device through Microsoft Graph's [rebootNow API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-rebootnow).

        **Use case**: finish an update or a configuration change that needs a restart, or restart a device that a user reported as stuck.

        **Permissions required**: `DeviceManagementManagedDevices.PrivilegedOperations.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_id | String | Yes | - | Intune device ID (GUID): the `device_id` returned by **Managed devices from Intune** |

        ### Example Input

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `device_id` | String | The Intune device ID that was asked to restart |

        ### Example Output

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the Intune device ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. A 404 asks you to check that the ID is the Intune device ID. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The device can restart without a warning to the signed-in user, so work that is not saved can be lost.
        - The restart usually starts within 5 minutes. It waits while the device is offline.
        - Microsoft supports this action on Windows, macOS, supervised iOS/iPadOS, and dedicated or fully managed Android devices, among others.
      END_OF_DESCRIPTION

      input_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      output_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      run do
        device_id = helpers.device_command(input[:device_id], 'rebootNow', PRIVILEGED_OPERATIONS_PERMISSION)
        [{ output: { device_id: device_id } }]
      end
    end

    action '01a1c8f9-2144-786f-8772-56984d886be3' do
      name 'Remote lock Intune device'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Locks the screen of one Intune managed device through Microsoft Graph's [remoteLock API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-remotelock). The user must enter the device passcode to unlock it.

        **Use case**: secure a device that was reported lost or stolen while you decide whether to wipe it with **Wipe Intune device**.

        **Permissions required**: `DeviceManagementManagedDevices.PrivilegedOperations.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_id | String | Yes | - | Intune device ID (GUID): the `device_id` returned by **Managed devices from Intune** |

        ### Example Input

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `device_id` | String | The Intune device ID that was asked to lock |

        ### Example Output

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the Intune device ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. A 404 asks you to check that the ID is the Intune device ID. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Not supported on Windows. Microsoft supports this action on iOS/iPadOS, macOS and corporate-owned Android devices, among others.
        - The lock protects the device only when a passcode or PIN is already set.
      END_OF_DESCRIPTION

      input_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      output_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      run do
        device_id = helpers.device_command(input[:device_id], 'remoteLock', PRIVILEGED_OPERATIONS_PERMISSION)
        [{ output: { device_id: device_id } }]
      end
    end

    action '01a1c8f9-21ba-77aa-99a8-0969b6e471f8' do
      name 'Reset Intune device passcode'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Resets the passcode of one Intune managed Android device, or of its work profile, through Microsoft Graph's [resetPasscode API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-resetpasscode). Intune shows the new passcode in the Microsoft Intune admin center for seven days.

        **Use case**: help a user who forgot the passcode of a company phone or of their work profile.

        **Permissions required**: `DeviceManagementManagedDevices.PrivilegedOperations.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_id | String | Yes | - | Intune device ID (GUID): the `device_id` returned by **Managed devices from Intune** |

        ### Example Input

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `device_id` | String | The Intune device ID whose passcode reset was requested |

        ### Example Output

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the Intune device ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. A 404 asks you to check that the ID is the Intune device ID. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Android Enterprise and Android Open Source Project devices only.
        - The new passcode is not part of the output. Read it on the device page in the Microsoft Intune admin center.
        - The reset fails when no passcode policy is assigned to the device.
      END_OF_DESCRIPTION

      input_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      output_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      run do
        device_id = helpers.device_command(input[:device_id], 'resetPasscode', PRIVILEGED_OPERATIONS_PERMISSION)
        [{ output: { device_id: device_id } }]
      end
    end

    action '01a1c8f9-2226-761e-ad75-9a6f29498827' do
      name 'Retire Intune device'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Removes the company apps, data and settings that Intune put on one managed device, and removes the device from Intune management, through Microsoft Graph's [retire API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-retire). The personal data of the user stays on the device. The device is retired the next time it checks in with Intune.

        **Use case**: offboard a personal (BYOD) device when its owner leaves, without erasing the owner's own data.

        **Permissions required**: `DeviceManagementManagedDevices.PrivilegedOperations.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_id | String | Yes | - | Intune device ID (GUID): the `device_id` returned by **Managed devices from Intune** |

        ### Example Input

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `device_id` | String | The Intune device ID that was asked to retire |

        ### Example Output

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the Intune device ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. A 404 asks you to check that the ID is the Intune device ID. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The action cannot be undone. Put an approval step in front of it. The device must be enrolled again before Intune can manage it.
        - A tenant can submit up to 1,000 Retire actions per day.
        - On a Microsoft Entra joined Windows device protected by BitLocker, retiring suspends BitLocker. Read the BitLocker recovery key and the local administrator password first if you still need them.
      END_OF_DESCRIPTION

      input_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      output_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      run do
        device_id = helpers.device_command(input[:device_id], 'retire', PRIVILEGED_OPERATIONS_PERMISSION)
        [{ output: { device_id: device_id } }]
      end
    end

    action '01a1c8f9-22a2-7b4d-bb27-edc74a5afe29' do
      name 'Wipe Intune device'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Resets one Intune managed device to its factory settings through Microsoft Graph's [wipe API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-wipe). Unless you set one of the keep options, all data on the device is erased.

        **Use case**: erase a company device that was lost or stolen, or prepare a device for a new user.

        **Permissions required**: `DeviceManagementManagedDevices.PrivilegedOperations.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_id | String | Yes | - | Intune device ID (GUID): the `device_id` returned by **Managed devices from Intune** |
        | keep_enrollment_data | Boolean | No | - | Windows: keep the provisioning data of the device through the wipe |
        | keep_user_data | Boolean | No | - | Windows: keep the enrollment state, the user accounts and their data. This is the admin center option **Wipe device, but keep enrollment state and associated user account** |
        | mac_os_unlock_code | Secret String | No | - | macOS: the six-digit recovery PIN that Macs without a T2 security chip need to reinstall macOS. Record it, because it is not shown after the wipe |
        | persist_esim_data_plan | Boolean | No | - | Keep the eSIM cellular data plan on the device |

        Options that are left empty are not sent, so Microsoft uses its own default for them.

        ### Example Input

        ```json
        {
          "device_id": "12345678-1234-1234-1234-123456789012",
          "keep_enrollment_data": false,
          "keep_user_data": false
        }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `device_id` | String | The Intune device ID that was asked to wipe |

        ### Example Output

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the Intune device ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. A 404 asks you to check that the ID is the Intune device ID. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The action cannot be undone. Put an approval step in front of it.
        - A tenant can submit up to 500 Wipe actions per day.
        - Microsoft accepts the request before the device acts on it. The device is wiped when it is next online.
        - This action does not send the macOS obliteration behavior (`obliterationBehavior`), so Macs get Microsoft's default.
      END_OF_DESCRIPTION

      input_schema do
        field :device_id, 'Intune device ID', :string, required: true
        field :keep_enrollment_data, 'Keep enrollment data', :boolean
        field :keep_user_data, 'Keep user data', :boolean
        field :mac_os_unlock_code, 'macOS unlock code', :secret_string, visibility: 'optional'
        field :persist_esim_data_plan, 'Keep eSIM data plan', :boolean, visibility: 'optional'
      end

      output_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      run do
        body = {
          keepEnrollmentData: input[:keep_enrollment_data],
          keepUserData: input[:keep_user_data],
          macOsUnlockCode: decrypt_secret_string(input[:mac_os_unlock_code]).presence,
          persistEsimDataPlan: input[:persist_esim_data_plan],
        }.compact
        device_id = helpers.device_command(input[:device_id], 'wipe', PRIVILEGED_OPERATIONS_PERMISSION, body: body)
        [{ output: { device_id: device_id } }]
      end
    end

    action '01a1c8f9-230f-7920-b44f-ae0546793092' do
      name 'Fresh Start Intune device'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Reinstalls the latest version of Windows on one Intune managed device and removes the apps that the manufacturer installed, through Microsoft Graph's [cleanWindowsDevice API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-cleanwindowsdevice). This is the **Fresh Start** action of the Microsoft Intune admin center.

        **Use case**: remove the preinstalled apps from a new PC, or clean up a Windows device before it goes to a new user.

        **Permissions required**: `DeviceManagementManagedDevices.PrivilegedOperations.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_id | String | Yes | - | Intune device ID (GUID): the `device_id` returned by **Managed devices from Intune** |
        | keep_user_data | Boolean | No | false | Keep the device joined to Microsoft Entra ID and keep the user's home folder. When `false`, the device goes back to the end of Windows setup, and a personal device is removed from Microsoft Entra ID and from Intune |

        ### Example Input

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012", "keep_user_data": true }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `device_id` | String | The Intune device ID that was asked to start fresh |
        | `keep_user_data` | Boolean | Whether the request asked Intune to keep the user data. `false` when the input was not set |

        ### Example Output

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012", "keep_user_data": true }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the Intune device ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. A 404 asks you to check that the ID is the Intune device ID. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Windows devices only.
        - The action cannot be undone. Put an approval step in front of it. Apps that were removed are not put back.
      END_OF_DESCRIPTION

      input_schema do
        field :device_id, 'Intune device ID', :string, required: true
        field :keep_user_data, 'Keep user data', :boolean
      end

      output_schema do
        field :device_id, 'Intune device ID', :string, required: true
        field :keep_user_data, 'Keep user data', :boolean, required: true
      end

      run do
        keep_user_data = input[:keep_user_data] == true
        device_id = helpers.device_command(input[:device_id], 'cleanWindowsDevice', PRIVILEGED_OPERATIONS_PERMISSION,
                                           body: { keepUserData: keep_user_data })
        [{ output: { device_id: device_id, keep_user_data: keep_user_data } }]
      end
    end

    action '01a1c8f9-2388-77a4-bf27-883d6b8746d1' do
      name 'Run Defender scan on Intune device'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Starts a Microsoft Defender Antivirus scan on one Intune managed Windows device through Microsoft Graph's [windowsDefenderScan API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-windowsdefenderscan).

        **Use case**: scan a device after a security alert, before you decide whether to isolate or wipe it.

        **Permissions required**: `DeviceManagementManagedDevices.PrivilegedOperations.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_id | String | Yes | - | Intune device ID (GUID): the `device_id` returned by **Managed devices from Intune** |
        | quick_scan | Boolean | No | true | `true` runs a quick scan, `false` runs a full scan |

        ### Example Input

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012", "quick_scan": false }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `device_id` | String | The Intune device ID that was asked to scan |
        | `quick_scan` | Boolean | `true` for a quick scan, `false` for a full scan |

        ### Example Output

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012", "quick_scan": false }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the Intune device ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. A 404 asks you to check that the ID is the Intune device ID. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Windows devices only.
        - A quick scan checks the places where threats usually appear, such as memory, startup folders and running processes. A full scan checks all files and running processes.
      END_OF_DESCRIPTION

      input_schema do
        field :device_id, 'Intune device ID', :string, required: true
        field :quick_scan, 'Quick scan', :boolean, default: true
      end

      output_schema do
        field :device_id, 'Intune device ID', :string, required: true
        field :quick_scan, 'Quick scan', :boolean, required: true
      end

      run do
        quick_scan = input[:quick_scan] != false
        device_id = helpers.device_command(input[:device_id], 'windowsDefenderScan', PRIVILEGED_OPERATIONS_PERMISSION,
                                           body: { quickScan: quick_scan })
        [{ output: { device_id: device_id, quick_scan: quick_scan } }]
      end
    end

    action '01a1c8f9-2402-7ed0-9856-803cb578712c' do
      name 'Rename Intune device (Beta)'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Renames one Intune managed device through Microsoft Graph's [setDeviceName API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-setdevicename?view=graph-rest-beta). Microsoft offers this call only in its beta API, which it can change.

        **Use case**: apply your naming standard to a device, for example after it was handed to a new user.

        **Permissions required**: `DeviceManagementManagedDevices.PrivilegedOperations.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_id | String | Yes | - | Intune device ID (GUID): the `device_id` returned by **Managed devices from Intune** |
        | device_name | String | Yes | - | The new name of the device |

        ### Example Input

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012", "device_name": "CONTOSO-LT-0042" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `device_id` | String | The Intune device ID that was asked to change its name |
        | `device_name` | String | The new name, as sent to Microsoft |

        ### Example Output

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012", "device_name": "CONTOSO-LT-0042" }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the Intune device ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. A 404 asks you to check that the ID is the Intune device ID. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The call is part of the Microsoft Graph beta API. Microsoft can change it, and the action can then fail.
        - Microsoft accepts the request before the device acts on it. The device takes its new name when it is next online.
      END_OF_DESCRIPTION

      input_schema do
        field :device_id, 'Intune device ID', :string, required: true
        field :device_name, 'Device name', :string, required: true
      end

      output_schema do
        field :device_id, 'Intune device ID', :string, required: true
        field :device_name, 'Device name', :string, required: true
      end

      run do
        device_name = input[:device_name].to_s.strip
        device_id = helpers.device_command(input[:device_id], 'setDeviceName', PRIVILEGED_OPERATIONS_PERMISSION,
                                           body: { deviceName: device_name }, beta: true)
        [{ output: { device_id: device_id, device_name: device_name } }]
      end
    end

    action '01a1c8f9-2473-712a-8d3d-318cb91d8fba' do
      name 'Change primary user (Alpha)'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Sets the primary user of one Intune managed device. Microsoft does not document this call and can change or remove it without notice. The [managedDevice resource](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-manageddevice?view=graph-rest-beta) lists the primary users of a device as its `users` relationship, but Microsoft documents no call that changes them. This action sends the Microsoft Graph beta request `POST /deviceManagement/managedDevices/{device_id}/users/$ref` with the new user.

        **Use case**: move a device to its new user after a hand-over, so Intune reports and user-based assignments follow the right person.

        **Permissions required**: `DeviceManagementManagedDevices.ReadWrite.All`. Microsoft does not document this call. Its own 403 names this permission.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_id | String | Yes | - | Intune device ID (GUID): the `device_id` returned by **Managed devices from Intune** |
        | user_id | String | Yes | - | Object ID (GUID) of the Microsoft Entra user who becomes the primary user |

        ### Example Input

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012", "user_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `device_id` | String | The Intune device ID |
        | `user_id` | String | The object ID of the new primary user |

        ### Example Output

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012", "user_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd" }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the Intune device ID or the user ID is not a GUID. A 403 names `DeviceManagementManagedDevices.ReadWrite.All`. A 404 asks you to check that the ID is the Intune device ID. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Microsoft does not document this call. It can change or stop working at any time without notice, and the action then fails.
        - The call is part of the Microsoft Graph beta API.
      END_OF_DESCRIPTION

      input_schema do
        field :device_id, 'Intune device ID', :string, required: true
        field :user_id, 'User ID', :string, required: true
      end

      output_schema do
        field :device_id, 'Intune device ID', :string, required: true
        field :user_id, 'User ID', :string, required: true
      end

      run do
        device_id = helpers.guid_input(input[:device_id], 'Intune device ID')
        user_id = helpers.guid_input(input[:user_id], 'User ID')
        helpers.graph_request(:post, "/deviceManagement/managedDevices/#{device_id}/users/$ref",
                              MANAGED_DEVICE_WRITE_PERMISSION,
                              beta: true,
                              body: { '@odata.id' => helpers.graph_url("/users/#{user_id}", beta: true) },
                              expected: [NO_CONTENT_STATUS, OK_STATUS],
                              not_found_hint: INTUNE_DEVICE_NOT_FOUND_HINT)
        [{ output: { device_id: device_id, user_id: user_id } }]
      end
    end

    action '01a1c8f9-24ea-7dcb-97d4-28050033021b' do
      name 'Assign Autopilot device to user'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Assigns a user to one Windows Autopilot device through Microsoft Graph's [updateDeviceProperties API](https://learn.microsoft.com/en-us/graph/api/intune-enrollment-windowsautopilotdeviceidentity-updatedeviceproperties). For [supported manufacturers](https://learn.microsoft.com/en-us/autopilot/enrollment-autopilot), Windows setup then fills in the user principal name on the Microsoft Entra sign-in page and greets the user with the name you give. The assignment does not change which policies and apps the device gets.

        **Use case**: prepare a new laptop for a named user before it ships, from the Xurrent request that ordered it.

        **Permissions required**: `DeviceManagementServiceConfig.ReadWrite.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | autopilot_device_id | String | Yes | - | ID (GUID) of the Windows Autopilot device. This is not the Intune device ID |
        | user_principal_name | String | Yes | - | User principal name of the user, for example `adele.vance@contoso.com` |
        | addressable_user_name | String | No | - | The greeting name Windows shows to the user during setup |

        ### Example Input

        ```json
        {
          "autopilot_device_id": "4f3c2a1b-5d6e-4f70-8a9b-0c1d2e3f4a5b",
          "user_principal_name": "adele.vance@contoso.com",
          "addressable_user_name": "Adele Vance"
        }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `autopilot_device_id` | String | The Windows Autopilot device ID |
        | `user_principal_name` | String | The user principal name that was assigned |

        ### Example Output

        ```json
        { "autopilot_device_id": "4f3c2a1b-5d6e-4f70-8a9b-0c1d2e3f4a5b", "user_principal_name": "adele.vance@contoso.com" }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the Autopilot device ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The device must already be registered with Windows Autopilot, and the user must have an Intune license.
        - The assignment does not work when the tenant signs in through Active Directory Federation Services (ADFS).
      END_OF_DESCRIPTION

      input_schema do
        field :autopilot_device_id, 'Autopilot device ID', :string, required: true
        field :user_principal_name, 'User principal name', :string, required: true
        field :addressable_user_name, 'Addressable user name', :string
      end

      output_schema do
        field :autopilot_device_id, 'Autopilot device ID', :string, required: true
        field :user_principal_name, 'User principal name', :string, required: true
      end

      run do
        autopilot_id = helpers.guid_input(input[:autopilot_device_id], 'Autopilot device ID')
        user_principal_name = input[:user_principal_name].to_s.strip
        greeting_name = input[:addressable_user_name].to_s.strip.presence
        body = { userPrincipalName: user_principal_name, addressableUserName: greeting_name }.compact
        path = "/deviceManagement/windowsAutopilotDeviceIdentities/#{autopilot_id}/updateDeviceProperties"
        helpers.graph_request(:post, path, AUTOPILOT_WRITE_PERMISSION, body: body)
        [{ output: { autopilot_device_id: autopilot_id, user_principal_name: user_principal_name } }]
      end
    end

    action '01a1c8f9-2563-7631-aafc-803389571093' do
      name 'Approve Intune EPM elevation request (Beta)'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Approves one Endpoint Privilege Management (EPM) elevation request through Microsoft Graph's [approve API](https://learn.microsoft.com/en-us/graph/api/intune-epmgraphapiservice-privilegemanagementelevationrequest-approve?view=graph-rest-beta). Intune then tells the user that they can run the file with administrator rights. Microsoft offers this call only in its beta API, which it can change.

        **Use case**: approve a user's request to run an installer as administrator once the approval in a Xurrent request has passed.

        **Permissions required**: `DeviceManagementConfiguration.ReadWrite.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | elevation_request_id | String | Yes | - | ID (GUID) of the elevation request |
        | reviewer_justification | String | No | - | Why the request is approved. Stored with the request |

        ### Example Input

        ```json
        { "elevation_request_id": "3df245af-45af-3df2-af45-f23daf45f23d", "reviewer_justification": "Approved in request 70123" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `elevation_request_id` | String | The elevation request ID |
        | `status` | String | One of `none`, `pending`, `approved`, `denied`, `expired`, `revoked`, `completed` |
        | `requested_by_user_id` | String | Object ID of the user who asked for the elevation |
        | `requested_by_user_principal_name` | String | User principal name of the user who asked for the elevation |
        | `requested_on_device_id` | String | Intune device ID of the device the request came from |
        | `device_name` | String | Name of the device the request came from |
        | `request_justification` | String | The reason the user gave |
        | `request_created_date_time` | DateTime | When the user made the request |
        | `request_last_modified_date_time` | DateTime | When the request last changed |
        | `request_expiry_date_time` | DateTime | When the request expires |
        | `review_completed_by_user_id` | String | Object ID of the administrator who reviewed the request |
        | `review_completed_by_user_principal_name` | String | User principal name of the administrator who reviewed the request |
        | `review_completed_date_time` | DateTime | When the review was done |
        | `reviewer_justification` | String | The reason the reviewer gave |
        | `application_detail` | Object | The file the user wants to run. See **Application detail fields** below |

        #### Application detail fields

        | Field Name | Type | Description |
        |---|---|---|
        | `file_name` | String | File name |
        | `file_path` | String | Folder of the file on the device |
        | `file_hash` | String | Hash of the file |
        | `file_description` | String | Description stored in the file |
        | `publisher_name` | String | Publisher of the file |
        | `publisher_cert` | String | Certificate the file is signed with |
        | `product_name` | String | Product name stored in the file |
        | `product_internal_name` | String | Internal product name stored in the file |
        | `product_version` | String | Product version stored in the file |

        ### Example Output

        ```json
        {
          "elevation_request_id": "3df245af-45af-3df2-af45-f23daf45f23d",
          "status": "approved",
          "requested_by_user_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd",
          "requested_by_user_principal_name": "adele.vance@contoso.com",
          "requested_on_device_id": "12345678-1234-1234-1234-123456789012",
          "device_name": "CONTOSO-LT-0042",
          "request_justification": "Need to install the VPN client",
          "request_created_date_time": "2026-11-10T08:15:00Z",
          "request_last_modified_date_time": "2026-11-10T08:30:00Z",
          "request_expiry_date_time": "2026-11-11T08:15:00Z",
          "review_completed_by_user_id": "5b2a1c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d",
          "review_completed_by_user_principal_name": "it.admin@contoso.com",
          "review_completed_date_time": "2026-11-10T08:30:00Z",
          "reviewer_justification": "Approved in request 70123",
          "application_detail": {
            "file_name": "vpnclient.exe",
            "file_path": "C:\\\\Users\\\\adele\\\\Downloads",
            "file_hash": "4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b",
            "file_description": "VPN client installer",
            "publisher_name": "Contoso Ltd",
            "publisher_cert": "CN=Contoso Ltd",
            "product_name": "Contoso VPN",
            "product_internal_name": "vpnclient",
            "product_version": "5.2.1"
          }
        }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the elevation request ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The call is part of the Microsoft Graph beta API. Microsoft can change it, and the action can then fail.
        - Elevation requests exist only when an EPM elevation rule asks for support approval.
      END_OF_DESCRIPTION

      input_schema do
        field :elevation_request_id, 'Elevation request ID', :string, required: true
        field :reviewer_justification, 'Reviewer justification', :string
      end

      output_schema do
        field :elevation_request_id, 'Elevation request ID', :string, required: true
        field :status, 'Status', :string
        field :requested_by_user_id, 'Requested by user ID', :string
        field :requested_by_user_principal_name, 'Requested by user principal name', :string
        field :requested_on_device_id, 'Requested on device ID', :string
        field :device_name, 'Device name', :string
        field :request_justification, 'Request justification', :string
        field :request_created_date_time, 'Request created', :date_time
        field :request_last_modified_date_time, 'Request last modified', :date_time
        field :request_expiry_date_time, 'Request expires', :date_time
        field :review_completed_by_user_id, 'Reviewed by user ID', :string
        field :review_completed_by_user_principal_name, 'Reviewed by user principal name', :string
        field :review_completed_date_time, 'Review completed', :date_time
        field :reviewer_justification, 'Reviewer justification', :string
        field :application_detail, 'Application detail', :nested do
          field :file_name, 'File name', :string
          field :file_path, 'File path', :string
          field :file_hash, 'File hash', :string
          field :file_description, 'File description', :string
          field :publisher_name, 'Publisher name', :string
          field :publisher_cert, 'Publisher certificate', :string
          field :product_name, 'Product name', :string
          field :product_internal_name, 'Product internal name', :string
          field :product_version, 'Product version', :string
        end
      end

      run do
        [{ output: helpers.review_elevation(input[:elevation_request_id], 'approve', input[:reviewer_justification]) }]
      end
    end

    action '01a1c8f9-25d3-73ba-a936-156576ddab8e' do
      name 'Deny or revoke Intune EPM elevation (Beta)'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Denies a pending Endpoint Privilege Management (EPM) elevation request, or revokes one that was approved, through Microsoft Graph's [deny API](https://learn.microsoft.com/en-us/graph/api/intune-epmgraphapiservice-privilegemanagementelevationrequest-deny?view=graph-rest-beta) or [revoke API](https://learn.microsoft.com/en-us/graph/api/intune-epmgraphapiservice-privilegemanagementelevationrequest-revoke?view=graph-rest-beta). Microsoft offers these calls only in its beta API, which it can change.

        **Use case**: deny a user's request to run a file as administrator when the approval in a Xurrent request is rejected, or revoke an approval that was given by mistake.

        **Permissions required**: `DeviceManagementConfiguration.ReadWrite.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | elevation_request_id | String | Yes | - | ID (GUID) of the elevation request |
        | decision | String | Yes | - | `deny` for a pending request, `revoke` for an approved request |
        | reviewer_justification | String | No | - | Why the request is denied or revoked. Stored with the request |

        ### Example Input

        ```json
        { "elevation_request_id": "3df245af-45af-3df2-af45-f23daf45f23d", "decision": "deny", "reviewer_justification": "Not an approved application" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `elevation_request_id` | String | The elevation request ID |
        | `status` | String | One of `none`, `pending`, `approved`, `denied`, `expired`, `revoked`, `completed` |
        | `requested_by_user_id` | String | Object ID of the user who asked for the elevation |
        | `requested_by_user_principal_name` | String | User principal name of the user who asked for the elevation |
        | `requested_on_device_id` | String | Intune device ID of the device the request came from |
        | `device_name` | String | Name of the device the request came from |
        | `request_justification` | String | The reason the user gave |
        | `request_created_date_time` | DateTime | When the user made the request |
        | `request_last_modified_date_time` | DateTime | When the request last changed |
        | `request_expiry_date_time` | DateTime | When the request expires |
        | `review_completed_by_user_id` | String | Object ID of the administrator who reviewed the request |
        | `review_completed_by_user_principal_name` | String | User principal name of the administrator who reviewed the request |
        | `review_completed_date_time` | DateTime | When the review was done |
        | `reviewer_justification` | String | The reason the reviewer gave |
        | `application_detail` | Object | The file the user wants to run. See **Application detail fields** below |

        #### Application detail fields

        | Field Name | Type | Description |
        |---|---|---|
        | `file_name` | String | File name |
        | `file_path` | String | Folder of the file on the device |
        | `file_hash` | String | Hash of the file |
        | `file_description` | String | Description stored in the file |
        | `publisher_name` | String | Publisher of the file |
        | `publisher_cert` | String | Certificate the file is signed with |
        | `product_name` | String | Product name stored in the file |
        | `product_internal_name` | String | Internal product name stored in the file |
        | `product_version` | String | Product version stored in the file |

        ### Example Output

        ```json
        {
          "elevation_request_id": "3df245af-45af-3df2-af45-f23daf45f23d",
          "status": "denied",
          "requested_by_user_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd",
          "requested_by_user_principal_name": "adele.vance@contoso.com",
          "requested_on_device_id": "12345678-1234-1234-1234-123456789012",
          "device_name": "CONTOSO-LT-0042",
          "request_justification": "Need to install a game",
          "request_created_date_time": "2026-11-10T08:15:00Z",
          "request_last_modified_date_time": "2026-11-10T08:30:00Z",
          "request_expiry_date_time": "2026-11-11T08:15:00Z",
          "review_completed_by_user_id": "5b2a1c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d",
          "review_completed_by_user_principal_name": "it.admin@contoso.com",
          "review_completed_date_time": "2026-11-10T08:30:00Z",
          "reviewer_justification": "Not an approved application",
          "application_detail": {
            "file_name": "gamesetup.exe",
            "file_path": "C:\\\\Users\\\\adele\\\\Downloads",
            "file_hash": "9a8b7c6d5e4f30211a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f7081",
            "file_description": "Game setup",
            "publisher_name": "Fabrikam Games",
            "publisher_cert": "CN=Fabrikam Games",
            "product_name": "Fabrikam Racer",
            "product_internal_name": "gamesetup",
            "product_version": "1.0.4"
          }
        }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the elevation request ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The calls are part of the Microsoft Graph beta API. Microsoft can change them, and the action can then fail.
      END_OF_DESCRIPTION

      input_schema do
        field :elevation_request_id, 'Elevation request ID', :string, required: true
        field :decision, 'Decision', :string, required: true, enumeration: ELEVATION_DECISIONS
        field :reviewer_justification, 'Reviewer justification', :string
      end

      output_schema do
        field :elevation_request_id, 'Elevation request ID', :string, required: true
        field :status, 'Status', :string
        field :requested_by_user_id, 'Requested by user ID', :string
        field :requested_by_user_principal_name, 'Requested by user principal name', :string
        field :requested_on_device_id, 'Requested on device ID', :string
        field :device_name, 'Device name', :string
        field :request_justification, 'Request justification', :string
        field :request_created_date_time, 'Request created', :date_time
        field :request_last_modified_date_time, 'Request last modified', :date_time
        field :request_expiry_date_time, 'Request expires', :date_time
        field :review_completed_by_user_id, 'Reviewed by user ID', :string
        field :review_completed_by_user_principal_name, 'Reviewed by user principal name', :string
        field :review_completed_date_time, 'Review completed', :date_time
        field :reviewer_justification, 'Reviewer justification', :string
        field :application_detail, 'Application detail', :nested do
          field :file_name, 'File name', :string
          field :file_path, 'File path', :string
          field :file_hash, 'File hash', :string
          field :file_description, 'File description', :string
          field :publisher_name, 'Publisher name', :string
          field :publisher_cert, 'Publisher certificate', :string
          field :product_name, 'Product name', :string
          field :product_internal_name, 'Product internal name', :string
          field :product_version, 'Product version', :string
        end
      end

      run do
        [{ output: helpers.review_elevation(input[:elevation_request_id], input[:decision],
                                            input[:reviewer_justification]) }]
      end
    end

    action '01a1c8f9-2645-718c-96a4-02cff20a3f5f' do
      name 'Rotate Intune local admin password (Beta)'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Starts a manual rotation of the local administrator password on one Intune managed device through Microsoft Graph's [rotateLocalAdminPassword API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-rotatelocaladminpassword?view=graph-rest-beta). Microsoft offers this call only in its beta API, which it can change.

        **Use case**: change the local administrator password after a technician has used it, for example after **Get Intune device local admin password**.

        **Permissions required**: `DeviceManagementManagedDevices.PrivilegedOperations.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_id | String | Yes | - | Intune device ID (GUID): the `device_id` returned by **Managed devices from Intune** |

        ### Example Input

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `device_id` | String | The Intune device ID that was asked to rotate its password |

        ### Example Output

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the Intune device ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. A 404 asks you to check that the ID is the Intune device ID. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The call is part of the Microsoft Graph beta API. Microsoft can change it, and the action can then fail.
        - Windows devices only. The device needs a Windows LAPS policy from Intune.
        - Microsoft accepts the request before the device acts on it. The device makes the new password when it is next online.
      END_OF_DESCRIPTION

      input_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      output_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      run do
        device_id = helpers.device_command(input[:device_id], 'rotateLocalAdminPassword',
                                           PRIVILEGED_OPERATIONS_PERMISSION, beta: true)
        [{ output: { device_id: device_id } }]
      end
    end

    action '01a1c8f9-26ac-7c69-a57d-2e5b8d376d3a' do
      name 'Get Intune device local admin password'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Reads the local administrator password of one device from Microsoft Entra ID through Microsoft Graph's [get deviceLocalCredentialInfo API](https://learn.microsoft.com/en-us/graph/api/devicelocalcredentialinfo-get). The password is returned as a secret string.

        **Use case**: give a technician the local administrator password of a device for a support session, then change it with **Rotate Intune local admin password (Beta)**.

        **Permissions required**: `DeviceLocalCredential.Read.All`. `DeviceLocalCredential.ReadBasic.All` is not enough to read the password.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | azure_ad_device_id | String | Yes | - | Entra device ID (GUID): the `azure_ad_device_id` returned by **Managed devices from Intune**. This is not the Intune `device_id` |

        ### Example Input

        ```json
        { "azure_ad_device_id": "87654321-8765-8765-8765-876543210987" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `azure_ad_device_id` | String | The Entra device ID |
        | `device_name` | String | Name of the device |
        | `account_name` | String | Name of the local administrator account |
        | `account_sid` | String | Security identifier of the local administrator account |
        | `password` | Secret String | The password of the local administrator account |
        | `backup_date_time` | DateTime | When this password was backed up to Microsoft Entra ID |
        | `last_backup_date_time` | DateTime | When the device last backed up a password |
        | `refresh_date_time` | DateTime | When the device will next change the password |

        ### Example Output

        ```json
        {
          "azure_ad_device_id": "87654321-8765-8765-8765-876543210987",
          "device_name": "CONTOSO-LT-0042",
          "account_name": "ContosoLocalAdmin",
          "account_sid": "S-1-5-21-2318549658-1590267884-3984890135-1965",
          "password": "<secret>",
          "backup_date_time": "2026-11-01T13:45:30Z",
          "last_backup_date_time": "2026-11-01T13:45:30Z",
          "refresh_date_time": "2026-12-01T13:45:30Z"
        }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, when Microsoft returns no password for the device, and when the password has characters that this action cannot decode. It fails before calling Microsoft when the Entra device ID is not a GUID, or is `00000000-0000-0000-0000-000000000000`, which means that the device has no Microsoft Entra ID record. A 403 gives Microsoft's reason and names the permission the action needs. A 404 asks you to check that the ID is the Entra device ID. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The device needs Windows LAPS with its password backed up to Microsoft Entra ID.
        - Microsoft keeps earlier passwords too. The action returns the newest one.

        ### Operational notes
        - **Treat the password as a secret**: pass it on only through a secure channel, and do not log it in plain text.
      END_OF_DESCRIPTION

      input_schema do
        field :azure_ad_device_id, 'Entra device ID', :string, required: true
      end

      output_schema do
        field :azure_ad_device_id, 'Entra device ID', :string, required: true
        field :device_name, 'Device name', :string
        field :account_name, 'Account name', :string
        field :account_sid, 'Account SID', :string
        field :password, 'Password', :secret_string
        field :backup_date_time, 'Password backed up', :date_time
        field :last_backup_date_time, 'Last backup', :date_time
        field :refresh_date_time, 'Next password change', :date_time
      end

      run do
        device_id = helpers.entra_device_input(input[:azure_ad_device_id])
        response = helpers.graph_request(:get, "/directory/deviceLocalCredentials/#{device_id}",
                                         LOCAL_CREDENTIAL_PERMISSION,
                                         params: { '$select': LOCAL_CREDENTIAL_SELECT },
                                         expected: [OK_STATUS],
                                         not_found_hint: ENTRA_DEVICE_NOT_FOUND_HINT)
        info = helpers.graph_entity(response)
        # rubocop:disable-next Style/RedundantSort
        credential = Array(info['credentials']).sort_by { |entry| entry['backupDateTime'].to_s }.last
        unless credential.is_a?(Hash) && credential['passwordBase64'].present?
          fail_job!("Microsoft Graph returned no local administrator password for Entra device #{device_id}.")
        end

        [{ output: {
          azure_ad_device_id: device_id,
          device_name: info['deviceName'],
          account_name: credential['accountName'],
          account_sid: credential['accountSid'],
          password: helpers.local_admin_password(credential['passwordBase64']),
          backup_date_time: credential['backupDateTime'],
          last_backup_date_time: info['lastBackupDateTime'],
          refresh_date_time: info['refreshDateTime'],
        } }]
      end
    end

    action '01a1c8f9-271f-778f-9e2c-7623d07b7046' do
      name 'Get BitLocker recovery key'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Reads one BitLocker recovery key from Microsoft Entra ID through Microsoft Graph's [get bitlockerRecoveryKey API](https://learn.microsoft.com/en-us/graph/api/bitlockerrecoverykey-get). Give the recovery key ID, or give the Entra device ID to get the newest key of the device's operating system drive, found with the [list recoveryKeys API](https://learn.microsoft.com/en-us/graph/api/bitlocker-list-recoverykeys). The key is returned as a secret string, and Microsoft records each read in the Microsoft Entra audit log.

        **Use case**: give a user the recovery key that their locked Windows device asks for, from a Xurrent request that names the device.

        **Permissions required**: `BitlockerKey.Read.All`. `BitlockerKey.ReadBasic.All` does not allow reading the key.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | recovery_key_id | String | No | - | ID (GUID) of the recovery key |
        | azure_ad_device_id | String | No | - | Entra device ID (GUID): the `azure_ad_device_id` returned by **Managed devices from Intune**. This is not the Intune `device_id` |

        Give exactly one of `recovery_key_id` and `azure_ad_device_id`.

        ### Example Input

        ```json
        { "azure_ad_device_id": "1ab40ab2-32a8-4b00-b6b5-ba724e407de9" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `recovery_key_id` | String | ID of the recovery key |
        | `azure_ad_device_id` | String | Entra device ID of the device the key was backed up from |
        | `volume_type` | String | `operatingSystemVolume`, `fixedDataVolume` or `removableDataVolume`. Microsoft sends the type as a number (`1`, `2`, `3`) or as a name, and the action always returns the name. Any other value is returned as Microsoft sent it |
        | `created_date_time` | DateTime | When the key was backed up to Microsoft Entra ID |
        | `recovery_key` | Secret String | The BitLocker recovery key |

        ### Example Output

        ```json
        {
          "recovery_key_id": "b465e4e8-e4e8-b465-e8e4-65b4e8e465b4",
          "azure_ad_device_id": "1ab40ab2-32a8-4b00-b6b5-ba724e407de9",
          "volume_type": "operatingSystemVolume",
          "created_date_time": "2026-06-15T13:45:30Z",
          "recovery_key": "<secret>"
        }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and when Microsoft returns the recovery key without the key. It fails before calling Microsoft when neither or both inputs are given, when an ID is not a GUID, or when the Entra device ID is `00000000-0000-0000-0000-000000000000`, which means that the device has no Microsoft Entra ID record. With an Entra device ID, the job fails when the device has no recovery key for its operating system drive. This also happens when the ID is the Intune device ID instead. It fails too when the keys of the device fill more than 10 pages. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - With an Entra device ID, the action returns the newest key of the operating system drive. To read the key of a data drive, give its recovery key ID.

        ### Operational notes
        - **Treat the key as a secret**: pass it on only through a secure channel, and do not log it in plain text.
      END_OF_DESCRIPTION

      input_schema do
        field :recovery_key_id, 'Recovery key ID', :string
        field :azure_ad_device_id, 'Entra device ID', :string
      end

      output_schema do
        field :recovery_key_id, 'Recovery key ID', :string, required: true
        field :azure_ad_device_id, 'Entra device ID', :string
        field :volume_type, 'Volume type', :string
        field :created_date_time, 'Backed up', :date_time
        field :recovery_key, 'Recovery key', :secret_string
      end

      run do
        key_id = input[:recovery_key_id].to_s.strip
        device_id = input[:azure_ad_device_id].to_s.strip
        fail_job!('Give exactly one of Recovery key ID and Entra device ID.') if key_id.present? == device_id.present?

        key_id = helpers.newest_os_volume_key_id(helpers.entra_device_input(device_id)) if key_id.blank?
        key_id = helpers.guid_input(key_id, 'Recovery key ID')
        response = helpers.graph_request(:get, "#{BITLOCKER_KEYS_PATH}/#{key_id}", BITLOCKER_PERMISSION,
                                         params: { '$select': BITLOCKER_KEY_SELECT }, expected: [OK_STATUS])
        key = helpers.graph_entity(response)
        fail_job!("Microsoft Graph returned no key for BitLocker recovery key ID #{key_id}.") if key['key'].blank?

        [{ output: {
          recovery_key_id: key_id,
          azure_ad_device_id: key['deviceId'],
          volume_type: helpers.volume_type_name(key['volumeType']),
          created_date_time: key['createdDateTime'],
          recovery_key: make_secret_string(key['key'].to_s),
        } }]
      end
    end

    action '01a1c8f9-279c-75e3-8838-16c5c30519a5' do
      name 'Delete Intune device record'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Removes one device from Intune through Microsoft Graph's [delete managedDevice API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-delete). Intune also sends the device a **Retire** command, or a **Wipe** command for a corporate-owned Android device, so the company data on it is removed too.

        **Use case**: remove a device that is no longer needed, is being repurposed, or is missing, so it no longer shows in Intune and in the next **Managed devices from Intune** sync.

        **Permissions required**: `DeviceManagementManagedDevices.ReadWrite.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_id | String | Yes | - | Intune device ID (GUID): the `device_id` returned by **Managed devices from Intune** |

        ### Example Input

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `device_id` | String | The Intune device ID |
        | `existed` | Boolean | `false` when Microsoft Graph found no Intune device record with this ID (HTTP 404), so nothing was deleted |

        ### Example Output

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012", "existed": true }
        ```

        ### Error Handling
        A 404 is not an error: `existed` is `false`. The job fails without retry on 400 / 401 / 403 responses, and before calling Microsoft when the Intune device ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The action cannot be undone. Put an approval step in front of it.
        - `existed` is `false` whenever Microsoft Graph finds no Intune record with the ID. That also happens when the ID is the wrong kind of ID, such as the Entra device ID, or when a retried delete follows one that Microsoft had already done.
        - A tenant can submit up to 1,000 Delete actions per day.
        - On a Microsoft Entra joined Windows device protected by BitLocker, deleting suspends BitLocker. Read the BitLocker recovery key and the local administrator password first if you still need them.
      END_OF_DESCRIPTION

      input_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      output_schema do
        field :device_id, 'Intune device ID', :string, required: true
        field :existed, 'Existed', :boolean, required: true
      end

      run do
        device_id = helpers.guid_input(input[:device_id], 'Intune device ID')
        response = helpers.graph_request(:delete, "/deviceManagement/managedDevices/#{device_id}",
                                         MANAGED_DEVICE_WRITE_PERMISSION,
                                         expected: [NO_CONTENT_STATUS, NOT_FOUND_STATUS])
        [{ output: { device_id: device_id, existed: response.status != NOT_FOUND_STATUS } }]
      end
    end

    action '01a1c8f9-2807-7459-8434-7edcfd84a9d1' do
      name 'Collect Intune device diagnostics (Beta)'
      avatar '/assets/icons/microsoft-intune.svg'
      description <<~END_OF_DESCRIPTION
        Asks one Intune managed Windows device to collect its diagnostic logs and upload them to Intune, through Microsoft Graph's [createDeviceLogCollectionRequest API](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-createdevicelogcollectionrequest?view=graph-rest-beta). Microsoft offers this call only in its beta API, which it can change.

        **Use case**: collect the logs of a device for a support request, without asking the user to send them.

        **Permissions required**: `DeviceManagementManagedDevices.ReadWrite.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | device_id | String | Yes | - | Intune device ID (GUID): the `device_id` returned by **Managed devices from Intune** |

        ### Example Input

        ```json
        { "device_id": "12345678-1234-1234-1234-123456789012" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `request_id` | String | ID of the log collection request |
        | `status` | String | One of `pending`, `completed`, `failed` |
        | `managed_device_id` | String | The Intune device ID |
        | `requested_date_time_utc` | DateTime | When the logs were requested |
        | `received_date_time_utc` | DateTime | When Intune received the logs |
        | `expiration_date_time_utc` | DateTime | When the logs will be deleted |
        | `initiated_by_user_principal_name` | String | Who asked for the logs |
        | `enrolled_by_user` | String | User principal name of the user who enrolled the device |
        | `size_in_kb` | Float | Size of the logs in KB |
        | `error_code` | Integer | Error code of the request, if any |
        | `size` | Float | Size of the logs, as Microsoft returns it. Microsoft gives no unit for it: use `size_in_kb` for the size in KB |

        ### Example Output

        ```json
        {
          "request_id": "9c46a35a-b7cd-42ef-9ce5-9ea1481d40f1_12345678-1234-1234-1234-123456789012_05fb97dc-97dc-05fb-dc97-fb05dc97fb05",
          "status": "pending",
          "managed_device_id": "12345678-1234-1234-1234-123456789012",
          "requested_date_time_utc": "2026-11-10T09:00:00Z",
          "received_date_time_utc": null,
          "expiration_date_time_utc": "2026-12-10T09:00:00Z",
          "initiated_by_user_principal_name": "it.admin@contoso.com",
          "enrolled_by_user": "adele.vance@contoso.com",
          "size_in_kb": 0,
          "error_code": 0,
          "size": 0
        }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and before calling Microsoft when the Intune device ID is not a GUID. A 403 gives Microsoft's reason and names the permission the action needs. A 404 asks you to check that the ID is the Intune device ID. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The call is part of the Microsoft Graph beta API. Microsoft can change it, and the action can then fail.
        - Corporate-owned Windows devices only.
        - The logs are collected when the device is next online. Download them from the device in the Microsoft Intune admin center when `status` is `completed`.
      END_OF_DESCRIPTION

      input_schema do
        field :device_id, 'Intune device ID', :string, required: true
      end

      output_schema do
        field :request_id, 'Request ID', :string
        field :status, 'Status', :string
        field :managed_device_id, 'Intune device ID', :string
        field :requested_date_time_utc, 'Requested', :date_time
        field :received_date_time_utc, 'Received', :date_time
        field :expiration_date_time_utc, 'Expires', :date_time
        field :initiated_by_user_principal_name, 'Initiated by', :string
        field :enrolled_by_user, 'Enrolled by user', :string
        field :size_in_kb, 'Size in KB', :float
        field :error_code, 'Error code', :integer
        field :size, 'Size', :float
      end

      run do
        device_id = helpers.guid_input(input[:device_id], 'Intune device ID')
        path = "/deviceManagement/managedDevices/#{device_id}/createDeviceLogCollectionRequest"
        response = helpers.graph_request(:post, path, MANAGED_DEVICE_WRITE_PERMISSION,
                                         beta: true, body: { templateType: LOG_COLLECTION_TEMPLATE },
                                         expected: [OK_STATUS], not_found_hint: INTUNE_DEVICE_NOT_FOUND_HINT)
        log_request = helpers.graph_entity(response)
        [{ output: helpers.snake_case_keys(log_request).merge('request_id' => log_request['id']) }]
      end
    end

    helper :graph_fetch_page do |initial_url, parameters|
      url = helpers.trusted_next_link(iteration_state_value(:odata_nextLink))
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
          raw_value = device_hash[field]
          value = case field_schema.type
                  when :secret_string then raw_value.to_s
                  when :boolean then raw_value
                  else raw_value.presence
                  end
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

    helper :graph_segment do |value, label|
      segment = value.to_s.strip
      fail_job!("#{label} is required.") if segment.blank?
      fail_job!("#{label} '#{segment}' is not a valid id.") if DOT_SEGMENTS.include?(segment)

      segment.gsub('%', '%25').gsub('#', '%23').gsub('?', '%3F').gsub('/', '%2F').gsub(' ', '%20')
    end

    helper :trusted_next_link do |link|
      next nil if link.blank?

      base = URI.parse(helpers.graph_endpoint.to_s.chomp('/'))
      next_uri = URI.parse(link.to_s)
      same_host = [next_uri.scheme.to_s.downcase, next_uri.host.to_s.downcase, next_uri.port] ==
                  [base.scheme.to_s.downcase, base.host.to_s.downcase, base.port]
      unless same_host && next_uri.path.to_s.start_with?("#{base.path}/")
        fail_job!("Microsoft Graph answered with a next page link that is not on #{base}: '#{link}'")
      end

      link.to_s
    rescue URI::InvalidURIError
      fail_job!("Microsoft Graph answered with a next page link that is not a URL: '#{link}'")
    end

    helper :graph_url do |path, beta: false|
      base = helpers.graph_endpoint.to_s.sub(TRAILING_SLASHES, '')
      next "#{base}#{path}" if !beta || BETA_SUFFIX.match?(base)

      unless V1_SUFFIX.match?(base)
        fail_job!('This action calls the Microsoft Graph beta API, so the Graph API endpoint of the connection ' \
                  "must end in /v1.0 or /beta. '#{base}' does not.")
      end

      "#{base.sub(V1_SUFFIX, BETA_PATH)}#{path}"
    end

    helper :guid_input do |value, label|
      id = value.to_s.strip
      fail_job!("#{label} '#{id}' is not a valid id (a GUID).") unless GUID_PATTERN.match?(id)

      id
    end

    helper :entra_device_input do |value|
      id = helpers.guid_input(value, 'Entra device ID')
      fail_job!("Entra device ID '#{id}' means that the device has no Microsoft Entra ID record.") if id == EMPTY_GUID

      id
    end

    helper :device_command do |device_id, command, permission, body: nil, beta: false|
      id = helpers.guid_input(device_id, 'Intune device ID')
      helpers.graph_request(:post, "/deviceManagement/managedDevices/#{id}/#{command}", permission,
                            beta: beta, body: body, not_found_hint: INTUNE_DEVICE_NOT_FOUND_HINT)
      id
    end

    helper :graph_request do |method, path, permission, beta: false, body: nil, params: nil,
                              expected: [NO_CONTENT_STATUS], not_found_hint: nil|
      url = helpers.graph_url(path, beta: beta)
      response = case method
                 when :get then http_get(url, params)
                 when :delete then http_delete(url)
                 when :post then http_post(url, body&.to_json, JSON_HEADERS)
                 else raise IPaaS::Error, "Unsupported Microsoft Graph method '#{method}'"
                 end
      helpers.checked_graph_response(response, permission, expected: expected, not_found_hint: not_found_hint)
    end

    helper :checked_graph_response do |response, permission, expected: [OK_STATUS], not_found_hint: nil|
      backoff_if_needed(response, api_name: 'Microsoft')
      next response if expected.include?(response.status)

      failure = helpers.describe_graph_failure(response, permission)
      failure = "#{failure} #{not_found_hint}" if not_found_hint && response.status == NOT_FOUND_STATUS
      fail_job!(failure)
    end

    helper :graph_error do |response|
      error = parse_json_object_or_empty(response.body.to_s)['error']
      error.is_a?(Hash) ? error : {}
    end

    helper :graph_failure_text do |status, error, fallback|
      message = error['message'].to_s
      wrapped = parse_json_object_or_empty(message)['Message']
      wrapped = nil unless wrapped.is_a?(String)
      "Microsoft Graph returned HTTP #{status} #{error['code']}: #{wrapped.presence || message.presence || fallback}"
    end

    helper :describe_graph_failure do |response, permission|
      text = helpers.graph_failure_text(response.status, helpers.graph_error(response),
                                        response.body.to_s.presence || 'no response body')
      next text unless response.status == FORBIDDEN_STATUS

      "#{text} Permission this action needs: #{permission}. Admin consent is required."
    end

    helper :graph_entity do |response|
      body = parse_json_response(response.body.to_s, error_message: NOT_JSON_MESSAGE)
      entity = body.is_a?(Hash) && body.key?('value') ? body['value'] : body
      fail_job!('Microsoft Graph returned a value that is not an object.') unless entity.is_a?(Hash)

      entity
    end

    helper :graph_list do |response|
      page = parse_json_response(response.body.to_s, error_message: NOT_JSON_MESSAGE)
      unless page.is_a?(Hash) && page['value'].is_a?(Array)
        fail_job!('Microsoft Graph returned a list with no value array.')
      end

      page
    end

    helper :snake_case_keys do |hash|
      hash.transform_keys { |key| key.to_s.underscore }
    end

    helper :review_elevation do |request_id, decision, justification|
      id = helpers.guid_input(request_id, 'Elevation request ID')
      body = { reviewerJustification: justification.to_s.strip }
      response = helpers.graph_request(:post, "/deviceManagement/elevationRequests/#{id}/#{decision}",
                                       ELEVATION_PERMISSION, beta: true, body: body, expected: [OK_STATUS])
      request = helpers.graph_entity(response)
      helpers.snake_case_keys(request).merge(
        'elevation_request_id' => id,
        'application_detail' => helpers.snake_case_keys(request['applicationDetail'].presence || {})
      )
    end

    helper :local_admin_password do |encoded|
      decoded = Base64.strict_decode64(encoded.to_s)
      next make_secret_string(decoded) unless decoded.bytes.include?(0)

      make_secret_string(helpers.utf16le_text(decoded.bytes))
    rescue ArgumentError
      fail_job!('Microsoft Graph returned a local administrator password that is not Base64.')
    end

    helper :utf16le_text do |bytes|
      units = bytes.each_slice(2).map { |low, high| low + (high.to_i * BYTE_VALUES) }
      complete = units.size * 2 == bytes.size
      # rubocop:disable-next Style/ComparableBetween
      unless complete && units.none? { |unit| unit >= FIRST_SURROGATE && unit <= LAST_SURROGATE }
        fail_job!('The local administrator password has characters that this action cannot decode.')
      end

      units.map { |unit| CHARACTER_FORMAT % unit }.join
    end

    helper :volume_type_name do |value|
      name = value.to_s.presence
      VOLUME_TYPE_NAMES.fetch(name, name)
    end

    helper :newest_os_volume_key_id do |device_id|
      os_keys = helpers.device_recovery_keys(device_id).select do |key|
        key.is_a?(Hash) && helpers.volume_type_name(key['volumeType']) == OS_VOLUME_TYPE
      end
      # rubocop:disable-next Style/RedundantSort
      newest = os_keys.sort_by { |key| key['createdDateTime'].to_s }.last
      unless newest.is_a?(Hash)
        fail_job!('Microsoft Entra ID holds no BitLocker recovery key for the operating system drive of ' \
                  "Entra device #{device_id}. The ID may be the Intune device ID instead of the Entra device ID.")
      end

      newest['id']
    end

    helper :device_recovery_keys do |device_id|
      page = helpers.graph_list(helpers.graph_request(:get, BITLOCKER_KEYS_PATH, BITLOCKER_PERMISSION,
                                                      params: { '$filter': "deviceId eq '#{device_id}'" },
                                                      expected: [OK_STATUS],
                                                      not_found_hint: ENTRA_DEVICE_NOT_FOUND_HINT))
      keys = page['value']
      (BITLOCKER_KEY_PAGE_LIMIT - 1).times do
        next_link = helpers.trusted_next_link(page['@odata.nextLink'])
        break if next_link.blank?

        page = helpers.graph_list(helpers.checked_graph_response(http_get(next_link, nil), BITLOCKER_PERMISSION))
        keys += page['value']
      end
      if page['@odata.nextLink'].present?
        fail_job!("Microsoft Graph returned more than #{BITLOCKER_KEY_PAGE_LIMIT} pages of BitLocker recovery keys " \
                  "for Entra device #{device_id}. Give the recovery key ID instead.")
      end

      keys
    end
  end
end
