class MicrosoftOutlookConnector < IPaaS::Connector::Definition
  GRAPH_API_BASE = 'https://graph.microsoft.com/v1.0'.freeze
  GRAPH_LOGIN_BASE = 'https://login.microsoftonline.com'.freeze
  GRAPH_DEFAULT_SCOPE = 'https://graph.microsoft.com/.default'.freeze
  # Microsoft Graph's maximum subscription lifetime for message resources is 4230 minutes (~2.94 days).
  # See https://learn.microsoft.com/en-us/graph/api/resources/subscription
  MAIL_SUBSCRIPTION_MAX_MINUTES = 4230
  GRAPH_SERVER_ERROR_STATUSES = [503, 504].freeze
  GRAPH_SUCCESS_STATUSES = [200, 201, 202, 204].freeze
  MAX_ATTACHMENT_BYTES = 3 * 1_048_576
  MAX_BATCH_MESSAGE_IDS = 20

  connector 'f6d6ff74-c001-40a8-90e7-97363438e58f' do
    name 'Microsoft Outlook'
    avatar '/assets/icons/microsoft-outlook.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Connects to Outlook mail via [Microsoft Graph](https://learn.microsoft.com/en-us/graph/overview) to
      read, search, send, move, and archive email across both user mailboxes and shared mailboxes, to react
      to new mail in near real time via Graph change notifications, and to fall back to a constrained
      Generic Microsoft Graph API action for capabilities not yet exposed as native actions.

      ## Prerequisites
      - An Azure AD (Microsoft Entra ID) [app registration](https://learn.microsoft.com/en-us/graph/auth-register-app-v2)
        with **application** (not delegated) API permissions granted, and admin-consented, for the Graph scopes
        the actions you use need, e.g. `Mail.Read`, `Mail.ReadWrite`, `Mail.Send`.
      - The app registration's **Tenant ID**, **Client ID**, and a **Client secret** value.
      - A **Default mailbox** (SMTP address or user ID) to use as the target for actions/triggers that don't
        specify their own mailbox.

      ## Authentication
      Uses the OAuth 2 **client credentials** grant (app-only access) against your tenant's token endpoint.
      There is no signed-in user and therefore no `/me` context — every call resolves to a `/users/{id}` path,
      either the connection's Default mailbox, an action's own Target mailbox override, or (for the Shared
      Mailbox actions) an explicit Shared mailbox address. Delegated, user-context access (the authorization
      code grant) is not supported by this connector.

      Application permissions such as `Mail.Send` are tenant-wide — granting it allows sending as **any**
      mailbox in the tenant, not just the Default mailbox configured here. Consider an Exchange Application
      Access Policy in your tenant if you want to restrict this app registration to specific mailboxes.

      ## Actions
      - **Send email** / **Send email from shared mailbox** — sends a message.
      - **Get email** / **Get shared mailbox email** — retrieves a single message including its body.
      - **List emails** / **List shared mailbox emails** — lists messages in a folder, paginated.
      - **Search emails** / **Search shared mailbox emails** — searches/filters messages, paginated.
      - **Move email** / **Move shared mailbox email** — moves one message, or up to 20 in a single batch call.
      - **Archive email** / **Archive shared mailbox email** — moves message(s) to the One-Click Archive folder.
      - **Get email attachments** — lists attachment metadata for a message (no content).
      - **Download attachment** — downloads one attachment's content.
      - **Execute Microsoft Graph API request** — a constrained escape hatch for any other
        `graph.microsoft.com/v1.0` call, using this connection's stored credentials and automatic
        retry/backoff, for capabilities this connector does not yet expose as a native action.
      - **Renew mail subscription** — extends a mail trigger's change-notification subscription before it
        expires. Schedule this to run periodically (e.g. via the **Scheduler** connector).

      ## Triggers
      - **New email received** — starts the runbook when a message arrives in the connection's Default mailbox.
      - **New shared mailbox email received** — starts the runbook when a message arrives in a shared mailbox.

      ## Shared mailbox access
      Reading or sending from a shared mailbox with application permissions needs only the same `Mail.Read` /
      `Mail.Send` permission as the user-mailbox actions (application permissions are tenant-wide by nature).
      Every Shared Mailbox action first checks `GET /users/{address}/mailFolders/inbox`; a 403 there is
      surfaced immediately as "this connection does not have access to {address}" rather than failing deeper
      in the call chain.

      ## One-Click Archive vs. Online Archive
      The **archive** well-known folder used by the Archive actions is the One-Click Archive folder inside the
      primary mailbox, **not** Exchange Online's separate In-Place/Online Archive mailbox — Microsoft Graph
      does not expose the Online Archive mailbox.

      ## Attachments
      Attachments under 3 MB are supported directly. Microsoft Graph's upload-session mechanism for 3-150 MB
      attachments is not implemented by this connector; attachments over 150 MB are not supported by Graph
      itself.

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
        field :default_mailbox, 'Default mailbox', :string,
              required: true,
              hint: 'SMTP address or user ID used as the target mailbox for actions and triggers that do ' \
                    'not specify a Target mailbox override or a Shared mailbox address. Required because ' \
                    'this connector authenticates as the application itself, which has no signed-in user ' \
                    'to fall back to.'
      end

      authenticate do |request|
        credentials = config[:credentials]
        body = oauth2_client_credentials_body(credentials[:client_id],
                                              decrypt_secret_string(credentials[:client_secret]))
        body[:scope] = GRAPH_DEFAULT_SCOPE
        request.headers['Authorization'] = oauth2_authorization_header(helpers.graph_token_url, body)
      end

      config_tester do
        mailbox = config[:default_mailbox]
        response = http_get(helpers.graph_url("users/#{mailbox}/mailFolders/inbox"), nil, nil,
                            open_timeout: 2, timeout: 5)
        if response.status == 200
          { status: :success,
            message: "Connection successful. Default mailbox '#{mailbox}' is reachable with Mail.Read access.", }
        elsif [401, 403].include?(response.status)
          { status: :failed, message: "Microsoft Graph rejected the credentials (HTTP #{response.status})." }
        elsif response.status == 404
          { status: :failed, message: "Mailbox '#{mailbox}' was not found. Check the Default mailbox address." }
        else
          { status: :error, message: "Unable to reach Microsoft Graph (HTTP #{response.status}): '#{response.body}'" }
        end
      rescue IPaaS::Job::Outbound::CustomerCredentialsError => e
        { status: :failed, message: e.message }
      rescue StandardError => e
        { status: :error, message: e.message }
      end
    end

    # ──────────────────────────────────────────────
    # Action: Send email
    # ──────────────────────────────────────────────

    action '71c046bb-7c2a-45fc-b88a-0e25d94a3975' do
      name 'Send email'
      avatar '/assets/icons/microsoft-outlook.svg'
      description <<~END_OF_DESCRIPTION
        Sends a message from the Default mailbox, or a Target mailbox override (`POST /users/{id}/sendMail`).
        Requires the `Mail.Send` application permission.

        A message has exactly one body and one content type per Graph's model — there is no dual
        plain-text-and-HTML body in a single send.
      END_OF_DESCRIPTION

      input_schema do
        field :target_mailbox, 'Target mailbox', :string,
              visibility: 'optional',
              hint: "Overrides the connection's Default mailbox for this action."
        field :subject, 'Subject', :string, required: true
        field :body_content, 'Body', :string, required: true
        field :body_content_type, 'Body content type', :string,
              visibility: 'optional', default: 'HTML', enumeration: %w[Text HTML]
        field :to_recipients, 'To recipients', :nested, array: true, required: true do
          field :name, 'Name', :string, visibility: 'optional'
          field :address, 'Address', :string, required: true
        end
        field :cc_recipients, 'Cc recipients', :nested, array: true, visibility: 'optional' do
          field :name, 'Name', :string, visibility: 'optional'
          field :address, 'Address', :string, required: true
        end
        field :bcc_recipients, 'Bcc recipients', :nested, array: true, visibility: 'optional' do
          field :name, 'Name', :string, visibility: 'optional'
          field :address, 'Address', :string, required: true
        end
        field :attachments, 'Attachments', :nested, array: true, visibility: 'optional' do
          field :name, 'File name', :string, required: true
          field :content_bytes, 'Content', :base64, required: true
          field :content_type, 'Content type', :string, visibility: 'optional'
        end
        field :importance, 'Importance', :string, visibility: 'optional', enumeration: %w[low normal high]
        field :save_to_sent_items, 'Save to Sent Items', :boolean,
              required: true,
              hint: "Graph's sendMail defaults this to true when omitted, but this connector requires an " \
                    'explicit choice.'
      end

      output_schema do
        field :sent, 'Sent', :boolean, required: true
        field :internet_message_id, 'Internet message ID', :string
      end

      run do
        mailbox = helpers.resolve_target_mailbox(input)
        [{ output: helpers.graph_send_mail(mailbox, input) }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Send email from shared mailbox
    # ──────────────────────────────────────────────

    action '0e714f55-e685-4c39-b336-8b7c870c40c9' do
      name 'Send email from shared mailbox'
      avatar '/assets/icons/microsoft-outlook.svg'
      description <<~END_OF_DESCRIPTION
        Sends a message from an explicit shared mailbox (`POST /users/{sharedMailboxAddress}/sendMail`).
        Requires the `Mail.Send` application permission.
      END_OF_DESCRIPTION

      input_schema do
        field :shared_mailbox_address, 'Shared mailbox address', :string,
              required: true,
              hint: 'SMTP address of the shared mailbox to send from, e.g. "helpdesk@contoso.com".'
        field :subject, 'Subject', :string, required: true
        field :body_content, 'Body', :string, required: true
        field :body_content_type, 'Body content type', :string,
              visibility: 'optional', default: 'HTML', enumeration: %w[Text HTML]
        field :to_recipients, 'To recipients', :nested, array: true, required: true do
          field :name, 'Name', :string, visibility: 'optional'
          field :address, 'Address', :string, required: true
        end
        field :cc_recipients, 'Cc recipients', :nested, array: true, visibility: 'optional' do
          field :name, 'Name', :string, visibility: 'optional'
          field :address, 'Address', :string, required: true
        end
        field :bcc_recipients, 'Bcc recipients', :nested, array: true, visibility: 'optional' do
          field :name, 'Name', :string, visibility: 'optional'
          field :address, 'Address', :string, required: true
        end
        field :attachments, 'Attachments', :nested, array: true, visibility: 'optional' do
          field :name, 'File name', :string, required: true
          field :content_bytes, 'Content', :base64, required: true
          field :content_type, 'Content type', :string, visibility: 'optional'
        end
        field :importance, 'Importance', :string, visibility: 'optional', enumeration: %w[low normal high]
        field :save_to_sent_items, 'Save to Sent Items', :boolean, required: true
      end

      output_schema do
        field :sent, 'Sent', :boolean, required: true
        field :internet_message_id, 'Internet message ID', :string
      end

      run do
        mailbox = input[:shared_mailbox_address]
        helpers.ensure_shared_mailbox_access(mailbox)
        [{ output: helpers.graph_send_mail(mailbox, input) }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Get email
    # ──────────────────────────────────────────────

    action '62dd41d4-fb3d-4b29-be5e-921bf55b6896' do
      name 'Get email'
      avatar '/assets/icons/microsoft-outlook.svg'
      description <<~END_OF_DESCRIPTION
        Retrieves a single email including its body (`GET /users/{id}/messages/{id}`). Requires the
        `Mail.Read` application permission.
      END_OF_DESCRIPTION

      input_schema do
        field :target_mailbox, 'Target mailbox', :string,
              visibility: 'optional',
              hint: "Overrides the connection's Default mailbox for this action."
        field :message_id, 'Message ID', :string, required: true
        field :include_html_body, 'Include HTML body', :boolean,
              visibility: 'optional', default: true,
              hint: 'When true, requests the HTML body; when false, requests plain text.'
      end

      output_schema do
        field :message_id, 'Message ID', :string, required: true
        field :subject, 'Subject', :string
        field :from_address, 'From address', :string
        field :from_name, 'From name', :string
        field :to_recipients, 'To recipients', :nested, array: true do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :cc_recipients, 'Cc recipients', :nested, array: true do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :bcc_recipients, 'Bcc recipients', :nested, array: true do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :received_date_time, 'Received at', :date_time
        field :sent_date_time, 'Sent at', :date_time
        field :importance, 'Importance', :string
        field :categories, 'Categories', :string, array: true
        field :is_read, 'Is read', :boolean
        field :has_attachments, 'Has attachments', :boolean
        field :conversation_id, 'Conversation ID', :string
        field :internet_message_id, 'Internet message ID', :string
        field :body_preview, 'Body preview', :string
        field :html_body, 'HTML body', :string
        field :text_body, 'Text body', :string
        field :folder, 'Folder', :string
      end

      run do
        mailbox = helpers.resolve_target_mailbox(input)
        message = helpers.graph_get_message(mailbox, input[:message_id], include_html_body: input[:include_html_body])
        [{ output: message }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Get shared mailbox email
    # ──────────────────────────────────────────────

    action 'b7635516-0e3f-4e1c-b447-efb59ace546f' do
      name 'Get shared mailbox email'
      avatar '/assets/icons/microsoft-outlook.svg'
      description <<~END_OF_DESCRIPTION
        Retrieves a single email including its body from a shared mailbox
        (`GET /users/{sharedMailboxAddress}/messages/{id}`). Requires the `Mail.Read` application permission.
      END_OF_DESCRIPTION

      input_schema do
        field :shared_mailbox_address, 'Shared mailbox address', :string, required: true
        field :message_id, 'Message ID', :string, required: true
        field :include_html_body, 'Include HTML body', :boolean, visibility: 'optional', default: true
      end

      output_schema do
        field :message_id, 'Message ID', :string, required: true
        field :subject, 'Subject', :string
        field :from_address, 'From address', :string
        field :from_name, 'From name', :string
        field :to_recipients, 'To recipients', :nested, array: true do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :cc_recipients, 'Cc recipients', :nested, array: true do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :bcc_recipients, 'Bcc recipients', :nested, array: true do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :received_date_time, 'Received at', :date_time
        field :sent_date_time, 'Sent at', :date_time
        field :importance, 'Importance', :string
        field :categories, 'Categories', :string, array: true
        field :is_read, 'Is read', :boolean
        field :has_attachments, 'Has attachments', :boolean
        field :conversation_id, 'Conversation ID', :string
        field :internet_message_id, 'Internet message ID', :string
        field :body_preview, 'Body preview', :string
        field :html_body, 'HTML body', :string
        field :text_body, 'Text body', :string
        field :folder, 'Folder', :string
      end

      run do
        mailbox = input[:shared_mailbox_address]
        helpers.ensure_shared_mailbox_access(mailbox)
        message = helpers.graph_get_message(mailbox, input[:message_id], include_html_body: input[:include_html_body])
        [{ output: message }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: List emails
    # ──────────────────────────────────────────────

    action 'b9a6600b-9954-4e2e-9fc9-e07915ed39ee' do
      name 'List emails'
      avatar '/assets/icons/microsoft-outlook.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Lists messages in a folder (`GET /users/{id}/mailFolders/{folderId}/messages`), paging through all
        results. Requires the `Mail.Read` application permission.
      END_OF_DESCRIPTION

      input_schema do
        field :target_mailbox, 'Target mailbox', :string, visibility: 'optional'
        field :folder, 'Mail folder', :string,
              visibility: 'optional', default: 'inbox',
              hint: 'Well-known folder name (e.g. "inbox", "archive", "sentitems") or a mail folder ID.'
        field :top, 'Page size', :integer,
              min: 1, max: 999, visibility: 'optional', default: 25,
              hint: 'Number of messages per page (max 999).'
        field :order_by, 'Order by', :string, visibility: 'optional', default: 'receivedDateTime desc'
      end

      output_schema 'page' do
        field :has_next_page, 'Has next page', :boolean, required: true
        field :messages, 'Messages', :nested, array: true do
          field :message_id, 'Message ID', :string, required: true
          field :subject, 'Subject', :string
          field :from_address, 'From address', :string
          field :from_name, 'From name', :string
          field :received_date_time, 'Received at', :date_time
          field :has_attachments, 'Has attachments', :boolean
          field :is_read, 'Is read', :boolean
          field :importance, 'Importance', :string
          field :body_preview, 'Body preview', :string
        end
      end

      iteration_state_schema do
        field :next_link, 'Next link', :string
      end

      run do
        mailbox = helpers.resolve_target_mailbox(input)
        next_link = iteration_state_value(:next_link)
        result = if next_link.present?
                   helpers.graph_get_url(next_link)
                 else
                   query = { '$top' => input[:top].to_s, '$orderby' => input[:order_by] }
                   helpers.graph_get("users/#{mailbox}/mailFolders/#{input[:folder]}/messages", query)
                 end

        messages = Array(result[:value]).map { |m| helpers.map_graph_message_summary(m) }
        new_next_link = result[:'@odata.nextLink']
        self.iteration_state_value = new_next_link.present? ? { next_link: new_next_link } : nil

        [{ output: { has_next_page: iteration_state_value.present?, messages: messages }, schema_reference: 'page' }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Search emails
    # ──────────────────────────────────────────────

    action '3137a300-6b66-4720-bea0-d37305036a57' do
      name 'Search emails'
      avatar '/assets/icons/microsoft-outlook.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Searches or filters messages (`GET /users/{id}/messages` using `$search` and/or `$filter`), paging
        through results. Requires the `Mail.Read` application permission.

        `$search` (free text) and `$filter` (structured) cannot always be combined in a single Graph request,
        so when both are provided this action issues two calls and intersects the results client-side; the
        combined result is not paginated further.
      END_OF_DESCRIPTION

      input_schema do
        field :target_mailbox, 'Target mailbox', :string, visibility: 'optional'
        field :folder, 'Mail folder', :string,
              visibility: 'optional',
              hint: 'Limit the search to this folder (well-known name or folder ID). Leave blank to search ' \
                    'the whole mailbox.'
        field :query_text, 'Search text', :string,
              visibility: 'optional', hint: 'Free-text search across subject and body ($search).'
        field :sender, 'Sender', :string, visibility: 'optional', hint: 'Filter by sender email address.'
        field :importance, 'Importance', :string, visibility: 'optional', enumeration: %w[low normal high]
        field :categories, 'Categories', :string, array: true, visibility: 'optional'
        field :has_attachments, 'Has attachments', :boolean, visibility: 'optional'
        field :is_read, 'Read status', :boolean, visibility: 'optional'
        field :received_after, 'Received after', :date_time, visibility: 'optional'
        field :received_before, 'Received before', :date_time, visibility: 'optional'
        field :top, 'Page size', :integer, min: 1, max: 999, visibility: 'optional', default: 25
      end

      output_schema 'page' do
        field :has_next_page, 'Has next page', :boolean, required: true
        field :messages, 'Messages', :nested, array: true do
          field :message_id, 'Message ID', :string, required: true
          field :subject, 'Subject', :string
          field :from_address, 'From address', :string
          field :from_name, 'From name', :string
          field :received_date_time, 'Received at', :date_time
          field :has_attachments, 'Has attachments', :boolean
          field :is_read, 'Is read', :boolean
          field :importance, 'Importance', :string
          field :body_preview, 'Body preview', :string
        end
      end

      iteration_state_schema do
        field :next_link, 'Next link', :string
      end

      run do
        mailbox = helpers.resolve_target_mailbox(input)
        next_link = iteration_state_value(:next_link)
        result = next_link.present? ? helpers.graph_get_url(next_link) : helpers.graph_search_messages(mailbox, input)

        messages = Array(result[:value]).map { |m| helpers.map_graph_message_summary(m) }
        new_next_link = result[:'@odata.nextLink']
        self.iteration_state_value = new_next_link.present? ? { next_link: new_next_link } : nil

        [{ output: { has_next_page: iteration_state_value.present?, messages: messages }, schema_reference: 'page' }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Search shared mailbox emails
    # ──────────────────────────────────────────────

    action '73339012-50d8-4e4a-9ddd-e59dc1a7b18e' do
      name 'Search shared mailbox emails'
      avatar '/assets/icons/microsoft-outlook.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Searches or filters messages in a shared mailbox (`GET /users/{sharedMailboxAddress}/messages` using
        `$search` and/or `$filter`), paging through results. Requires the `Mail.Read` application permission.
      END_OF_DESCRIPTION

      input_schema do
        field :shared_mailbox_address, 'Shared mailbox address', :string, required: true
        field :folder, 'Mail folder', :string, visibility: 'optional'
        field :query_text, 'Search text', :string, visibility: 'optional'
        field :sender, 'Sender', :string, visibility: 'optional'
        field :importance, 'Importance', :string, visibility: 'optional', enumeration: %w[low normal high]
        field :categories, 'Categories', :string, array: true, visibility: 'optional'
        field :has_attachments, 'Has attachments', :boolean, visibility: 'optional'
        field :is_read, 'Read status', :boolean, visibility: 'optional'
        field :received_after, 'Received after', :date_time, visibility: 'optional'
        field :received_before, 'Received before', :date_time, visibility: 'optional'
        field :top, 'Page size', :integer, min: 1, max: 999, visibility: 'optional', default: 25
      end

      output_schema 'page' do
        field :has_next_page, 'Has next page', :boolean, required: true
        field :messages, 'Messages', :nested, array: true do
          field :message_id, 'Message ID', :string, required: true
          field :subject, 'Subject', :string
          field :from_address, 'From address', :string
          field :from_name, 'From name', :string
          field :received_date_time, 'Received at', :date_time
          field :has_attachments, 'Has attachments', :boolean
          field :is_read, 'Is read', :boolean
          field :importance, 'Importance', :string
          field :body_preview, 'Body preview', :string
        end
      end

      iteration_state_schema do
        field :next_link, 'Next link', :string
      end

      run do
        mailbox = input[:shared_mailbox_address]
        helpers.ensure_shared_mailbox_access(mailbox)
        next_link = iteration_state_value(:next_link)
        result = next_link.present? ? helpers.graph_get_url(next_link) : helpers.graph_search_messages(mailbox, input)

        messages = Array(result[:value]).map { |m| helpers.map_graph_message_summary(m) }
        new_next_link = result[:'@odata.nextLink']
        self.iteration_state_value = new_next_link.present? ? { next_link: new_next_link } : nil

        [{ output: { has_next_page: iteration_state_value.present?, messages: messages }, schema_reference: 'page' }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Move email
    # ──────────────────────────────────────────────

    action '7e175ec7-97ac-4d85-94ed-82880a49c6fc' do
      name 'Move email'
      avatar '/assets/icons/microsoft-outlook.svg'
      description <<~END_OF_DESCRIPTION
        Moves a message to another folder (`POST /users/{id}/messages/{id}/move`). Requires the
        `Mail.ReadWrite` application permission.

        Provide either **Message ID** to move one message, or **Message IDs** (up to 20) to move several in
        a single Microsoft Graph `$batch` call, returning a per-message success/failure result.
      END_OF_DESCRIPTION

      input_schema do
        field :target_mailbox, 'Target mailbox', :string, visibility: 'optional'
        field :message_id, 'Message ID', :string, visibility: 'optional'
        field :message_ids, 'Message IDs', :string,
              array: true, visibility: 'optional',
              hint: 'Move up to 20 messages in one batch call, instead of Message ID.'
        field :destination_folder_id, 'Destination folder', :string,
              required: true,
              hint: 'Well-known folder name (e.g. "archive", "deleteditems") or a mail folder ID.'
      end

      output_schema do
        field :message_id, 'Message ID', :string
        field :parent_folder_id, 'Parent folder ID', :string
        field :results, 'Batch results', :nested, array: true do
          field :message_id, 'Message ID', :string, required: true
          field :success, 'Success', :boolean, required: true
          field :error, 'Error', :string
        end
      end

      run do
        mailbox = helpers.resolve_target_mailbox(input)
        [{ output: helpers.perform_move(mailbox, input, input[:destination_folder_id]) }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Move shared mailbox email
    # ──────────────────────────────────────────────

    action 'b21652b0-d776-4f0b-880d-be84a9176f18' do
      name 'Move shared mailbox email'
      avatar '/assets/icons/microsoft-outlook.svg'
      description <<~END_OF_DESCRIPTION
        Moves a message to another folder in a shared mailbox
        (`POST /users/{sharedMailboxAddress}/messages/{id}/move`). Requires the `Mail.ReadWrite` application
        permission.
      END_OF_DESCRIPTION

      input_schema do
        field :shared_mailbox_address, 'Shared mailbox address', :string, required: true
        field :message_id, 'Message ID', :string, visibility: 'optional'
        field :message_ids, 'Message IDs', :string, array: true, visibility: 'optional'
        field :destination_folder_id, 'Destination folder', :string, required: true
      end

      output_schema do
        field :message_id, 'Message ID', :string
        field :parent_folder_id, 'Parent folder ID', :string
        field :results, 'Batch results', :nested, array: true do
          field :message_id, 'Message ID', :string, required: true
          field :success, 'Success', :boolean, required: true
          field :error, 'Error', :string
        end
      end

      run do
        mailbox = input[:shared_mailbox_address]
        helpers.ensure_shared_mailbox_access(mailbox)
        [{ output: helpers.perform_move(mailbox, input, input[:destination_folder_id]) }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Archive email
    # ──────────────────────────────────────────────

    action 'ae525aa1-831d-4f8a-8103-bcb1c84d2061' do
      name 'Archive email'
      avatar '/assets/icons/microsoft-outlook.svg'
      description <<~END_OF_DESCRIPTION
        Moves a message to the One-Click Archive folder (`POST /users/{id}/messages/{id}/move` with
        `destinationId: "archive"`). Requires the `Mail.ReadWrite` application permission.

        This is the One-Click Archive folder inside the primary mailbox, not Exchange Online's separate
        In-Place/Online Archive mailbox, which Microsoft Graph does not expose.
      END_OF_DESCRIPTION

      input_schema do
        field :target_mailbox, 'Target mailbox', :string, visibility: 'optional'
        field :message_id, 'Message ID', :string, visibility: 'optional'
        field :message_ids, 'Message IDs', :string, array: true, visibility: 'optional'
      end

      output_schema do
        field :message_id, 'Message ID', :string
        field :parent_folder_id, 'Parent folder ID', :string
        field :results, 'Batch results', :nested, array: true do
          field :message_id, 'Message ID', :string, required: true
          field :success, 'Success', :boolean, required: true
          field :error, 'Error', :string
        end
      end

      run do
        mailbox = helpers.resolve_target_mailbox(input)
        [{ output: helpers.perform_move(mailbox, input, 'archive') }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Archive shared mailbox email
    # ──────────────────────────────────────────────

    action '0afc1f39-f18d-456f-be7a-a95fa112c177' do
      name 'Archive shared mailbox email'
      avatar '/assets/icons/microsoft-outlook.svg'
      description <<~END_OF_DESCRIPTION
        Moves a message in a shared mailbox to the One-Click Archive folder
        (`POST /users/{sharedMailboxAddress}/messages/{id}/move` with `destinationId: "archive"`). Requires
        the `Mail.ReadWrite` application permission.
      END_OF_DESCRIPTION

      input_schema do
        field :shared_mailbox_address, 'Shared mailbox address', :string, required: true
        field :message_id, 'Message ID', :string, visibility: 'optional'
        field :message_ids, 'Message IDs', :string, array: true, visibility: 'optional'
      end

      output_schema do
        field :message_id, 'Message ID', :string
        field :parent_folder_id, 'Parent folder ID', :string
        field :results, 'Batch results', :nested, array: true do
          field :message_id, 'Message ID', :string, required: true
          field :success, 'Success', :boolean, required: true
          field :error, 'Error', :string
        end
      end

      run do
        mailbox = input[:shared_mailbox_address]
        helpers.ensure_shared_mailbox_access(mailbox)
        [{ output: helpers.perform_move(mailbox, input, 'archive') }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Get email attachments
    # ──────────────────────────────────────────────

    action 'bf04a725-708d-4e1c-a8b8-cfff4dfa32cb' do
      name 'Get email attachments'
      avatar '/assets/icons/microsoft-outlook.svg'
      description <<~END_OF_DESCRIPTION
        Retrieves attachment metadata for a message, without downloading content
        (`GET /users/{id}/messages/{id}/attachments`). Requires the `Mail.Read` application permission.
      END_OF_DESCRIPTION

      input_schema do
        field :target_mailbox, 'Target mailbox', :string, visibility: 'optional'
        field :message_id, 'Message ID', :string, required: true
      end

      output_schema do
        field :attachments, 'Attachments', :nested, array: true do
          field :attachment_id, 'Attachment ID', :string, required: true
          field :name, 'Name', :string
          field :size_in_bytes, 'Size (bytes)', :integer
          field :content_type, 'Content type', :string
          field :is_inline, 'Is inline', :boolean
        end
      end

      run do
        mailbox = helpers.resolve_target_mailbox(input)
        result = helpers.graph_get("users/#{mailbox}/messages/#{input[:message_id]}/attachments")
        attachments = Array(result[:value]).map { |a| helpers.map_graph_attachment_metadata(a) }
        [{ output: { attachments: attachments } }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Download attachment
    # ──────────────────────────────────────────────

    action '3c9483f9-ab03-4e40-a181-fe3f104553ec' do
      name 'Download attachment'
      avatar '/assets/icons/microsoft-outlook.svg'
      description <<~END_OF_DESCRIPTION
        Downloads one attachment's content
        (`GET /users/{id}/messages/{id}/attachments/{attachmentId}`). Requires the `Mail.Read` application
        permission.

        The output shape (`name`, `content_bytes`, `content_type`) matches **Send email**'s Attachments
        input, so an attachment downloaded from one message can be sent unmodified.
      END_OF_DESCRIPTION

      input_schema do
        field :target_mailbox, 'Target mailbox', :string, visibility: 'optional'
        field :message_id, 'Message ID', :string, required: true
        field :attachment_id, 'Attachment ID', :string, required: true
      end

      output_schema do
        field :name, 'Name', :string, required: true
        field :content_bytes, 'Content', :base64, required: true
        field :content_type, 'Content type', :string
      end

      run do
        mailbox = helpers.resolve_target_mailbox(input)
        path = "users/#{mailbox}/messages/#{input[:message_id]}/attachments/#{input[:attachment_id]}"
        attachment = helpers.graph_get(path)
        [{ output: { name: attachment[:name], content_bytes: attachment[:contentBytes],
                     content_type: attachment[:contentType], } }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Execute Microsoft Graph API request
    # ──────────────────────────────────────────────

    action 'd056b997-b39d-4081-9126-0e541098cf82' do
      name 'Execute Microsoft Graph API request'
      avatar '/assets/icons/microsoft-outlook.svg'
      description <<~END_OF_DESCRIPTION
        A constrained escape hatch for Microsoft Graph calls this connector does not yet expose as a native
        action. Unlike a generic HTTP call, this action automatically uses this connection's stored token
        (refreshing and retrying once on a 401 the same as every native action), is hard-constrained to
        `https://graph.microsoft.com/v1.0` (the Graph Path field only accepts a relative path, never a host),
        and applies the same Retry-After-aware retry policy as every other action in this connector.

        This action does not pre-validate that the connection's granted permissions cover the endpoint being
        called — the first indication of a missing permission is a 403 at execution time, same as any direct
        Graph API caller would see.

        #### Example
        Method `GET`, Graph Path `/me/outlook/masterCategories` returns the mailbox's defined category list.
        (Note: with Client Credentials there is no `/me` — use `/users/{id}/outlook/masterCategories`.)
      END_OF_DESCRIPTION

      input_schema do
        field :method, 'HTTP method', :string, required: true, enumeration: %w[GET POST PATCH PUT DELETE]
        field :graph_path, 'Graph path', :string,
              required: true,
              pattern: %r{\A/[A-Za-z0-9\-._~!$&'()*+,;=:@%/]*\z},
              hint: 'Relative path under /v1.0, e.g. "/users/{id}/messages". Do not include the host or ' \
                    '/v1.0 prefix.'
        field :query_parameters, 'Query parameters', :nested, array: true, visibility: 'optional' do
          field :name, 'Name', :string, required: true
          field :value, 'Value', :string
        end
        field :headers, 'Headers', :nested, array: true, visibility: 'optional' do
          field :name, 'Name', :string, required: true
          field :value, 'Value', :string
        end
        field :request_body, 'Request body', :string,
              visibility: 'optional', hint: 'JSON request body, used for POST/PATCH/PUT.'
      end

      output_schema do
        field :status, 'Status', :integer, required: true
        field :body, 'Body', :binary
        field :next_link, 'Next link (@odata.nextLink)', :string
      end

      run do
        [{ output: helpers.execute_generic_graph_request(input) }]
      end
    end

    # ──────────────────────────────────────────────
    # Action: Renew mail subscription
    # ──────────────────────────────────────────────

    action '8fb16815-5d47-4b96-8acb-7b410138d41e' do
      name 'Renew mail subscription'
      avatar '/assets/icons/microsoft-outlook.svg'
      description <<~END_OF_DESCRIPTION
        Extends a **New email received** or **New shared mailbox email received** trigger's Microsoft Graph
        change-notification subscription before it expires. Message subscriptions last at most ~2.94 days,
        so schedule this action to run periodically (e.g. via the **Scheduler** connector) against the same
        runbook that uses the trigger.

        Fails the step if no active subscription is found for that runbook — the trigger's runbook must be
        enabled (provisioned) at least once before this action can renew it.
      END_OF_DESCRIPTION

      input_schema do
        field :mail_trigger_runbook, 'Mail trigger runbook', :runbook,
              required: true,
              hint: 'The runbook using the New email received or New shared mailbox email received ' \
                    'trigger whose subscription should be renewed.'
      end

      output_schema do
        field :subscription_id, 'Subscription ID', :string, required: true
        field :expiration_date_time, 'New expiration', :date_time, required: true
      end

      run do
        target_runbook = input[:mail_trigger_runbook]
        subscription_id = outbound_connection.store.read(
          helpers.outlook_mail_subscription_store_key(target_runbook.uuid),
        )
        if subscription_id.blank?
          fail_job!('No active Microsoft Graph subscription found for that runbook. Has the trigger been enabled?')
        end

        new_expiration = MAIL_SUBSCRIPTION_MAX_MINUTES.minutes.from_now
        helpers.graph_patch("subscriptions/#{subscription_id}", { expirationDateTime: new_expiration.iso8601 })

        [{ output: { subscription_id: subscription_id, expiration_date_time: new_expiration } }]
      end
    end

    # ──────────────────────────────────────────────
    # Trigger: New email received
    # ──────────────────────────────────────────────

    trigger 'b5822f83-0da0-4140-80c9-dfd814db980e' do
      name 'New email received'
      avatar '/assets/icons/microsoft-outlook.svg'
      outbound_traffic true
      description <<~END_OF_DESCRIPTION
        Starts the runbook when a message arrives in the connection's Default mailbox, via a Microsoft Graph
        change-notification subscription on `users/{id}/mailFolders('{folder}')/messages`.

        #### Subscription lifecycle
        - **Provisioning** (enabling the runbook) creates the Graph subscription and stores its ID and a
          generated `clientState` secret against this connection. Any subscription already stored for this
          runbook is deleted first, so re-enabling the trigger without an intervening disable does not
          orphan a previous subscription.
        - **Deprovisioning** (disabling or deleting the runbook) deletes the subscription.
        - Microsoft Graph's validation handshake (a `validationToken` query parameter sent when the
          subscription is created) is answered automatically — no runbook job is created for it.
        - **Message subscriptions expire after ~2.94 days.** Schedule the **Renew mail subscription** action
          (e.g. daily, via the **Scheduler** connector) against this runbook to keep it alive.

        #### Limitations
        A single Graph notification call can carry more than one event. This trigger processes only the
        first event in each call and logs how many additional events were dropped.
      END_OF_DESCRIPTION

      config_schema do
        field :folder, 'Mail folder', :string,
              visibility: 'optional', default: 'inbox',
              hint: 'Well-known folder name (e.g. "inbox", "archive") or a mail folder ID.'
        field :include_html_body, 'Include HTML body', :boolean, visibility: 'optional', default: true
        field :download_attachments, 'Download attachments', :boolean,
              visibility: 'optional', default: false,
              hint: 'When true, fetches attachment metadata and content for the new message.'
        field :mark_as_read, 'Mark email as read', :boolean,
              visibility: 'optional', default: false,
              hint: 'Requires the Mail.ReadWrite application permission in addition to Mail.Read.'
      end

      output_schema do
        field :message_id, 'Message ID', :string, required: true
        field :subject, 'Subject', :string
        field :from_address, 'From address', :string
        field :from_name, 'From name', :string
        field :to_recipients, 'To recipients', :nested, array: true do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :cc_recipients, 'Cc recipients', :nested, array: true do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :bcc_recipients, 'Bcc recipients', :nested, array: true do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :received_date_time, 'Received at', :date_time
        field :sent_date_time, 'Sent at', :date_time
        field :importance, 'Importance', :string
        field :categories, 'Categories', :string, array: true
        field :is_read, 'Is read', :boolean
        field :has_attachments, 'Has attachments', :boolean
        field :conversation_id, 'Conversation ID', :string
        field :internet_message_id, 'Internet message ID', :string
        field :body_preview, 'Body preview', :string
        field :html_body, 'HTML body', :string
        field :text_body, 'Text body', :string
        field :folder, 'Folder', :string
        field :attachments, 'Attachments', :nested, array: true do
          field :attachment_id, 'Attachment ID', :string, required: true
          field :name, 'Name', :string
          field :size_in_bytes, 'Size (bytes)', :integer
          field :content_type, 'Content type', :string
          field :is_inline, 'Is inline', :boolean
          field :content_bytes, 'Content', :base64
        end
      end

      parse do |request|
        validation_token = request.params['validationToken']
        if validation_token.present?
          discard_trigger_event!('Responding to Microsoft Graph subscription validation request.')
        end

        body = JSON.parse(request.body.read.presence || '{}')
        notifications = Array(body['value'])
        fail_job!('Microsoft Graph notification contained no items.') if notifications.blank?

        if notifications.size > 1
          log("Received #{notifications.size} notifications in one call; processing only the first, the " \
              "other #{notifications.size - 1} are dropped.")
        end

        notification = notifications.first
        stored_client_state = outbound_connection.store.read(
          helpers.outlook_client_state_store_key(trigger.runbook.uuid),
        )
        if stored_client_state.blank? || notification['clientState'] != stored_client_state
          fail_job!('Microsoft Graph notification clientState did not match the stored value; discarding as untrusted.')
        end

        message_id = notification.dig('resourceData', 'id')
        fail_job!('Microsoft Graph notification did not include a message id.') if message_id.blank?

        mailbox = outbound_connection.config[:default_mailbox]
        helpers.build_mail_trigger_output(mailbox, message_id, trigger.config)
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
        helpers.delete_stored_mail_subscription(trigger.runbook.uuid)

        client_state = SecureRandom.uuid
        folder = trigger.config[:folder].presence || 'inbox'
        mailbox = outbound_connection.config[:default_mailbox]
        resource = "users/#{mailbox}/mailFolders('#{folder}')/messages"
        subscription = helpers.graph_post('subscriptions', {
          changeType: 'created',
          notificationUrl: trigger.endpoint,
          resource: resource,
          expirationDateTime: MAIL_SUBSCRIPTION_MAX_MINUTES.minutes.from_now.iso8601,
          clientState: client_state,
        })

        outbound_connection.store.write(helpers.outlook_mail_subscription_store_key(trigger.runbook.uuid),
                                        subscription[:id])
        outbound_connection.store.write(helpers.outlook_client_state_store_key(trigger.runbook.uuid), client_state)
      end

      deprovision do
        helpers.delete_stored_mail_subscription(trigger.runbook.uuid)
      end
    end

    # ──────────────────────────────────────────────
    # Trigger: New shared mailbox email received
    # ──────────────────────────────────────────────

    trigger '07305bda-b00d-49c7-ac3f-00dd31eebdaf' do
      name 'New shared mailbox email received'
      avatar '/assets/icons/microsoft-outlook.svg'
      outbound_traffic true
      description <<~END_OF_DESCRIPTION
        Starts the runbook when a message arrives in a shared mailbox, via a Microsoft Graph
        change-notification subscription on `users/{sharedMailboxAddress}/mailFolders('{folder}')/messages`.

        Subscription lifecycle mechanics (provisioning, deprovisioning, validation handshake, renewal) are
        identical to **New email received** — see that trigger's description.
      END_OF_DESCRIPTION

      config_schema do
        field :shared_mailbox_address, 'Shared mailbox address', :string,
              required: true,
              hint: 'SMTP address of the shared mailbox to watch, e.g. "helpdesk@contoso.com". There is no ' \
                    'connection-level default for this trigger — the address must always be explicit.'
        field :folder, 'Mail folder', :string, visibility: 'optional', default: 'inbox'
        field :include_html_body, 'Include HTML body', :boolean, visibility: 'optional', default: true
        field :download_attachments, 'Download attachments', :boolean, visibility: 'optional', default: false
        field :mark_as_read, 'Mark email as read', :boolean, visibility: 'optional', default: false
      end

      output_schema do
        field :message_id, 'Message ID', :string, required: true
        field :subject, 'Subject', :string
        field :from_address, 'From address', :string
        field :from_name, 'From name', :string
        field :to_recipients, 'To recipients', :nested, array: true do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :cc_recipients, 'Cc recipients', :nested, array: true do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :bcc_recipients, 'Bcc recipients', :nested, array: true do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :received_date_time, 'Received at', :date_time
        field :sent_date_time, 'Sent at', :date_time
        field :importance, 'Importance', :string
        field :categories, 'Categories', :string, array: true
        field :is_read, 'Is read', :boolean
        field :has_attachments, 'Has attachments', :boolean
        field :conversation_id, 'Conversation ID', :string
        field :internet_message_id, 'Internet message ID', :string
        field :body_preview, 'Body preview', :string
        field :html_body, 'HTML body', :string
        field :text_body, 'Text body', :string
        field :folder, 'Folder', :string
        field :attachments, 'Attachments', :nested, array: true do
          field :attachment_id, 'Attachment ID', :string, required: true
          field :name, 'Name', :string
          field :size_in_bytes, 'Size (bytes)', :integer
          field :content_type, 'Content type', :string
          field :is_inline, 'Is inline', :boolean
          field :content_bytes, 'Content', :base64
        end
      end

      parse do |request|
        validation_token = request.params['validationToken']
        if validation_token.present?
          discard_trigger_event!('Responding to Microsoft Graph subscription validation request.')
        end

        body = JSON.parse(request.body.read.presence || '{}')
        notifications = Array(body['value'])
        fail_job!('Microsoft Graph notification contained no items.') if notifications.blank?

        if notifications.size > 1
          log("Received #{notifications.size} notifications in one call; processing only the first, the " \
              "other #{notifications.size - 1} are dropped.")
        end

        notification = notifications.first
        stored_client_state = outbound_connection.store.read(
          helpers.outlook_client_state_store_key(trigger.runbook.uuid),
        )
        if stored_client_state.blank? || notification['clientState'] != stored_client_state
          fail_job!('Microsoft Graph notification clientState did not match the stored value; discarding as untrusted.')
        end

        message_id = notification.dig('resourceData', 'id')
        fail_job!('Microsoft Graph notification did not include a message id.') if message_id.blank?

        mailbox = trigger.config[:shared_mailbox_address]
        helpers.build_mail_trigger_output(mailbox, message_id, trigger.config)
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
        helpers.delete_stored_mail_subscription(trigger.runbook.uuid)

        client_state = SecureRandom.uuid
        folder = trigger.config[:folder].presence || 'inbox'
        mailbox = trigger.config[:shared_mailbox_address]
        helpers.ensure_shared_mailbox_access(mailbox)
        resource = "users/#{mailbox}/mailFolders('#{folder}')/messages"
        subscription = helpers.graph_post('subscriptions', {
          changeType: 'created',
          notificationUrl: trigger.endpoint,
          resource: resource,
          expirationDateTime: MAIL_SUBSCRIPTION_MAX_MINUTES.minutes.from_now.iso8601,
          clientState: client_state,
        })

        outbound_connection.store.write(helpers.outlook_mail_subscription_store_key(trigger.runbook.uuid),
                                        subscription[:id])
        outbound_connection.store.write(helpers.outlook_client_state_store_key(trigger.runbook.uuid), client_state)
      end

      deprovision do
        helpers.delete_stored_mail_subscription(trigger.runbook.uuid)
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
      helpers.graph_ensure_success(response) unless [404, 410].include?(response.status)
    end

    helper :graph_ensure_success do |response|
      next if GRAPH_SUCCESS_STATUSES.include?(response.status)

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

    # ──────────────────────────────────────────────
    # Connector-level helpers: mailbox resolution
    # ──────────────────────────────────────────────

    helper :resolve_target_mailbox do |input|
      input[:target_mailbox].presence || outbound_connection.config[:default_mailbox]
    end

    helper :ensure_shared_mailbox_access do |address|
      response = http_get(helpers.graph_url("users/#{address}/mailFolders/inbox"))
      fail_job!("This connection does not have access to #{address}.") if response.status == 403
      backoff_if_needed(response, api_name: 'Microsoft Graph', server_error_statuses: GRAPH_SERVER_ERROR_STATUSES)
      helpers.graph_ensure_success(response)
    end

    # ──────────────────────────────────────────────
    # Connector-level helpers: message mapping
    # ──────────────────────────────────────────────

    helper :map_graph_recipients do |recipients|
      Array(recipients).map do |r|
        email = r[:emailAddress] || {}
        { name: email[:name], address: email[:address] }
      end
    end

    helper :build_graph_recipients do |recipients|
      Array(recipients).map do |r|
        email = { address: r[:address] }
        email[:name] = r[:name] if r[:name].present?
        { emailAddress: email }
      end
    end

    helper :map_graph_message do |message|
      body = message[:body] || {}
      is_html = body[:contentType].to_s.downcase == 'html'
      {
        message_id: message[:id],
        subject: message[:subject],
        from_address: message.dig(:from, :emailAddress, :address),
        from_name: message.dig(:from, :emailAddress, :name),
        to_recipients: helpers.map_graph_recipients(message[:toRecipients]),
        cc_recipients: helpers.map_graph_recipients(message[:ccRecipients]),
        bcc_recipients: helpers.map_graph_recipients(message[:bccRecipients]),
        received_date_time: message[:receivedDateTime],
        sent_date_time: message[:sentDateTime],
        importance: message[:importance],
        categories: Array(message[:categories]),
        is_read: message[:isRead],
        has_attachments: message[:hasAttachments],
        conversation_id: message[:conversationId],
        internet_message_id: message[:internetMessageId],
        body_preview: message[:bodyPreview],
        html_body: is_html ? body[:content] : nil,
        text_body: is_html ? nil : body[:content],
        folder: message[:parentFolderId],
      }
    end

    helper :map_graph_message_summary do |message|
      {
        message_id: message[:id],
        subject: message[:subject],
        from_address: message.dig(:from, :emailAddress, :address),
        from_name: message.dig(:from, :emailAddress, :name),
        received_date_time: message[:receivedDateTime],
        has_attachments: message[:hasAttachments],
        is_read: message[:isRead],
        importance: message[:importance],
        body_preview: message[:bodyPreview],
      }
    end

    helper :map_graph_attachment_metadata do |attachment|
      {
        attachment_id: attachment[:id],
        name: attachment[:name],
        size_in_bytes: attachment[:size],
        content_type: attachment[:contentType],
        is_inline: attachment[:isInline],
      }
    end

    helper :graph_get_message do |mailbox, message_id, include_html_body:|
      prefer_type = include_html_body ? 'html' : 'text'
      response = http_get(helpers.graph_url("users/#{mailbox}/messages/#{message_id}"), nil,
                          { 'Prefer' => "outlook.body-content-type=\"#{prefer_type}\"" })
      backoff_if_needed(response, api_name: 'Microsoft Graph', server_error_statuses: GRAPH_SERVER_ERROR_STATUSES)
      helpers.map_graph_message(helpers.graph_json(response))
    end

    helper :build_mail_trigger_output do |mailbox, message_id, trigger_config|
      message = helpers.graph_get_message(mailbox, message_id, include_html_body: trigger_config[:include_html_body])

      helpers.graph_patch("users/#{mailbox}/messages/#{message_id}", { isRead: true }) if trigger_config[:mark_as_read]

      if trigger_config[:download_attachments] && message[:has_attachments]
        result = helpers.graph_get("users/#{mailbox}/messages/#{message_id}/attachments")
        message[:attachments] = Array(result[:value]).map do |a|
          helpers.map_graph_attachment_metadata(a).merge(content_bytes: a[:contentBytes])
        end
      end

      message
    end

    # ──────────────────────────────────────────────
    # Connector-level helpers: send mail
    # ──────────────────────────────────────────────

    helper :validate_attachment_sizes! do |attachments|
      attachments.each do |attachment|
        content = attachment[:content_bytes]
        size = begin
          Base64.strict_decode64(content).bytesize
        rescue ArgumentError
          content.bytesize
        end
        next if size <= MAX_ATTACHMENT_BYTES

        fail_job!("Attachment '#{attachment[:name]}' exceeds the 3 MB MVP limit. Large attachment support " \
                  '(3-150 MB) is planned.')
      end
    end

    helper :build_graph_file_attachment do |attachment|
      {
        '@odata.type': '#microsoft.graph.fileAttachment',
        name: attachment[:name],
        contentBytes: attachment[:content_bytes],
        contentType: attachment[:content_type].presence || 'application/octet-stream',
      }
    end

    helper :find_sent_internet_message_id do |mailbox, subject|
      query = { '$top' => '1', '$orderby' => 'sentDateTime desc',
                '$filter' => "subject eq '#{subject.gsub("'", "''")}'", }
      result = helpers.graph_get("users/#{mailbox}/mailFolders/sentitems/messages", query)
      Array(result[:value]).first&.dig(:internetMessageId)
    rescue StandardError => e
      log("Could not retrieve the sent item's internet message id: #{e.message}")
      nil
    end

    helper :graph_send_mail do |mailbox, input|
      message = {
        subject: input[:subject],
        body: { contentType: input[:body_content_type], content: input[:body_content] },
        toRecipients: helpers.build_graph_recipients(input[:to_recipients]),
      }
      cc_recipients = Array(input[:cc_recipients])
      message[:ccRecipients] = helpers.build_graph_recipients(cc_recipients) if cc_recipients.any?
      bcc_recipients = Array(input[:bcc_recipients])
      message[:bccRecipients] = helpers.build_graph_recipients(bcc_recipients) if bcc_recipients.any?
      message[:importance] = input[:importance] if input[:importance].present?

      attachments = Array(input[:attachments])
      if attachments.any?
        helpers.validate_attachment_sizes!(attachments)
        message[:attachments] = attachments.map { |a| helpers.build_graph_file_attachment(a) }
      end

      body = { message: message, saveToSentItems: input[:save_to_sent_items] }
      response = http_post(helpers.graph_url("users/#{mailbox}/sendMail"), body.to_json,
                           { 'Content-Type' => 'application/json' })
      backoff_if_needed(response, api_name: 'Microsoft Graph', server_error_statuses: GRAPH_SERVER_ERROR_STATUSES)
      helpers.graph_ensure_success(response)

      { sent: true, internet_message_id: helpers.find_sent_internet_message_id(mailbox, input[:subject]) }
    end

    # ──────────────────────────────────────────────
    # Connector-level helpers: search
    # ──────────────────────────────────────────────

    helper :build_graph_search_filter_clauses do |input|
      clauses = []
      clauses << "from/emailAddress/address eq '#{input[:sender]}'" if input[:sender].present?
      clauses << "importance eq '#{input[:importance]}'" if input[:importance].present?
      clauses << "hasAttachments eq #{input[:has_attachments]}" unless input[:has_attachments].nil?
      clauses << "isRead eq #{input[:is_read]}" unless input[:is_read].nil?
      clauses << "receivedDateTime ge #{input[:received_after].iso8601}" if input[:received_after].present?
      clauses << "receivedDateTime le #{input[:received_before].iso8601}" if input[:received_before].present?
      Array(input[:categories]).each { |category| clauses << "categories/any(c:c eq '#{category}')" }
      clauses
    end

    helper :graph_search_messages do |mailbox, input|
      base_path = if input[:folder].present?
                    "users/#{mailbox}/mailFolders/#{input[:folder]}/messages"
                  else
                    "users/#{mailbox}/messages"
                  end
      filter_clauses = helpers.build_graph_search_filter_clauses(input)
      query_text = input[:query_text]

      if query_text.present? && filter_clauses.any?
        search_result = helpers.graph_get(base_path, { '$search' => "\"#{query_text}\"", '$top' => input[:top].to_s })
        filter_result = helpers.graph_get(base_path,
                                          { '$filter' => filter_clauses.join(' and '), '$top' => input[:top].to_s })
        search_ids = Array(search_result[:value]).filter_map { |m| m[:id] }.to_set
        { value: Array(filter_result[:value]).select { |m| search_ids.include?(m[:id]) } }
      elsif query_text.present?
        helpers.graph_get(base_path, { '$search' => "\"#{query_text}\"", '$top' => input[:top].to_s })
      elsif filter_clauses.any?
        helpers.graph_get(base_path, { '$filter' => filter_clauses.join(' and '), '$top' => input[:top].to_s })
      else
        helpers.graph_get(base_path, { '$top' => input[:top].to_s })
      end
    end

    # ──────────────────────────────────────────────
    # Connector-level helpers: move / archive
    # ──────────────────────────────────────────────

    helper :graph_batch_move do |mailbox, message_ids, destination_folder_id|
      requests = message_ids.each_with_index.map do |message_id, index|
        {
          id: (index + 1).to_s,
          method: 'POST',
          url: "/users/#{mailbox}/messages/#{message_id}/move",
          body: { destinationId: destination_folder_id },
          headers: { 'Content-Type' => 'application/json' },
        }
      end

      result = helpers.graph_post('$batch', { requests: requests })
      responses = Array(result[:responses]).sort_by { |r| r[:id].to_i }
      responses.map do |r|
        message_id = message_ids[r[:id].to_i - 1]
        success = GRAPH_SUCCESS_STATUSES.include?(r[:status])
        { message_id: message_id, success: success, error: success ? nil : r.dig(:body, :error, :message) }
      end
    end

    helper :perform_move do |mailbox, input, destination_folder_id|
      message_ids = Array(input[:message_ids])
      if message_ids.any?
        if message_ids.size > MAX_BATCH_MESSAGE_IDS
          fail_job!("Move Multiple Emails supports at most #{MAX_BATCH_MESSAGE_IDS} message IDs per call.")
        end
        { results: helpers.graph_batch_move(mailbox, message_ids, destination_folder_id) }
      else
        fail_job!('Provide either Message ID or Message IDs.') if input[:message_id].blank?
        result = helpers.graph_post("users/#{mailbox}/messages/#{input[:message_id]}/move",
                                    { destinationId: destination_folder_id })
        { message_id: result[:id], parent_folder_id: result[:parentFolderId] }
      end
    end

    # ──────────────────────────────────────────────
    # Connector-level helpers: Generic Microsoft Graph API request
    # ──────────────────────────────────────────────

    helper :execute_generic_graph_request do |input|
      path = input[:graph_path].to_s.sub(%r{\A/+}, '')
      url = helpers.graph_url(path)
      query = Array(input[:query_parameters]).to_h { |q| [q[:name], q[:value]] }.presence
      headers = Array(input[:headers]).to_h { |h| [h[:name], h[:value]] }

      response = case input[:method]
                 when 'GET' then http_get(url, query, headers.presence)
                 when 'DELETE' then http_delete(url, query, headers.presence)
                 when 'POST'
                   headers['Content-Type'] ||= 'application/json' if input[:request_body].present?
                   http_post(url, input[:request_body], headers.presence)
                 when 'PATCH'
                   headers['Content-Type'] ||= 'application/json' if input[:request_body].present?
                   http_patch(url, input[:request_body], headers.presence)
                 else
                   headers['Content-Type'] ||= 'application/json' if input[:request_body].present?
                   http_put(url, input[:request_body], headers.presence)
                 end

      backoff_if_needed(response, api_name: 'Microsoft Graph', server_error_statuses: GRAPH_SERVER_ERROR_STATUSES)
      helpers.graph_ensure_success(response)

      next_link = begin
        JSON.parse(response.body)['@odata.nextLink']
      rescue JSON::ParserError, TypeError
        nil
      end

      { status: response.status, body: response.body, next_link: next_link }
    end

    # ──────────────────────────────────────────────
    # Connector-level helpers: mail subscriptions
    # ──────────────────────────────────────────────

    helper :outlook_mail_subscription_store_key do |runbook_uuid|
      "outlook_mail_subscription_id-#{runbook_uuid}"
    end

    helper :outlook_client_state_store_key do |runbook_uuid|
      "outlook_mail_client_state-#{runbook_uuid}"
    end

    helper :delete_stored_mail_subscription do |runbook_uuid|
      subscription_id = outbound_connection.store.read(helpers.outlook_mail_subscription_store_key(runbook_uuid))
      next if subscription_id.blank?

      helpers.graph_delete("subscriptions/#{subscription_id}")
      outbound_connection.store.write(helpers.outlook_mail_subscription_store_key(runbook_uuid), nil)
      outbound_connection.store.write(helpers.outlook_client_state_store_key(runbook_uuid), nil)
    end
  end
end
