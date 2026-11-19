class MsEntraConnector < IPaaS::Connector::Definition
  DEVICE_ODATA_TYPE = '#microsoft.graph.device'.freeze

  JSON_HEADERS           = { 'Content-Type' => 'application/json' }.freeze
  ADVANCED_QUERY_HEADERS = { 'ConsistencyLevel' => 'eventual' }.freeze
  GUID_PATTERN           = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  DOT_SEGMENTS           = %w[. ..].freeze
  DOLLAR_PREFIX          = '$'.freeze
  DEFAULT_PAGE_SIZE      = 100
  MAX_PAGE_SIZE          = 999
  SEARCH_QUOTE           = '"'.freeze
  OK_STATUS              = 200
  CREATED_STATUS         = 201
  NO_CONTENT_STATUS      = 204
  BAD_REQUEST_STATUS     = 400
  FORBIDDEN_STATUS       = 403
  NOT_FOUND_STATUS       = 404
  DEFAULT_SERVER_ERROR_STATUSES = [503].freeze

  USER_SELECT = 'id,displayName,givenName,surname,userPrincipalName,mail,jobTitle,department,officeLocation,' \
                'mobilePhone,businessPhones,accountEnabled,usageLocation,employeeId,companyName,city,country,' \
                'createdDateTime'.freeze
  DEFAULT_USER_FIELDS = [
    :user_id, :display_name, :given_name, :surname, :user_principal_name, :mail, :job_title, :office_location,
    :mobile_phone, :business_phones,
  ].freeze
  USER_ODATA_TYPE = '#microsoft.graph.user'.freeze
  GROUP_SELECT = 'id,displayName,description,mailNickname,mail,mailEnabled,securityEnabled,groupTypes,' \
                 'visibility,isAssignableToRole,createdDateTime'.freeze
  LICENSE_SELECT = 'id,assignedLicenses,licenseAssignmentStates'.freeze

  USER_READ_PERMISSION        = 'User.Read.All'.freeze
  USER_WRITE_PERMISSION       = 'User.ReadWrite.All'.freeze
  USER_UPDATE_PERMISSION      = 'User.ReadWrite.All (Account enabled also needs User.EnableDisableAccount.All, ' \
                                'and phone numbers also need User-Phone.ReadWrite.All)'.freeze
  LICENSE_WRITE_PERMISSION    = 'LicenseAssignment.ReadWrite.All'.freeze
  REVOKE_PERMISSION           = 'User.RevokeSessions.All'.freeze
  GROUP_READ_PERMISSION       = 'Group.Read.All'.freeze
  GROUP_WRITE_PERMISSION      = 'Group.ReadWrite.All'.freeze
  MEMBER_READ_PERMISSION      = 'GroupMember.Read.All'.freeze
  MEMBER_WRITE_PERMISSION     = 'GroupMember.ReadWrite.All (a group that can be assigned to a role also needs ' \
                                'RoleManagement.ReadWrite.Directory)'.freeze
  MEMBER_ADD_PERMISSION       = 'GroupMember.ReadWrite.All (adding a device also needs Device.ReadWrite.All, and ' \
                                'a group that can be assigned to a role also needs ' \
                                'RoleManagement.ReadWrite.Directory)'.freeze
  GROUP_DELETE_PERMISSION     = 'Group.ReadWrite.All (a group that can be assigned to a role also needs ' \
                                'RoleManagement.ReadWrite.Directory, unless the app owns the group)'.freeze
  SUBSCRIPTION_PERMISSION     = 'User.Read.All for the user triggers and Group.Read.All for the group triggers'.freeze
  GENERIC_PERMISSION          = "the one that this endpoint's Microsoft Graph page lists".freeze
  USER_CREATE_PERMISSION      = 'User.Create'.freeze
  USER_RESTORE_PERMISSION     = 'User.DeleteRestore.All (restoring a user who holds a privileged administrator ' \
                                'role also needs User.ReadWrite.All and an administrator role on the app)'.freeze
  PASSWORD_RESET_PERMISSION   = 'User-PasswordProfile.ReadWrite.All (the app also needs at least the User ' \
                                'Administrator role in Microsoft Entra)'.freeze
  TAP_PERMISSION              = 'UserAuthMethod-TAP.ReadWrite.All'.freeze
  METHOD_READ_PERMISSION      = 'UserAuthenticationMethod.Read.All'.freeze
  METHOD_WRITE_PERMISSION     = 'UserAuthenticationMethod.ReadWrite.All'.freeze
  INVITE_PERMISSION           = 'User.Invite.All'.freeze
  APP_ASSIGN_PERMISSION       = 'AppRoleAssignment.ReadWrite.All and Application.Read.All'.freeze
  APP_UNASSIGN_PERMISSION     = 'AppRoleAssignment.ReadWrite.All'.freeze
  ENTITLEMENT_PERMISSION      = 'EntitlementManagement.ReadWrite.All'.freeze
  ROLE_PERMISSION             = 'RoleManagement.ReadWrite.Directory'.freeze
  ROLE_ELIGIBILITY_PERMISSION = 'RoleEligibilitySchedule.ReadWrite.Directory'.freeze
  RISKY_USER_PERMISSION       = 'IdentityRiskyUser.ReadWrite.All (the tenant also needs a Microsoft Entra ID P2 ' \
                                'license)'.freeze

  MIN_TAP_LIFETIME_MINUTES = 10
  MAX_TAP_LIFETIME_MINUTES = 43_200
  TAP_REPLY_HIDDEN         = 'the reply is not shown because it can hold the Temporary Access Pass'.freeze
  PASSWORD_METHOD_TYPE     = '#microsoft.graph.passwordAuthenticationMethod'.freeze
  EXTERNAL_METHOD_TYPE     = '#microsoft.graph.externalAuthenticationMethod'.freeze
  AUTH_METHOD_PATHS        = {
    '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' => 'microsoftAuthenticatorMethods',
    '#microsoft.graph.phoneAuthenticationMethod' => 'phoneMethods',
    '#microsoft.graph.fido2AuthenticationMethod' => 'fido2Methods',
    '#microsoft.graph.softwareOathAuthenticationMethod' => 'softwareOathMethods',
    '#microsoft.graph.emailAuthenticationMethod' => 'emailMethods',
    '#microsoft.graph.temporaryAccessPassAuthenticationMethod' => 'temporaryAccessPassMethods',
    '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod' => 'windowsHelloForBusinessMethods',
    '#microsoft.graph.platformCredentialAuthenticationMethod' => 'platformCredentialMethods',
    '#microsoft.graph.externalAuthenticationMethod' => 'externalAuthenticationMethods',
    '#microsoft.graph.resourceAccountKeyAuthenticationMethod' => 'resourceAccountKeyAuthenticationMethods',
  }.freeze
  ALREADY_REFERENCE_CODE   = 'Request_BadRequest'.freeze
  ALREADY_OWNER_MESSAGE    = /added object references already exists? for the following modified properties: 'owners'/
  ALREADY_MEMBER_MESSAGE   = /added object references already exists? for the following modified properties: 'members'/
  FAILED_REQUEST_STATUSES  = %w[Canceled Denied Failed Revoked].freeze
  DEFAULT_APP_ROLE_ID      = '00000000-0000-0000-0000-000000000000'.freeze
  TENANT_SCOPE             = '/'.freeze
  ADMIN_ADD_REQUEST        = 'adminAdd'.freeze
  ADMIN_ASSIGN_ACTION      = 'adminAssign'.freeze
  NO_EXPIRATION            = 'noExpiration'.freeze
  AFTER_DATE_TIME          = 'afterDateTime'.freeze

  UPDATE_USER_FIELDS = {
    display_name: 'displayName', given_name: 'givenName', surname: 'surname', job_title: 'jobTitle',
    department: 'department', office_location: 'officeLocation', company_name: 'companyName',
    employee_id: 'employeeId', employee_type: 'employeeType', mobile_phone: 'mobilePhone', city: 'city',
    state: 'state', country: 'country', street_address: 'streetAddress', postal_code: 'postalCode',
    usage_location: 'usageLocation', preferred_language: 'preferredLanguage',
    user_principal_name: 'userPrincipalName', mail_nickname: 'mailNickname',
  }.freeze
  UPDATE_GROUP_FIELDS = {
    display_name: 'displayName', description: 'description', mail_nickname: 'mailNickname',
    visibility: 'visibility',
  }.freeze

  SECURITY_GROUP           = 'Security'.freeze
  MICROSOFT_365_GROUP      = 'Microsoft 365'.freeze
  GROUP_TYPES              = ['Security', 'Microsoft 365'].freeze
  UNIFIED_GROUP_TYPE       = 'Unified'.freeze
  GROUP_VISIBILITIES       = %w[Private Public HiddenMembership].freeze
  MAX_GROUP_CREATE_BINDS   = 20
  MEMBER_TYPE_CASTS        = {
    'All' => '', 'Users' => '/microsoft.graph.user', 'Groups' => '/microsoft.graph.group',
    'Devices' => '/microsoft.graph.device',
  }.freeze
  DEFAULT_MEMBER_TYPE      = 'All'.freeze

  GRAPH_SCOPE_PATH         = '/.default'.freeze
  GLOBAL_GRAPH_HOST        = 'graph.microsoft.com'.freeze
  NATIONAL_GRAPH_HOSTS     = %w[graph.microsoft.us dod-graph.microsoft.us microsoftgraph.chinacloudapi.cn].freeze
  GENERIC_METHODS          = %w[GET POST PATCH PUT DELETE].freeze
  GENERIC_RETRIED_METHODS  = %w[GET DELETE].freeze
  GENERIC_PATH_REFUSED     = %r{\A//|\.\.|://|\\|#|\s|%2e|%2f|%5c}i
  MIN_ERROR_STATUS         = 400

  SUBSCRIPTION_PATH                 = '/subscriptions'.freeze
  BATCH_PATH                        = '/$batch'.freeze
  SUBSCRIPTIONS_STORE_KEY           = 'subscriptions'.freeze
  WATCH_KEYS                        = %w[resource change_type endpoint].freeze
  REPORTED_STORE_PREFIX             = 'reported:'.freeze
  LIFECYCLE_EVENT_KEY               = 'lifecycleEvent'.freeze
  MEMBERS_DELTA_KEY                 = 'members@delta'.freeze
  REMOVED_KEY                       = '@removed'.freeze
  UPDATED_CHANGE_TYPE               = 'updated'.freeze
  DELETED_CHANGE_TYPE               = 'deleted'.freeze
  USERS_RESOURCE                    = 'users'.freeze
  GROUPS_RESOURCE                   = 'groups'.freeze
  MAX_SUBSCRIPTION_LIFETIME_MINUTES = 41_760
  CLOCK_SKEW_MARGIN_MINUTES         = 30
  RENEWAL_WINDOW_MINUTES            = 1440
  MAX_SUBSCRIPTION_LIST_REQUESTS    = 10
  BATCH_REQUEST_LIMIT               = 20
  SUBSCRIPTION_CREATED_STATUSES     = [200, 201].freeze
  OUTCOME_CREATED                   = 'created'.freeze
  OUTCOME_RENEWED                   = 'renewed'.freeze
  OUTCOME_REMOVED                   = 'removed'.freeze
  OUTCOME_SKIPPED                   = 'skipped'.freeze
  OUTCOME_FAILED                    = 'failed'.freeze
  TRANSIENT_SERVER_ERROR_STATUSES   = [500, 502, 503, 504].freeze
  ROW_CHANGED_WHILE_ANSWERING       = 'The trigger changed while Microsoft was answering, so nothing was stored.'.freeze
  NOTHING_RECORDED                  = 'No trigger records a subscription on this connection. A trigger records ' \
                                      'one when its runbook is deployed.'.freeze

  VALIDATION_TOKEN_PARAM      = 'validationToken'.freeze
  VALIDATION_ECHO_PREFIX      = 'graph-validation:'.freeze
  VALIDATION_CONTENT_TYPE     = 'text/plain'.freeze
  NO_SNIFF                    = 'nosniff'.freeze
  MAX_VALIDATION_TOKEN_LENGTH = 1024
  GRAPH_RETRY_PREFIX          = 'graph-retry:'.freeze
  GRAPH_RETRY_STATUS          = 503
  URL_POSTFIX_REFUSED         = 'Microsoft Entra triggers take no URL postfix. Microsoft sends its notifications to ' \
                                'one address per trigger, so leave URL postfix empty.'.freeze

  NEW_OBJECT_WINDOW_MINUTES       = 60
  CREATED_LOOKUP_BATCH            = 15
  CREATED_LOOKUP_DEADLINE_SECONDS = 2.0
  UNSEEN_RETRY_MINUTES            = 5
  CREATED_LOOKUP_SELECT           = 'id,createdDateTime'.freeze
  DELETED_LOOKUP_SELECT           = 'id'.freeze
  DELETED_ITEMS_PATHS             = { '/users' => '/directory/deletedItems/microsoft.graph.user',
                                      '/groups' => '/directory/deletedItems/microsoft.graph.group', }.freeze
  UNSEEN_STORE_PREFIX             = 'unseen:'.freeze
  OBJECT_NOT_FOUND_CODE           = 'Request_ResourceNotFound'.freeze
  MIN_LOOKUP_SECONDS              = 1.0
  LOOKUP_OPEN_TIMEOUT_SECONDS     = 0.5

  connector '01a1c8aa-ffe0-76a6-a459-1d2b527671c4' do
    name 'Microsoft Entra'
    avatar '/assets/icons/microsoft-entra.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Connects to [Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/) via the [Microsoft Graph API](https://learn.microsoft.com/en-us/graph/) to create, manage and restore users, set their managers, reset their passwords and sign-in methods, invite guests, manage licenses, groups and group members, app assignments, access packages and directory roles, mark user risk, and to start workflows when users, groups or group members change. Intune managed devices are in the **Microsoft Intune** connector.

      ## Prerequisites
      - A Microsoft Entra ID (formerly Azure AD) tenant.
      - An app registration in Microsoft Entra. Obtain:
        - **Tenant ID**: GUID visible in **Microsoft Entra → Overview → Tenant ID**.
        - **Client ID**: visible on the app registration's **Overview** page.
        - **Client Secret**: created under the app registration's **Certificates & secrets**. Copy the value at creation time; it is not shown again.
      - API permissions granted on the app registration (type: Application), with admin consent. Grant only the ones for the actions and triggers you use:
        - `Device.Read.All`: lets **Retrieve Entra group members** return the `device_id` of members that are devices. Without it, Microsoft Graph returns a device member with its ID and type only, its `device_id` is empty, and the job fails with `Not all devices have deviceId`.
        - `GroupMember.Read.All`: used by the group lookup and group members actions.
        - `User.Read.All`: used by **Get Entra user**, **Search Entra users**, **Get Entra user licenses**, **Restore deleted Entra user** and the user triggers.
        - `User.ReadWrite.All`: used by **Update Entra user**, **Delete Entra user** and **Set Entra user manager**. **Account enabled** also needs `User.EnableDisableAccount.All`, and phone numbers also need `User-Phone.ReadWrite.All`.
        - `User.Create`: used by **Create Entra user**. `User.ReadWrite.All` also works.
        - `User.DeleteRestore.All`: used by **Restore deleted Entra user**. Restoring a user who holds a privileged administrator role also needs `User.ReadWrite.All` and an administrator role on the app.
        - `LicenseAssignment.ReadWrite.All`: used by **Assign or remove Entra user licenses**.
        - `User.RevokeSessions.All`: used by **Revoke Entra user sign-in sessions**.
        - `Group.Read.All`: used by **Get Entra group by ID** and the group triggers.
        - `Group.ReadWrite.All`: used by **Create Entra group**, **Update Entra group**, **Delete Entra group** and **Add Entra group owner**.
        - `GroupMember.ReadWrite.All`: used by **Add member to Entra group** and **Remove member from Entra group**. **Remove member from Entra group** also reads the group after a 404, which Microsoft lists under `GroupMember.Read.All`.
        - `Device.ReadWrite.All`: used by **Add member to Entra group** when the member is a device.
        - `User-PasswordProfile.ReadWrite.All`: used by **Reset Entra user password**. The app also needs at least the **User Administrator** role in Microsoft Entra.
        - `UserAuthMethod-TAP.ReadWrite.All`: used by **Issue Entra Temporary Access Pass**.
        - `UserAuthenticationMethod.Read.All`: used by **List Entra user authentication methods**.
        - `UserAuthenticationMethod.ReadWrite.All`: used by **Remove Entra user authentication method**.
        - `User.Invite.All`: used by **Invite Entra guest user**.
        - `AppRoleAssignment.ReadWrite.All`: used by **Assign Entra enterprise app to user**, which also needs `Application.Read.All`, and by **Remove Entra enterprise app assignment**.
        - `EntitlementManagement.ReadWrite.All`: used by **Request Entra access package assignment**.
        - `RoleManagement.ReadWrite.Directory`: used by **Assign Entra directory role** and **Remove Entra directory role assignment**. **Delete Entra group**, **Add member to Entra group** and **Remove member from Entra group** also need it when the group can be assigned to a role.
        - `RoleEligibilitySchedule.ReadWrite.Directory`: used by **Create Entra PIM eligible role assignment**.
        - `IdentityRiskyUser.ReadWrite.All`: used by **Confirm Entra user compromised** and **Dismiss Entra user risk**. These need a Microsoft Entra ID P2 license.
        - The transitive group members action uses `GroupMember.Read.All`. **Call Microsoft Graph** uses whatever its endpoint needs.
      - **Warning**: `RoleManagement.ReadWrite.Directory`, `RoleEligibilitySchedule.ReadWrite.Directory`, `AppRoleAssignment.ReadWrite.All` and `EntitlementManagement.ReadWrite.All` let the app give itself, or anyone, more access: any directory role, any Microsoft Graph permission, or any access package. `UserAuthMethod-TAP.ReadWrite.All` and `UserAuthenticationMethod.ReadWrite.All` let the app sign in as any user or change how a user signs in. Grant them only when you use the actions that need them.
      - Licenses: **Create Entra PIM eligible role assignment** needs Microsoft Entra ID P2 or Microsoft Entra ID Governance. **Request Entra access package assignment** needs Microsoft Entra ID P2 or Microsoft Entra ID Governance for the users it assigns. Assigning a group with **Assign Entra enterprise app to user** needs Microsoft Entra ID P1 or P2, and members of groups inside that group get no access.

      ## Authentication
      The connector uses the OAuth 2.0 client credentials flow against `https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token` and requests the `https://graph.microsoft.com/.default` scope. The Tenant ID, Client ID, and Client Secret obtained in **Prerequisites** are passed as:
      - `tenant_id`: substituted into the OAuth2 token endpoint URL.
      - `client_id` and `client_secret`: sent in the token request body as form-encoded credentials.

      ## Best Practices
      - **Resolve IDs at runbook start**: Call **Entra group ID from name** to convert friendly group names into IDs. Don't hard-code GUIDs that may change.
      - **Paginate to completion**: **Retrieve Entra group members**, **Search Entra users** and **Search transitive Entra group members** are iterator actions. Call until `has_next_page` is `false`.
      - **Scope permissions minimally**: Grant only the permissions that the actions and triggers you use list. Don't grant broader scopes.
      - **Keep subscriptions alive**: Run **Renew directory subscriptions** every 15 minutes in its own runbook whenever a trigger of this connector is deployed.
      - **Check before you create again**: **Create Entra user** does not retry when Microsoft answers with a server error, because the user may exist. Call **Get Entra user** with the user principal name before you run it again.
      - **Remove sign-in methods one at a time**: **Remove Entra user authentication method** removes one method. Loop over the `methods` of **List Entra user authentication methods** and pass each `method_id` and `odata_type`. Skip `#microsoft.graph.passwordAuthenticationMethod` and `#microsoft.graph.qrCodePinAuthenticationMethod`, which this action cannot remove.
      - **Prefer eligible administrator roles**: **Create Entra PIM eligible role assignment** gives a role that the user turns on only when needed. Keep **Assign Entra directory role** for roles that must stay active.
      - **Keep privileged IDs fixed**: Set the role definition ID and directory scope of **Assign Entra directory role** and **Create Entra PIM eligible role assignment**, the enterprise application ID and app role ID of **Assign Entra enterprise app to user**, and the access package ID and policy ID of **Request Entra access package assignment**, as fixed values in the runbook. Do not map them from what a requester typed.
      - **Check for role-assignable groups**: A member of a group that can be assigned to a role gets the roles of the group, Global Administrator included. When the connection holds `RoleManagement.ReadWrite.Directory`, **Add member to Entra group** can add a requester to such a group. Before you add a requester, call **Get Entra group by ID** and stop when `is_assignable_to_role` is `true`. An owner of such a group can add members to it, so do the same check before **Add Entra group owner**. Keep the directory role actions on an app registration of their own, so that the app registration behind **Add member to Entra group** does not hold that permission.

      ## Common Use Cases
      - **Group-based access workflows**: **Entra group ID from name** → **Retrieve Entra group members** → provision or revoke Xurrent access based on membership changes.
      - **User onboarding**: **New Entra user** → **Get Entra user** → **Update Entra user** (usage location) → **Assign or remove Entra user licenses** → **Add member to Entra group**.
      - **User offboarding**: **Update Entra user** (account enabled `false`) → **Revoke Entra user sign-in sessions** → **Remove member from Entra group** → **Delete Entra user**.
      - **New hire from a Xurrent request**: **Create Entra user** (usage location set) → **Set Entra user manager** → **Assign or remove Entra user licenses** → **Add member to Entra group**.
      - **Rehire within 30 days**: **Restore deleted Entra user** → **Update Entra user** (account enabled `true`, new job title) → **Set Entra user manager**.
      - **Lost phone**: **List Entra user authentication methods** → **Remove Entra user authentication method** (the lost phone) → **Issue Entra Temporary Access Pass** so the user can register a new one.
      - **Compromised account**: **Confirm Entra user compromised** → **Revoke Entra user sign-in sessions** → **Reset Entra user password** → **Dismiss Entra user risk** when the incident is closed.
      - **Guest access**: **Invite Entra guest user** → **Add member to Entra group** or **Assign Entra enterprise app to user**.
      - **Access requests**: **Request Entra access package assignment** for a bundle of access, or **Assign Entra enterprise app to user** for one application. **Remove Entra enterprise app assignment** takes it back.
      - **Administrator access**: **Create Entra PIM eligible role assignment**, or **Assign Entra directory role** and later **Remove Entra directory role assignment**.

      ## References

      ### API Reference
      - [Microsoft Graph REST API (v1.0)](https://learn.microsoft.com/en-us/graph/api/overview)
      - [List groups (Microsoft Graph API)](https://learn.microsoft.com/en-us/graph/api/group-list)
      - [List group members (Microsoft Graph API)](https://learn.microsoft.com/en-us/graph/api/group-list-members)
      - [user resource type](https://learn.microsoft.com/en-us/graph/api/resources/user)
      - [group resource type](https://learn.microsoft.com/en-us/graph/api/resources/group)
      - [subscription resource type](https://learn.microsoft.com/en-us/graph/api/resources/subscription)
      - [Change notifications overview](https://learn.microsoft.com/en-us/graph/api/resources/change-notifications-api-overview)

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
        body[:scope] = helpers.graph_scope
        request.headers['Authorization'] = oauth2_authorization_header(helpers.oauth_endpoint, body)
      end
    end

    action '01a1c8aa-ffe0-70f2-b55a-767990afbe4d' do
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

    action '01a1c8aa-ffe0-7c3d-8164-4d89d5ef57db' do
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
        | `device_id` | String | Entra device ID (the AAD-side `deviceId`). Populated only when the member is a device. Distinct from the Intune managed-device ID returned by **Managed devices from Intune** in the **Microsoft Intune** connector. |
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

    action '01a1a1c8-debd-74ef-8177-c76b3080d857' do
      name 'Get Entra user'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Reads one Microsoft Entra user by object ID or user principal name through Microsoft Graph's [get user API](https://learn.microsoft.com/en-us/graph/api/user-get).

        **Use case**: look up a user's name, job details, account status and usage location before you update, license or remove them.

        **Permissions required**: `User.Read.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_id | String | Yes | - | Object ID (GUID) or user principal name of the user |

        ### Example Input

        ```json
        { "user_id": "adele.vance@contoso.com" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `user` | Object | The user. See **User object fields** below. |

        #### User object fields

        | Field Name | Type | Description |
        |---|---|---|
        | `user_id` | String | Object ID (GUID) |
        | `display_name` | String | Display name |
        | `given_name` | String | First name |
        | `surname` | String | Last name |
        | `user_principal_name` | String | User principal name (sign-in name) |
        | `mail` | String | Primary SMTP address |
        | `job_title` | String | Job title |
        | `department` | String | Department |
        | `office_location` | String | Office location |
        | `mobile_phone` | String | Mobile phone number |
        | `business_phones` | String[] | Business phone numbers |
        | `account_enabled` | Boolean | `true` when the account can sign in |
        | `usage_location` | String | Two-letter country code. Required before a license can be assigned. |
        | `employee_id` | String | Employee ID |
        | `company_name` | String | Company name |
        | `city` | String | City |
        | `country` | String | Country or region |
        | `created_date_time` | DateTime | When the user was created |

        ### Example Output

        ```json
        {
          "user": {
            "user_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd",
            "display_name": "Adele Vance",
            "user_principal_name": "adele.vance@contoso.com",
            "account_enabled": true,
            "usage_location": "US"
          }
        }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'User ID or user principal name', :string, required: true
      end

      output_schema do
        field :user, 'User', :nested, required: true do
          field :user_id, 'User ID', :string, required: true
          field :display_name, 'Display name', :string
          field :given_name, 'First name', :string
          field :surname, 'Last name', :string
          field :user_principal_name, 'User principal name', :string
          field :mail, 'Mail', :string
          field :job_title, 'Job title', :string
          field :department, 'Department', :string
          field :office_location, 'Office location', :string
          field :mobile_phone, 'Mobile phone', :string
          field :business_phones, 'Business phones', :string, array: true
          field :account_enabled, 'Account enabled', :boolean
          field :usage_location, 'Usage location', :string
          field :employee_id, 'Employee ID', :string
          field :company_name, 'Company name', :string
          field :city, 'City', :string
          field :country, 'Country or region', :string
          field :created_date_time, 'Created date time', :date_time
        end
      end

      run do
        path = helpers.user_path(input[:user_id])
        user = helpers.graph_object(path, USER_READ_PERMISSION, { '$select': USER_SELECT })
        [{ output: { user: helpers.user_summary(user) } }]
      end
    end

    action '01a1a1c8-debd-79fc-b010-425e03d4e3bd' do
      name 'Search Entra users'
      avatar '/assets/icons/microsoft-entra.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Lists Microsoft Entra users that match a filter or a display name search, one page at a time, through Microsoft Graph's [list users API](https://learn.microsoft.com/en-us/graph/api/user-list).

        **Use case**: find the users of a department, the disabled accounts, or a user whose name you know only in part.

        **Permissions required**: `User.Read.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | filter | String | No | - | OData filter, for example `department eq 'Sales'` or `accountEnabled eq false` |
        | search | String | No | - | Text to look for in the display name |
        | page_size | Integer | No | 100 | Number of users per page (1-999) |

        ### Example Input

        ```json
        { "filter": "department eq 'Sales'", "search": "adele", "page_size": 50 }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `odata_count` | Integer | Total users that match |
        | `has_next_page` | Boolean | `true` while more pages remain. Re-invoke the action until `false`. |
        | `users` | Object[] | One object per user, with the same fields as **Get Entra user** |

        ### Example Output

        ```json
        {
          "odata_count": 1,
          "has_next_page": false,
          "users": [{ "user_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd", "display_name": "Adele Vance" }]
        }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 responses. A 400 usually means the filter uses a property or operator that Microsoft Graph does not support. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Operational notes
        - Leave both **Filter** and **Search** empty to list every user.
        - Paginate to completion: call until `has_next_page` is `false`.
        - Microsoft Graph can take a short time to show users that were just created, updated or deleted.
      END_OF_DESCRIPTION

      input_schema do
        field :filter, 'Filter', :string,
              hint: "OData filter, for example department eq 'Sales'."
        field :search, 'Search display name', :string
        field :page_size, 'Page size', :integer,
              min: 1, max: MAX_PAGE_SIZE,
              visibility: 'optional',
              default: DEFAULT_PAGE_SIZE
      end

      output_schema 'page' do
        field :odata_count, 'OData count', :integer
        field :has_next_page, 'Has next page', :boolean, required: true
        field :users, 'Users', :nested, array: true do
          field :user_id, 'User ID', :string, required: true
          field :display_name, 'Display name', :string
          field :given_name, 'First name', :string
          field :surname, 'Last name', :string
          field :user_principal_name, 'User principal name', :string
          field :mail, 'Mail', :string
          field :job_title, 'Job title', :string
          field :department, 'Department', :string
          field :office_location, 'Office location', :string
          field :mobile_phone, 'Mobile phone', :string
          field :business_phones, 'Business phones', :string, array: true
          field :account_enabled, 'Account enabled', :boolean
          field :usage_location, 'Usage location', :string
          field :employee_id, 'Employee ID', :string
          field :company_name, 'Company name', :string
          field :city, 'City', :string
          field :country, 'Country or region', :string
          field :created_date_time, 'Created date time', :date_time
        end
      end

      iteration_state_schema do
        field :odata_nextLink, 'OData next link', :string, required: true
      end

      run do
        params = { '$select': USER_SELECT, '$top': helpers.page_size_param(input[:page_size]), '$count': 'true' }
        params[:$filter] = input[:filter].to_s.strip if input[:filter].present?
        params[:$search] = helpers.display_name_search(input[:search]) if input[:search].present?
        page = helpers.graph_page('/users', params, USER_READ_PERMISSION, ADVANCED_QUERY_HEADERS)
        helpers.build_graph_page(page, :users, page[:value].map { |user| helpers.user_summary(user) })
      end
    end

    action '01a1a1c8-debd-7527-bc54-6cfcdee8df58' do
      name 'Update Entra user'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Changes the properties of one Microsoft Entra user through Microsoft Graph's [update user API](https://learn.microsoft.com/en-us/graph/api/user-update). Only the fields you set are sent. An empty field leaves the property as it is.

        **Use case**: keep a user's job title, department, office and account status in step with Xurrent, or block sign-in for a leaver.

        **Permissions required**: `User.ReadWrite.All`. **Account enabled** also needs `User.EnableDisableAccount.All`, and **Mobile phone** and **Business phone** also need `User-Phone.ReadWrite.All`. Changing the account status or phone of an administrator also needs an administrator role on the app.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_id | String | Yes | - | Object ID (GUID) or user principal name of the user |
        | display_name | String | No | - | Display name |
        | given_name | String | No | - | First name |
        | surname | String | No | - | Last name |
        | job_title | String | No | - | Job title |
        | department | String | No | - | Department |
        | office_location | String | No | - | Office location |
        | company_name | String | No | - | Company name (up to 64 characters) |
        | employee_id | String | No | - | Employee ID (up to 16 characters) |
        | employee_type | String | No | - | Employee type, for example `Employee` or `Contractor` |
        | mobile_phone | String | No | - | Mobile phone number |
        | business_phone | String | No | - | Business phone number. Microsoft Entra keeps one. |
        | city | String | No | - | City |
        | state | String | No | - | State or province |
        | country | String | No | - | Country or region |
        | street_address | String | No | - | Street address |
        | postal_code | String | No | - | Postal code |
        | usage_location | String | No | - | Two-letter country code (ISO 3166). Required before a license can be assigned. |
        | preferred_language | String | No | - | Preferred language, for example `en-US` |
        | user_principal_name | String | No | - | New user principal name |
        | mail_nickname | String | No | - | Mail alias |
        | account_enabled | Boolean | No | - | `false` blocks sign-in, `true` allows it |

        ### Example Input

        ```json
        { "user_id": "adele.vance@contoso.com", "job_title": "Sales Lead", "account_enabled": true }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `user_id` | String | The user that was updated, as given. After a rename of a user given by user principal name, the new user principal name |
        | `updated_fields` | String[] | The Microsoft Graph properties that were sent |

        ### Example Output

        ```json
        { "user_id": "adele.vance@contoso.com", "updated_fields": ["jobTitle", "accountEnabled"] }
        ```

        ### Error Handling
        The job fails when no field is set. It fails without retry on 400 / 401 / 403 / 404 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The password cannot be changed with this action.
        - A field cannot be cleared: an empty field is not sent.
        - Properties of users synchronized from on-premises Active Directory may be read only.
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'User ID or user principal name', :string, required: true
        field :display_name, 'Display name', :string
        field :given_name, 'First name', :string
        field :surname, 'Last name', :string
        field :job_title, 'Job title', :string
        field :department, 'Department', :string
        field :office_location, 'Office location', :string
        field :company_name, 'Company name', :string, max_length: 64
        field :employee_id, 'Employee ID', :string, max_length: 16
        field :employee_type, 'Employee type', :string
        field :mobile_phone, 'Mobile phone', :string
        field :business_phone, 'Business phone', :string
        field :city, 'City', :string
        field :state, 'State or province', :string
        field :country, 'Country or region', :string
        field :street_address, 'Street address', :string
        field :postal_code, 'Postal code', :string
        field :usage_location, 'Usage location', :string,
              hint: 'Two-letter country code, such as US. Required before a license can be assigned.'
        field :preferred_language, 'Preferred language', :string
        field :user_principal_name, 'New user principal name', :string
        field :mail_nickname, 'Mail alias', :string
        field :account_enabled, 'Account enabled', :boolean
      end

      output_schema do
        field :user_id, 'User ID', :string, required: true
        field :updated_fields, 'Updated fields', :string, array: true
      end

      run do
        path = helpers.user_path(input[:user_id])
        body = helpers.changed_fields(input, UPDATE_USER_FIELDS)
        body['businessPhones'] = [input[:business_phone].to_s.strip] if input[:business_phone].present?
        enabled = helpers.boolean_input(input[:account_enabled])
        body['accountEnabled'] = enabled unless enabled.nil?
        fail_job!('Set at least one field to update.') if body.empty?

        helpers.graph_request(:patch, path, USER_UPDATE_PERMISSION, body: body, expected: [NO_CONTENT_STATUS])
        given = input[:user_id].to_s.strip
        renamed = body['userPrincipalName'] unless GUID_PATTERN.match?(given)
        [{ output: { user_id: renamed || given, updated_fields: body.keys } }]
      end
    end

    action '01a1a1c8-debd-71ed-a4ea-6f92cb341908' do
      name 'Delete Entra user'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Deletes one Microsoft Entra user through Microsoft Graph's [delete user API](https://learn.microsoft.com/en-us/graph/api/user-delete). Microsoft keeps a deleted user for 30 days, with its mailbox, licenses and group memberships, and an administrator can restore it in that time. After 30 days the user is deleted permanently.

        **Use case**: remove the account of a leaver at the end of an offboarding workflow.

        **Permissions required**: `User.ReadWrite.All`. Deleting a user who holds an administrator role also needs an administrator role on the app.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_id | String | Yes | - | Object ID (GUID) or user principal name of the user |

        ### Example Input

        ```json
        { "user_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `user_id` | String | The user, as given |
        | `existed` | Boolean | `false` when Microsoft Graph had no such user, so nothing was deleted |

        ### Example Output

        ```json
        { "user_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd", "existed": true }
        ```

        ### Error Handling
        A 404 is not an error: `existed` is `false`. The job fails without retry on 400 / 401 / 403 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Microsoft Graph can take about 30 seconds to show a user that was just created or restored. In that time it answers 404, so `existed` is `false` and nothing is deleted. When the user was created or restored a moment before, wait about 30 seconds and run the step again.
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'User ID or user principal name', :string, required: true
      end

      output_schema do
        field :user_id, 'User ID', :string, required: true
        field :existed, 'Existed', :boolean, required: true
      end

      run do
        path = helpers.user_path(input[:user_id])
        response = helpers.graph_request(:delete, path, USER_WRITE_PERMISSION,
                                         expected: [NO_CONTENT_STATUS, NOT_FOUND_STATUS])
        [{ output: { user_id: input[:user_id].to_s.strip, existed: response.status != NOT_FOUND_STATUS } }]
      end
    end

    action '01a1a1c8-debd-7d34-8ad6-5318d41eb50c' do
      name 'Get Entra user licenses'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Reads the licenses of one Microsoft Entra user from the user's `assignedLicenses` and `licenseAssignmentStates` properties through Microsoft Graph's [get user API](https://learn.microsoft.com/en-us/graph/api/user-get).

        **Use case**: check which licenses a user holds, and whether each one came from a group, before you assign or remove one.

        **Permissions required**: `User.Read.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_id | String | Yes | - | Object ID (GUID) or user principal name of the user |

        ### Example Input

        ```json
        { "user_id": "adele.vance@contoso.com" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `user_id` | String | Object ID of the user |
        | `assigned_licenses` | Object[] | Every license the user holds, direct or from a group: `sku_id` and `disabled_plans` |
        | `license_assignment_states` | Object[] | One row per assignment: `sku_id`, `state` (for example `Active` or `Error`), `error`, `assigned_by_group` (empty for a direct assignment) and `disabled_plans` |

        ### Example Output

        ```json
        {
          "user_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd",
          "assigned_licenses": [{ "sku_id": "c7df2760-2c81-4ef7-b578-5b5392b571df", "disabled_plans": [] }],
          "license_assignment_states": [
            { "sku_id": "c7df2760-2c81-4ef7-b578-5b5392b571df", "state": "Active", "error": "None", "assigned_by_group": null, "disabled_plans": [] }
          ]
        }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'User ID or user principal name', :string, required: true
      end

      output_schema do
        field :user_id, 'User ID', :string, required: true
        field :assigned_licenses, 'Assigned licenses', :nested, array: true do
          field :sku_id, 'SKU ID', :string, required: true
          field :disabled_plans, 'Disabled plans', :string, array: true
        end
        field :license_assignment_states, 'License assignment states', :nested, array: true do
          field :sku_id, 'SKU ID', :string
          field :state, 'State', :string
          field :error, 'Error', :string
          field :assigned_by_group, 'Assigned by group', :string
          field :disabled_plans, 'Disabled plans', :string, array: true
        end
      end

      run do
        path = helpers.user_path(input[:user_id])
        user = helpers.graph_object(path, USER_READ_PERMISSION, { '$select': LICENSE_SELECT })
        [{ output: helpers.license_summary(user) }]
      end
    end

    action '01a1a1c8-debd-7648-a5aa-39879582ac3f' do
      name 'Assign or remove Entra user licenses'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Adds licenses to, and removes licenses from, one Microsoft Entra user in one request through Microsoft Graph's [assign license API](https://learn.microsoft.com/en-us/graph/api/user-assignlicense).

        **Use case**: give a new hire their licenses, or take the licenses of a leaver back.

        **Permissions required**: `LicenseAssignment.ReadWrite.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_id | String | Yes | - | Object ID (GUID) or user principal name of the user |
        | add_sku_ids | String[] | No | - | SKU IDs (GUIDs) of the licenses to add |
        | disabled_plan_ids | String[] | No | - | Service plan IDs (GUIDs) to turn off in every license that is added |
        | remove_sku_ids | String[] | No | - | SKU IDs (GUIDs) of the licenses to remove |

        ### Example Input

        ```json
        { "user_id": "adele.vance@contoso.com", "add_sku_ids": ["c7df2760-2c81-4ef7-b578-5b5392b571df"], "remove_sku_ids": [] }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `user_id` | String | Object ID of the user |
        | `added_sku_ids` | String[] | The SKU IDs that were added |
        | `removed_sku_ids` | String[] | The SKU IDs that were removed |

        ### Example Output

        ```json
        { "user_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd", "added_sku_ids": ["c7df2760-2c81-4ef7-b578-5b5392b571df"], "removed_sku_ids": [] }
        ```

        ### Error Handling
        The job fails when neither list holds a SKU ID, or when a value is not a GUID. It fails without retry on 400 / 401 / 403 / 404 responses. A 400 often means the user has no **Usage location**: set it with **Update Entra user** first. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Operational notes
        - A license that a group gives cannot be removed from the user directly. Remove the user from the group instead.
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'User ID or user principal name', :string, required: true
        field :add_sku_ids, 'SKU IDs to add', :string, array: true
        field :disabled_plan_ids, 'Service plan IDs to turn off', :string, array: true,
                                                                           visibility: 'optional'
        field :remove_sku_ids, 'SKU IDs to remove', :string, array: true
      end

      output_schema do
        field :user_id, 'User ID', :string, required: true
        field :added_sku_ids, 'Added SKU IDs', :string, array: true
        field :removed_sku_ids, 'Removed SKU IDs', :string, array: true
      end

      run do
        path = "#{helpers.user_path(input[:user_id])}/assignLicense"
        add = helpers.guid_list(input[:add_sku_ids], 'SKU ID to add')
        remove = helpers.guid_list(input[:remove_sku_ids], 'SKU ID to remove')
        disabled = helpers.guid_list(input[:disabled_plan_ids], 'Service plan ID')
        fail_job!('Set at least one SKU ID to add or to remove.') if add.empty? && remove.empty?

        body = { addLicenses: add.map { |sku_id| { skuId: sku_id, disabledPlans: disabled } }, removeLicenses: remove }
        user = helpers.graph_json(helpers.graph_request(:post, path, LICENSE_WRITE_PERMISSION, body: body))
        [{ output: { user_id: user['id'].presence || input[:user_id].to_s.strip, added_sku_ids: add,
                     removed_sku_ids: remove, } }]
      end
    end

    action '01a1a1c8-debd-7957-8f3e-8d470af6b22f' do
      name 'Revoke Entra user sign-in sessions'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Signs one Microsoft Entra user out of every application through Microsoft Graph's [revoke sign-in sessions API](https://learn.microsoft.com/en-us/graph/api/user-revokesigninsessions). Every refresh token and browser session cookie of the user stops working, so the user must sign in again.

        **Use case**: lock a leaver or a compromised account out at once, together with **Update Entra user** setting **Account enabled** to `false`.

        **Permissions required**: `User.RevokeSessions.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_id | String | Yes | - | Object ID (GUID) or user principal name of the user |

        ### Example Input

        ```json
        { "user_id": "adele.vance@contoso.com" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `user_id` | String | The user, as given |
        | `revoked` | Boolean | `true` when Microsoft accepted the request |

        ### Example Output

        ```json
        { "user_id": "adele.vance@contoso.com", "revoked": true }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Microsoft can take a few minutes to revoke the tokens.
        - External (guest) users are not signed out, because they sign in through their home tenant.
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'User ID or user principal name', :string, required: true
      end

      output_schema do
        field :user_id, 'User ID', :string, required: true
        field :revoked, 'Revoked', :boolean, required: true
      end

      run do
        path = "#{helpers.user_path(input[:user_id])}/revokeSignInSessions"
        response = helpers.graph_request(:post, path, REVOKE_PERMISSION)
        [{ output: { user_id: input[:user_id].to_s.strip, revoked: helpers.graph_json(response)['value'] == true } }]
      end
    end

    action '01a1c8f4-ea61-7511-b944-fe8b9c8e17d2' do
      name 'Create Entra user'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Creates one Microsoft Entra user with a first password through Microsoft Graph's [create user API](https://learn.microsoft.com/en-us/graph/api/user-post-users). Of the optional profile fields, only the ones you set are sent.

        **Use case**: create the account of a new hire from a Xurrent request, before you give it a manager, licenses and groups.

        **Permissions required**: `User.Create`. `User.ReadWrite.All` also works.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | display_name | String | Yes | - | Display name |
        | user_principal_name | String | Yes | - | Sign-in name, `alias@domain`. The domain must be a verified domain of the tenant. |
        | mail_nickname | String | Yes | - | Mail alias |
        | password | Secret String | Yes | - | First password. It must meet the password rules of the tenant. |
        | force_change_password_next_sign_in | Boolean | No | true | `true` makes the user choose a new password at the first sign-in |
        | account_enabled | Boolean | No | true | `false` creates the account with sign-in blocked |
        | given_name | String | No | - | First name |
        | surname | String | No | - | Last name |
        | job_title | String | No | - | Job title |
        | department | String | No | - | Department |
        | office_location | String | No | - | Office location |
        | company_name | String | No | - | Company name (up to 64 characters) |
        | employee_id | String | No | - | Employee ID (up to 16 characters) |
        | employee_type | String | No | - | Employee type, for example `Employee` or `Contractor` |
        | city | String | No | - | City |
        | state | String | No | - | State or province |
        | country | String | No | - | Country or region |
        | street_address | String | No | - | Street address |
        | postal_code | String | No | - | Postal code |
        | usage_location | String | No | - | Two-letter country code (ISO 3166). Required before a license can be assigned. |
        | preferred_language | String | No | - | Preferred language, for example `en-US` |

        ### Example Input

        ```json
        { "display_name": "Adele Vance", "user_principal_name": "adele.vance@contoso.com", "mail_nickname": "adele.vance", "password": "<secret>", "usage_location": "US" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `user` | Object | The new user, with the fields that Microsoft returns when it creates a user: `user_id`, `display_name`, `given_name`, `surname`, `user_principal_name`, `mail`, `job_title`, `office_location`, `mobile_phone` and `business_phones`. Read the other fields with **Get Entra user**. |

        ### Example Output

        ```json
        { "user": { "user_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd", "display_name": "Adele Vance", "user_principal_name": "adele.vance@contoso.com" } }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 responses, and on 5xx responses: Microsoft may have created the user before it failed, so check for it with **Get Entra user** before you run the step again. A 403 gives Microsoft's reason and names the permission the action needs. On 429, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The password is not part of the output.
        - Phone numbers are not set by this action. Set them with **Update Entra user** after the user is created.
      END_OF_DESCRIPTION

      input_schema do
        field :display_name, 'Display name', :string, required: true
        field :user_principal_name, 'User principal name', :string, required: true,
                                                                    hint: 'alias@domain, with a verified domain'
        field :mail_nickname, 'Mail alias', :string, required: true
        field :password, 'Password', :secret_string, required: true
        field :force_change_password_next_sign_in, 'Change password at first sign-in', :boolean, default: true
        field :account_enabled, 'Account enabled', :boolean, default: true
        field :given_name, 'First name', :string
        field :surname, 'Last name', :string
        field :job_title, 'Job title', :string
        field :department, 'Department', :string
        field :office_location, 'Office location', :string
        field :company_name, 'Company name', :string, max_length: 64
        field :employee_id, 'Employee ID', :string, max_length: 16
        field :employee_type, 'Employee type', :string
        field :city, 'City', :string
        field :state, 'State or province', :string
        field :country, 'Country or region', :string
        field :street_address, 'Street address', :string
        field :postal_code, 'Postal code', :string
        field :usage_location, 'Usage location', :string,
              hint: 'Two-letter country code, such as US. Required before a license can be assigned.'
        field :preferred_language, 'Preferred language', :string
      end

      output_schema do
        field :user, 'User', :nested, required: true do
          field :user_id, 'User ID', :string, required: true
          field :display_name, 'Display name', :string
          field :given_name, 'First name', :string
          field :surname, 'Last name', :string
          field :user_principal_name, 'User principal name', :string
          field :mail, 'Mail', :string
          field :job_title, 'Job title', :string
          field :office_location, 'Office location', :string
          field :mobile_phone, 'Mobile phone', :string
          field :business_phones, 'Business phones', :string, array: true
        end
      end

      run do
        body = helpers.changed_fields(input, UPDATE_USER_FIELDS)
        body['accountEnabled'] = helpers.boolean_input(input[:account_enabled]) != false
        body['passwordProfile'] = helpers.password_profile(input[:password], input[:force_change_password_next_sign_in])

        response = helpers.graph_request(:post, '/users', USER_CREATE_PERMISSION,
                                         body: body, expected: [CREATED_STATUS], server_error_statuses: [])
        [{ output: { user: helpers.default_user_summary(helpers.graph_json(response)) } }]
      end
    end

    action '01a1c8f4-ead7-7cb5-9e09-43e37ab37a39' do
      name 'Set Entra user manager'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Sets the manager of one Microsoft Entra user through Microsoft Graph's [assign manager API](https://learn.microsoft.com/en-us/graph/api/user-post-manager). A user has one manager, so this replaces the current one.

        **Use case**: put a new hire under the right manager, or move a user to a new manager after a team change in Xurrent.

        **Permissions required**: `User.ReadWrite.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_id | String | Yes | - | Object ID (GUID) or user principal name of the user |
        | manager_id | String | Yes | - | Object ID (GUID) of the manager: a user or an organizational contact |

        ### Example Input

        ```json
        { "user_id": "adele.vance@contoso.com", "manager_id": "6ea91a8d-e32e-41a1-b7bd-d2d185eed0e0" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `user_id` | String | The user, as given |
        | `manager_id` | String | Object ID of the manager |

        ### Example Output

        ```json
        { "user_id": "adele.vance@contoso.com", "manager_id": "6ea91a8d-e32e-41a1-b7bd-d2d185eed0e0" }
        ```

        ### Error Handling
        The job fails when the manager ID is not a GUID. It fails without retry on 400 / 401 / 403 / 404 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'User ID or user principal name', :string, required: true
        field :manager_id, 'Manager ID', :string, required: true
      end

      output_schema do
        field :user_id, 'User ID', :string, required: true
        field :manager_id, 'Manager ID', :string, required: true
      end

      run do
        path = "#{helpers.user_path(input[:user_id])}/manager/$ref"
        manager_id = helpers.guid_input(input[:manager_id], 'Manager ID')
        body = { '@odata.id' => helpers.directory_object_ref(manager_id) }
        helpers.graph_request(:put, path, USER_WRITE_PERMISSION, body: body, expected: [NO_CONTENT_STATUS])
        [{ output: { user_id: input[:user_id].to_s.strip, manager_id: manager_id } }]
      end
    end

    action '01a1c8f4-eb48-7ece-bfbe-8fb53da0c7fe' do
      name 'Restore deleted Entra user'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Restores one deleted Microsoft Entra user through Microsoft Graph's [restore deleted item API](https://learn.microsoft.com/en-us/graph/api/directory-deleteditems-restore). Microsoft keeps a deleted user for 30 days. After 30 days the user is deleted permanently and cannot be restored. The action restores the ID only when it is a deleted user. When the ID is an active user, for example because an earlier run restored it, the action returns that user with `already_restored` set to `true`.

        **Use case**: bring back the account of a user who was deleted by mistake, or of a leaver who returns within 30 days.

        **Permissions required**: `User.DeleteRestore.All` and `User.Read.All`. Restoring a user who holds a privileged administrator role also needs `User.ReadWrite.All` and an administrator role on the app.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_id | String | Yes | - | Object ID (GUID) of the deleted user |
        | new_user_principal_name | String | No | - | New user principal name for the restored user, for example when another user now has the old one |
        | auto_reconcile_proxy_conflict | Boolean | No | false | `true` removes the email addresses of the restored user that an active user now has, instead of failing |

        ### Example Input

        ```json
        { "user_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd", "auto_reconcile_proxy_conflict": true }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `user` | Object | The restored user, with the fields that Microsoft returns when it restores a user: `user_id`, `display_name`, `given_name`, `surname`, `user_principal_name`, `mail`, `job_title`, `office_location`, `mobile_phone` and `business_phones`. Read the other fields with **Get Entra user**. |
        | `already_restored` | Boolean | `true` when the ID was already an active user, so nothing was restored |

        ### Example Output

        ```json
        { "user": { "user_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd", "display_name": "Adele Vance", "user_principal_name": "adele.vance@contoso.com" }, "already_restored": false }
        ```

        ### Error Handling
        The job fails, and restores nothing, when the user ID is not a GUID, when the ID is a deleted object that is not a user, or when the ID is neither a deleted user nor an active user. It fails without retry on 400 / 401 / 403 / 404 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Microsoft Graph can take about 30 seconds to catch up after a user is deleted or restored. In that time the job can fail with a 404, such as `Unable to read the company information from the directory`. When the user was deleted or restored a moment before, wait about 30 seconds and run the step again.
        - Right after a delete, Microsoft Graph can still answer 404 when the action looks for the user in the deleted items, and still return the user as an active user. The action then returns `already_restored` set to `true` and restores nothing. Wait about 30 seconds after a delete before you restore the user.

        ### Operational notes
        - A deleted user is found by its object ID only. **New or updated Entra user** reports the ID of a user deleted in a way that can still be restored.
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'Deleted user ID', :string, required: true
        field :new_user_principal_name, 'New user principal name', :string, visibility: 'optional'
        field :auto_reconcile_proxy_conflict, 'Remove conflicting email addresses', :boolean,
              visibility: 'optional', default: false
      end

      output_schema do
        field :user, 'User', :nested, required: true do
          field :user_id, 'User ID', :string, required: true
          field :display_name, 'Display name', :string
          field :given_name, 'First name', :string
          field :surname, 'Last name', :string
          field :user_principal_name, 'User principal name', :string
          field :mail, 'Mail', :string
          field :job_title, 'Job title', :string
          field :office_location, 'Office location', :string
          field :mobile_phone, 'Mobile phone', :string
          field :business_phones, 'Business phones', :string, array: true
        end
        field :already_restored, 'Already restored', :boolean, required: true
      end

      run do
        user_id = helpers.guid_input(input[:user_id], 'Deleted user ID')
        deleted = helpers.graph_request(:get, "/directory/deletedItems/#{user_id}", USER_READ_PERMISSION,
                                        expected: [OK_STATUS, NOT_FOUND_STATUS])
        next helpers.active_user_output(user_id) if deleted.status == NOT_FOUND_STATUS

        deleted_type = helpers.graph_json(deleted)['@odata.type']
        unless deleted_type == USER_ODATA_TYPE
          fail_job!("Deleted item '#{user_id}' is #{deleted_type.presence || 'of no stated type'}, not " \
                    "#{USER_ODATA_TYPE}. Nothing was restored.")
        end

        new_name = input[:new_user_principal_name].to_s.strip
        body = {}
        body['newUserPrincipalName'] = new_name if new_name.present?
        body['autoReconcileProxyConflict'] = true if helpers.boolean_input(input[:auto_reconcile_proxy_conflict])

        response = helpers.graph_request(:post, "/directory/deletedItems/#{user_id}/restore", USER_RESTORE_PERMISSION,
                                         body: body.presence)
        [{ output: { user: helpers.default_user_summary(helpers.graph_json(response)), already_restored: false } }]
      end
    end

    action '01a1c904-3826-7215-b9e9-5462f1e399b6' do
      name 'Reset Entra user password'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Sets a new password for one Microsoft Entra user by changing the user's password profile through Microsoft Graph's [update user API](https://learn.microsoft.com/en-us/graph/api/user-update).

        **Use case**: give a locked-out user a new first password from a Xurrent request, or reset the password of a compromised account.

        **Permissions required**: `User-PasswordProfile.ReadWrite.All`, and the app must also hold at least the **User Administrator** role in Microsoft Entra. Resetting the password of an administrator needs a higher role.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_id | String | Yes | - | Object ID (GUID) or user principal name of the user |
        | password | Secret String | Yes | - | New password. It must meet the password rules of the tenant. |
        | force_change_password_next_sign_in | Boolean | No | true | `true` makes the user choose a new password at the next sign-in |

        ### Example Input

        ```json
        { "user_id": "adele.vance@contoso.com", "password": "<secret>", "force_change_password_next_sign_in": true }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `user_id` | String | The user, as given |
        | `force_change_password_next_sign_in` | Boolean | `true` when the user must choose a new password at the next sign-in |

        ### Example Output

        ```json
        { "user_id": "adele.vance@contoso.com", "force_change_password_next_sign_in": true }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses. A 403 gives Microsoft's reason and names the permission and role the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The password of a federated user cannot be reset with this action.
        - The password is not part of the output.
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'User ID or user principal name', :string, required: true
        field :password, 'New password', :secret_string, required: true
        field :force_change_password_next_sign_in, 'Change password at next sign-in', :boolean, default: true
      end

      output_schema do
        field :user_id, 'User ID', :string, required: true
        field :force_change_password_next_sign_in, 'Change password at next sign-in', :boolean, required: true
      end

      run do
        path = helpers.user_path(input[:user_id])
        profile = helpers.password_profile(input[:password], input[:force_change_password_next_sign_in])
        helpers.graph_request(:patch, path, PASSWORD_RESET_PERMISSION,
                              body: { 'passwordProfile' => profile }, expected: [NO_CONTENT_STATUS])
        [{ output: { user_id: input[:user_id].to_s.strip,
                     force_change_password_next_sign_in: profile['forceChangePasswordNextSignIn'], } }]
      end
    end

    action '01a1c904-3890-7851-9792-dcdecb1e77d3' do
      name 'Issue Entra Temporary Access Pass'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Creates a Temporary Access Pass for one Microsoft Entra user through Microsoft Graph's [create temporaryAccessPassMethod API](https://learn.microsoft.com/en-us/graph/api/authentication-post-temporaryaccesspassmethods). A Temporary Access Pass is a passcode with a time limit that the user signs in with, for example to set up a new phone or security key.

        **Use case**: let a user who lost their phone sign in to register a new authentication method, after the service desk has checked who they are.

        **Permissions required**: `UserAuthMethod-TAP.ReadWrite.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_id | String | Yes | - | Object ID (GUID) or user principal name of the user |
        | lifetime_in_minutes | Integer | No | - | How long the pass works, from 10 to 43200 minutes (30 days). Empty uses the default of the tenant's Temporary Access Pass policy. |
        | is_usable_once | Boolean | No | - | `true` makes the pass work for one sign-in only |
        | start_date_time | DateTime | No | - | When the pass starts to work |

        ### Example Input

        ```json
        { "user_id": "adele.vance@contoso.com", "lifetime_in_minutes": 60, "is_usable_once": true }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `method_id` | String | ID of the pass as an authentication method |
        | `temporary_access_pass` | Secret String | The passcode |
        | `start_date_time` | DateTime | When the pass starts to work |
        | `lifetime_in_minutes` | Integer | How long the pass works |
        | `is_usable_once` | Boolean | `true` when the pass works for one sign-in only |
        | `is_usable` | Boolean | `true` when the pass can be used now |
        | `method_usability_reason` | String | Why the pass can or cannot be used now, for example `NotYetValid` |
        | `created_date_time` | DateTime | When the pass was created |

        ### Example Output

        ```json
        { "method_id": "6f1967b7-15e8-4935-ac26-d50770ed07a7", "temporary_access_pass": "<secret>", "lifetime_in_minutes": 60, "is_usable_once": true, "is_usable": true, "method_usability_reason": "EnabledByPolicy" }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses, and on 5xx responses: Microsoft may have created the pass before it failed, so check for it with **List Entra user authentication methods** before you run the step again. A 403 gives Microsoft's reason and names the permission the action needs. On 429, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - A user can have only one Temporary Access Pass that is usable within its lifetime. A new pass deletes the current one, so running the step again makes a pass that was already handed out stop working.
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'User ID or user principal name', :string, required: true
        field :lifetime_in_minutes, 'Lifetime in minutes', :integer,
              min: MIN_TAP_LIFETIME_MINUTES, max: MAX_TAP_LIFETIME_MINUTES
        field :is_usable_once, 'Usable once', :boolean
        field :start_date_time, 'Start date time', :date_time, visibility: 'optional'
      end

      output_schema do
        field :method_id, 'Method ID', :string, required: true
        field :temporary_access_pass, 'Temporary Access Pass', :secret_string, required: true
        field :start_date_time, 'Start date time', :date_time
        field :lifetime_in_minutes, 'Lifetime in minutes', :integer
        field :is_usable_once, 'Usable once', :boolean
        field :is_usable, 'Usable', :boolean
        field :method_usability_reason, 'Usability reason', :string
        field :created_date_time, 'Created date time', :date_time
      end

      run do
        path = "#{helpers.user_path(input[:user_id])}/authentication/temporaryAccessPassMethods"
        body = {}
        body['lifetimeInMinutes'] = input[:lifetime_in_minutes].to_i if input[:lifetime_in_minutes].present?
        once = helpers.boolean_input(input[:is_usable_once])
        body['isUsableOnce'] = once unless once.nil?
        body['startDateTime'] = input[:start_date_time].iso8601 if input[:start_date_time].present?

        response = helpers.graph_request(:post, path, TAP_PERMISSION,
                                         body: body, expected: [CREATED_STATUS], server_error_statuses: [],
                                         failure_fallback: TAP_REPLY_HIDDEN)
        not_json = "Microsoft Graph returned a reply that is not JSON: #{TAP_REPLY_HIDDEN}."
        pass = parse_json_response(response.body.to_s, error_message: not_json)
        unless pass.is_a?(Hash) && pass['temporaryAccessPass'].present?
          raise IPaaS::Error, 'Microsoft Graph returned no Temporary Access Pass'
        end

        [{ output: {
          method_id: pass['id'], temporary_access_pass: make_secret_string(pass['temporaryAccessPass'].to_s),
          start_date_time: pass['startDateTime'], lifetime_in_minutes: pass['lifetimeInMinutes'],
          is_usable_once: pass['isUsableOnce'], is_usable: pass['isUsable'],
          method_usability_reason: pass['methodUsabilityReason'], created_date_time: pass['createdDateTime'],
        } }]
      end
    end

    action '01a1c904-3903-7545-ab54-e1c6d28bfc63' do
      name 'List Entra user authentication methods'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Lists the authentication methods that one Microsoft Entra user has registered, such as Microsoft Authenticator, phone numbers, security keys and Windows Hello for Business, through Microsoft Graph's [list methods API](https://learn.microsoft.com/en-us/graph/api/authentication-list-methods).

        **Use case**: see what a user has set up before you remove a lost phone or issue a Temporary Access Pass.

        **Permissions required**: `UserAuthenticationMethod.Read.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_id | String | Yes | - | Object ID (GUID) or user principal name of the user |

        ### Example Input

        ```json
        { "user_id": "adele.vance@contoso.com" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `methods` | Object[] | One object per method. See **Method object fields** below. |

        #### Method object fields

        | Field Name | Type | Description |
        |---|---|---|
        | `method_id` | String | ID of the method |
        | `odata_type` | String | Kind of method, for example `#microsoft.graph.phoneAuthenticationMethod`. **Remove Entra user authentication method** takes it as the method type. |
        | `display_name` | String | Name of the app, key or device, for Microsoft Authenticator, security keys and Windows Hello for Business |
        | `phone_number` | String | Phone number, for a phone method |
        | `phone_type` | String | `mobile`, `alternateMobile` or `office`, for a phone method |
        | `email_address` | String | Email address, for an email method |

        ### Example Output

        ```json
        { "methods": [{ "method_id": "3179e48a-750b-4051-897c-87b9720928f7", "odata_type": "#microsoft.graph.phoneAuthenticationMethod", "phone_number": "+1 5555551234", "phone_type": "mobile" }] }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Operational notes
        - The password is listed as a method too. It cannot be removed: change it with **Reset Entra user password**.
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'User ID or user principal name', :string, required: true
      end

      output_schema do
        field :methods, 'Methods', :nested, array: true do
          field :method_id, 'Method ID', :string, required: true
          field :odata_type, 'OData type', :string
          field :display_name, 'Display name', :string
          field :phone_number, 'Phone number', :string
          field :phone_type, 'Phone type', :string
          field :email_address, 'Email address', :string
        end
      end

      run do
        path = "#{helpers.user_path(input[:user_id])}/authentication/methods"
        listed = helpers.graph_object(path, METHOD_READ_PERMISSION, nil)['value']
        raise IPaaS::Error, 'Microsoft Graph returned no list of authentication methods' unless listed.is_a?(Array)

        methods = listed.map do |auth_method|
          { method_id: auth_method['id'], odata_type: auth_method['@odata.type'],
            display_name: auth_method['displayName'], phone_number: auth_method['phoneNumber'],
            phone_type: auth_method['phoneType'], email_address: auth_method['emailAddress'], }
        end
        [{ output: { methods: methods } }]
      end
    end

    action '01a1c904-396c-701c-8eb9-96b9b41ebbc6' do
      name 'Remove Entra user authentication method'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Removes one authentication method of one Microsoft Entra user, for example a lost phone, an old Microsoft Authenticator app or a security key. Microsoft Graph removes each kind of method through its own API, such as [delete phoneAuthenticationMethod](https://learn.microsoft.com/en-us/graph/api/phoneauthenticationmethod-delete), so the action takes the type of the method as well as its ID.

        **Use case**: remove a lost or stolen device from the sign-in methods of a user. To remove every method, loop over the list from **List Entra user authentication methods** and skip the password and QR code PIN methods.

        **Permissions required**: `UserAuthenticationMethod.ReadWrite.All`. For security keys (FIDO2), `UserAuthMethod-Passkey.ReadWrite.All` is enough.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_id | String | Yes | - | Object ID (GUID) or user principal name of the user |
        | method_id | String | Yes | - | `method_id` from **List Entra user authentication methods** |
        | method_type | String | Yes | - | `odata_type` from **List Entra user authentication methods**, for example `#microsoft.graph.microsoftAuthenticatorAuthenticationMethod` |

        ### Example Input

        ```json
        { "user_id": "adele.vance@contoso.com", "method_id": "3179e48a-750b-4051-897c-87b9720928f7", "method_type": "#microsoft.graph.phoneAuthenticationMethod" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `user_id` | String | The user, as given |
        | `method_id` | String | ID of the method |
        | `existed` | Boolean | `false` when the user had no such method, so nothing was removed |

        ### Example Output

        ```json
        { "user_id": "adele.vance@contoso.com", "method_id": "3179e48a-750b-4051-897c-87b9720928f7", "existed": true }
        ```

        ### Error Handling
        The job fails when the method type is the password or a type that this action does not know. A 404 is not an error: `existed` is `false`. The job fails without retry on 400 / 401 / 403 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - These types can be removed: Microsoft Authenticator, phone, FIDO2 security key, software OATH token, email, Temporary Access Pass, Windows Hello for Business, platform credential, external authentication method and resource account key.
        - `existed` is also `false` when the user does not exist.
        - The password cannot be removed. Change it with **Reset Entra user password**.
        - A QR code PIN method cannot be removed: Microsoft Graph offers that only in beta, at `/beta/users/{id}/authentication/qrCodePinMethod`. The job fails for that type, so a loop over the methods of a user stops there.
        - A phone number that is the default multifactor authentication method of the user cannot be removed.
        - A mobile number cannot be removed while the user has an alternate mobile number.
        - Microsoft Graph can take about 30 seconds to show a method that was just added, such as a new Temporary Access Pass. In that time it answers 404, so `existed` is `false` and nothing is removed. When the method was added a moment before, wait about 30 seconds and run the step again.
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'User ID or user principal name', :string, required: true
        field :method_id, 'Method ID', :string, required: true
        field :method_type, 'Method type', :string, required: true,
                                                    hint: 'odata_type from List Entra user authentication methods'
      end

      output_schema do
        field :user_id, 'User ID', :string, required: true
        field :method_id, 'Method ID', :string, required: true
        field :existed, 'Existed', :boolean, required: true
      end

      run do
        method_type = input[:method_type].to_s.strip
        if method_type == PASSWORD_METHOD_TYPE
          fail_job!('The password cannot be removed. Change it with Reset Entra user password.')
        end
        kind = AUTH_METHOD_PATHS.fetch(method_type) do
          fail_job!("Method type '#{method_type}' cannot be removed by this action. " \
                    "Use one of #{AUTH_METHOD_PATHS.keys.join(', ')}.")
        end
        method_id = helpers.graph_segment(input[:method_id], 'Method ID')
        reference = method_type == EXTERNAL_METHOD_TYPE ? '/$ref' : ''
        path = "#{helpers.user_path(input[:user_id])}/authentication/#{kind}/#{method_id}#{reference}"

        response = helpers.graph_request(:delete, path, METHOD_WRITE_PERMISSION,
                                         expected: [NO_CONTENT_STATUS, NOT_FOUND_STATUS])
        [{ output: { user_id: input[:user_id].to_s.strip, method_id: input[:method_id].to_s.strip,
                     existed: response.status != NOT_FOUND_STATUS, } }]
      end
    end

    action '01a1c904-3b1b-7c72-a388-e5932ade7ee9' do
      name 'Invite Entra guest user'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Invites one external person to the tenant as a guest user through Microsoft Graph's [create invitation API](https://learn.microsoft.com/en-us/graph/api/invitation-post). Microsoft creates the guest user at once, and the person redeems the invitation to sign in.

        **Use case**: give a partner or contractor access from a Xurrent request, then add the guest user to a group.

        **Permissions required**: `User.Invite.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | email_address | String | Yes | - | Email address of the person to invite |
        | redirect_url | String | Yes | - | Address the person lands on after redeeming the invitation, for example `https://myapps.microsoft.com` |
        | display_name | String | No | - | Display name of the guest user |
        | send_invitation_message | Boolean | No | false | `true` makes Microsoft send the invitation email |

        ### Example Input

        ```json
        { "email_address": "megan@fabrikam.com", "redirect_url": "https://myapps.microsoft.com", "display_name": "Megan Bowen", "send_invitation_message": true }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `invitation_id` | String | ID of the invitation |
        | `user_id` | String | Object ID of the guest user that Microsoft created |
        | `invite_redeem_url` | String | Address the person uses to redeem the invitation |
        | `status` | String | `PendingAcceptance`, `Completed`, `InProgress` or `Error` |
        | `invited_user_type` | String | Type of the new user, `Guest` by default |

        ### Example Output

        ```json
        { "invitation_id": "9071bfde-35e0-47d2-a582-d244ab1b4af6", "user_id": "cbb896f9-8306-49d0-b56b-b8e39cd28825", "status": "PendingAcceptance", "invited_user_type": "Guest" }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 responses, and on 5xx responses: Microsoft may have created the guest user before it failed, so check for it with **Search Entra users** before you run the step again. A 403 gives Microsoft's reason and names the permission the action needs. On 429, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - The action does not work when B2B invitations are turned off in the tenant.
      END_OF_DESCRIPTION

      input_schema do
        field :email_address, 'Email address', :string, required: true
        field :redirect_url, 'Redirect URL', :string, required: true, hint: 'For example https://myapps.microsoft.com'
        field :display_name, 'Display name', :string
        field :send_invitation_message, 'Send invitation email', :boolean, default: false
      end

      output_schema do
        field :invitation_id, 'Invitation ID', :string, required: true
        field :user_id, 'User ID', :string
        field :invite_redeem_url, 'Invitation redeem URL', :string
        field :status, 'Status', :string
        field :invited_user_type, 'Invited user type', :string
      end

      run do
        body = {
          invitedUserEmailAddress: input[:email_address].to_s.strip, inviteRedirectUrl: input[:redirect_url].to_s.strip,
          sendInvitationMessage: helpers.boolean_input(input[:send_invitation_message]) == true,
        }
        body[:invitedUserDisplayName] = input[:display_name].to_s.strip if input[:display_name].present?

        response = helpers.graph_request(:post, '/invitations', INVITE_PERMISSION,
                                         body: body, expected: [CREATED_STATUS], server_error_statuses: [])
        invitation = helpers.graph_json(response)
        invited_user = invitation['invitedUser'].is_a?(Hash) ? invitation['invitedUser'] : {}
        [{ output: { invitation_id: invitation['id'], user_id: invited_user['id'],
                     invite_redeem_url: invitation['inviteRedeemUrl'], status: invitation['status'],
                     invited_user_type: invitation['invitedUserType'], } }]
      end
    end

    action '01a1a1c8-debd-7155-9ff2-4b9f575c138e' do
      name 'Create Entra group'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Creates a Microsoft Entra security group or Microsoft 365 group through Microsoft Graph's [create group API](https://learn.microsoft.com/en-us/graph/api/group-post-groups), optionally with its owners and members.

        **Use case**: create the access group of a new project or team from a Xurrent request.

        **Permissions required**: `Group.ReadWrite.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | display_name | String | Yes | - | Group name (up to 256 characters) |
        | mail_nickname | String | Yes | - | Mail alias (up to 64 characters, no spaces or `@ ( ) \\ [ ] " ; : < > ,`) |
        | description | String | No | - | Group description |
        | group_type | String | No | Security | `Security` or `Microsoft 365` |
        | visibility | String | No | - | `Private`, `Public` or `HiddenMembership` |
        | owner_ids | String[] | No | - | Object IDs (GUIDs) of the owners |
        | member_ids | String[] | No | - | Object IDs (GUIDs) of the first members |

        ### Example Input

        ```json
        { "display_name": "Project Falcon", "mail_nickname": "project-falcon", "group_type": "Security", "owner_ids": ["87d349ed-44d7-43e1-9a83-5f2406dee5bd"] }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `group` | Object | The new group. See **Group object fields** below. |

        #### Group object fields

        | Field Name | Type | Description |
        |---|---|---|
        | `group_id` | String | Object ID (GUID) |
        | `display_name` | String | Group name |
        | `description` | String | Group description |
        | `mail_nickname` | String | Mail alias |
        | `mail` | String | Email address, for a mail-enabled group |
        | `mail_enabled` | Boolean | `true` for a Microsoft 365 group |
        | `security_enabled` | Boolean | `true` for a security group |
        | `group_types` | String[] | `Unified` for a Microsoft 365 group, `DynamicMembership` for a dynamic group |
        | `visibility` | String | `Private`, `Public` or `HiddenMembership` |
        | `is_assignable_to_role` | Boolean | `true` when the group can be assigned to a Microsoft Entra role, so its members get that role. Microsoft Graph leaves it empty for other groups. |
        | `created_date_time` | DateTime | When the group was created |

        ### Example Output

        ```json
        { "group": { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315", "display_name": "Project Falcon", "security_enabled": true } }
        ```

        ### Error Handling
        The job fails when owners and members together are more than 20, or when an ID is not a GUID. It fails without retry on 400 / 401 / 403 responses, and on 5xx responses: Microsoft may have created the group before it failed, so check for it with **Entra group ID from name** before you run the step again. A 403 gives Microsoft's reason and names the permission the action needs. On 429, the connector waits for the time in `Retry-After` and retries the request.

        ### Operational notes
        - Set at least one owner. Microsoft creates a group that has no owner anonymously, and that group cannot be changed afterwards.
        - Mail-enabled security groups and distribution groups cannot be created through Microsoft Graph.
      END_OF_DESCRIPTION

      input_schema do
        field :display_name, 'Display name', :string, required: true, max_length: 256
        field :mail_nickname, 'Mail alias', :string, required: true, max_length: 64
        field :description, 'Description', :string
        field :group_type, 'Group type', :string, enumeration: GROUP_TYPES, default: SECURITY_GROUP
        field :visibility, 'Visibility', :string, enumeration: GROUP_VISIBILITIES, visibility: 'optional'
        field :owner_ids, 'Owner IDs', :string, array: true
        field :member_ids, 'Member IDs', :string, array: true
      end

      output_schema do
        field :group, 'Group', :nested, required: true do
          field :group_id, 'Group ID', :string, required: true
          field :display_name, 'Display name', :string
          field :description, 'Description', :string
          field :mail_nickname, 'Mail alias', :string
          field :mail, 'Mail', :string
          field :mail_enabled, 'Mail enabled', :boolean
          field :security_enabled, 'Security enabled', :boolean
          field :group_types, 'Group types', :string, array: true
          field :visibility, 'Visibility', :string
          field :is_assignable_to_role, 'Assignable to role', :boolean
          field :created_date_time, 'Created date time', :date_time
        end
      end

      run do
        owners = helpers.guid_list(input[:owner_ids], 'Owner ID')
        members = helpers.guid_list(input[:member_ids], 'Member ID')
        if owners.length + members.length > MAX_GROUP_CREATE_BINDS
          fail_job!("A group can be created with at most #{MAX_GROUP_CREATE_BINDS} owners and members together. " \
                    'Add the others with Add member to Entra group.')
        end

        unified = input[:group_type].to_s == MICROSOFT_365_GROUP
        body = {
          displayName: input[:display_name].to_s.strip, mailNickname: input[:mail_nickname].to_s.strip,
          mailEnabled: unified, securityEnabled: !unified, groupTypes: unified ? [UNIFIED_GROUP_TYPE] : [],
        }
        body[:description] = input[:description].to_s.strip if input[:description].present?
        body[:visibility] = input[:visibility].to_s if input[:visibility].present?
        body['owners@odata.bind'] = owners.map { |id| helpers.directory_object_ref(id) } if owners.any?
        body['members@odata.bind'] = members.map { |id| helpers.directory_object_ref(id) } if members.any?

        response = helpers.graph_request(:post, '/groups', GROUP_WRITE_PERMISSION,
                                         body: body, expected: [CREATED_STATUS], server_error_statuses: [])
        [{ output: { group: helpers.group_summary(helpers.graph_json(response)) } }]
      end
    end

    action '01a1a1c8-debd-7bd0-a77f-f0ccf831d3ce' do
      name 'Update Entra group'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Changes the name, description, mail alias or visibility of one Microsoft Entra group through Microsoft Graph's [update group API](https://learn.microsoft.com/en-us/graph/api/group-update). Only the fields you set are sent.

        **Use case**: rename a group, or change its description, when the team or project it serves changes.

        **Permissions required**: `Group.ReadWrite.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | group_id | String | Yes | - | Object ID (GUID) of the group |
        | display_name | String | No | - | Group name |
        | description | String | No | - | Group description |
        | mail_nickname | String | No | - | Mail alias |
        | visibility | String | No | - | `Private`, `Public` or `HiddenMembership` |

        ### Example Input

        ```json
        { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315", "description": "Members of Project Falcon" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `group_id` | String | Object ID of the group |
        | `updated_fields` | String[] | The Microsoft Graph properties that were sent |

        ### Example Output

        ```json
        { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315", "updated_fields": ["description"] }
        ```

        ### Error Handling
        The job fails when no field is set, or when the group ID is not a GUID. It fails without retry on 400 / 401 / 403 / 404 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.
      END_OF_DESCRIPTION

      input_schema do
        field :group_id, 'Group ID', :string, required: true
        field :display_name, 'Display name', :string, max_length: 256
        field :description, 'Description', :string
        field :mail_nickname, 'Mail alias', :string, max_length: 64
        field :visibility, 'Visibility', :string, enumeration: GROUP_VISIBILITIES
      end

      output_schema do
        field :group_id, 'Group ID', :string, required: true
        field :updated_fields, 'Updated fields', :string, array: true
      end

      run do
        group_id = helpers.guid_input(input[:group_id], 'Group ID')
        body = helpers.changed_fields(input, UPDATE_GROUP_FIELDS)
        fail_job!('Set at least one field to update.') if body.empty?

        helpers.graph_request(:patch, "/groups/#{group_id}", GROUP_WRITE_PERMISSION,
                              body: body, expected: [NO_CONTENT_STATUS])
        [{ output: { group_id: group_id, updated_fields: body.keys } }]
      end
    end

    action '01a1a1c8-debd-7126-9e3b-d99a994d165a' do
      name 'Delete Entra group'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Deletes one Microsoft Entra group through Microsoft Graph's [delete group API](https://learn.microsoft.com/en-us/graph/api/group-delete). Microsoft 365 groups and security groups can be restored for 30 days and are then deleted permanently. Distribution groups are deleted permanently at once.

        **Use case**: remove the access group of a project that has ended.

        **Permissions required**: `Group.ReadWrite.All`. A group that can be assigned to a role also needs `RoleManagement.ReadWrite.Directory`, unless the app owns the group.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | group_id | String | Yes | - | Object ID (GUID) of the group |

        ### Example Input

        ```json
        { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `group_id` | String | Object ID of the group |
        | `existed` | Boolean | `false` when Microsoft Graph had no such group, so nothing was deleted |

        ### Example Output

        ```json
        { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315", "existed": true }
        ```

        ### Error Handling
        A 404 is not an error: `existed` is `false`. The job fails without retry on 400 / 401 / 403 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Microsoft Graph can take about 30 seconds to show a group that was just created or restored. In that time it answers 404, so `existed` is `false` and nothing is deleted. When the group was created or restored a moment before, wait about 30 seconds and run the step again.
      END_OF_DESCRIPTION

      input_schema do
        field :group_id, 'Group ID', :string, required: true
      end

      output_schema do
        field :group_id, 'Group ID', :string, required: true
        field :existed, 'Existed', :boolean, required: true
      end

      run do
        group_id = helpers.guid_input(input[:group_id], 'Group ID')
        response = helpers.graph_request(:delete, "/groups/#{group_id}", GROUP_DELETE_PERMISSION,
                                         expected: [NO_CONTENT_STATUS, NOT_FOUND_STATUS])
        [{ output: { group_id: group_id, existed: response.status != NOT_FOUND_STATUS } }]
      end
    end

    action '01a1a1c8-debd-7203-a795-ae91d9efe502' do
      name 'Get Entra group by ID'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Reads one Microsoft Entra group by object ID through Microsoft Graph's [get group API](https://learn.microsoft.com/en-us/graph/api/group-get).

        **Use case**: read a group's name, type and visibility before you change it or its members.

        **Permissions required**: `Group.Read.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | group_id | String | Yes | - | Object ID (GUID) of the group |

        ### Example Input

        ```json
        { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `group` | Object | The group, with the same fields as **Create Entra group** returns |

        ### Example Output

        ```json
        { "group": { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315", "display_name": "Project Falcon", "security_enabled": true } }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.
      END_OF_DESCRIPTION

      input_schema do
        field :group_id, 'Group ID', :string, required: true
      end

      output_schema do
        field :group, 'Group', :nested, required: true do
          field :group_id, 'Group ID', :string, required: true
          field :display_name, 'Display name', :string
          field :description, 'Description', :string
          field :mail_nickname, 'Mail alias', :string
          field :mail, 'Mail', :string
          field :mail_enabled, 'Mail enabled', :boolean
          field :security_enabled, 'Security enabled', :boolean
          field :group_types, 'Group types', :string, array: true
          field :visibility, 'Visibility', :string
          field :is_assignable_to_role, 'Assignable to role', :boolean
          field :created_date_time, 'Created date time', :date_time
        end
      end

      run do
        group_id = helpers.guid_input(input[:group_id], 'Group ID')
        group = helpers.graph_object("/groups/#{group_id}", GROUP_READ_PERMISSION, { '$select': GROUP_SELECT })
        [{ output: { group: helpers.group_summary(group) } }]
      end
    end

    action '01a1a1c8-debd-7138-b3bf-ca8fb41fd9b4' do
      name 'Add member to Entra group'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Adds one user, group, device or other directory object to a Microsoft Entra group through Microsoft Graph's [add members API](https://learn.microsoft.com/en-us/graph/api/group-post-members).

        **Use case**: give a user the access that comes with a group, for example when a Xurrent request is approved.

        **Permissions required**: `GroupMember.ReadWrite.All`. Adding a device also needs `Device.ReadWrite.All`. A group that can be assigned to a role also needs `RoleManagement.ReadWrite.Directory`.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | group_id | String | Yes | - | Object ID (GUID) of the group |
        | member_id | String | Yes | - | Object ID (GUID) of the user, group or device to add |

        ### Example Input

        ```json
        { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315", "member_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `group_id` | String | Object ID of the group |
        | `member_id` | String | Object ID of the member |
        | `already_member` | Boolean | `true` when the object was already a member, so nothing was added |

        ### Example Output

        ```json
        { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315", "member_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd", "already_member": false }
        ```

        ### Error Handling
        The job fails when an ID is not a GUID. A 400 that says the object is already a member is not an error: `already_member` is `true`, and the job log says that nothing changed. The job fails without retry on other 400 responses and on 401 / 403 / 404 responses. Microsoft Graph answers 404 when the object or the group does not exist. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - A Microsoft 365 group takes only users as members.
        - Members cannot be added to a group with dynamic membership.
      END_OF_DESCRIPTION

      input_schema do
        field :group_id, 'Group ID', :string, required: true
        field :member_id, 'Member ID', :string, required: true
      end

      output_schema do
        field :group_id, 'Group ID', :string, required: true
        field :member_id, 'Member ID', :string, required: true
        field :already_member, 'Already member', :boolean, required: true
      end

      run do
        group_id = helpers.guid_input(input[:group_id], 'Group ID')
        member_id = helpers.guid_input(input[:member_id], 'Member ID')
        response = helpers.graph_request(:post, "/groups/#{group_id}/members/$ref", MEMBER_ADD_PERMISSION,
                                         body: { '@odata.id' => helpers.directory_object_ref(member_id) },
                                         expected: [NO_CONTENT_STATUS, BAD_REQUEST_STATUS])
        already_member = helpers.already_reference_answer(response, ALREADY_MEMBER_MESSAGE)
        unless response.status == NO_CONTENT_STATUS || already_member
          fail_job!(helpers.describe_graph_failure(response, MEMBER_ADD_PERMISSION))
        end
        log("Object #{member_id} is already a member of group #{group_id}, so nothing changed.") if already_member

        [{ output: { group_id: group_id, member_id: member_id, already_member: already_member } }]
      end
    end

    action '01a1a1c8-debd-7799-a9de-11a0c8bb324e' do
      name 'Remove member from Entra group'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Removes one member from a Microsoft Entra group through Microsoft Graph's [remove member API](https://learn.microsoft.com/en-us/graph/api/group-delete-members). The member object itself is not deleted.

        **Use case**: take away the access that comes with a group when a user changes role or leaves.

        **Permissions required**: `GroupMember.ReadWrite.All`, and `GroupMember.Read.All`, which Microsoft lists for reading a group, to check the group after a 404. A group that can be assigned to a role also needs `RoleManagement.ReadWrite.Directory`.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | group_id | String | Yes | - | Object ID (GUID) of the group |
        | member_id | String | Yes | - | Object ID (GUID) of the member to remove |

        ### Example Input

        ```json
        { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315", "member_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `group_id` | String | Object ID of the group |
        | `member_id` | String | Object ID of the member |
        | `existed` | Boolean | `false` when the object was not a member of the group, so nothing was removed |

        ### Example Output

        ```json
        { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315", "member_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd", "existed": true }
        ```

        ### Error Handling
        On a 404, the action reads the group. When the group exists, `existed` is `false`: the object was not a direct member, or a delete that was sent again had already removed it. When Microsoft Graph has no group with that ID, the job fails. The job fails without retry on 400 / 401 / 403 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Members cannot be removed from a group with dynamic membership.
        - Only a direct member is removed. A member through a group inside this group keeps the access. Call **Search transitive Entra group members** to see who still gets it.
        - Microsoft Graph can take about 30 seconds to show a group that was just created. In that time the job fails with "Microsoft Graph has no group with ID". Run the step again after about 30 seconds.
        - Microsoft Graph can take about 30 seconds to show a member that was just added. In that time it answers 404, so `existed` is `false` and nothing is removed. When the member was added a moment before, wait about 30 seconds and run the step again.
      END_OF_DESCRIPTION

      input_schema do
        field :group_id, 'Group ID', :string, required: true
        field :member_id, 'Member ID', :string, required: true
      end

      output_schema do
        field :group_id, 'Group ID', :string, required: true
        field :member_id, 'Member ID', :string, required: true
        field :existed, 'Existed', :boolean, required: true
      end

      run do
        group_id = helpers.guid_input(input[:group_id], 'Group ID')
        member_id = helpers.guid_input(input[:member_id], 'Member ID')
        response = helpers.graph_request(:delete, "/groups/#{group_id}/members/#{member_id}/$ref",
                                         MEMBER_WRITE_PERMISSION, expected: [NO_CONTENT_STATUS, NOT_FOUND_STATUS])
        if response.status == NOT_FOUND_STATUS
          group_response = helpers.graph_request(:get, "/groups/#{group_id}", MEMBER_READ_PERMISSION,
                                                 params: { '$select': 'id' }, expected: [OK_STATUS, NOT_FOUND_STATUS])
          fail_job!("Microsoft Graph has no group with ID #{group_id}.") if group_response.status == NOT_FOUND_STATUS
        end

        [{ output: { group_id: group_id, member_id: member_id, existed: response.status != NOT_FOUND_STATUS } }]
      end
    end

    action '01a1c904-39d5-7f42-9276-6d9a336c442d' do
      name 'Add Entra group owner'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Adds one user or service principal as an owner of a Microsoft Entra group through Microsoft Graph's [add owners API](https://learn.microsoft.com/en-us/graph/api/group-post-owners).

        **Use case**: hand a group to the manager of a new team, or add a second owner so that the group keeps an owner when one leaves.

        **Permissions required**: `Group.ReadWrite.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | group_id | String | Yes | - | Object ID (GUID) of the group |
        | owner_id | String | Yes | - | Object ID (GUID) of the user or service principal to add as an owner |

        ### Example Input

        ```json
        { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315", "owner_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `group_id` | String | Object ID of the group |
        | `owner_id` | String | Object ID of the owner |
        | `already_owner` | Boolean | `true` when the object was already an owner, so nothing was added |

        ### Example Output

        ```json
        { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315", "owner_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd", "already_owner": false }
        ```

        ### Error Handling
        The job fails when an ID is not a GUID. A 400 that says the object is already an owner is not an error: `already_owner` is `true`. The job fails without retry on other 400 responses and on 401 / 403 / 404 responses. Microsoft Graph answers 404 when the object does not exist. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Microsoft Teams can take up to 2 hours to show a new owner of the group of a team.
      END_OF_DESCRIPTION

      input_schema do
        field :group_id, 'Group ID', :string, required: true
        field :owner_id, 'Owner ID', :string, required: true
      end

      output_schema do
        field :group_id, 'Group ID', :string, required: true
        field :owner_id, 'Owner ID', :string, required: true
        field :already_owner, 'Already owner', :boolean, required: true
      end

      run do
        group_id = helpers.guid_input(input[:group_id], 'Group ID')
        owner_id = helpers.guid_input(input[:owner_id], 'Owner ID')
        response = helpers.graph_request(:post, "/groups/#{group_id}/owners/$ref", GROUP_WRITE_PERMISSION,
                                         body: { '@odata.id' => helpers.directory_object_ref(owner_id) },
                                         expected: [NO_CONTENT_STATUS, BAD_REQUEST_STATUS])
        already_owner = helpers.already_reference_answer(response, ALREADY_OWNER_MESSAGE)
        unless response.status == NO_CONTENT_STATUS || already_owner
          fail_job!(helpers.describe_graph_failure(response, GROUP_WRITE_PERMISSION))
        end

        [{ output: { group_id: group_id, owner_id: owner_id, already_owner: already_owner } }]
      end
    end

    action '01a1a1c8-debd-792d-bd1a-c75b96378489' do
      name 'Search transitive Entra group members'
      avatar '/assets/icons/microsoft-entra.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Lists every member of a Microsoft Entra group, including the members of the groups inside it, one page at a time, through Microsoft Graph's [list transitive members API](https://learn.microsoft.com/en-us/graph/api/group-list-transitivemembers).

        **Use case**: find everyone who gets a group's access, also through nested groups, for an access review.

        **Permissions required**: `GroupMember.Read.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | group_id | String | Yes | - | Object ID (GUID) of the group |
        | member_type | String | No | All | `All`, `Users`, `Groups` or `Devices` |
        | search | String | No | - | Text to look for in the display name |
        | page_size | Integer | No | 100 | Number of members per page (1-999) |

        ### Example Input

        ```json
        { "group_id": "02bd9fd6-8f93-4758-87c3-1fb73740a315", "member_type": "Users", "page_size": 200 }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `odata_count` | Integer | Total members that match |
        | `has_next_page` | Boolean | `true` while more pages remain. Re-invoke the action until `false`. |
        | `members` | Object[] | One object per member: `member_id`, `odata_type` (for example `#microsoft.graph.user`), `display_name`, and for users `user_principal_name` and `mail` |

        ### Example Output

        ```json
        {
          "odata_count": 1,
          "has_next_page": false,
          "members": [{ "member_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd", "odata_type": "#microsoft.graph.user", "display_name": "Adele Vance" }]
        }
        ```

        ### Error Handling
        The job fails without retry on 400 / 401 / 403 / 404 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Operational notes
        - Paginate to completion: call until `has_next_page` is `false`.
        - Without permission to read a kind of member, Microsoft Graph returns those members with only their ID and type.
      END_OF_DESCRIPTION

      input_schema do
        field :group_id, 'Group ID', :string, required: true
        field :member_type, 'Member type', :string,
              enumeration: MEMBER_TYPE_CASTS.keys, default: DEFAULT_MEMBER_TYPE
        field :search, 'Search display name', :string
        field :page_size, 'Page size', :integer,
              min: 1, max: MAX_PAGE_SIZE,
              visibility: 'optional',
              default: DEFAULT_PAGE_SIZE
      end

      output_schema 'page' do
        field :odata_count, 'OData count', :integer
        field :has_next_page, 'Has next page', :boolean, required: true
        field :members, 'Members', :nested, array: true do
          field :member_id, 'Member ID', :string, required: true
          field :odata_type, 'OData type', :string
          field :display_name, 'Display name', :string
          field :user_principal_name, 'User principal name', :string
          field :mail, 'Mail', :string
        end
      end

      iteration_state_schema do
        field :odata_nextLink, 'OData next link', :string, required: true
      end

      run do
        group_id = helpers.guid_input(input[:group_id], 'Group ID')
        cast = MEMBER_TYPE_CASTS.fetch(input[:member_type].presence || DEFAULT_MEMBER_TYPE) do
          fail_job!("Member type must be one of #{MEMBER_TYPE_CASTS.keys.join(', ')}.")
        end
        params = { '$top': helpers.page_size_param(input[:page_size]), '$count': 'true' }
        params[:$search] = helpers.display_name_search(input[:search]) if input[:search].present?
        page = helpers.graph_page("/groups/#{group_id}/transitiveMembers#{cast}", params, MEMBER_READ_PERMISSION,
                                  ADVANCED_QUERY_HEADERS)
        cast_type = cast.sub('/', '#').presence
        members = page[:value].map { |member| helpers.member_summary(member, cast_type) }
        helpers.build_graph_page(page, :members, members)
      end
    end

    action '01a1c904-3a41-78b3-b0bf-d64f41edac41' do
      name 'Assign Entra enterprise app to user'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Assigns one user, security group or service principal to an enterprise application, with one of the app's roles, through Microsoft Graph's [grant appRoleAssignment API](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-post-approleassignedto).

        **Use case**: give a user access to an application that signs in through Microsoft Entra, when a Xurrent request is approved.

        **Permissions required**: `AppRoleAssignment.ReadWrite.All` and `Application.Read.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | service_principal_id | String | Yes | - | Object ID (GUID) of the enterprise application (its service principal) |
        | principal_id | String | Yes | - | Object ID (GUID) of the user, security group or service principal to assign |
        | app_role_id | String | No | 00000000-0000-0000-0000-000000000000 | ID (GUID) of the app role to give. The default assigns an app that declares no roles. |

        ### Example Input

        ```json
        { "service_principal_id": "9028d19c-26a9-4809-8e3f-20ff73e2d75e", "principal_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd", "app_role_id": "ef7437e6-4f94-4a0a-a110-a439eb2aa8f7" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `assignment_id` | String | ID of the assignment. **Remove Entra enterprise app assignment** takes it. |
        | `app_role_id` | String | The app role that was given |
        | `principal_id` | String | Object ID of the user, group or service principal |
        | `principal_type` | String | `User`, `Group` or `ServicePrincipal` |
        | `principal_display_name` | String | Name of the user, group or service principal |
        | `resource_id` | String | Object ID of the enterprise application |
        | `resource_display_name` | String | Name of the enterprise application |
        | `created_date_time` | DateTime | When the assignment was made |

        ### Example Output

        ```json
        { "assignment_id": "-WmtM5na7Uus0D8kI1yylpU9Mdo0Pb9OoBJvd3T5eKc", "app_role_id": "ef7437e6-4f94-4a0a-a110-a439eb2aa8f7", "principal_id": "87d349ed-44d7-43e1-9a83-5f2406dee5bd", "principal_type": "User", "resource_display_name": "Fabrikam App" }
        ```

        ### Error Handling
        The job fails when an ID is not a GUID. It fails without retry on 400 / 401 / 403 / 404 responses, and on 5xx responses: Microsoft may have made the assignment before it failed. A 403 gives Microsoft's reason and names the permission the action needs. On 429, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Assigning a group needs a Microsoft Entra ID P1 or P2 license. Members of groups inside the assigned group get no access.
        - Running the step again fails the job when the assignment already exists.
      END_OF_DESCRIPTION

      input_schema do
        field :service_principal_id, 'Enterprise application ID', :string, required: true
        field :principal_id, 'User, group or service principal ID', :string, required: true
        field :app_role_id, 'App role ID', :string, default: DEFAULT_APP_ROLE_ID
      end

      output_schema do
        field :assignment_id, 'Assignment ID', :string, required: true
        field :app_role_id, 'App role ID', :string
        field :principal_id, 'Principal ID', :string
        field :principal_type, 'Principal type', :string
        field :principal_display_name, 'Principal display name', :string
        field :resource_id, 'Enterprise application ID', :string
        field :resource_display_name, 'Enterprise application name', :string
        field :created_date_time, 'Created date time', :date_time
      end

      run do
        resource_id = helpers.guid_input(input[:service_principal_id], 'Enterprise application ID')
        body = {
          principalId: helpers.guid_input(input[:principal_id], 'Principal ID'), resourceId: resource_id,
          appRoleId: helpers.guid_input(input[:app_role_id].presence || DEFAULT_APP_ROLE_ID, 'App role ID'),
        }
        response = helpers.graph_request(:post, "/servicePrincipals/#{resource_id}/appRoleAssignedTo",
                                         APP_ASSIGN_PERMISSION, body: body, expected: [CREATED_STATUS],
                                                                server_error_statuses: [])
        assignment = helpers.graph_json(response)
        [{ output: {
          assignment_id: assignment['id'], app_role_id: assignment['appRoleId'],
          principal_id: assignment['principalId'], principal_type: assignment['principalType'],
          principal_display_name: assignment['principalDisplayName'], resource_id: assignment['resourceId'],
          resource_display_name: assignment['resourceDisplayName'], created_date_time: assignment['createdDateTime'],
        } }]
      end
    end

    action '01a1c904-3aaa-797f-9746-c036ef90f363' do
      name 'Remove Entra enterprise app assignment'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Removes one assignment of a user, group or service principal from an enterprise application through Microsoft Graph's [delete appRoleAssignedTo API](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-delete-approleassignedto).

        **Use case**: take away the access of a leaver to an application that signs in through Microsoft Entra.

        **Permissions required**: `AppRoleAssignment.ReadWrite.All`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | service_principal_id | String | Yes | - | Object ID (GUID) of the enterprise application (its service principal) |
        | assignment_id | String | Yes | - | `assignment_id` from **Assign Entra enterprise app to user** |

        ### Example Input

        ```json
        { "service_principal_id": "9028d19c-26a9-4809-8e3f-20ff73e2d75e", "assignment_id": "-WmtM5na7Uus0D8kI1yylpU9Mdo0Pb9OoBJvd3T5eKc" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `service_principal_id` | String | Object ID of the enterprise application |
        | `assignment_id` | String | ID of the assignment |
        | `existed` | Boolean | `false` when the application had no such assignment, so nothing was removed |

        ### Example Output

        ```json
        { "service_principal_id": "9028d19c-26a9-4809-8e3f-20ff73e2d75e", "assignment_id": "-WmtM5na7Uus0D8kI1yylpU9Mdo0Pb9OoBJvd3T5eKc", "existed": true }
        ```

        ### Error Handling
        The job fails when the enterprise application ID is not a GUID, and when Microsoft Graph answers 404 because it has no enterprise application with that ID. A 404 about the assignment is not an error: `existed` is `false`. The job fails without retry on 400 / 401 / 403 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Microsoft Graph can take about 30 seconds to show an assignment that was just made. In that time it answers 404, so `existed` is `false` and the assignment stays in place. When the assignment was made a moment before, wait about 30 seconds and run the step again.
      END_OF_DESCRIPTION

      input_schema do
        field :service_principal_id, 'Enterprise application ID', :string, required: true
        field :assignment_id, 'Assignment ID', :string, required: true
      end

      output_schema do
        field :service_principal_id, 'Enterprise application ID', :string, required: true
        field :assignment_id, 'Assignment ID', :string, required: true
        field :existed, 'Existed', :boolean, required: true
      end

      run do
        resource_id = helpers.guid_input(input[:service_principal_id], 'Enterprise application ID')
        path = "/servicePrincipals/#{resource_id}/appRoleAssignedTo/" \
               "#{helpers.graph_segment(input[:assignment_id], 'Assignment ID')}"
        response = helpers.graph_request(:delete, path, APP_UNASSIGN_PERMISSION,
                                         expected: [NO_CONTENT_STATUS, NOT_FOUND_STATUS])
        if response.status == NOT_FOUND_STATUS &&
           helpers.graph_error(response)['message'].to_s.downcase.include?(resource_id.downcase)
          fail_job!("Microsoft Graph has no enterprise application with ID #{resource_id}. Use the Object ID of the " \
                    'enterprise application, not its Application (client) ID.')
        end

        [{ output: { service_principal_id: resource_id, assignment_id: input[:assignment_id].to_s.strip,
                     existed: response.status != NOT_FOUND_STATUS, } }]
      end
    end

    action '01a1c904-3b90-7f58-8517-9b2b8a4100e4' do
      name 'Request Entra access package assignment'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Assigns one user to an access package of Microsoft Entra entitlement management, as an administrator request, through Microsoft Graph's [create assignmentRequest API](https://learn.microsoft.com/en-us/graph/api/entitlementmanagement-post-assignmentrequests). The access package then gives the user its resources, under the rules of the chosen policy.

        **Use case**: give a user the set of groups, apps and sites that an access package holds, when a Xurrent request is approved.

        **Permissions required**: `EntitlementManagement.ReadWrite.All`. Instead of that permission, the app can hold the **Access package assignment manager** role. The users it assigns need a Microsoft Entra ID P2 or Microsoft Entra ID Governance license.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_id | String | Yes | - | Object ID (GUID) of the user to assign |
        | access_package_id | String | Yes | - | ID (GUID) of the access package |
        | assignment_policy_id | String | Yes | - | ID (GUID) of the access package policy to assign under |
        | justification | String | No | - | Reason for the request |

        ### Example Input

        ```json
        { "user_id": "46184453-e63b-4f20-86c2-c557ed5d5df9", "access_package_id": "a914b616-e04e-476b-aa37-91038f0b165b", "assignment_policy_id": "2264bf65-76ba-417b-a27d-54d291f0cbc8" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `request_id` | String | ID of the request |
        | `request_type` | String | `adminAdd` |
        | `state` | String | How far the request got, for example `submitted`, `delivering` or `delivered` |
        | `status` | String | More detail on the state, for example `Accepted` |

        ### Example Output

        ```json
        { "request_id": "c0a2d3e1-6f2b-4a8e-9b4d-1e7f3a2c5d60", "request_type": "adminAdd", "state": "submitted", "status": "Accepted" }
        ```

        ### Error Handling
        The job fails when an ID is not a GUID. It fails without retry on 400 / 401 / 403 / 404 responses, and on 5xx responses: Microsoft may have accepted the request before it failed. A 403 gives Microsoft's reason and names the permission the action needs. On 429, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Running the step again for a user who already has the assignment fails the job.

        ### Operational notes
        - Microsoft accepts the request first and delivers the access after that, so `state` can still be `submitted` when the step ends.
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'User ID', :string, required: true
        field :access_package_id, 'Access package ID', :string, required: true
        field :assignment_policy_id, 'Assignment policy ID', :string, required: true
        field :justification, 'Justification', :string
      end

      output_schema do
        field :request_id, 'Request ID', :string, required: true
        field :request_type, 'Request type', :string
        field :state, 'State', :string
        field :status, 'Status', :string
      end

      run do
        assignment = {
          targetId: helpers.guid_input(input[:user_id], 'User ID'),
          assignmentPolicyId: helpers.guid_input(input[:assignment_policy_id], 'Assignment policy ID'),
          accessPackageId: helpers.guid_input(input[:access_package_id], 'Access package ID'),
        }
        body = { requestType: ADMIN_ADD_REQUEST, assignment: assignment }
        body[:justification] = input[:justification].to_s.strip if input[:justification].present?

        response = helpers.graph_request(:post, '/identityGovernance/entitlementManagement/assignmentRequests',
                                         ENTITLEMENT_PERMISSION, body: body, expected: [CREATED_STATUS],
                                                                 server_error_statuses: [])
        request = helpers.graph_json(response)
        [{ output: { request_id: request['id'], request_type: request['requestType'], state: request['state'],
                     status: request['status'], } }]
      end
    end

    action '01a1c904-3bf9-70f0-ad58-d5cbf46927ba' do
      name 'Assign Entra directory role'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Gives one user, service principal or role-assignable group a Microsoft Entra directory role, such as Helpdesk Administrator, as an active assignment through Microsoft Graph's [create unifiedRoleAssignment API](https://learn.microsoft.com/en-us/graph/api/rbacapplication-post-roleassignments).

        **Use case**: give a new service desk member the role they need, from an approved Xurrent request.

        **Permissions required**: `RoleManagement.ReadWrite.Directory`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | principal_id | String | Yes | - | Object ID (GUID) of the user, service principal or group |
        | role_definition_id | String | Yes | - | ID (GUID) of the role: the role template ID or the role definition ID of the tenant |
        | directory_scope_id | String | No | / | Where the role applies: `/` for the whole tenant, or `/administrativeUnits/{id}` for one administrative unit |

        ### Example Input

        ```json
        { "principal_id": "f8ca5a85-489a-49a0-b555-0a6d81e56f0d", "role_definition_id": "c2cf284d-6c41-4e6b-afac-4b80928c9034" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `assignment_id` | String | ID of the assignment. **Remove Entra directory role assignment** takes it. |
        | `role_definition_id` | String | The role |
        | `principal_id` | String | Object ID of the user, service principal or group |
        | `directory_scope_id` | String | Where the role applies |

        ### Example Output

        ```json
        { "assignment_id": "YUb1sHQtUEyvox7IA_Eu_mm3jqnUe4lEhvatluHVi2I-1", "role_definition_id": "c2cf284d-6c41-4e6b-afac-4b80928c9034", "principal_id": "f8ca5a85-489a-49a0-b555-0a6d81e56f0d", "directory_scope_id": "/" }
        ```

        ### Error Handling
        The job fails when an ID is not a GUID. It fails without retry on 400 / 401 / 403 / 404 responses, and on 5xx responses: Microsoft may have made the assignment before it failed. A 403 gives Microsoft's reason and names the permission the action needs. On 429, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Running the step again for the same principal, role and scope fails the job, because the assignment already exists.

        ### Operational notes
        - For an administrator role, **Create Entra PIM eligible role assignment** lets the user turn the role on only when they need it.
      END_OF_DESCRIPTION

      input_schema do
        field :principal_id, 'Principal ID', :string, required: true
        field :role_definition_id, 'Role definition ID', :string, required: true
        field :directory_scope_id, 'Directory scope ID', :string, default: TENANT_SCOPE
      end

      output_schema do
        field :assignment_id, 'Assignment ID', :string, required: true
        field :role_definition_id, 'Role definition ID', :string
        field :principal_id, 'Principal ID', :string
        field :directory_scope_id, 'Directory scope ID', :string
      end

      run do
        body = {
          principalId: helpers.guid_input(input[:principal_id], 'Principal ID'),
          roleDefinitionId: helpers.guid_input(input[:role_definition_id], 'Role definition ID'),
          directoryScopeId: input[:directory_scope_id].to_s.strip.presence || TENANT_SCOPE,
        }
        response = helpers.graph_request(:post, '/roleManagement/directory/roleAssignments', ROLE_PERMISSION,
                                         body: body, expected: [CREATED_STATUS], server_error_statuses: [])
        assignment = helpers.graph_json(response)
        [{ output: { assignment_id: assignment['id'], role_definition_id: assignment['roleDefinitionId'],
                     principal_id: assignment['principalId'], directory_scope_id: assignment['directoryScopeId'], } }]
      end
    end

    action '01a1c904-3c60-780b-9a1c-7b4f9d5147a5' do
      name 'Create Entra PIM eligible role assignment'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Makes one user, service principal or role-assignable group eligible for a Microsoft Entra directory role in Privileged Identity Management (PIM), through Microsoft Graph's [create roleEligibilityScheduleRequest API](https://learn.microsoft.com/en-us/graph/api/rbacapplication-post-roleeligibilityschedulerequests). An eligible user does not hold the role until they turn it on in PIM.

        **Use case**: let an administrator turn on a role when they need it, instead of holding it all the time.

        **Permissions required**: `RoleEligibilitySchedule.ReadWrite.Directory`. The tenant needs a Microsoft Entra ID P2 or Microsoft Entra ID Governance license.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | principal_id | String | Yes | - | Object ID (GUID) of the user, service principal or group |
        | role_definition_id | String | Yes | - | ID (GUID) of the role: the role template ID or the role definition ID of the tenant |
        | directory_scope_id | String | No | / | Where the role applies: `/` for the whole tenant, or `/administrativeUnits/{id}` for one administrative unit |
        | justification | String | No | - | Reason for the assignment. The role settings in PIM can require it. |
        | start_date_time | DateTime | No | - | When the eligibility starts. Empty means now. |
        | end_date_time | DateTime | No | - | When the eligibility ends. Empty asks for an eligibility that does not end, which the role settings in PIM can refuse. |

        ### Example Input

        ```json
        { "principal_id": "071cc716-8147-4397-a5ba-b2105951cc0b", "role_definition_id": "8424c6f0-a189-499e-bbd0-26c1753c96d4", "justification": "On-call rota", "end_date_time": "2027-04-10T00:00:00Z" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `request_id` | String | ID of the request |
        | `status` | String | State of the request, for example `Provisioned` |
        | `principal_id` | String | Object ID of the user, service principal or group |
        | `role_definition_id` | String | The role |
        | `directory_scope_id` | String | Where the role applies |
        | `target_schedule_id` | String | ID of the eligibility schedule that the request made |

        ### Example Output

        ```json
        { "request_id": "50877283-9d40-433c-bab8-7986dc10458a", "status": "Provisioned", "principal_id": "071cc716-8147-4397-a5ba-b2105951cc0b", "role_definition_id": "8424c6f0-a189-499e-bbd0-26c1753c96d4", "directory_scope_id": "/", "target_schedule_id": "50877283-9d40-433c-bab8-7986dc10458a" }
        ```

        ### Error Handling
        The job fails when an ID is not a GUID, and when Microsoft answers with the request in status `Canceled`, `Denied`, `Failed` or `Revoked`. It fails without retry on 400 / 401 / 403 / 404 responses, and on 5xx responses: Microsoft may have accepted the request before it failed. A 403 gives Microsoft's reason and names the permission the action needs. On 429, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - Running the step again for the same principal, role and scope fails the job, because the eligibility already exists.
      END_OF_DESCRIPTION

      input_schema do
        field :principal_id, 'Principal ID', :string, required: true
        field :role_definition_id, 'Role definition ID', :string, required: true
        field :directory_scope_id, 'Directory scope ID', :string, default: TENANT_SCOPE
        field :justification, 'Justification', :string
        field :start_date_time, 'Start date time', :date_time, visibility: 'optional'
        field :end_date_time, 'End date time', :date_time
      end

      output_schema do
        field :request_id, 'Request ID', :string, required: true
        field :status, 'Status', :string
        field :principal_id, 'Principal ID', :string
        field :role_definition_id, 'Role definition ID', :string
        field :directory_scope_id, 'Directory scope ID', :string
        field :target_schedule_id, 'Target schedule ID', :string
      end

      run do
        start = input[:start_date_time].present? ? input[:start_date_time].iso8601 : Time.now.utc.iso8601
        expiration = if input[:end_date_time].present?
                       { type: AFTER_DATE_TIME, endDateTime: input[:end_date_time].iso8601 }
                     else
                       { type: NO_EXPIRATION }
                     end
        body = {
          action: ADMIN_ASSIGN_ACTION,
          principalId: helpers.guid_input(input[:principal_id], 'Principal ID'),
          roleDefinitionId: helpers.guid_input(input[:role_definition_id], 'Role definition ID'),
          directoryScopeId: input[:directory_scope_id].to_s.strip.presence || TENANT_SCOPE,
          scheduleInfo: { startDateTime: start, expiration: expiration },
        }
        body[:justification] = input[:justification].to_s.strip if input[:justification].present?

        response = helpers.graph_request(:post, '/roleManagement/directory/roleEligibilityScheduleRequests',
                                         ROLE_ELIGIBILITY_PERMISSION, body: body, expected: [CREATED_STATUS],
                                                                      server_error_statuses: [])
        request = helpers.graph_json(response)
        if FAILED_REQUEST_STATUSES.include?(request['status'])
          fail_job!("Microsoft Graph answered with request '#{request['id']}' in status #{request['status']}, " \
                    'so the eligible role assignment was not made.')
        end

        [{ output: { request_id: request['id'], status: request['status'], principal_id: request['principalId'],
                     role_definition_id: request['roleDefinitionId'], directory_scope_id: request['directoryScopeId'],
                     target_schedule_id: request['targetScheduleId'], } }]
      end
    end

    action '01a1c904-3cd4-7be0-bb32-5d9cfce48a06' do
      name 'Remove Entra directory role assignment'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Removes one active Microsoft Entra directory role assignment through Microsoft Graph's [delete unifiedRoleAssignment API](https://learn.microsoft.com/en-us/graph/api/unifiedroleassignment-delete).

        **Use case**: take an administrator role away from a user who changes job or leaves.

        **Permissions required**: `RoleManagement.ReadWrite.Directory`

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | assignment_id | String | Yes | - | `assignment_id` from **Assign Entra directory role** |

        ### Example Input

        ```json
        { "assignment_id": "lAPpYvVpN0KRkAEhdxReEJC2sEqbR_9Hr48lds9SGHI-1" }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `assignment_id` | String | ID of the assignment |
        | `existed` | Boolean | `false` when Microsoft Graph had no such assignment, so nothing was removed |

        ### Example Output

        ```json
        { "assignment_id": "lAPpYvVpN0KRkAEhdxReEJC2sEqbR_9Hr48lds9SGHI-1", "existed": true }
        ```

        ### Error Handling
        A 404 is not an error: `existed` is `false`. The job fails without retry on 400 / 401 / 403 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.

        ### Limitations
        - An eligible assignment from **Create Entra PIM eligible role assignment** is not an active assignment, so this action does not remove it.
        - Microsoft Graph can take about 30 seconds to show an assignment that was just made. In that time it answers 404, so `existed` is `false` and the assignment stays in place. When the assignment was made a moment before, wait about 30 seconds and run the step again.
      END_OF_DESCRIPTION

      input_schema do
        field :assignment_id, 'Assignment ID', :string, required: true
      end

      output_schema do
        field :assignment_id, 'Assignment ID', :string, required: true
        field :existed, 'Existed', :boolean, required: true
      end

      run do
        assignment_id = helpers.graph_segment(input[:assignment_id], 'Assignment ID')
        response = helpers.graph_request(:delete, "/roleManagement/directory/roleAssignments/#{assignment_id}",
                                         ROLE_PERMISSION, expected: [NO_CONTENT_STATUS, NOT_FOUND_STATUS])
        [{ output: { assignment_id: input[:assignment_id].to_s.strip, existed: response.status != NOT_FOUND_STATUS } }]
      end
    end

    action '01a1c904-3d42-7a21-83c1-c08626f302c3' do
      name 'Confirm Entra user compromised'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Marks one or more Microsoft Entra users as compromised in Microsoft Entra ID Protection through Microsoft Graph's [confirm compromised API](https://learn.microsoft.com/en-us/graph/api/riskyuser-confirmcompromised). Microsoft sets the risk level of each user to high.

        **Use case**: record it in Microsoft Entra when a Xurrent security incident confirms that an account was taken over.

        **Permissions required**: `IdentityRiskyUser.ReadWrite.All`. The tenant needs a Microsoft Entra ID P2 license.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_ids | String[] | Yes | - | Object IDs (GUIDs) of the users |

        ### Example Input

        ```json
        { "user_ids": ["29f270bb-4d23-4f68-8a57-dc73dc0d4caf"] }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `user_ids` | String[] | The users that were marked as compromised |

        ### Example Output

        ```json
        { "user_ids": ["29f270bb-4d23-4f68-8a57-dc73dc0d4caf"] }
        ```

        ### Error Handling
        The job fails when no user ID is set, or when an ID is not a GUID. It fails without retry on 400 / 401 / 403 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.
      END_OF_DESCRIPTION

      input_schema do
        field :user_ids, 'User IDs', :string, array: true, required: true
      end

      output_schema do
        field :user_ids, 'User IDs', :string, array: true, required: true
      end

      run do
        user_ids = helpers.risky_user_ids(input[:user_ids])
        helpers.graph_request(:post, '/identityProtection/riskyUsers/confirmCompromised', RISKY_USER_PERMISSION,
                              body: { userIds: user_ids }, expected: [NO_CONTENT_STATUS])
        [{ output: { user_ids: user_ids } }]
      end
    end

    action '01a1c904-3dac-78d9-83e3-0e7423735dc5' do
      name 'Dismiss Entra user risk'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Dismisses the risk of one or more Microsoft Entra users in Microsoft Entra ID Protection through Microsoft Graph's [dismiss API](https://learn.microsoft.com/en-us/graph/api/riskyuser-dismiss). Microsoft sets the risk level of each user to none.

        **Use case**: close a risk alert after the security team has checked the sign-ins and found nothing wrong, or after the password of the user was reset.

        **Permissions required**: `IdentityRiskyUser.ReadWrite.All`. The tenant needs a Microsoft Entra ID P2 license.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | user_ids | String[] | Yes | - | Object IDs (GUIDs) of the users |

        ### Example Input

        ```json
        { "user_ids": ["04487ee0-f4f6-4e7f-8999-facc5a30e232"] }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `user_ids` | String[] | The users whose risk was dismissed |

        ### Example Output

        ```json
        { "user_ids": ["04487ee0-f4f6-4e7f-8999-facc5a30e232"] }
        ```

        ### Error Handling
        The job fails when no user ID is set, or when an ID is not a GUID. It fails without retry on 400 / 401 / 403 responses. A 403 gives Microsoft's reason and names the permission the action needs. On 429 or 503, the connector waits for the time in `Retry-After` and retries the request.
      END_OF_DESCRIPTION

      input_schema do
        field :user_ids, 'User IDs', :string, array: true, required: true
      end

      output_schema do
        field :user_ids, 'User IDs', :string, array: true, required: true
      end

      run do
        user_ids = helpers.risky_user_ids(input[:user_ids])
        helpers.graph_request(:post, '/identityProtection/riskyUsers/dismiss', RISKY_USER_PERMISSION,
                              body: { userIds: user_ids }, expected: [NO_CONTENT_STATUS])
        [{ output: { user_ids: user_ids } }]
      end
    end

    action '01a1a1c8-debd-77d8-a35b-763f55973100' do
      name 'Renew directory subscriptions'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Creates and keeps alive every Microsoft Graph subscription that the triggers on this connection depend on, through the [subscription API](https://learn.microsoft.com/en-us/graph/api/resources/subscription).

        Put this action in a runbook of its own, on a Scheduler trigger that runs every 15 minutes, and set that runbook's concurrency to one run at a time. The triggers of this connector do not work without it. Each run lists the subscriptions Microsoft holds for this application, deletes any that points at a trigger of this connection but is not recorded, creates the subscription of every recorded trigger that has none, and renews, in batches of 20, every subscription that ends within a day. Microsoft ends a user or group subscription after 29 days unless it is renewed.

        **Permissions required**: `User.Read.All` for the user triggers, `Group.Read.All` for the group triggers.

        ### Input Parameters
        None.

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `results` | Object[] | One row per subscription the run touched: `runbook_id`, `resource`, `change_type`, `subscription_id`, `expires_at`, `outcome` (`created`, `renewed`, `removed`, `skipped` or `failed`) and `error` |
        | `created` | Integer | Subscriptions created |
        | `renewed` | Integer | Subscriptions renewed |
        | `removed` | Integer | Subscriptions deleted because no trigger records them |

        ### Example Output

        ```json
        {
          "created": 1,
          "renewed": 0,
          "removed": 0,
          "results": [{ "runbook_id": "01a13544-c2d4-7cc7-8726-e73182d73e05", "resource": "users", "change_type": "updated", "subscription_id": "0fc0f4a5-3f6e-4bc5-9d1a-52e2c5b81e0c", "outcome": "created" }]
        }
        ```

        ### Error Handling
        A run with nothing to do ends quietly. A run in which a subscription could not be created or renewed fails after it has handled every other row, and its log names the trigger and what Microsoft answered. The next run tries again.

        ### Operational notes
        - Use the connection the triggers use. A run on another connection finds nothing to keep alive.
        - Deprovision a trigger before you delete its runbook, or this action keeps its subscription alive.
      END_OF_DESCRIPTION

      output_schema do
        field :results, 'Results', :nested, array: true do
          field :runbook_id, 'Runbook ID', :string
          field :resource, 'Resource', :string
          field :change_type, 'Change type', :string
          field :subscription_id, 'Subscription ID', :string
          field :expires_at, 'Expires at', :date_time
          field :outcome, 'Outcome', :string, required: true
          field :error, 'Error', :string
        end
        field :created, 'Created', :integer, required: true
        field :renewed, 'Renewed', :integer, required: true
        field :removed, 'Removed', :integer, required: true
      end

      run do
        rows = helpers.subscription_rows
        if rows.empty?
          log(NOTHING_RECORDED)
          next [{ output: { created: 0, renewed: 0, removed: 0, results: [] } }]
        end

        held = helpers.held_subscriptions
        results = helpers.remove_unrecorded_subscriptions(rows, held)
        unsubscribed = rows.reject { |_key, row| helpers.held_id(row, held) }
        expiring = rows.select { |_key, row| helpers.held_id(row, held) && helpers.expiring_soon(row) }
        results += expiring.each_slice(BATCH_REQUEST_LIMIT).flat_map { |slice| helpers.renew_batch(slice) }
        results += unsubscribed.map { |key, row| helpers.create_subscription_for(key, row) }
        failed = results.select { |result| result[:outcome] == OUTCOME_FAILED }
        failed.each { |result| log("#{result[:resource]} for #{result[:runbook_id]}: #{result[:error]}") }
        if failed.any?
          fail_job!("#{failed.length} subscription(s) could not be kept alive. The run log names each one.")
        end

        counts = { created: OUTCOME_CREATED, renewed: OUTCOME_RENEWED, removed: OUTCOME_REMOVED }
                 .transform_values { |outcome| results.select { |result| result[:outcome] == outcome }.length }
        [{ output: counts.merge(results: results) }]
      end
    end

    action '01a1a1c8-debd-760e-bdd2-e162ae2c5b97' do
      name 'Call Microsoft Graph'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Sends one request to any [Microsoft Graph v1.0 endpoint](https://learn.microsoft.com/en-us/graph/api/overview) with this connection's credentials, for what the other actions do not cover.

        **Use case**: read or change a directory object that has no action of its own, for example a user's manager (`/users/{id}/manager`).

        **Permissions required**: the application permission that the endpoint's Microsoft Graph page lists.

        ### Input Parameters

        | Parameter | Type | Required | Default | Description |
        |-----------|------|----------|---------|-------------|
        | method | String | Yes | GET | `GET`, `POST`, `PATCH`, `PUT` or `DELETE` |
        | path | String | Yes | - | Path after the Graph address, starting with `/`, for example `/users/adele.vance@contoso.com/manager` |
        | query | Object[] | No | - | Query parameters, each with `name` and `value`, for example `$select` = `id,displayName` |
        | body | String | No | - | Request body as JSON |
        | advanced_query | Boolean | No | false | Sends `ConsistencyLevel: eventual`, which `$search`, `$count` and some filters need |

        ### Example Input

        ```json
        { "method": "GET", "path": "/users/adele.vance@contoso.com/manager", "query": [{ "name": "$select", "value": "id,displayName" }] }
        ```

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `status` | Integer | HTTP status of the answer |
        | `body` | String | Body of the answer as text. Usually JSON. |

        ### Example Output

        ```json
        { "status": 200, "body": "{\\"id\\":\\"0b2e1b59-2b8c-4b36-8d2b-5f6a5d4e1a2b\\",\\"displayName\\":\\"Megan Bowen\\"}" }
        ```

        ### Error Handling
        The job fails when the path does not start with one `/`, or holds `..`, `://`, `\\`, `#` or spaces, and when the body is not JSON. It fails without retry on any status from 400 up, and the message gives Microsoft's error. On a 403, the message also names the permission that the endpoint's Microsoft Graph page lists, and says that it needs admin consent. On 429, the connector waits for the time in `Retry-After` and retries the request. On 503, it does so for `GET` and `DELETE` only.

        ### Operational notes
        - The request always goes to the Graph address of this connection, so the credentials are never sent to another host.
        - A `POST`, `PATCH` or `PUT` is sent again only after a 429, which Microsoft answers before it runs the request.
        - The job log shows the body and the answer as text. Use the dedicated actions, such as **Issue Entra Temporary Access Pass**, for a request that sends or returns a secret.
      END_OF_DESCRIPTION

      input_schema do
        field :method, 'Method', :string, required: true, enumeration: GENERIC_METHODS, default: 'GET'
        field :path, 'Path', :string, required: true,
                                      hint: 'Starts with /, for example /users/adele.vance@contoso.com/manager'
        field :query, 'Query parameters', :nested, array: true do
          field :name, 'Name', :string, required: true
          field :value, 'Value', :string
        end
        field :body, 'Body', :string, hint: 'JSON'
        field :advanced_query, 'Advanced query', :boolean, visibility: 'optional', default: false
      end

      output_schema do
        field :status, 'Status', :integer, required: true
        field :body, 'Body', :string
      end

      run do
        method = input[:method].to_s
        url = helpers.generic_url(input[:path], input[:query])
        body = helpers.generic_body(input[:body])
        headers = helpers.boolean_input(input[:advanced_query]) ? ADVANCED_QUERY_HEADERS : {}
        headers = headers.merge(JSON_HEADERS) if body
        response = case method
                   when 'GET' then http_get(url, nil, headers)
                   when 'DELETE' then http_delete(url, nil, headers)
                   when 'POST' then http_post(url, body, headers)
                   when 'PATCH' then http_patch(url, body, headers)
                   else http_put(url, body, headers)
                   end
        server_errors = GENERIC_RETRIED_METHODS.include?(method) ? DEFAULT_SERVER_ERROR_STATUSES : []
        backoff_if_needed(response, api_name: 'Microsoft', server_error_statuses: server_errors)
        fail_job!(helpers.describe_graph_failure(response, GENERIC_PERMISSION)) if response.status >= MIN_ERROR_STATUS

        [{ output: { status: response.status, body: response.body.to_s } }]
      end
    end

    trigger '01a1a1c8-debd-7086-8378-07dda2914300' do
      name 'New Entra user'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Starts a workflow when a user is created in Microsoft Entra ID. Microsoft Graph sends a change notification, so nothing polls the directory.

        Microsoft Graph sends the same notification for a new user, a changed user and a deleted user that can still be restored. When a notification arrives, this trigger asks Microsoft Graph when each user was created, and keeps the users created in the last 60 minutes. Microsoft sends a notification that was not accepted again for up to 4 hours, so after an iPaaS outage longer than 60 minutes, a user created more than 60 minutes before the outage ended is not reported. Each new user is reported once, even when it changes again in that hour, unless two notifications about it arrive at the same moment. When more than 300 objects change in one delivery, only the first 300 are checked. A deleted user is not reported, and the log of the trigger event names its ID. When Microsoft Graph does not show a user yet, the trigger asks Microsoft to send the notification again, for up to 5 minutes. After that, the user is not reported, and the log names its ID. A notification carries the user ID, not the user: call **Get Entra user** to read the user.

        Microsoft can put several notifications in one request, so Users is a list. Read every user in it with the Flow connector's Loop action. Microsoft can deliver the same notification twice, so a workflow that must act once checks the User ID first. When this trigger cannot ask Microsoft Graph in time, it answers with an error, and Microsoft sends the notifications again later.

        **Required**: the **Renew directory subscriptions** action, in its own runbook on a Scheduler trigger every 15 minutes, creates this trigger's subscription within 15 minutes of a deploy and keeps it alive. Leave URL postfix empty. Deprovision the trigger before you delete its runbook.

        **Permissions required**: `User.Read.All`

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `users` | Object[] | The new users: `user_id` and `created_date_time` |
        | `subscription_id` | String | The Microsoft Graph subscription that sent the notification |
      END_OF_DESCRIPTION

      outbound_traffic true

      output_schema do
        field :users, 'Users', :nested, array: true, required: true do
          field :user_id, 'User ID', :string, required: true
          field :created_date_time, 'Created date time', :date_time
        end
        field :subscription_id, 'Subscription ID', :string
      end

      provision do
        helpers.record_watch(USERS_RESOURCE, UPDATED_CHANGE_TYPE)
      end

      deprovision do
        helpers.forget_watch
      end

      parse do |request|
        helpers.new_objects_output(request, '/users', :users, :user_id, 'user')
      end

      respond_with do |context, response|
        helpers.graph_answer(context, response)
      end
    end

    trigger '01a1a1c8-debd-736f-9cab-7df55db8b836' do
      name 'New or updated Entra user'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Starts a workflow when a user in Microsoft Entra ID is created, changed, or deleted in a way that can still be restored. Microsoft Graph sends a change notification, so nothing polls the directory.

        A notification carries the user ID, not the user: call **Get Entra user** to read it. A user deleted in the last 30 days is not found by **Get Entra user**. Before a step that deletes something or removes access, read the user again with **Get Entra user**, and go on only when it shows the change.

        A runbook that changes the user it was started for, for example with **Update Entra user**, starts this trigger again. Check a field that the first run set before you change the user again.

        Microsoft can put several notifications in one request, so Users is a list. Read every user in it with the Flow connector's Loop action. Microsoft can deliver the same notification twice, so a workflow that must act once checks the User ID first.

        **Required**: the **Renew directory subscriptions** action, in its own runbook on a Scheduler trigger every 15 minutes, creates this trigger's subscription within 15 minutes of a deploy and keeps it alive. Leave URL postfix empty. Deprovision the trigger before you delete its runbook.

        **Permissions required**: `User.Read.All`

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `users` | Object[] | The users that changed: `user_id` |
        | `subscription_id` | String | The Microsoft Graph subscription that sent the notification |
      END_OF_DESCRIPTION

      outbound_traffic true

      output_schema do
        field :users, 'Users', :nested, array: true, required: true do
          field :user_id, 'User ID', :string, required: true
        end
        field :subscription_id, 'Subscription ID', :string
      end

      provision do
        helpers.record_watch(USERS_RESOURCE, UPDATED_CHANGE_TYPE)
      end

      deprovision do
        helpers.forget_watch
      end

      parse do |request|
        helpers.changed_ids_output(helpers.directory_changes(request), :users, :user_id)
      end

      respond_with do |context, response|
        helpers.graph_answer(context, response)
      end
    end

    trigger '01a1a1c8-debd-7797-b0ba-8658029c0537' do
      name 'Deleted Entra user'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Starts a workflow when a user is deleted permanently from Microsoft Entra ID. Microsoft Graph sends a change notification, so nothing polls the directory.

        Microsoft keeps a deleted user for 30 days, and this trigger fires when the user is deleted for good: when the 30 days end, or when an administrator deletes the user from the deleted users list. A user deleted in a way that can still be restored starts **New or updated Entra user** instead.

        Microsoft can put several notifications in one request, so Users is a list. Read every user in it with the Flow connector's Loop action. Microsoft can deliver the same notification twice.

        **Required**: the **Renew directory subscriptions** action, in its own runbook on a Scheduler trigger every 15 minutes, creates this trigger's subscription within 15 minutes of a deploy and keeps it alive. Leave URL postfix empty. Deprovision the trigger before you delete its runbook.

        **Permissions required**: `User.Read.All`

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `users` | Object[] | The deleted users: `user_id` |
        | `subscription_id` | String | The Microsoft Graph subscription that sent the notification |
      END_OF_DESCRIPTION

      outbound_traffic true

      output_schema do
        field :users, 'Users', :nested, array: true, required: true do
          field :user_id, 'User ID', :string, required: true
        end
        field :subscription_id, 'Subscription ID', :string
      end

      provision do
        helpers.record_watch(USERS_RESOURCE, DELETED_CHANGE_TYPE)
      end

      deprovision do
        helpers.forget_watch
      end

      parse do |request|
        helpers.changed_ids_output(helpers.directory_changes(request), :users, :user_id)
      end

      respond_with do |context, response|
        helpers.graph_answer(context, response)
      end
    end

    trigger '01a1a1c8-debd-7633-926d-308136659fdd' do
      name 'New Entra group'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Starts a workflow when a group is created in Microsoft Entra ID. Microsoft Graph sends a change notification, so nothing polls the directory.

        Microsoft Graph sends the same notification for a new group, a changed group and a deleted group that can still be restored. When a notification arrives, this trigger asks Microsoft Graph when each group was created, and keeps the groups created in the last 60 minutes. Microsoft sends a notification that was not accepted again for up to 4 hours, so after an iPaaS outage longer than 60 minutes, a group created more than 60 minutes before the outage ended is not reported. Each new group is reported once, even when it changes again in that hour, unless two notifications about it arrive at the same moment. When more than 300 objects change in one delivery, only the first 300 are checked. A deleted group is not reported, and the log of the trigger event names its ID. When Microsoft Graph does not show a group yet, the trigger asks Microsoft to send the notification again, for up to 5 minutes. After that, the group is not reported, and the log names its ID. A notification carries the group ID, not the group: call **Get Entra group by ID** to read the group.

        Microsoft can put several notifications in one request, so Groups is a list. Read every group in it with the Flow connector's Loop action. Microsoft can deliver the same notification twice, so a workflow that must act once checks the Group ID first. When this trigger cannot ask Microsoft Graph in time, it answers with an error, and Microsoft sends the notifications again later.

        **Required**: the **Renew directory subscriptions** action, in its own runbook on a Scheduler trigger every 15 minutes, creates this trigger's subscription within 15 minutes of a deploy and keeps it alive. Leave URL postfix empty. Deprovision the trigger before you delete its runbook.

        **Permissions required**: `Group.Read.All`

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `groups` | Object[] | The new groups: `group_id` and `created_date_time` |
        | `subscription_id` | String | The Microsoft Graph subscription that sent the notification |
      END_OF_DESCRIPTION

      outbound_traffic true

      output_schema do
        field :groups, 'Groups', :nested, array: true, required: true do
          field :group_id, 'Group ID', :string, required: true
          field :created_date_time, 'Created date time', :date_time
        end
        field :subscription_id, 'Subscription ID', :string
      end

      provision do
        helpers.record_watch(GROUPS_RESOURCE, UPDATED_CHANGE_TYPE)
      end

      deprovision do
        helpers.forget_watch
      end

      parse do |request|
        helpers.new_objects_output(request, '/groups', :groups, :group_id, 'group')
      end

      respond_with do |context, response|
        helpers.graph_answer(context, response)
      end
    end

    trigger '01a1a1c8-debd-7198-a231-55393b18083d' do
      name 'New or updated Entra group'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Starts a workflow when a group in Microsoft Entra ID is created, changed, or deleted in a way that can still be restored. Microsoft Graph sends a change notification, so nothing polls the directory.

        A notification carries the group ID, not the group: call **Get Entra group by ID** to read it. Before a step that deletes something or removes access, read the group again with **Get Entra group by ID**, and go on only when it shows the change.

        A runbook that changes the group it was started for, for example with **Update Entra group** or **Add member to Entra group**, starts this trigger again. Check a field that the first run set before you change the group again.

        Microsoft can put several notifications in one request, so Groups is a list. Read every group in it with the Flow connector's Loop action. Microsoft can deliver the same notification twice, so a workflow that must act once checks the Group ID first.

        **Required**: the **Renew directory subscriptions** action, in its own runbook on a Scheduler trigger every 15 minutes, creates this trigger's subscription within 15 minutes of a deploy and keeps it alive. Leave URL postfix empty. Deprovision the trigger before you delete its runbook.

        **Permissions required**: `Group.Read.All`

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `groups` | Object[] | The groups that changed: `group_id` |
        | `subscription_id` | String | The Microsoft Graph subscription that sent the notification |
      END_OF_DESCRIPTION

      outbound_traffic true

      output_schema do
        field :groups, 'Groups', :nested, array: true, required: true do
          field :group_id, 'Group ID', :string, required: true
        end
        field :subscription_id, 'Subscription ID', :string
      end

      provision do
        helpers.record_watch(GROUPS_RESOURCE, UPDATED_CHANGE_TYPE)
      end

      deprovision do
        helpers.forget_watch
      end

      parse do |request|
        helpers.changed_ids_output(helpers.directory_changes(request), :groups, :group_id)
      end

      respond_with do |context, response|
        helpers.graph_answer(context, response)
      end
    end

    trigger '01a1a1c8-debd-7d82-85a7-58459994a3ed' do
      name 'New or updated Entra group member'
      avatar '/assets/icons/microsoft-entra.svg'
      description <<~END_OF_DESCRIPTION
        Starts a workflow when the members of one Microsoft Entra group change. Microsoft Graph sends a change notification, so nothing polls the directory.

        A notification names each member who joined or left the group by object ID only. It does not say whether the member is a user, a group, a device or another directory object. Call **Retrieve Entra group members** to read the type of a member who joined. If a notification names no member, the trigger skips it. Before a step that deletes something or removes access, read the members again with **Retrieve Entra group members**, and go on only when they show the change.

        A runbook that adds a member to or removes a member from the group it watches starts this trigger again. Check whether the change came from the runbook itself before you change the members again.

        Microsoft can put several notifications in one request, so Changes is a list. Read every change in it with the Flow connector's Loop action. Microsoft can deliver the same notification twice, so a workflow that must act once checks the Member ID first.

        One trigger watches one group. Microsoft allows 100 user and group subscriptions per application in a tenant, and each trigger of this kind takes one of them.

        **Required**: the **Renew directory subscriptions** action, in its own runbook on a Scheduler trigger every 15 minutes, creates this trigger's subscription within 15 minutes of a deploy and keeps it alive. Leave URL postfix empty. Deprovision the trigger before you delete its runbook.

        **Permissions required**: `Group.Read.All`

        ### Configuration

        | Field | Required | Description |
        |---|---|---|
        | Group ID | Yes | Object ID (GUID) of the group to watch |

        ### Output

        | Field Name | Type | Description |
        |---|---|---|
        | `group_id` | String | The group this trigger watches |
        | `changes` | Object[] | One row per member who joined or left, in the order Microsoft sent them: `member_id`, and `removed`, which is true when the member left the group. A member who joined and then left has two rows |
        | `subscription_id` | String | The Microsoft Graph subscription that sent the notification |
      END_OF_DESCRIPTION

      outbound_traffic true

      config_schema do
        field :group_id, 'Group ID', :string, required: true,
                                              hint: 'Object ID (GUID) of the group to watch.'
      end

      output_schema do
        field :group_id, 'Group ID', :string, required: true
        field :changes, 'Changes', :nested, array: true, required: true do
          field :member_id, 'Member ID', :string, required: true
          field :removed, 'Removed', :boolean, required: true
        end
        field :subscription_id, 'Subscription ID', :string
      end

      provision do
        group_id = helpers.guid_input(trigger.config[:group_id], 'Group ID')
        helpers.record_watch("#{GROUPS_RESOURCE}/#{group_id}/members", UPDATED_CHANGE_TYPE)
      end

      deprovision do
        helpers.forget_watch
      end

      parse do |request|
        group_id = trigger.config[:group_id].to_s.strip
        changes = helpers.directory_changes(request)
        members = helpers.member_changes(changes, group_id)
        discard_trigger_event!('No notification named a member who joined or left the group') if members.empty?

        { group_id: group_id, changes: members, subscription_id: changes.first['subscriptionId'] }
      end

      respond_with do |context, response|
        helpers.graph_answer(context, response)
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

    helper :graph_scope do
      host = URI.parse(helpers.graph_endpoint.to_s).host.to_s.downcase
      "https://#{NATIONAL_GRAPH_HOSTS.include?(host) ? host : GLOBAL_GRAPH_HOST}#{GRAPH_SCOPE_PATH}"
    rescue URI::InvalidURIError
      "https://#{GLOBAL_GRAPH_HOST}#{GRAPH_SCOPE_PATH}"
    end

    helper :env_config_value do |key, default|
      env_config = outbound_connection.config[:environment] || {}
      env_config[key].presence || default
    end

    helper :graph_url do |path|
      raise IPaaS::Error, "graph path '#{path}' does not start with a slash" unless path.to_s.start_with?('/')

      "#{helpers.graph_endpoint.to_s.chomp('/')}#{path}"
    end

    helper :user_path do |value|
      user = value.to_s.strip
      next "/users/#{helpers.graph_segment(user, 'User ID')}" unless user.start_with?(DOLLAR_PREFIX)

      "/users('#{helpers.graph_segment(user, 'User ID').gsub("'", "''")}')"
    end

    helper :graph_segment do |value, label|
      segment = value.to_s.strip
      fail_job!("#{label} is required.") if segment.blank?
      fail_job!("#{label} '#{segment}' is not a valid id.") if DOT_SEGMENTS.include?(segment)

      segment.gsub('%', '%25').gsub('#', '%23').gsub('?', '%3F').gsub('/', '%2F').gsub(' ', '%20').gsub('^', '%5E')
    end

    helper :guid_input do |value, label|
      id = value.to_s.strip
      fail_job!("#{label} '#{id}' is not a Microsoft Entra object id (a GUID).") unless GUID_PATTERN.match?(id)

      id
    end

    helper :guid_list do |values, label|
      list = values.is_a?(Array) ? values : []
      list.map { |value| value.to_s.strip }.reject(&:blank?).uniq.map { |value| helpers.guid_input(value, label) }
    end

    helper :boolean_input do |value|
      case value
      when true, 'true' then true
      when false, 'false' then false
      end
    end

    helper :page_size_param do |value|
      size = value.to_s.strip
      size.blank? ? DEFAULT_PAGE_SIZE.to_s : size.to_i.to_s
    end

    helper :graph_error do |response|
      error = parse_json_object_or_empty(response.body.to_s)['error']
      error.is_a?(Hash) ? error : {}
    end

    helper :graph_failure_text do |status, error, fallback|
      "Microsoft Graph returned HTTP #{status} #{error['code']}: #{error['message'].presence || fallback}"
    end

    helper :already_reference_answer do |response, message_pattern|
      error = helpers.graph_error(response)
      response.status == BAD_REQUEST_STATUS && error['code'] == ALREADY_REFERENCE_CODE &&
        message_pattern.match?(error['message'].to_s)
    end

    helper :describe_graph_failure do |response, permission = nil, fallback: nil|
      text = helpers.graph_failure_text(response.status, helpers.graph_error(response),
                                        fallback || response.body.to_s.presence || 'no response body')
      next text unless response.status == FORBIDDEN_STATUS && permission.present?

      "#{text} Permission this action needs: #{permission}. Admin consent is required."
    end

    helper :graph_request do |method, path, permission, body: nil, params: nil, headers: nil, expected: [OK_STATUS],
                              server_error_statuses: DEFAULT_SERVER_ERROR_STATUSES, failure_fallback: nil|
      url = helpers.graph_url(path)
      response = case method
                 when :get then http_get(url, params, headers)
                 when :delete then http_delete(url, params, headers)
                 when :post then http_post(url, body&.to_json, JSON_HEADERS.merge(headers || {}))
                 when :patch then http_patch(url, body&.to_json, JSON_HEADERS.merge(headers || {}))
                 when :put then http_put(url, body&.to_json, JSON_HEADERS.merge(headers || {}))
                 else raise IPaaS::Error, "Unsupported Microsoft Graph method '#{method}'"
                 end
      backoff_if_needed(response, api_name: 'Microsoft', server_error_statuses: server_error_statuses)
      unless expected.include?(response.status)
        fail_job!(helpers.describe_graph_failure(response, permission, fallback: failure_fallback))
      end

      response
    end

    helper :graph_json do |response|
      body = parse_json_response(response.body.to_s,
                                 error_message: 'Microsoft Graph returned a response that is not JSON: ' \
                                                "'#{response.body}'")
      raise IPaaS::Error, 'Microsoft Graph returned a value that is not an object' unless body.is_a?(Hash)

      body
    end

    helper :graph_object do |path, permission, params|
      helpers.graph_json(helpers.graph_request(:get, path, permission, params: params))
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

    helper :graph_page do |path, params, permission, headers = nil|
      stored = iteration_state_value(:odata_nextLink)
      response = if stored.present?
                   url = helpers.trusted_next_link(stored)
                   http_get(url, nil, headers)
                 else
                   http_get(helpers.graph_url(path), params, headers)
                 end
      backoff_if_needed(response, api_name: 'Microsoft')
      fail_job!(helpers.describe_graph_failure(response, permission)) unless response.status == OK_STATUS

      body = helpers.graph_json(response)
      values = body['value']
      raise IPaaS::Error, "No value in Microsoft Graph API response: '#{response.body}'" unless values.is_a?(Array)

      { value: values, odata_nextLink: helpers.trusted_next_link(body['@odata.nextLink']),
        odata_count: body['@odata.count']&.to_i, }
    end

    helper :display_name_search do |text|
      "#{SEARCH_QUOTE}displayName:#{text.to_s.delete(SEARCH_QUOTE).strip}#{SEARCH_QUOTE}"
    end

    helper :string_list do |value|
      value.is_a?(Array) ? value.map(&:to_s) : []
    end

    helper :user_summary do |user|
      raise IPaaS::Error, 'Microsoft Graph returned a user with no id' if user['id'].blank?

      {
        user_id: user['id'], display_name: user['displayName'], given_name: user['givenName'],
        surname: user['surname'], user_principal_name: user['userPrincipalName'], mail: user['mail'],
        job_title: user['jobTitle'], department: user['department'], office_location: user['officeLocation'],
        mobile_phone: user['mobilePhone'], business_phones: helpers.string_list(user['businessPhones']),
        account_enabled: user['accountEnabled'], usage_location: user['usageLocation'],
        employee_id: user['employeeId'], company_name: user['companyName'], city: user['city'],
        country: user['country'], created_date_time: user['createdDateTime'],
      }
    end

    helper :default_user_summary do |user|
      helpers.user_summary(user).slice(*DEFAULT_USER_FIELDS)
    end

    helper :active_user_output do |user_id|
      response = helpers.graph_request(:get, "/users/#{user_id}", USER_READ_PERMISSION,
                                       expected: [OK_STATUS, NOT_FOUND_STATUS])
      if response.status == NOT_FOUND_STATUS
        fail_job!("Deleted user ID '#{user_id}' is not a deleted user, and no active user has this ID. " \
                  'Nothing was restored.')
      end

      [{ output: { user: helpers.default_user_summary(helpers.graph_json(response)), already_restored: true } }]
    end

    helper :group_summary do |group|
      raise IPaaS::Error, 'Microsoft Graph returned a group with no id' if group['id'].blank?

      {
        group_id: group['id'], display_name: group['displayName'], description: group['description'],
        mail_nickname: group['mailNickname'], mail: group['mail'], mail_enabled: group['mailEnabled'],
        security_enabled: group['securityEnabled'], group_types: helpers.string_list(group['groupTypes']),
        visibility: group['visibility'], is_assignable_to_role: group['isAssignableToRole'],
        created_date_time: group['createdDateTime'],
      }
    end

    helper :member_summary do |member, fallback_type|
      raise IPaaS::Error, 'Microsoft Graph returned a member with no id' if member['id'].blank?

      {
        member_id: member['id'], odata_type: member['@odata.type'].presence || fallback_type,
        display_name: member['displayName'],
        user_principal_name: member['userPrincipalName'], mail: member['mail'],
      }
    end

    helper :license_summary do |user|
      assigned = user['assignedLicenses'].is_a?(Array) ? user['assignedLicenses'] : []
      states = user['licenseAssignmentStates'].is_a?(Array) ? user['licenseAssignmentStates'] : []
      {
        user_id: user['id'],
        assigned_licenses: assigned.map do |license|
          { sku_id: license['skuId'], disabled_plans: helpers.string_list(license['disabledPlans']) }
        end,
        license_assignment_states: states.map do |state|
          { sku_id: state['skuId'], state: state['state'], error: state['error'],
            assigned_by_group: state['assignedByGroup'], disabled_plans: helpers.string_list(state['disabledPlans']), }
        end,
      }
    end

    helper :changed_fields do |values, mapping|
      mapping.each_with_object({}) do |(input_key, graph_key), body|
        value = values[input_key].to_s.strip
        body[graph_key] = value if value.present?
      end
    end

    helper :directory_object_ref do |id|
      helpers.graph_url("/directoryObjects/#{id}")
    end

    helper :password_profile do |secret, force_change|
      { 'password' => decrypt_secret_string(secret),
        'forceChangePasswordNextSignIn' => helpers.boolean_input(force_change) != false, }
    end

    helper :risky_user_ids do |values|
      ids = helpers.guid_list(values, 'User ID')
      fail_job!('Set at least one user ID.') if ids.empty?

      ids
    end

    helper :generic_url do |path, query|
      clean = path.to_s.strip
      unless clean.start_with?('/') && !GENERIC_PATH_REFUSED.match?(clean)
        fail_job!("Path '#{clean}' must be a Microsoft Graph path that starts with one '/', such as '/users'. " \
                  "It must not hold '..', '://', '\\', '#', spaces, or an encoded '.', '/' or '\\'.")
      end
      pairs = (query.is_a?(Array) ? query : []).filter_map do |pair|
        name = pair[:name].to_s.strip
        name.present? ? [name, pair[:value].to_s] : nil
      end
      url = helpers.graph_url(clean)
      next url if pairs.empty?

      "#{url}#{clean.include?('?') ? '&' : '?'}#{URI.encode_www_form(pairs)}"
    end

    helper :generic_body do |text|
      raw = text.to_s
      next nil if raw.strip.blank?

      parse_json_response(raw, error_message: 'Body must be JSON.')
      raw
    end

    helper :url_postfix_set do
      !trigger.config[:url_postfix].nil?
    end

    helper :subscription_rows do
      stored = outbound_connection.store.read(SUBSCRIPTIONS_STORE_KEY)
      next {} unless stored.is_a?(Hash)

      stored.to_h.transform_values { |row| row.is_a?(Hash) ? row.to_h : {} }
    end

    helper :write_subscription_rows do |rows|
      outbound_connection.store.write(SUBSCRIPTIONS_STORE_KEY, rows)
    end

    helper :own_row do
      helpers.subscription_rows[trigger.runbook.uuid] || {}
    end

    helper :store_own_row do |watch|
      rows = helpers.subscription_rows
      kept = rows[trigger.runbook.uuid]
      same_watch = watch.present? && kept.present? && kept.slice(*WATCH_KEYS) == watch
      row = same_watch ? kept.merge(watch) : watch
      next if kept == row

      if row
        rows[trigger.runbook.uuid] = row
      else
        rows.delete(trigger.runbook.uuid)
      end
      helpers.write_subscription_rows(rows)
    end

    helper :record_watch do |resource, change_type|
      fail_job!(URL_POSTFIX_REFUSED) if helpers.url_postfix_set
      watch = { 'resource' => resource, 'change_type' => change_type, 'endpoint' => trigger.endpoint }
      row = helpers.own_row
      helpers.delete_subscription(row) if row.slice(*WATCH_KEYS) != watch
      helpers.store_own_row(watch)
    end

    helper :forget_watch do
      fail_job!(URL_POSTFIX_REFUSED) if helpers.url_postfix_set
      helpers.delete_subscription(helpers.own_row)
      helpers.store_own_row(nil)
      outbound_connection.store.write("#{REPORTED_STORE_PREFIX}#{trigger.runbook.uuid}", {})
      outbound_connection.store.write("#{UNSEEN_STORE_PREFIX}#{trigger.runbook.uuid}", {})
    end

    helper :validation_token do |request|
      token = begin
        Rack::Utils.parse_query(URI.parse(request.url).query)[VALIDATION_TOKEN_PARAM].to_s
      rescue StandardError
        ''
      end
      if token.length > MAX_VALIDATION_TOKEN_LENGTH
        discard_trigger_event!('A validation token longer than Microsoft sends')
      end

      token
    end

    helper :notifications do |raw_body|
      body = begin
        JSON.parse(raw_body.to_s)
      rescue JSON::ParserError
        fail_job!('This endpoint answers Microsoft Graph, which sends JSON. Its ' \
                  "#{raw_body.to_s.bytesize} byte request body could not be read as JSON.")
      end
      batch = body.is_a?(Hash) ? body['value'] : nil
      # rubocop:disable-next Style/PredicateWithKind, Performance/RedundantEqualityComparisonBlock
      unless batch.is_a?(Array) && batch.any? && batch.all? { |item| item.is_a?(Hash) }
        discard_trigger_event!('A request to this endpoint carried no Microsoft change notification')
      end

      batch
    end

    helper :trusted_notifications do |batch, client_states|
      expected = client_states.map(&:to_s).select(&:present?)
      trusted = batch.select do |item|
        expected.any? { |client_state| OpenSSL.secure_compare(item['clientState'].to_s, client_state) }
      end
      discard_trigger_event!('No notification carried the client state this trigger set') if trusted.empty?
      if trusted.length < batch.length
        log("Ignored #{batch.length - trusted.length} notification(s) with a client state this trigger did not set")
      end

      trusted
    end

    helper :directory_changes do |request|
      discard_trigger_event!(URL_POSTFIX_REFUSED) if helpers.url_postfix_set
      token = helpers.validation_token(request)
      discard_trigger_event!("#{VALIDATION_ECHO_PREFIX}#{token}") if token.present?

      row = helpers.own_row
      expected = [row['client_state'], row['previous_client_state']].map(&:to_s).select(&:present?).map do |secret|
        decrypt_secret_string(secret)
      end
      batch = helpers.trusted_notifications(helpers.notifications(request.body&.read), expected)
      changes = batch.reject { |item| item[LIFECYCLE_EVENT_KEY].present? }
      discard_trigger_event!('A request to this endpoint carried no directory change') if changes.empty?

      helpers.with_object_id(changes)
    end

    helper :changed_object_ids do |changes|
      changes.map { |change| helpers.object_id_of(change).downcase }.uniq
    end

    helper :with_object_id do |changes|
      named = changes.select { |change| helpers.object_id_of(change).present? }
      log("Ignored #{changes.length - named.length} notification(s) with no object id") if named.length < changes.length
      discard_trigger_event!('No notification named a directory object') if named.empty?

      named
    end

    helper :member_changes do |changes, group_id|
      own = changes.select { |change| helpers.object_id_of(change).downcase == group_id.downcase }
      log("Ignored #{changes.length - own.length} notification(s) about another group") if own.length < changes.length
      listed = own.select { |change| change['resourceData'][MEMBERS_DELTA_KEY].is_a?(Array) }
      log("Ignored #{own.length - listed.length} notification(s) that named no member") if listed.length < own.length
      entries = listed.flat_map { |change| change['resourceData'][MEMBERS_DELTA_KEY] }
      named = entries.select { |member| member.is_a?(Hash) && member['id'].present? }
      log("Ignored #{entries.length - named.length} member entry(ies) with no id") if named.length < entries.length

      named.map { |member| { member_id: member['id'].to_s, removed: member.key?(REMOVED_KEY) } }
    end

    helper :object_id_of do |notification|
      resource_data = notification['resourceData']
      resource_data.is_a?(Hash) ? resource_data['id'].to_s : ''
    end

    helper :changed_ids_output do |changes, items_key, id_key|
      { items_key => helpers.changed_object_ids(changes).map { |id| { id_key => id } },
        subscription_id: changes.first['subscriptionId'], }
    end

    helper :new_objects_output do |request, path, items_key, id_key, label|
      started_at = Time.now
      changes = helpers.directory_changes(request)
      since = NEW_OBJECT_WINDOW_MINUTES.minutes.ago
      recent = helpers.created_recently(path, helpers.changed_object_ids(changes), started_at, since)
      discard_trigger_event!("No #{label} in these notifications could be reported as new") if recent.empty?

      created = helpers.claim_unreported(recent, since)
      discard_trigger_event!("Every #{label} in these notifications was already reported") if created.empty?

      { items_key => created.map { |object| { id_key => object['id'], created_date_time: object['createdDateTime'] } },
        subscription_id: changes.first['subscriptionId'], }
    end

    helper :graph_answer do |context, response|
      error = context[:error]
      message = error.is_a?(IPaaS::Job::DiscardTriggerEvent) ? error.message.to_s : ''
      if message.start_with?(VALIDATION_ECHO_PREFIX)
        response[:status] = OK_STATUS
        response[:headers]['content-type'] = VALIDATION_CONTENT_TYPE
        response[:headers]['x-content-type-options'] = NO_SNIFF
        response[:body] = message[VALIDATION_ECHO_PREFIX.length..]
      elsif message.start_with?(GRAPH_RETRY_PREFIX)
        response[:status] = GRAPH_RETRY_STATUS
      end
      response
    end

    helper :ask_again_later do |reason|
      discard_trigger_event!("#{GRAPH_RETRY_PREFIX} #{reason} Microsoft is asked to send these notifications again.")
    end

    helper :created_recently do |path, ids, started_at, since|
      # rubocop:disable-next Style/SelectByRegexp
      guids = ids.select { |id| GUID_PATTERN.match?(id) }
      if guids.length < ids.length
        log("Ignored #{ids.length - guids.length} notification(s) whose object id is not a GUID")
      end
      discard_trigger_event!('No notification named a directory object by a GUID') if guids.empty?
      checked = guids.first(CREATED_LOOKUP_BATCH * BATCH_REQUEST_LIMIT)
      if checked.length < guids.length
        log("#{guids.length} objects changed at once. Only the first #{checked.length} were checked, " \
            'the rest are not reported.')
      end

      left = helpers.lookup_seconds_left(started_at)
      helpers.ask_again_later('There was no time left to check which objects are new.') if left < MIN_LOOKUP_SECONDS

      objects = helpers.objects_by_id(path, checked, CREATED_LOOKUP_SELECT, left)
      missing = checked - objects.map { |object| object['id'] }
      helpers.hold_unless_deleted(path, missing, started_at, since) if missing.any?

      objects.select do |object|
        created = object['createdDateTime'].to_s
        created.present? && Time.parse(created) >= since
      rescue ArgumentError
        log("Microsoft Graph gave object #{object['id']} a creation time that is not a time: '#{created}'")
        false
      end
    rescue IPaaS::Job::DiscardTriggerEvent
      raise
    rescue StandardError => e
      helpers.ask_again_later("Could not check which objects are new. #{e.message}")
    end

    helper :lookup_seconds_left do |started_at|
      CREATED_LOOKUP_DEADLINE_SECONDS - (Time.now - started_at)
    end

    helper :objects_by_id do |path, ids, select, left|
      slices = ids.each_slice(CREATED_LOOKUP_BATCH).to_a
      requests = slices.each_with_index.map do |slice, index|
        query = URI.encode_www_form('$filter' => "id in (#{slice.map { |id| "'#{id}'" }.join(',')})",
                                    '$select' => select, '$top' => CREATED_LOOKUP_BATCH.to_s)
        { id: index.to_s, method: 'GET', url: "#{path}?#{query}" }
      end
      response = http_post(helpers.graph_url(BATCH_PATH), { requests: requests }.to_json, JSON_HEADERS,
                           open_timeout: LOOKUP_OPEN_TIMEOUT_SECONDS, timeout: left)
      raise IPaaS::Error, helpers.describe_graph_failure(response) unless response.status == OK_STATUS

      answers = helpers.batch_answers(helpers.graph_json(response), requests.pluck(:id))
      requests.zip(slices).flat_map do |request, slice|
        answer = answers[request[:id]]
        status = answer.is_a?(Hash) ? answer['status'].to_s.to_i : 0
        next [] if status == NOT_FOUND_STATUS && slice.length == 1 && helpers.not_found_answer?(answer)

        raise IPaaS::Error, helpers.describe_batch_failure(answer) unless status == OK_STATUS

        values = answer['body'].is_a?(Hash) ? answer['body']['value'] : nil
        raise IPaaS::Error, 'Microsoft Graph returned a list that is not a list' unless values.is_a?(Array)

        values.select { |object| object.is_a?(Hash) }.map { |object| object.merge('id' => object['id'].to_s.downcase) }
      end
    end

    helper :hold_unless_deleted do |path, missing, started_at, since|
      left = helpers.lookup_seconds_left(started_at)
      deleted = left >= MIN_LOOKUP_SECONDS ? helpers.deleted_ids(path, missing, left) : []
      log("These changed objects are deleted, so they are not reported: #{deleted.join(', ')}") if deleted.any?
      helpers.hold_unseen(missing - deleted, since)
    end

    helper :deleted_ids do |path, ids, left|
      found = helpers.objects_by_id(DELETED_ITEMS_PATHS.fetch(path), ids, DELETED_LOOKUP_SELECT, left)
      found.map { |object| object['id'] }
    rescue StandardError => e
      log('Could not check which changed objects are deleted, so they are held like objects that Microsoft Graph ' \
          "does not show yet. #{e.message}")
      []
    end

    helper :hold_unseen do |missing, since|
      key = "#{UNSEEN_STORE_PREFIX}#{trigger.runbook.uuid}"
      first_seen = helpers.entries_since(key, since)
      waiting = missing.select do |id|
        next true unless first_seen.key?(id)

        Time.parse(first_seen[id].to_s) > UNSEEN_RETRY_MINUTES.minutes.ago
      rescue ArgumentError
        true
      end
      new_ids = missing.reject { |id| first_seen.key?(id) }.to_h { |id| [id, Time.now.utc.iso8601] }
      outbound_connection.store.write(key, new_ids.merge(helpers.entries_since(key, since))) if new_ids.any?
      helpers.ask_again_later("Microsoft Graph does not show #{waiting.length} changed object(s) yet.") if waiting.any?
      next if missing.empty?

      log("Microsoft Graph did not show these changed objects within #{UNSEEN_RETRY_MINUTES} minutes, " \
          "so they are not reported: #{missing.join(', ')}")
    end

    helper :not_found_answer? do |answer|
      body = answer['body']
      error = body.is_a?(Hash) ? body['error'] : nil
      error.is_a?(Hash) && error['code'] == OBJECT_NOT_FOUND_CODE
    end

    helper :claim_unreported do |created, since|
      key = "#{REPORTED_STORE_PREFIX}#{trigger.runbook.uuid}"
      reported = helpers.entries_since(key, since)
      fresh = created.reject { |object| reported.key?(object['id']) }
      next fresh if fresh.empty?

      newly_reported = fresh.to_h { |object| [object['id'], object['createdDateTime']] }
      outbound_connection.store.write(key, helpers.entries_since(key, since).merge(newly_reported))
      fresh
    end

    helper :entries_since do |key, since|
      stored = outbound_connection.store.read(key)
      (stored.is_a?(Hash) ? stored.to_h : {}).select do |_id, created_at|
        Time.parse(created_at.to_s) >= since
      rescue ArgumentError
        false
      end
    end

    helper :created_subscription do |response|
      unless SUBSCRIPTION_CREATED_STATUSES.include?(response.status)
        fail_job!('Microsoft did not create the subscription. ' \
                  "#{helpers.describe_graph_failure(response, SUBSCRIPTION_PERMISSION)} " \
                  'Microsoft checks that it can reach the trigger before it checks anything else, so it reports an ' \
                  'iPaaS it cannot reach, a runbook that is not deployed and a wrong group alike.')
      end
      body = parse_json_response(response.body.to_s,
                                 error_message: 'Microsoft Graph returned a subscription that is not JSON: ' \
                                                "'#{response.body}'")
      unless body.is_a?(Hash) && GUID_PATTERN.match?(body['id'].to_s)
        fail_job!('Microsoft Graph created a subscription without a valid subscription id. The next run removes it.')
      end

      body
    end

    helper :subscription_expiry do
      (MAX_SUBSCRIPTION_LIFETIME_MINUTES - CLOCK_SKEW_MARGIN_MINUTES).minutes.from_now.utc.iso8601
    end

    helper :create_subscription do |endpoint, resource, change_type|
      fail_job!('This subscription records nothing to watch. Deploy the trigger again.') if resource.blank?

      client_state = SecureRandom.uuid
      expiry = helpers.subscription_expiry
      response = http_post(helpers.graph_url(SUBSCRIPTION_PATH),
                           {
                             changeType: change_type,
                             notificationUrl: endpoint,
                             resource: resource,
                             clientState: client_state,
                             expirationDateTime: expiry,
                           }.to_json,
                           JSON_HEADERS)
      backoff_if_needed(response, api_name: 'Microsoft', server_error_statuses: [])
      subscription = helpers.created_subscription(response)
      { 'id' => subscription['id'], 'client_state' => make_secret_string(client_state).to_s,
        'expires_at' => subscription['expirationDateTime'].presence || expiry, }
    end

    helper :held_subscriptions do
      by_id = {}
      url = helpers.graph_url(SUBSCRIPTION_PATH)
      MAX_SUBSCRIPTION_LIST_REQUESTS.times do
        response = http_get(url)
        backoff_if_needed(response, api_name: 'Microsoft')
        if response.status != OK_STATUS
          raise IPaaS::Error, helpers.describe_graph_failure(response, SUBSCRIPTION_PERMISSION)
        end

        body = helpers.graph_json(response)
        page = body['value']
        # rubocop:disable-next Style/PredicateWithKind, Performance/RedundantEqualityComparisonBlock
        unless page.is_a?(Array) && page.all? { |subscription| subscription.is_a?(Hash) }
          raise IPaaS::Error, 'Microsoft Graph returned a subscription list that is not a list of subscriptions.'
        end

        page.each { |subscription| by_id[subscription['id'].to_s] = subscription }
        url = helpers.trusted_next_link(body['@odata.nextLink'])
        break if url.blank?
      end
      if url.present?
        log("Microsoft holds more subscriptions than #{MAX_SUBSCRIPTION_LIST_REQUESTS} pages list, so this run " \
            'trusts every stored subscription id.')
      end

      { 'by_id' => by_id, 'complete' => url.blank? }
    rescue IPaaS::Job::Outbound::CustomerCredentialsError, IPaaS::Job::RescheduleJob
      raise
    rescue IPaaS::Error, IPaaS::Job::FailJob => e
      log("Microsoft did not list its subscriptions, so this run trusts every stored subscription id: #{e.message}")
      { 'by_id' => by_id, 'complete' => false }
    end

    helper :held_id do |row, held|
      id = helpers.stored_subscription_id(row)
      next nil if id.nil?
      next id unless held['complete']

      held['by_id'].key?(id) ? id : nil
    end

    helper :expiring_soon do |row|
      expires_at = row['expires_at'].to_s
      next true if expires_at.blank?

      Time.parse(expires_at) < RENEWAL_WINDOW_MINUTES.minutes.from_now
    rescue ArgumentError
      true
    end

    helper :remove_unrecorded_subscriptions do |rows, held|
      keys_by_endpoint = rows.to_h { |key, row| [row['endpoint'], key] }
      known = rows.values.map { |row| helpers.stored_subscription_id(row) }
      held['by_id'].values.filter_map do |subscription|
        key = keys_by_endpoint[subscription['notificationUrl']]
        id = helpers.stored_subscription_id(subscription)
        next if key.nil? || id.nil? || known.include?(id)

        recorded = helpers.subscription_rows.values.map { |row| helpers.stored_subscription_id(row) }
        next if recorded.include?(id)

        row = { 'resource' => subscription['resource'], 'change_type' => subscription['changeType'], 'id' => id,
                'expires_at' => subscription['expirationDateTime'], }
        helpers.delete_subscription(row)
        helpers.subscription_result(key, row, OUTCOME_REMOVED, nil)
      rescue IPaaS::Job::Outbound::CustomerCredentialsError
        raise
      rescue IPaaS::Job::FailJob => e
        helpers.subscription_result(key, row, OUTCOME_FAILED, e.message)
      end
    end

    helper :create_subscription_for do |key, row|
      created = row.merge(helpers.create_subscription(row['endpoint'], row['resource'], row['change_type']))
      created['previous_client_state'] = row['client_state'] if row['client_state'].present?
      next helpers.subscription_result(key, created, OUTCOME_CREATED, nil) if helpers.store_result(key, row, created)

      helpers.delete_subscription(created)
      helpers.subscription_result(key, row, OUTCOME_SKIPPED, ROW_CHANGED_WHILE_ANSWERING)
    rescue IPaaS::Job::Outbound::CustomerCredentialsError
      raise
    rescue IPaaS::Job::FailJob => e
      helpers.subscription_result(key, row, OUTCOME_FAILED, e.message)
    end

    helper :renew_batch do |slice|
      expiry = helpers.subscription_expiry
      requests = slice.each_with_index.map do |pair, index|
        _key, row = pair
        { id: index.to_s, method: 'PATCH', url: "#{SUBSCRIPTION_PATH}/#{helpers.stored_subscription_id(row)}",
          headers: JSON_HEADERS, body: { expirationDateTime: expiry }, }
      end
      response = http_post(helpers.graph_url(BATCH_PATH), { requests: requests }.to_json, JSON_HEADERS)
      backoff_if_needed(response, api_name: 'Microsoft', server_error_statuses: TRANSIENT_SERVER_ERROR_STATUSES)
      if response.status != OK_STATUS
        raise IPaaS::Error, helpers.describe_graph_failure(response, SUBSCRIPTION_PERMISSION)
      end

      answers = helpers.batch_answers(helpers.graph_json(response), requests.pluck(:id))
      slice.each_with_index.map do |pair, index|
        key, row = pair
        helpers.renewal_result(key, row, answers[index.to_s], expiry)
      end
    rescue IPaaS::Job::Outbound::CustomerCredentialsError, IPaaS::Job::RescheduleJob
      raise
    rescue IPaaS::Error => e
      slice.map { |pair| helpers.subscription_result(pair.first, pair.last, OUTCOME_FAILED, e.message) }
    end

    helper :batch_answers do |body, sent|
      answers = body['responses']
      unless answers.is_a?(Array)
        raise IPaaS::Error, 'Microsoft Graph returned a batch answer whose responses are not a list'
      end
      # rubocop:disable-next Style/PredicateWithKind, Performance/RedundantEqualityComparisonBlock
      unless answers.all? { |answer| answer.is_a?(Hash) }
        raise IPaaS::Error, 'Microsoft Graph returned a batch answer with a response that is not an object'
      end

      by_id = answers.index_by { |answer| answer['id'].to_s }
      if by_id.length != answers.length
        raise IPaaS::Error, 'Microsoft Graph answered one request of this batch more than once'
      end

      unexpected = by_id.keys.reject { |id| sent.include?(id) }
      if unexpected.present?
        raise IPaaS::Error, "Microsoft Graph answered request '#{unexpected.first}', which this batch never sent"
      end

      by_id
    end

    helper :describe_batch_failure do |answer|
      next 'Microsoft Graph returned no answer for this request.' if answer.blank?

      body = answer['body'].is_a?(Hash) ? answer['body'] : {}
      error = body['error'].is_a?(Hash) ? body['error'] : {}
      helpers.graph_failure_text(answer['status'], error, 'no error details')
    end

    helper :renewal_result do |key, row, answer, expiry|
      status = answer.is_a?(Hash) ? answer['status'].to_s.to_i : 0
      next helpers.create_subscription_for(key, row) if status == NOT_FOUND_STATUS
      unless status == OK_STATUS
        next helpers.subscription_result(key, row, OUTCOME_FAILED, helpers.describe_batch_failure(answer))
      end

      body = answer['body'].is_a?(Hash) ? answer['body'] : {}
      renewed = row.merge('expires_at' => body['expirationDateTime'].presence || expiry)
      next helpers.subscription_result(key, renewed, OUTCOME_RENEWED, nil) if helpers.store_result(key, row, renewed)

      helpers.subscription_result(key, row, OUTCOME_SKIPPED, ROW_CHANGED_WHILE_ANSWERING)
    end

    helper :store_result do |key, before, after|
      rows = helpers.subscription_rows
      current = rows[key]
      unchanged = rows.key?(key) && current.slice(*WATCH_KEYS) == before.slice(*WATCH_KEYS) &&
                  helpers.stored_subscription_id(current) == helpers.stored_subscription_id(before)
      next false unless unchanged

      helpers.write_subscription_rows(rows.merge(key => after))
      true
    end

    helper :subscription_result do |key, row, outcome, error|
      { runbook_id: key, resource: row['resource'], change_type: row['change_type'], subscription_id: row['id'],
        expires_at: row['expires_at'].presence, outcome: outcome, error: error, }
    end

    helper :stored_subscription_id do |row|
      stored = row.is_a?(Hash) ? row : {}
      id = stored['id'].to_s.strip
      GUID_PATTERN.match?(id) ? id : nil
    end

    helper :delete_subscription do |row|
      id = helpers.stored_subscription_id(row)
      if id.present?
        response = http_delete(helpers.graph_url("#{SUBSCRIPTION_PATH}/#{id}"))
        backoff_if_needed(response, api_name: 'Microsoft')
        deleted = response.status == NO_CONTENT_STATUS
        gone = response.status == NOT_FOUND_STATUS
        fail_job!(helpers.describe_graph_failure(response, SUBSCRIPTION_PERMISSION)) unless deleted || gone
      end

      id
    end
  end
end
