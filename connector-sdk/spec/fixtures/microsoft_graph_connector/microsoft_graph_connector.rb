class MicrosoftGraphConnector < IPaaS::Connector::Definition
  GRAPH_API_BASE = 'https://graph.microsoft.com/v1.0'.freeze
  GRAPH_LOGIN_BASE = 'https://login.microsoftonline.com'.freeze
  GRAPH_DEFAULT_SCOPE = 'https://graph.microsoft.com/.default'.freeze
  # Microsoft Graph's maximum subscription lifetime for message resources is 4230 minutes (~2.94 days).
  # See https://learn.microsoft.com/en-us/graph/api/resources/subscription
  MAIL_SUBSCRIPTION_MAX_MINUTES = 4230
  GRAPH_SERVER_ERROR_STATUSES = [503, 504].freeze

  connector '019ff9e8-8af5-75e8-941c-66be5c24a6a1' do
    name 'Microsoft Graph API'
    avatar '/assets/icons/microsoft-graph.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Connects to [Microsoft Graph](https://learn.microsoft.com/en-us/graph/overview) to manage Microsoft 365
      users, mail, OneDrive files, and Intune-managed devices from a runbook, and to start a runbook when new
      mail arrives in a mailbox.

      ## Prerequisites
      - An Azure AD (Microsoft Entra ID) [app registration](https://learn.microsoft.com/en-us/graph/auth-register-app-v2)
        with **application** (not delegated) API permissions granted, and admin-consented, for the Graph scopes
        the actions you use need, e.g. `User.Read.All`, `Mail.Send`, `Mail.ReadWrite`, `Files.ReadWrite.All`,
        `DeviceManagementManagedDevices.Read.All`.
      - The app registration's **Tenant ID**, **Client ID**, and a **Client secret** value.

      ## Authentication
      Uses the OAuth 2 **client credentials** grant (app-only access) against your tenant's token endpoint.
      No end-user sign-in is involved; every action calls Graph as the application itself, so the app
      registration must be granted (and have admin consent for) the application permissions each action needs.
      Delegated, user-context access (the authorization code grant) is not supported by this connector.

      ## Actions
      - **List users** — lists users in the directory, with paging and an optional `$filter`.
      - **Get user** — retrieves a single user's profile.
      - **Send mail** — sends a message from a mailbox.
      - **Move mail message** — moves a message to another mail folder.
      - **Upload file** — uploads a small file (up to 4 MB) to a user's OneDrive.
      - **Download file** — downloads a OneDrive file's content.
      - **Create shareable link** — creates a sharing link for a OneDrive item.
      - **List managed devices** — lists Intune-managed devices.
      - **Renew mail subscription** — extends a **New mail received** trigger's change-notification
        subscription before it expires. Schedule this to run periodically (e.g. via the **Scheduler**
        connector) — see that trigger's description.

      ## Triggers
      - **New mail received** — starts the runbook when a message arrives in a mailbox, via a Microsoft
        Graph change-notification subscription.

      ## Rate Limiting and Error Handling
      Graph returns `429` with a `Retry-After` header when throttled, and occasionally `503`/`504` when
      temporarily unavailable; the connector backs off on those and lets iPaaS retry automatically. Any other
      non-success response fails the step with the Graph error code and message when available.
    END_OF_DESCRIPTION

    outbound_connection do
      config_schema do
        field :credentials, 'Credentials', :nested,
              required: true,
              hint: 'Application (client) credentials from your Azure AD app registration. Requires ' \
                    'application-type API permissions, admin-consented for your tenant.' do
          field :tenant_id, 'Tenant ID', :string,
                required: true,
                hint: 'Directory (tenant) ID of the Azure AD tenant the app is registered in.'
          field :client_id, 'Client ID', :string,
                required: true,
                hint: 'Application (client) ID of the Azure AD app registration.'
          field :client_secret, 'Client secret', :secret_string,
                required: true,
                hint: 'A client secret value generated for the app registration.'
        end
      end

      authenticate do |request|
        credentials = config[:credentials]
        body = oauth2_client_credentials_body(credentials[:client_id],
                                              decrypt_secret_string(credentials[:client_secret]))
        body[:scope] = GRAPH_DEFAULT_SCOPE
        request.headers['Authorization'] = oauth2_authorization_header(helpers.graph_token_url, body)
      end

      config_tester do
        response = http_get(helpers.graph_url('users'), { '$top' => '1' }, nil, open_timeout: 2, timeout: 5)
        if response.status == 200
          { status: :success, message: 'Connection successful.' }
        elsif [401, 403].include?(response.status)
          { status: :failed, message: "Microsoft Graph rejected the credentials (HTTP #{response.status})." }
        else
          { status: :error, message: "Unable to reach Microsoft Graph (HTTP #{response.status}): '#{response.body}'" }
        end
      rescue IPaaS::Job::Outbound::CustomerCredentialsError => e
        { status: :failed, message: e.message }
      end
    end

    # ──────────────────────────────────────────────
    # Action: List users
    # ──────────────────────────────────────────────

    action '019ff9e8-8af5-7110-b964-3a7e3beb2691' do
      name 'List users'
      avatar '/assets/icons/microsoft-graph.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Lists users in the directory (`GET /users`), paging through all results.

        #### Input Parameters
        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | filter | String | No | - | OData `$filter` expression, e.g. `accountEnabled eq true`. |
        | page_size | Integer | No | 100 | Number of users per page (max 999). |

        #### Output
        | Field | Type | Description |
        |---|---|---|
        | has_next_page | Boolean | `true` while more pages remain. |
        | users | Array | One object per user — id, display_name, user_principal_name, mail, job_title, office_location, mobile_phone, account_enabled. |
      END_OF_DESCRIPTION

      input_schema do
        field :filter, 'Filter ($filter)', :string,
              visibility: 'optional',
              hint: 'OData $filter expression, e.g. "accountEnabled eq true".'
        field :page_size, 'Page size', :integer,
              min: 1, max: 999,
              visibility: 'optional',
              default: 100,
              hint: 'Number of users per page (max 999).'
      end

      output_schema 'page' do
        field :has_next_page, 'Has next page', :boolean, required: true
        field :users, 'Users', :nested, array: true do
          field :id, 'ID', :string, required: true
          field :display_name, 'Display name', :string
          field :user_principal_name, 'User principal name', :string
          field :mail, 'Mail', :string
          field :job_title, 'Job title', :string
          field :office_location, 'Office location', :string
          field :mobile_phone, 'Mobile phone', :string
          field :account_enabled, 'Account enabled', :boolean
        end
      end

      iteration_state_schema do
        field :next_link, 'Next link', :string
      end

      run do
        next_link = iteration_state_value(:next_link)
        result = if next_link.present?
                   helpers.graph_get_url(next_link)
                 else
                   query = { '$top' => input[:page_size].to_s }
                   query['$filter'] = input[:filter] if input[:filter].present?
                   helpers.graph_get('users', query)
                 end

        users = Array(result[:value]).map { |u| helpers.map_graph_user(u) }
        new_next_link = result[:'@odata.nextLink']
        self.iteration_state_value = new_next_link.present? ? { next_link: new_next_link } : nil

        [{ output: { has_next_page: iteration_state_value.present?, users: users }, schema_reference: 'page' }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Get user
    # ──────────────────────────────────────────────

    action '019ff9e8-8af5-70fb-8db3-c22f6f6d907f' do
      name 'Get user'
      avatar '/assets/icons/microsoft-graph.svg'
      description <<~END_OF_DESCRIPTION
        Retrieves a single user's profile (`GET /users/{id}`).

        #### Input Parameters
        | Parameter | Type | Required | Description |
        |---|---|---|---|
        | user_id | String | Yes | User ID or userPrincipalName (email). |
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'User', :string,
              required: true,
              hint: "The user's ID or userPrincipalName (email)."
      end

      output_schema do
        field :id, 'ID', :string, required: true
        field :display_name, 'Display name', :string
        field :user_principal_name, 'User principal name', :string
        field :mail, 'Mail', :string
        field :job_title, 'Job title', :string
        field :office_location, 'Office location', :string
        field :mobile_phone, 'Mobile phone', :string
        field :account_enabled, 'Account enabled', :boolean
      end

      run do
        user = helpers.graph_get("users/#{input[:user_id]}")
        [{ output: helpers.map_graph_user(user) }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Send mail
    # ──────────────────────────────────────────────

    action '019ff9e8-8af5-764a-8c05-e3165e778e98' do
      name 'Send mail'
      avatar '/assets/icons/microsoft-graph.svg'
      description <<~END_OF_DESCRIPTION
        Sends a message from a mailbox (`POST /users/{id}/sendMail`). Requires the `Mail.Send` application
        permission.

        #### Input Parameters
        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | user_id | String | Yes | - | The sending mailbox's user ID or userPrincipalName (email). |
        | subject | String | Yes | - | Message subject. |
        | body_content | String | Yes | - | Message body. |
        | body_content_type | String | No | HTML | `Text` or `HTML`. |
        | to_recipients | Array of String | Yes | - | Recipient email addresses. |
        | cc_recipients | Array of String | No | - | Cc email addresses. |
        | save_to_sent_items | Boolean | No | true | Whether to save a copy to Sent Items. |
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'From (mailbox user)', :string,
              required: true,
              hint: "The sending mailbox's user ID or userPrincipalName (email)."
        field :subject, 'Subject', :string, required: true
        field :body_content, 'Body', :string, required: true
        field :body_content_type, 'Body content type', :string,
              visibility: 'optional',
              default: 'HTML',
              enumeration: %w[Text HTML]
        field :to_recipients, 'To recipients', :string,
              array: true, required: true,
              hint: 'Recipient email addresses.'
        field :cc_recipients, 'Cc recipients', :string,
              array: true, visibility: 'optional',
              hint: 'Cc email addresses.'
        field :save_to_sent_items, 'Save to Sent Items', :boolean,
              visibility: 'optional', default: true
      end

      output_schema do
        field :sent, 'Sent', :boolean, required: true
      end

      run do
        message = {
          subject: input[:subject],
          body: { contentType: input[:body_content_type], content: input[:body_content] },
          toRecipients: Array(input[:to_recipients]).map { |address| { emailAddress: { address: address } } },
        }
        cc_recipients = Array(input[:cc_recipients])
        if cc_recipients.any?
          message[:ccRecipients] = cc_recipients.map do |address|
            { emailAddress: { address: address } }
          end
        end

        body = { message: message, saveToSentItems: input[:save_to_sent_items] }
        response = http_post(helpers.graph_url("users/#{input[:user_id]}/sendMail"), body.to_json,
                             { 'Content-Type' => 'application/json' })
        backoff_if_needed(response, api_name: 'Microsoft Graph', server_error_statuses: GRAPH_SERVER_ERROR_STATUSES)
        helpers.graph_ensure_success(response)

        [{ output: { sent: true } }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Move mail message
    # ──────────────────────────────────────────────

    action '019ff9e8-8af5-7e12-b3d0-9b16fa604a52' do
      name 'Move mail message'
      avatar '/assets/icons/microsoft-graph.svg'
      description <<~END_OF_DESCRIPTION
        Moves a message to another mail folder (`POST /users/{id}/messages/{message-id}/move`).

        #### Input Parameters
        | Parameter | Type | Required | Description |
        |---|---|---|---|
        | user_id | String | Yes | Mailbox user ID or userPrincipalName. |
        | message_id | String | Yes | ID of the message to move. |
        | destination_folder_id | String | Yes | Well-known folder name (e.g. `archive`, `deleteditems`) or a mail folder ID. |
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'Mailbox user', :string, required: true
        field :message_id, 'Message ID', :string, required: true
        field :destination_folder_id, 'Destination folder', :string,
              required: true,
              hint: 'Well-known folder name (e.g. "archive", "deleteditems") or a mail folder ID.'
      end

      output_schema do
        field :message_id, 'Message ID', :string, required: true
        field :parent_folder_id, 'Parent folder ID', :string
      end

      run do
        result = helpers.graph_post("users/#{input[:user_id]}/messages/#{input[:message_id]}/move",
                                    { destinationId: input[:destination_folder_id] })
        [{ output: { message_id: result[:id], parent_folder_id: result[:parentFolderId] } }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Upload file
    # ──────────────────────────────────────────────

    action '019ff9e8-8af5-742f-86bc-75cb94125756' do
      name 'Upload file'
      avatar '/assets/icons/microsoft-graph.svg'
      description <<~END_OF_DESCRIPTION
        Uploads a small file (up to 4 MB) to a user's OneDrive (`PUT /users/{id}/drive/root:/{path}:/content`).
        Larger files need a resumable upload session, which this action does not implement.

        #### Input Parameters
        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | user_id | String | Yes | - | OneDrive owner's user ID or userPrincipalName. |
        | file_path | String | Yes | - | Destination path in the drive, e.g. `/Documents/report.pdf`. |
        | content | Base64 | Yes | - | File content. |
        | content_type | String | No | application/octet-stream | Content type of the file. |
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'Drive owner (user)', :string, required: true
        field :file_path, 'File path', :string,
              required: true,
              hint: 'Destination path in the drive, e.g. "/Documents/report.pdf".'
        field :content, 'Content', :base64, required: true
        field :content_type, 'Content type', :string,
              visibility: 'optional',
              default: 'application/octet-stream'
      end

      output_schema do
        field :item_id, 'Item ID', :string, required: true
        field :name, 'Name', :string
        field :web_url, 'Web URL', :string
        field :size, 'Size', :integer
      end

      run do
        path = input[:file_path].to_s.sub(%r{\A/+}, '')
        binary_content = Base64.strict_decode64(input[:content])
        url = helpers.graph_url("users/#{input[:user_id]}/drive/root:/#{path}:/content")
        headers = { 'Content-Type' => input[:content_type].presence || 'application/octet-stream' }

        response = http_put(url, binary_content, headers)
        backoff_if_needed(response, api_name: 'Microsoft Graph', server_error_statuses: GRAPH_SERVER_ERROR_STATUSES)
        item = helpers.graph_json(response)

        [{ output: { item_id: item[:id], name: item[:name], web_url: item[:webUrl], size: item[:size] } }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Download file
    # ──────────────────────────────────────────────

    action '019ff9e8-8af5-7ea7-8a15-37afdf2e2b61' do
      name 'Download file'
      avatar '/assets/icons/microsoft-graph.svg'
      description <<~END_OF_DESCRIPTION
        Downloads a OneDrive item's content (`GET /users/{id}/drive/items/{item-id}/content`).

        #### Input Parameters
        | Parameter | Type | Required | Description |
        |---|---|---|---|
        | user_id | String | Yes | OneDrive owner's user ID or userPrincipalName. |
        | item_id | String | Yes | DriveItem ID, e.g. from **Upload file**. |
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'Drive owner (user)', :string, required: true
        field :item_id, 'Item ID', :string, required: true
      end

      output_schema do
        field :content, 'Content', :base64, required: true
        field :content_type, 'Content type', :string
        field :file_name, 'File name', :string
        field :size, 'Size', :integer
      end

      run do
        content_url = helpers.graph_url("users/#{input[:user_id]}/drive/items/#{input[:item_id]}/content")
        response = http_get(content_url)
        backoff_if_needed(response, api_name: 'Microsoft Graph', server_error_statuses: GRAPH_SERVER_ERROR_STATUSES)

        if [301, 302, 303, 307, 308].include?(response.status)
          redirect_url = response.headers['location']
          fail_job!('Microsoft Graph did not include a redirect location for the file content.') if redirect_url.blank?
          response = http_get(redirect_url, nil, nil, skip_authentication: true)
        end

        unless response.status == 200
          fail_job!("HTTP error from Microsoft Graph API: #{response.status} '#{response.body}'")
        end

        metadata = helpers.graph_get("users/#{input[:user_id]}/drive/items/#{input[:item_id]}")

        [{ output: {
          content: response.body,
          content_type: response.headers['content-type'],
          file_name: metadata[:name],
          size: metadata[:size],
        } }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Create shareable link
    # ──────────────────────────────────────────────

    action '019ff9e8-8af5-7800-b158-cfe71c494c0e' do
      name 'Create shareable link'
      avatar '/assets/icons/microsoft-graph.svg'
      description <<~END_OF_DESCRIPTION
        Creates a sharing link for a OneDrive item (`POST /users/{id}/drive/items/{item-id}/createLink`).

        #### Input Parameters
        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | user_id | String | Yes | - | OneDrive owner's user ID or userPrincipalName. |
        | item_id | String | Yes | - | DriveItem ID. |
        | link_type | String | No | view | `view`, `edit`, or `embed`. |
        | link_scope | String | No | organization | `anonymous` or `organization`. |
      END_OF_DESCRIPTION

      input_schema do
        field :user_id, 'Drive owner (user)', :string, required: true
        field :item_id, 'Item ID', :string, required: true
        field :link_type, 'Link type', :string,
              visibility: 'optional', default: 'view',
              enumeration: %w[view edit embed]
        field :link_scope, 'Link scope', :string,
              visibility: 'optional', default: 'organization',
              enumeration: %w[anonymous organization]
      end

      output_schema do
        field :id, 'Permission ID', :string
        field :web_url, 'Web URL', :string
        field :link_type, 'Link type', :string
        field :link_scope, 'Link scope', :string
      end

      run do
        body = { type: input[:link_type], scope: input[:link_scope] }
        result = helpers.graph_post("users/#{input[:user_id]}/drive/items/#{input[:item_id]}/createLink", body)
        link = result[:link] || {}

        [{ output: {
          id: result[:id],
          web_url: link[:webUrl],
          link_type: link[:type],
          link_scope: link[:scope],
        } }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: List managed devices
    # ──────────────────────────────────────────────

    action '019ff9e8-8af5-7c17-bc22-e10d57fb9bb4' do
      name 'List managed devices'
      avatar '/assets/icons/microsoft-graph.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Lists Intune-managed devices (`GET /deviceManagement/managedDevices`), paging through all results.
        Requires the `DeviceManagementManagedDevices.Read.All` application permission.

        #### Input Parameters
        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | filter | String | No | - | OData `$filter` expression. |
        | page_size | Integer | No | 100 | Number of devices per page (max 1000). |

        #### Output
        | Field | Type | Description |
        |---|---|---|
        | has_next_page | Boolean | `true` while more pages remain. |
        | devices | Array | One object per device. |
      END_OF_DESCRIPTION

      input_schema do
        field :filter, 'Filter ($filter)', :string, visibility: 'optional'
        field :page_size, 'Page size', :integer,
              min: 1, max: 1000,
              visibility: 'optional',
              default: 100,
              hint: 'Number of devices per page (max 1000).'
      end

      output_schema 'page' do
        field :has_next_page, 'Has next page', :boolean, required: true
        field :devices, 'Devices', :nested, array: true do
          field :id, 'ID', :string, required: true
          field :device_name, 'Device name', :string
          field :operating_system, 'Operating system', :string
          field :os_version, 'OS version', :string
          field :compliance_state, 'Compliance state', :string
          field :managed_device_owner_type, 'Managed device owner type', :string
          field :user_principal_name, 'User principal name', :string
          field :last_sync_date_time, 'Last sync at', :date_time
          field :model, 'Model', :string
          field :manufacturer, 'Manufacturer', :string
          field :serial_number, 'Serial number', :string
        end
      end

      iteration_state_schema do
        field :next_link, 'Next link', :string
      end

      run do
        next_link = iteration_state_value(:next_link)
        result = if next_link.present?
                   helpers.graph_get_url(next_link)
                 else
                   query = { '$top' => input[:page_size].to_s }
                   query['$filter'] = input[:filter] if input[:filter].present?
                   helpers.graph_get('deviceManagement/managedDevices', query)
                 end

        devices = Array(result[:value]).map { |d| helpers.map_graph_device(d) }
        new_next_link = result[:'@odata.nextLink']
        self.iteration_state_value = new_next_link.present? ? { next_link: new_next_link } : nil

        [{ output: { has_next_page: iteration_state_value.present?, devices: devices }, schema_reference: 'page' }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Renew mail subscription
    # ──────────────────────────────────────────────

    action '019ff9e8-8af5-762d-be39-e82b1cbdebb0' do
      name 'Renew mail subscription'
      avatar '/assets/icons/microsoft-graph.svg'
      description <<~END_OF_DESCRIPTION
        Extends a **New mail received** trigger's Microsoft Graph change-notification subscription before it
        expires. Message subscriptions last at most ~2.94 days, so schedule this action to run periodically
        (e.g. every day, via the **Scheduler** connector's **Scheduler** trigger feeding a runbook that calls
        this action) against the same runbook that uses the **New mail received** trigger.

        #### Input Parameters
        | Parameter | Type | Required | Description |
        |---|---|---|---|
        | mail_trigger_runbook | Runbook | Yes | The runbook using the **New mail received** trigger whose subscription should be renewed. |

        #### Error Handling
        Fails the step if no active subscription is found for that runbook — the trigger's runbook must be
        enabled (provisioned) at least once before this action can renew it.
      END_OF_DESCRIPTION

      input_schema do
        field :mail_trigger_runbook, 'Mail trigger runbook', :runbook,
              required: true,
              hint: 'The runbook using the New mail received trigger whose subscription should be renewed.'
      end

      output_schema do
        field :subscription_id, 'Subscription ID', :string, required: true
        field :expiration_date_time, 'New expiration', :date_time, required: true
      end

      run do
        target_runbook = input[:mail_trigger_runbook]
        subscription_id = outbound_connection.store.read(helpers.graph_mail_subscription_store_key(target_runbook.uuid))
        if subscription_id.blank?
          fail_job!('No active Microsoft Graph subscription found for that runbook. Has the trigger been enabled?')
        end

        new_expiration = MAIL_SUBSCRIPTION_MAX_MINUTES.minutes.from_now
        helpers.graph_patch("subscriptions/#{subscription_id}", { expirationDateTime: new_expiration.iso8601 })

        [{ output: { subscription_id: subscription_id, expiration_date_time: new_expiration } }]
      end
    end

    # ──────────────────────────────────────────────
    # Trigger: New mail received
    # ──────────────────────────────────────────────

    trigger '019ff9e8-8af5-7641-b431-cff496f653ae' do
      name 'New mail received'
      avatar '/assets/icons/microsoft-graph.svg'
      outbound_traffic true
      description <<~END_OF_DESCRIPTION
        Starts the runbook when a message arrives in a mailbox, via a Microsoft Graph change-notification
        subscription on `users/{id}/mailFolders('{folder}')/messages`.

        #### Subscription lifecycle
        - **Provisioning** (enabling the runbook) creates the Graph subscription and stores its ID and a
          generated `clientState` secret against this connection.
        - **Deprovisioning** (disabling or deleting the runbook) deletes the subscription.
        - Microsoft Graph's validation handshake (a `validationToken` query parameter sent when the
          subscription is created) is answered automatically — no runbook job is created for it.
        - **Message subscriptions expire after ~2.94 days.** Schedule the **Renew mail subscription** action
          (e.g. daily, via the **Scheduler** connector) against this runbook to keep it alive, or the
          subscription will silently stop delivering notifications once it expires.

        #### Limitations
        A single Graph notification call can carry more than one event. This trigger processes only the
        first event in each call and logs how many additional events were dropped; for high-volume mailboxes,
        consider a dedicated subscription per mailbox to reduce batching.

        #### Input Parameters
        | Parameter | Type | Required | Default | Description |
        |---|---|---|---|---|
        | mailbox_user_id | String | Yes | - | Mailbox to watch: user ID or userPrincipalName (email). |
        | folder | String | No | inbox | Well-known folder name (e.g. `inbox`, `archive`) or a mail folder ID. |

        #### Output
        | Field | Type | Description |
        |---|---|---|
        | message_id | String | ID of the new message. |
        | subject | String | Message subject. |
        | body_preview | String | Short preview of the message body. |
        | from_address | String | Sender's email address. |
        | from_name | String | Sender's display name. |
        | received_date_time | DateTime | When the message was received. |
        | has_attachments | Boolean | Whether the message has attachments. |
        | importance | String | Message importance. |
        | web_link | String | Link to open the message in Outlook on the web. |
      END_OF_DESCRIPTION

      config_schema do
        field :mailbox_user_id, 'Mailbox user', :string,
              required: true,
              hint: "The mailbox to watch, as a user ID or userPrincipalName (email), e.g. 'jane@contoso.com'."
        field :folder, 'Mail folder', :string,
              visibility: 'optional',
              default: 'inbox',
              hint: "Well-known folder name (e.g. 'inbox', 'archive', 'sentitems') or a mail folder ID."
      end

      output_schema do
        field :message_id, 'Message ID', :string, required: true
        field :subject, 'Subject', :string
        field :body_preview, 'Body preview', :string
        field :from_address, 'From address', :string
        field :from_name, 'From name', :string
        field :received_date_time, 'Received at', :date_time
        field :has_attachments, 'Has attachments', :boolean
        field :importance, 'Importance', :string
        field :web_link, 'Web link', :string
      end

      parse do |request|
        validation_token = request.params['validationToken']
        if validation_token.present?
          discard_trigger_event!('Responding to Microsoft Graph subscription validation request.')
        end

        body = JSON.parse(request.body&.read || '{}')
        notifications = Array(body['value'])
        fail_job!('Microsoft Graph notification contained no items.') if notifications.blank?

        if notifications.size > 1
          log("Received #{notifications.size} notifications in one call; processing only the first, the " \
              "other #{notifications.size - 1} are dropped.")
        end

        notification = notifications.first
        stored_client_state = outbound_connection.store.read(
          helpers.graph_mail_client_state_store_key(trigger.runbook.uuid),
        )
        if stored_client_state.present? && notification['clientState'] != stored_client_state
          fail_job!('Microsoft Graph notification clientState did not match the stored value; discarding as untrusted.')
        end

        message_id = notification.dig('resourceData', 'id')
        fail_job!('Microsoft Graph notification did not include a message id.') if message_id.blank?

        message = helpers.graph_get("users/#{trigger.config[:mailbox_user_id]}/messages/#{message_id}")
        helpers.map_graph_mail_notification(message)
      end

      respond_with do |context, response|
        validation_token = context[:request].params['validationToken']
        if validation_token.present?
          response[:status] = 200
          response[:headers]['content-type'] = 'text/plain; charset=utf-8'
          response[:body] = validation_token
        end
        response
      end

      provision do
        client_state = SecureRandom.uuid
        folder = trigger.config[:folder].presence || 'inbox'
        resource = "users/#{trigger.config[:mailbox_user_id]}/mailFolders('#{folder}')/messages"
        subscription = helpers.graph_post('subscriptions', {
          changeType: 'created',
          notificationUrl: trigger.endpoint,
          resource: resource,
          expirationDateTime: MAIL_SUBSCRIPTION_MAX_MINUTES.minutes.from_now.iso8601,
          clientState: client_state,
        })

        outbound_connection.store.write(helpers.graph_mail_subscription_store_key(trigger.runbook.uuid),
                                        subscription[:id])
        outbound_connection.store.write(helpers.graph_mail_client_state_store_key(trigger.runbook.uuid), client_state)
      end

      deprovision do
        subscription_id = outbound_connection.store.read(
          helpers.graph_mail_subscription_store_key(trigger.runbook.uuid),
        )
        next if subscription_id.blank?

        helpers.graph_delete("subscriptions/#{subscription_id}")
      end

      helper :map_graph_mail_notification do |message|
        from = message[:from] || {}
        email_address = from[:emailAddress] || {}
        {
          message_id: message[:id],
          subject: message[:subject],
          body_preview: message[:bodyPreview],
          from_address: email_address[:address],
          from_name: email_address[:name],
          received_date_time: message[:receivedDateTime],
          has_attachments: message[:hasAttachments],
          importance: message[:importance],
          web_link: message[:webLink],
        }
      end
    end

    # ──────────────────────────────────────────────
    # Connector-level helpers: Microsoft Graph HTTP plumbing
    # ──────────────────────────────────────────────

    helper :graph_token_url do
      "#{GRAPH_LOGIN_BASE}/#{outbound_connection.config[:credentials][:tenant_id]}/oauth2/v2.0/token"
    end

    helper :graph_url do |path|
      "#{GRAPH_API_BASE}/#{path}"
    end

    helper :graph_get do |path, query = {}|
      response = http_get(helpers.graph_url(path), query)
      backoff_if_needed(response, api_name: 'Microsoft Graph', server_error_statuses: GRAPH_SERVER_ERROR_STATUSES)
      helpers.graph_json(response)
    end

    # `url` is expected to be a full, self-contained URL, e.g. an '@odata.nextLink' from a previous page.
    helper :graph_get_url do |url|
      response = http_get(url)
      backoff_if_needed(response, api_name: 'Microsoft Graph', server_error_statuses: GRAPH_SERVER_ERROR_STATUSES)
      helpers.graph_json(response)
    end

    helper :graph_post do |path, body|
      response = http_post(helpers.graph_url(path), body.to_json, { 'Content-Type' => 'application/json' })
      backoff_if_needed(response, api_name: 'Microsoft Graph', server_error_statuses: GRAPH_SERVER_ERROR_STATUSES)
      helpers.graph_json(response)
    end

    helper :graph_patch do |path, body|
      response = http_patch(helpers.graph_url(path), body.to_json, { 'Content-Type' => 'application/json' })
      backoff_if_needed(response, api_name: 'Microsoft Graph', server_error_statuses: GRAPH_SERVER_ERROR_STATUSES)
      helpers.graph_json(response)
    end

    helper :graph_delete do |path|
      response = http_delete(helpers.graph_url(path))
      backoff_if_needed(response, api_name: 'Microsoft Graph', server_error_statuses: GRAPH_SERVER_ERROR_STATUSES)
      helpers.graph_ensure_success(response) unless response.status == 404
    end

    helper :graph_ensure_success do |response|
      next if [200, 201, 202, 204].include?(response.status)

      error = helpers.graph_error_from_body(response.body)
      fail_job!("Microsoft Graph API error [#{error['code']}]: #{error['message']}") if error.present?

      fail_job!("HTTP error from Microsoft Graph API: #{response.status} '#{response.body}'")
    end

    helper :graph_error_from_body do |raw_body|
      next nil if raw_body.blank?

      parsed = begin
        JSON.parse(raw_body)
      rescue JSON::ParserError
        nil
      end
      parsed.is_a?(Hash) ? parsed['error'] : nil
    end

    helper :graph_json do |response|
      helpers.graph_ensure_success(response)
      next {} if response.body.blank?

      parsed = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        fail_job!("Microsoft Graph returned a non-JSON response (HTTP #{response.status}): '#{response.body}'")
      end
      parsed.with_indifferent_access
    end

    helper :map_graph_user do |u|
      {
        id: u[:id],
        display_name: u[:displayName],
        user_principal_name: u[:userPrincipalName],
        mail: u[:mail],
        job_title: u[:jobTitle],
        office_location: u[:officeLocation],
        mobile_phone: u[:mobilePhone],
        account_enabled: u[:accountEnabled],
      }
    end

    helper :map_graph_device do |d|
      {
        id: d[:id],
        device_name: d[:deviceName],
        operating_system: d[:operatingSystem],
        os_version: d[:osVersion],
        compliance_state: d[:complianceState],
        managed_device_owner_type: d[:managedDeviceOwnerType],
        user_principal_name: d[:userPrincipalName],
        last_sync_date_time: d[:lastSyncDateTime],
        model: d[:model],
        manufacturer: d[:manufacturer],
        serial_number: d[:serialNumber],
      }
    end

    helper :graph_mail_subscription_store_key do |runbook_uuid|
      "graph_mail_subscription_id-#{runbook_uuid}"
    end

    helper :graph_mail_client_state_store_key do |runbook_uuid|
      "graph_mail_client_state-#{runbook_uuid}"
    end
  end
end
