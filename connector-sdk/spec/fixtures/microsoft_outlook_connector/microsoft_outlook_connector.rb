class MicrosoftOutlookConnector < IPaaS::Connector::Definition
  CLOUDS = {
    'Global' => {
      login: 'https://login.microsoftonline.com',
      graph: 'https://graph.microsoft.com',
    }.freeze,
    'US Government GCC High' => {
      login: 'https://login.microsoftonline.us',
      graph: 'https://graph.microsoft.us',
    }.freeze,
    'US Government DoD' => {
      login: 'https://login.microsoftonline.us',
      graph: 'https://dod-graph.microsoft.us',
    }.freeze,
    'China' => {
      login: 'https://login.chinacloudapi.cn',
      graph: 'https://microsoftgraph.chinacloudapi.cn',
    }.freeze,
  }.freeze
  DEFAULT_CLOUD = 'Global'.freeze

  DEFAULT_FOLDER    = 'inbox'.freeze
  DEFAULT_PAGE_SIZE = 25
  MAX_PAGE_SIZE     = 1000

  DEFAULT_PAGE_LIMIT = 1
  MAX_PAGE_LIMIT     = 100

  DEFAULT_RESULT_LIMIT = 100
  MAX_RESULT_LIMIT     = 1000

  TOKEN_PATH         = '/oauth2/v2.0/token'.freeze
  TOKEN_SCOPE_SUFFIX = '/.default'.freeze
  GRAPH_API_VERSION  = 'v1.0'.freeze
  TENANT_ALIASES     = %w[common organizations consumers].freeze

  PROBE_OPEN_TIMEOUT = 2
  PROBE_TIMEOUT      = 5

  MAILTO_PREFIX              = 'mailto:'.freeze
  MAILBOX_ROUTING_CHARACTERS = %r{[/\\%]}
  FOLDER_PATTERN             = /\A[A-Za-z0-9_=-]+\z/
  MAX_FOLDER_LENGTH          = 256

  FOLDER_PATH_SEPARATOR = ' / '.freeze
  MAX_FOLDER_REQUESTS   = 12
  MAX_FOLDER_DEPTH      = 32

  MESSAGE_SELECT   = %w[id subject from receivedDateTime hasAttachments isRead importance bodyPreview].freeze
  MESSAGE_ORDER_BY = 'receivedDateTime desc'.freeze

  # 401 and 403 are Microsoft refusing the caller. Every other failure can come from the folder, the
  # filter or the message, so naming a mailbox on those would point at something that is working.
  MAILBOX_REFUSED_STATUSES = [401, 403].freeze
  TO_RECIPIENTS_FIELD = 'toRecipients'.freeze

  SEARCH_FILTER_JOIN  = ' and '.freeze
  SEARCH_DATE_FORMAT  = '%Y-%m-%dT%H:%M:%SZ'.freeze
  ODATA_QUOTE         = "'".freeze
  ODATA_ESCAPED_QUOTE = "''".freeze
  SEARCH_QUOTE        = '"'.freeze
  MAX_SEARCH_REQUESTS = 50

  # Written out rather than built from MESSAGE_SELECT: the loader refuses a connector whose constant
  # is assigned anything but a literal, so deriving one from another stops the connector loading.
  MESSAGE_DETAIL_SELECT = %w[id subject from receivedDateTime hasAttachments isRead importance
                             bodyPreview body].freeze

  BODY_FORMATS        = { 'HTML' => 'html', 'Plain text' => 'text' }.freeze
  DEFAULT_BODY_FORMAT = 'HTML'.freeze
  BODY_PREFER_HEADER  = 'Prefer'.freeze

  PERCENT_ESCAPE = /%[0-9A-Fa-f]{2}/

  SEND_MAIL_PATH    = '/sendMail'.freeze
  BODY_TYPES        = %w[text html].freeze
  DEFAULT_BODY_TYPE = 'text'.freeze

  SEND_MAIL_ACCEPTED_STATUS = 202
  SAVE_TO_SENT_ITEMS        = true
  JSON_HEADERS              = { 'Content-Type' => 'application/json' }.freeze
  RECIPIENT_PATTERN         = /\A[^@\s]+@[^@\s]+\z/

  ATTACHMENT_SELECT         = %w[id name contentType size isInline].freeze
  ATTACHMENT_CONTENT_SELECT = %w[id name contentType microsoft.graph.fileAttachment/contentBytes].freeze
  FILE_ATTACHMENT_TYPE      = '#microsoft.graph.fileAttachment'.freeze
  ITEM_ATTACHMENT_TYPE      = '#microsoft.graph.itemAttachment'.freeze
  REFERENCE_ATTACHMENT_TYPE = '#microsoft.graph.referenceAttachment'.freeze
  MAX_ATTACHMENT_BYTES      = 3072 * 1024

  BATCH_REQUEST_LIMIT = 20
  ARCHIVE_FOLDER      = 'archive'.freeze
  BATCH_PATH            = '/$batch'.freeze
  MOVE_PATH_SUFFIX      = '/move'.freeze
  CONTENT_TYPE_HEADER   = 'Content-Type'.freeze
  JSON_CONTENT_TYPE     = 'application/json'.freeze
  MOVE_SUCCESS_STATUSES = [200, 201].freeze
  MESSAGE_ID_PATTERN    = /\A[A-Za-z0-9_=-]+\z/

  EVENTS_PATH                = '/events'.freeze
  CALENDARS_PATH             = '/calendars'.freeze
  EVENT_CREATED_STATUS       = 201
  EVENT_DELETED_STATUS       = 204
  EVENT_GONE_STATUS          = 404
  EVENT_GONE_CODE            = 'ErrorItemNotFound'.freeze
  DUPLICATE_TRANSACTION_CODE = 'ErrorDuplicateTransactionId'.freeze
  UNKNOWN_TIME_ZONE_CODE     = 'TimeZoneNotSupportedException'.freeze
  REFUSED_PROPERTY_CODE      = 'ErrorPropertyValidationFailure'.freeze
  MAX_GRAPH_ID_LENGTH        = 256
  ATTENDEE_TYPE              = 'required'.freeze
  WALL_TIME_PATTERN          = /\A(\d{4}-\d{2}-\d{2})[ T]([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d)(?:\.\d+)?)?\z/
  WALL_TIME_CONVERSION       = "<value>.in_time_zone('Europe/Zurich').strftime('%Y-%m-%d %H:%M')".freeze
  WALL_TIME_COLON_CAVEAT     = 'The conversion needs a colon in the time: it reads 08.00 as midnight.'.freeze
  CALENDAR_PERMISSION_HINT   = 'Check that the app holds the Calendars.ReadWrite application permission for ' \
                               'this mailbox.'.freeze
  EVENT_MAY_EXIST_HINT       = 'Microsoft may have created the event before it failed, so look in the calendar ' \
                               'before you run the step again, or map a Transaction ID.'.freeze

  SUBSCRIPTION_PATH           = '/subscriptions'.freeze
  SUBSCRIPTIONS_STORE_KEY     = 'subscriptions'.freeze
  SUBSCRIPTION_GONE_STATUSES  = [404].freeze
  SUBSCRIPTION_DELETED_STATUS = 204
  SUBSCRIPTION_ID_PATTERN     = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  LIFECYCLE_EVENT_KEY         = 'lifecycleEvent'.freeze

  SUBSCRIPTION_CHANGE_TYPE          = 'created'.freeze
  MAX_SUBSCRIPTION_LIFETIME_MINUTES = 10_080
  CLOCK_SKEW_MARGIN_MINUTES         = 30
  RENEWAL_WINDOW_MINUTES            = 1440
  MAX_SUBSCRIPTION_LIST_REQUESTS    = 10
  SUBSCRIPTION_CREATED_STATUSES     = [200, 201].freeze
  SUBSCRIPTION_RENEWED_STATUS       = 200
  OUTCOME_CREATED                   = 'created'.freeze
  OUTCOME_RENEWED                   = 'renewed'.freeze
  OUTCOME_REMOVED                   = 'removed'.freeze
  OUTCOME_SKIPPED                   = 'skipped'.freeze
  OUTCOME_FAILED                    = 'failed'.freeze
  TRANSIENT_SERVER_ERROR_STATUSES   = [500, 502, 503, 504].freeze
  ROW_CHANGED_WHILE_ANSWERING       = 'The trigger changed while Microsoft was answering, so nothing was stored.'.freeze
  NOTHING_RECORDED                  = 'No trigger records a subscription on this connection. A trigger records ' \
                                      'on the Outlook connection it uses, so this step must use that connection.'.freeze
  ADDRESS_KEY_PREFIX                = 'http'.freeze

  VALIDATION_TOKEN_PARAM      = 'validationToken'.freeze
  VALIDATION_ECHO_PREFIX      = 'graph-validation:'.freeze
  VALIDATION_CONTENT_TYPE     = 'text/plain'.freeze
  MAX_VALIDATION_TOKEN_LENGTH = 1024
  URL_POSTFIX_REFUSED         = 'New Email Received takes no URL postfix. Microsoft sends its notifications to one ' \
                                'address, and a postfix changes it. Clear URL postfix and try again.'.freeze

  connector '01a0d336-be93-7f28-ad86-75b8273e1010' do
    name 'Microsoft Outlook Connector'
    avatar '/assets/icons/microsoft-outlook.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Connects to Microsoft 365 mailboxes through the [Microsoft Graph API](https://learn.microsoft.com/en-us/graph/) to read email from user and shared mailboxes into Xurrent, to send email as those mailboxes, and to create and delete events in their calendars.

      ## Prerequisites
      - A Microsoft Entra ID tenant with Exchange Online mailboxes.
      - An app registration in Microsoft Entra (single tenant, no redirect URI). Obtain:
        - **Tenant ID**: **Microsoft Entra admin center → Entra ID → Overview → Properties → Tenant ID**.
        - **Client ID**: the **Application (client) ID** on the app registration's **Overview** page.
        - **Client secret**: created under **Certificates & secrets → Client secrets**. Copy the **Value** at creation time; it is not shown again. A secret lives at most 24 months.
      - Application permissions for Microsoft Graph, granted on the app registration and consented by a Privileged Role Administrator or Global Administrator:
        - `Mail.Read`: read mail in every mailbox the app may reach.
        - `Mail.ReadWrite`: move and update mail.
        - `Mail.Send`: send mail as any mailbox.
        - `Calendars.ReadWrite`: create and delete events in every calendar the app may reach.
      - Grant only what the runbooks use. **Test** reads the inbox of the **Default mailbox**, so an app that holds `Calendars.ReadWrite` and no mail permission fails Test while its calendar actions work. Leave Default mailbox empty on such a connection, and name the mailbox on every step.
      - Optional: limit the app to chosen mailboxes with **RBAC for Applications in Exchange Online**. The Entra grant and the Exchange grant add up, so remove the tenant-wide Entra grant when a scope should apply.

      ## Authentication
      The connector signs in as the application (OAuth 2.0 client credentials). No user logs in. The token request goes to `{login host}/{tenant_id}/oauth2/v2.0/token` with the scope `{graph host}/.default`; both hosts follow the selected **Cloud**. Access tokens are cached until they expire and renewed automatically. When the client secret expires or is revoked, every job on the connection fails with Microsoft's own error text until a new secret is entered.

      ### Mailbox identifiers
      Every action names the mailbox it works on, as a **user principal name**, an **object id**, or an **SMTP address**. Microsoft documents the first two; an SMTP address works when it equals the user principal name, which is common but not guaranteed. The **Default mailbox** on the connection is used when an action leaves its mailbox empty.

      ## Triggers

      ### New Email Received
      Starts a workflow when a message arrives in a folder of a mailbox, through [Microsoft Graph change notifications](https://learn.microsoft.com/en-us/graph/change-notifications-overview).

      **Permissions required**: `Mail.Read`

      Deploying the solution records the mailbox and folder to watch on the connection, under the runbook of this trigger. Recording alone starts no delivery. The subscription is created, and then kept alive, by the Renew Subscriptions action: put that action in a runbook of its own, on a Scheduler trigger that runs every 15 minutes, and set that runbook's concurrency to one run at a time. Within 15 minutes of a deploy, or of a change to the mailbox or folder, a run creates the subscription, and a run renews it a day before Microsoft would end it. A trigger that has gone quiet is repaired the same way. Deprovision the trigger in the designer before you delete its runbook: deprovisioning deletes the subscription and its record, while deleting the runbook leaves both behind, and the renewal runbook keeps that subscription alive.

      Microsoft can deliver the same notification more than once, so a workflow that must act on a message exactly once checks the Message ID before it acts. An iPaaS outage long enough to time out deliveries makes Microsoft slow down or drop notifications to this endpoint for a while afterwards, and mail that arrives while deliveries are dropped is not delivered later.

      One request can carry several notifications, so one arrival of the trigger can report several messages. A notification carries the message id, not the message. A workflow that needs the subject or the body calls Get Email with that message id.

      #### Input Parameters
      - **Mailbox** (required): user principal name, object id or SMTP address. One subscription watches one named mailbox, so this trigger does not fall back to the connection's Default mailbox.
      - **Folder** (optional, default `inbox`): a well-known folder name such as `inbox`, `archive`, `junkemail`, or a folder id. Only mail that arrives in this folder starts a workflow.
      - **URL postfix**: leave it empty. Microsoft sends its notifications to one address, so deploying refuses a postfix.

      #### Output
      - **Messages**: one entry per message in the request, each carrying **Message ID**, the id of the message that arrived. Read the list with the Flow connector's Loop action.
      - **Mailbox** and **Folder**: the mailbox and the folder the subscription watches.
      - **Subscription ID**: the Microsoft subscription that sent the notification. One subscription sends every message in a request, so this names the request rather than a message.

      ## Actions

      ### List Emails
      Returns one page of message summaries from a folder of a mailbox, newest first, through the [list messages API](https://learn.microsoft.com/en-us/graph/api/user-list-messages).

      **Permissions required**: `Mail.Read`

      The step repeats once per page, and steps placed inside it run for every page. The connector keeps the position between pages, so no page token is ever mapped by hand.

      #### Input Parameters
      - **Mailbox** (optional): user principal name, object id or SMTP address. Falls back to the connection's Default mailbox.
      - **Folder** (optional, default `inbox`): pick a folder from the mailbox, or type a well-known folder name such as `inbox`, `sentitems`, `archive`, `drafts`, or a folder id. The list reads the folders of the mailbox typed into Mailbox on this step. A Mailbox that carries a value from another step reaches the list as nothing, so the list then reads the connection's Default mailbox, as it does when Mailbox is empty. The list names every parent folder before the folder itself, and two folders can carry the same name: the value the step stores is the folder id, never the name.
      - **Page size** (optional, default 25, maximum 1000): how many messages one page holds.
      - **Page limit** (optional, default 1, maximum 100): how many pages to fetch in total.
      - **Fetch all pages** (optional, default off): ignore Page limit and keep going until the mailbox has no more messages.

      #### Output
      - **Messages**: message id, subject, from (name and address), received date time, has attachments, is read, importance, body preview.
      - **Has next page**: true while the step will run again for a further page.

      ### Search Emails
      Returns the messages of a mailbox that match the criteria you give, in one bounded result set, through the [list messages API](https://learn.microsoft.com/en-us/graph/api/user-list-messages).

      **Permissions required**: `Mail.Read`

      The step runs once and returns every match it read, up to Result limit. Order is not guaranteed, so bound the range with Received after and Received before when the range matters.

      #### Input Parameters
      - **Mailbox** (optional): user principal name, object id or SMTP address. Falls back to the connection's Default mailbox.
      - **Folder** (optional): a well-known folder name such as `inbox`, `sentitems`, `archive`, `drafts`, or a folder id. Empty searches the whole mailbox.
      - **From address**: only messages sent by this address.
      - **To address**: only messages addressed to this address. Microsoft Graph cannot filter on recipients, so this criterion is applied to the messages after they are read.
      - **Subject contains**: only messages whose subject holds this text.
      - **Received after**: only messages received at or after this moment.
      - **Received before**: only messages received at or before this moment.
      - **Has attachments**: on returns only messages with an attachment, off only messages without one.
      - **Is unread**: on returns only unread messages, off only read ones.
      - **Search text**: free text searched in the message content. Microsoft caps a free-text search at a few hundred messages and does not report that it did, so a search that fills this field can miss matches.
      - **Page size** (optional, default 25, maximum 1000): how many messages one request to Microsoft reads. It is not how many messages come back.
      - **Result limit** (optional, default 100, maximum 1000): how many matching messages to return at most. A run makes at most 50 requests to Microsoft, so a small Page size can stop it before this many are found.

      A message must match every criterion you filled. A criterion you leave empty narrows nothing.

      #### Output
      - **Messages**: message id, subject, from (name and address), received date time, has attachments, is read, importance, body preview.
      - **More results exist**: true when matches were left behind, because Result limit was reached, because the run stopped after its 50 requests, or because Microsoft cut a free-text search short.

      ### Get Email
      Returns one message with its body, through the [get message API](https://learn.microsoft.com/en-us/graph/api/message-get).

      **Permissions required**: `Mail.Read`

      A message carries one body, either HTML or plain text, never both. The step asks Microsoft for the one it wants. Microsoft treats that as a preference, so the format it actually used comes back as an output field.

      #### Input Parameters
      - **Message ID** (required): the Message ID an earlier step returned. Ids are never built by hand.
      - **Mailbox** (optional): user principal name, object id or SMTP address. Falls back to the connection's Default mailbox.
      - **Body format** (optional, default HTML): `HTML` or `Plain text`.

      #### Output
      - Everything List Emails returns for a message, plus **Body** and the **Body format** Microsoft used.

      ### Send Email
      Sends one message from a mailbox through the [send mail API](https://learn.microsoft.com/en-us/graph/api/user-sendmail). Microsoft delivers it straight away, so nothing is left in Drafts and there is nothing to send later.

      **Permissions required**: `Mail.Send`

      A message carries one body and one body type, never a plain text copy beside an HTML one. Attachments are not part of this release.

      #### Input Parameters
      - **Mailbox** (optional): the mailbox the message is sent from, as a user principal name, object id or SMTP address. Falls back to the connection's Default mailbox.
      - **To** (required): the recipient addresses.
      - **Cc** (optional): the addresses that receive a copy.
      - **Bcc** (optional): the addresses that receive a copy the other recipients do not see.
      - **Subject** (required): the subject line.
      - **Body** (required): the text of the message.
      - **Body type** (optional, default `text`): `text` keeps the line breaks as typed, `html` reads the body as markup.

      #### Output
      - **Sent**: true when Microsoft accepted the message.
      - **Mailbox**, **To**, **Cc**, **Bcc**, **Subject**: what was sent, so a later step can report it without mapping the same values again.

      ### List Attachments
      Names the attachments of one message through the [list attachments API](https://learn.microsoft.com/en-us/graph/api/message-list-attachments).

      **Permissions required**: `Mail.Read`

      The list carries the name and the size of every attachment, and the media type of a file. It never carries the file itself. A message attached to a message is listed too, with no media type, and Download Attachment refuses it because it holds no file. A workflow that needs a file calls Download Attachment with the attachment id from this list.

      #### Input Parameters
      - **Message ID** (required): the id of the message to read, as returned by List Emails.
      - **Mailbox** (optional): user principal name, object id or SMTP address. Falls back to the connection's Default mailbox.

      #### Output
      - **Attachments**: attachment id, name, content type, size in bytes, is inline.

      ### Download Attachment
      Reads one attachment of one message, with its bytes as base64 text, through the [get attachment API](https://learn.microsoft.com/en-us/graph/api/attachment-get).

      **Permissions required**: `Mail.Read`

      **Content bytes** holds the base64 text Microsoft sends, not the raw file. A step that takes a file reads raw bytes, so map it through `Base64.decode64` first, for example `Base64.decode64(action_output('download-attachment')&.drill(:content_bytes))` into Upload Attachment on the Xurrent connector. Mapping it straight across uploads the base64 text as the file.

      Only a file attachment carries bytes. A message attached to a message (an item attachment) and a link to a cloud file (a reference attachment) hold none, so the step fails and says which kind it found.

      #### Input Parameters
      - **Message ID** (required): the id of the message that holds the attachment, as returned by List Emails.
      - **Attachment ID** (required): the id of the attachment, as returned by List Attachments.
      - **Mailbox** (optional): user principal name, object id or SMTP address. Falls back to the connection's Default mailbox.

      #### Output
      - **Name**: the file name Microsoft reports, such as report.pdf.
      - **Content bytes**: the file as base64 text, exactly as Microsoft sends it.
      - **Content type**: the media type of the file, such as application/pdf.

      ### Renew Subscriptions
      Creates and keeps alive every Microsoft Graph subscription the triggers on this connection depend on, through the [subscription API](https://learn.microsoft.com/en-us/graph/api/resources/subscription).

      **Permissions required**: the read permission of what is watched, `Mail.Read` for a mailbox folder

      Microsoft ends a subscription after seven days unless it is renewed. Put this action in a runbook of its own, on a Scheduler trigger that runs every 15 minutes, and set that runbook's concurrency to one run at a time, so two runs never create the same subscription. Each run lists the subscriptions Microsoft holds for this application, deletes any that points at a trigger of this connection but is not recorded, creates the subscription of every recorded trigger that has none, and renews, in batches of 20, every subscription that ends within a day. So a trigger is watched within 15 minutes of its deploy, or of a change to its mailbox or folder, with no step by hand. A run with nothing to do ends quietly. A run in which a subscription could not be created or renewed fails after it has handled every other row, and its log names the trigger, what it watched and what Microsoft answered. The next run tries again. Use the Outlook connection the triggers use: a run on another connection finds nothing to keep alive. A Scheduler trigger keeps the recurrence it was first deployed with, so after changing it, deprovision and provision that trigger.

      #### Input Parameters
      None. The action reads the subscriptions the connection holds.

      #### Output
      - **Results**: one row per subscription the run touched, with **Runbook ID**, **Resource**, **Mailbox**, **Folder**, **Subscription ID**, **Expires at**, **Outcome** and **Error**. Outcome is `created`, `renewed`, `removed` for a subscription nobody recorded that the run deleted, or `skipped` for a trigger that changed while Microsoft was answering, with the reason in Error. A run in which a row failed ends with the failure instead of this output.
      - **Created**, **Renewed**, **Removed**: how many rows ended with each outcome.

      ### Move Email
      Moves one or more messages into another folder of the same mailbox, through the [move message API](https://learn.microsoft.com/en-us/graph/api/message-move).

      **Permissions required**: `Mail.ReadWrite`

      Moving a message gives it a new id. The id that went in stops working, so a later step that reads the message uses the **New message ID** this action returns.

      Microsoft answers a move once per message, so one message can fail while the rest succeed. Every message id that went in comes back as its own row saying whether it moved.

      #### Input Parameters
      - **Message IDs** (required): the Message IDs an earlier step returned. Ids are never built by hand. At most 20 ids in one step.
      - **Destination folder** (required): a well-known folder name such as `archive`, `deleteditems`, `junkemail`, or a folder id. A display name such as Sent Items is not accepted. A folder that does not exist fails every row with Microsoft's `Id is malformed`, which is the same text a bad message id gets.
      - **Mailbox** (optional): user principal name, object id or SMTP address. Falls back to the connection's Default mailbox.

      #### Output
      - **Results**: one row per message id that went in, and a repeated id comes back once. A row that worked carries the new message id and no error. A row that failed carries the error text and no new message id.

      ### Archive Email
      Moves one or more messages into the archive folder of the mailbox, through the same [move message API](https://learn.microsoft.com/en-us/graph/api/message-move) that Move Email uses.

      **Permissions required**: `Mail.ReadWrite`

      The destination is fixed to the well-known `archive` folder. That is the one-click Archive folder in the mailbox, not the separate online archive mailbox, which Microsoft does not reach the same way.

      Archiving a message gives it a new id, exactly as Move Email does. The id that went in stops working, so a later step that reads the message uses the **New message ID** this action returns.

      #### Input Parameters
      - **Message IDs** (required): the Message IDs an earlier step returned. Ids are never built by hand. At most 20 ids in one step.
      - **Mailbox** (optional): user principal name, object id or SMTP address. Falls back to the connection's Default mailbox.

      #### Output
      - **Results**: one row per message id that went in, and a repeated id comes back once. A row that worked carries the new message id and no error. A row that failed carries the error text and no new message id.

      ### Create Calendar Event
      Creates one event in a calendar of a mailbox, through the [create event API](https://learn.microsoft.com/en-us/graph/api/user-post-events). Microsoft sends an invitation to every attendee.

      **Permissions required**: `Calendars.ReadWrite`

      Start and End are the local date and time in the zone named in Time zone, such as `2026-12-01 08:00` in `W. Europe Standard Time`. Microsoft applies that zone's clock changes, so the time stays the same in winter and in summer. A Start that does not exist in the zone, such as 02:30 on the night the clocks go forward, is moved later by Microsoft without an error, and **Start** and **End** in the output show the time Microsoft stored. When the moved Start falls after End, Microsoft refuses the event.

      A step that runs again creates a second event, unless it carries a **Transaction ID**. Microsoft remembers the Transaction ID of every event it holds: a second create with the same Transaction ID and the same values returns the event that exists, and one with different values fails. Map a value that is the same for one booking and different for the next one, such as the delivery id of the webhook that asked for the booking.

      #### Input Parameters
      - **Mailbox** (optional): the mailbox that owns the calendar and sends the invitations, as a user principal name, object id or SMTP address. Falls back to the connection's Default mailbox.
      - **Calendar ID** (optional): the id of a calendar in the mailbox. Empty uses the default calendar of the mailbox. A read-only calendar, such as a holiday calendar, is refused by Microsoft.
      - **Subject** (required): the title of the event.
      - **Start** (required) and **End** (required): the local date and time, written `2026-12-01 08:00` or `2026-12-01T08:00:00`, with no offset and no `Z`. Convert a time that carries an offset first, such as `<value>.in_time_zone('Europe/Zurich').strftime('%Y-%m-%d %H:%M')`, and name the same zone in Time zone. The conversion takes an IANA name only, and it needs a colon in the time: it reads `08.00` as midnight. End may equal Start, and may not be earlier.
      - **Time zone** (required): the zone of Start and End, as a Windows name such as `W. Europe Standard Time` or an IANA name such as `Europe/Zurich`.
      - **Body** (optional) and **Body type** (optional, default `text`): the text of the event. `text` keeps the line breaks as typed, `html` reads the body as markup.
      - **Location** (optional): **Display name**, **Street**, **Postal code** and **City**. Only the fields that hold a value are sent.
      - **Attendees** (optional): the addresses that receive the invitation, all as required attendees.
      - **Reminder minutes before start** (optional): turns the reminder on that many minutes before Start. Empty leaves the choice to Microsoft, which turns a 15 minute reminder on.
      - **Transaction ID** (optional): a value that makes a repeated create return the existing event instead of a second one.

      #### Output
      - **Event ID**: the id that Delete Calendar Event takes.
      - **Web link**, **iCal UID**, **Subject**, **Start** and **End** (each a date time and a time zone, as Microsoft stored them), **Organizer**, **Attendees**, **Location**, **Is reminder on**, **Reminder minutes before start**, **Created date time** and **Mailbox**.

      ### Delete Calendar Event
      Deletes one event from the mailbox, through the [delete event API](https://learn.microsoft.com/en-us/graph/api/event-delete). When the mailbox organised the event, Microsoft sends a cancellation to the attendees.

      **Permissions required**: `Calendars.ReadWrite`

      An event that Microsoft does not find in the mailbox passes with **Deleted** false, so a cancel that arrives twice does not fail the second time. Deleted false says only that this mailbox held no such event when the step asked: an earlier delete removed it, an earlier try of this same step removed it before Microsoft answered with a server error, or the Event ID was never in this mailbox. An empty Event ID fails the step, because there is nothing to delete.

      #### Input Parameters
      - **Event ID** (required): the Event ID that Create Calendar Event returned.
      - **Mailbox** (optional): the mailbox that holds the event, as a user principal name, object id or SMTP address. Falls back to the connection's Default mailbox.

      #### Output
      - **Deleted**: true when this step deleted the event, false when the mailbox held no event with this id when the step asked.
      - **Event ID** and **Mailbox**: what the step asked Microsoft to delete.

      ## References
      - [Get access without a user](https://learn.microsoft.com/en-us/graph/auth-v2-service)
      - [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
      - [Register an application with Microsoft Entra](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)
      - [Role Based Access Control for Applications in Exchange Online](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)
      - [The date, time and time zone of an event](https://learn.microsoft.com/en-us/graph/api/resources/datetimetimezone)

    END_OF_DESCRIPTION

    outbound_connection do
      config_schema do
        field :credentials, 'Credentials', :nested,
              required: true do
          field :tenant_id, 'Tenant ID', :string,
                required: true,
                hint: 'Directory (tenant) ID of the Microsoft Entra tenant, a GUID or a verified domain name.'
          field :client_id, 'Client ID', :string,
                required: true,
                hint: 'Application (client) ID of the app registration.'
          field :client_secret, 'Client secret', :secret_string,
                required: true,
                hint: 'The secret Value from Certificates & secrets. Microsoft shows it once.'
        end

        field :cloud, 'Cloud', :string,
              required: true,
              default: DEFAULT_CLOUD,
              enumeration: CLOUDS.keys,
              hint: 'Selects the Microsoft login host and the Graph host together.'

        field :default_mailbox, 'Default mailbox', :string,
              visibility: 'optional',
              hint: 'User principal name (AdeleV@contoso.com), object id (59bb3898-...) or SMTP address. ' \
                    'Used when an action leaves its mailbox empty, and probed by Test.'
      end

      authenticate do |request|
        request.headers['Authorization'] = oauth2_authorization_header(helpers.token_url, helpers.token_body)
      end

      config_tester do
        mailbox = helpers.normalize_mailbox(outbound_connection.config[:default_mailbox])
        if mailbox.blank?
          oauth2_authorization_header(helpers.token_url, helpers.token_body)
          {
            status: :success,
            message: 'Microsoft accepted the credentials. Set a Default mailbox to also check mailbox access.',
          }
        else
          response = http_get(helpers.graph_url("#{helpers.user_path(mailbox)}/mailFolders/inbox"),
                              nil, nil, open_timeout: PROBE_OPEN_TIMEOUT, timeout: PROBE_TIMEOUT)
          if response.status == 200
            { status: :success, message: "Connection successful. Read the inbox of #{mailbox}." }
          elsif [401, 403, 404].include?(response.status)
            { status: :failed, message: helpers.describe_graph_failure(response) }
          else
            { status: :error, message: helpers.describe_graph_failure(response) }
          end
        end
      rescue IPaaS::Job::FailJob => e
        { status: :failed, message: e.message }
      end
    end

    trigger '5e6feeca-3703-414d-bcf6-2be3aa66ae50' do
      name 'New Email Received'
      avatar '/assets/icons/microsoft-outlook.svg'

      description <<~END_OF_DESCRIPTION
        Starts a workflow when a message arrives in a folder of a mailbox. Microsoft Graph watches the folder and sends a notification, so nothing polls the mailbox.

        Microsoft can put several notifications in one request, so Messages is a list and a workflow reads every message in it with the Flow connector's Loop action. A notification carries the message id, not the message. A workflow that needs the subject or the body calls Get Email with that message id.

        One subscription watches one named mailbox and one folder. Give a second mailbox, or a second folder, its own trigger. Leave URL postfix empty: Microsoft sends its notifications to one address, and deploying refuses a postfix.

        Deploying the solution records the mailbox and folder to watch, and starts no delivery by itself. The Renew Subscriptions action, run on a Scheduler trigger every 15 minutes, creates the subscription within 15 minutes of a deploy or a change, and keeps it alive. Deprovision the trigger before you delete its runbook, or the renewal runbook keeps its subscription alive. Microsoft can deliver the same notification twice, so a workflow that must act once checks the Message ID first.
      END_OF_DESCRIPTION

      outbound_traffic true

      config_schema do
        field :mailbox, 'Mailbox', :string,
              required: true,
              hint: 'User principal name, object id or SMTP address. One subscription watches one named mailbox, ' \
                    'so this trigger does not fall back to the connection\'s Default mailbox.'
        field :folder, 'Folder', :string,
              visibility: 'optional',
              default: DEFAULT_FOLDER,
              hint: 'Well-known name (inbox, sentitems, archive, drafts, deleteditems, junkemail) or a folder id.'
      end

      output_schema do
        field :messages, 'Messages', :nested, array: true, required: true do
          field :message_id, 'Message ID', :string, required: true
        end
        field :mailbox, 'Mailbox', :string
        field :folder, 'Folder', :string
        field :subscription_id, 'Subscription ID', :string
      end

      provision do
        fail_job!(URL_POSTFIX_REFUSED) if helpers.url_postfix_set
        mailbox = helpers.normalize_mailbox(trigger.config[:mailbox])
        folder = helpers.folder_for(trigger.config[:folder])
        resource = helpers.subscription_resource(mailbox, folder)
        row = helpers.own_row
        changed = row['resource'] != resource || row.fetch('endpoint', trigger.endpoint) != trigger.endpoint
        helpers.delete_subscription(row) if changed
        watch = { 'resource' => resource, 'mailbox' => mailbox, 'folder' => folder, 'endpoint' => trigger.endpoint }
        helpers.store_own_row(watch)
      end

      deprovision do
        fail_job!(URL_POSTFIX_REFUSED) if helpers.url_postfix_set
        rows = helpers.subscription_rows
        helpers.delete_subscription(rows[trigger.runbook.uuid])
        helpers.delete_subscription(rows[trigger.endpoint])
        helpers.store_own_row(nil)
      end

      parse do |request|
        discard_trigger_event!(URL_POSTFIX_REFUSED) if helpers.url_postfix_set
        token = helpers.validation_token(request)
        discard_trigger_event!("#{VALIDATION_ECHO_PREFIX}#{token}") if token.present?

        row = helpers.own_row
        secret = row['client_state'].to_s
        expected = secret.present? ? decrypt_secret_string(secret) : ''
        batch = helpers.trusted_notifications(helpers.notifications(request.body&.read), expected)
        mail = batch.reject { |item| item[LIFECYCLE_EVENT_KEY].present? }
        discard_trigger_event!('A request to this endpoint carried no new mail') if mail.empty?

        {
          messages: mail.map { |item| { message_id: helpers.notification_message_id(item) } },
          mailbox: row['mailbox'],
          folder: row['folder'],
          subscription_id: mail.first['subscriptionId'],
        }
      end

      respond_with do |context, response|
        error = context[:error]
        if error.is_a?(IPaaS::Job::DiscardTriggerEvent) &&
           error.message.to_s.start_with?(VALIDATION_ECHO_PREFIX)
          response[:status] = 200
          response[:headers]['content-type'] = VALIDATION_CONTENT_TYPE
          response[:body] = error.message.to_s[VALIDATION_ECHO_PREFIX.length..]
        end
        response
      end
    end

    action '01a0d336-be94-7be9-9d8b-3bd3998d055b' do
      name 'List Emails'
      avatar '/assets/icons/microsoft-outlook.svg'
      nested true

      description <<~END_OF_DESCRIPTION
        Returns message summaries from a folder of a mailbox, newest first, one page per round. Steps placed inside this step run for every page, and the connector keeps the position itself, so nothing carries a page token through the workflow.

        Page size sets how many messages one page holds. Page limit sets how many pages to fetch in total. Turn on Fetch all pages to keep going until the mailbox has no more messages.

        The body is not part of the summary. A workflow that needs the body of one listed message calls Get Email with that message id.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              visibility: 'optional',
              hint: 'User principal name, object id or SMTP address. Empty uses the connection\'s Default mailbox.'
        field :folder, 'Folder', :string,
              visibility: 'optional',
              default: DEFAULT_FOLDER,
              hint: 'Pick a folder from the list. The list is read from the mailbox typed into Mailbox, and ' \
                    'from the connection\'s Default mailbox when Mailbox is empty. A Mailbox filled in by ' \
                    'an earlier step is not known until the runbook runs, so the list is read from the ' \
                    'Default mailbox then too, and a folder the step really reads may not appear on it.' do
          options do |mailbox: nil|
            helpers.fetch_folder_options(mailbox: mailbox)
          end
        end
        field :page_size, 'Page size', :integer,
              visibility: 'optional',
              default: DEFAULT_PAGE_SIZE,
              min: 1,
              max: MAX_PAGE_SIZE,
              hint: 'Messages per page.'
        field :page_limit, 'Page limit', :integer,
              visibility: 'optional',
              default: DEFAULT_PAGE_LIMIT,
              min: 1,
              max: MAX_PAGE_LIMIT,
              hint: 'How many pages to fetch in total. Each page is one round of this step.'
        field :all_pages, 'Fetch all pages', :boolean,
              visibility: 'optional',
              default: false,
              hint: 'Ignore Page limit and keep going until the mailbox has no more messages.'
      end

      output_schema 'page' do
        field :messages, 'Messages', :nested, array: true do
          field :message_id, 'Message ID', :string, required: true
          field :subject, 'Subject', :string
          field :from, 'From', :nested do
            field :name, 'Name', :string
            field :address, 'Address', :string
          end
          field :received_date_time, 'Received date time', :date_time
          field :has_attachments, 'Has attachments', :boolean
          field :is_read, 'Is read', :boolean
          field :importance, 'Importance', :string
          field :body_preview, 'Body preview', :string
        end
        field :has_next_page, 'Has next page', :boolean,
              required: true,
              hint: 'True while this step will run again for a further page.'
      end

      iteration_state_schema do
        field :next_link, 'Next link', :string, required: true
        field :mailbox, 'Mailbox', :string, required: true
        field :folder, 'Folder', :string, required: true
        field :graph_host, 'Graph host', :string, required: true
      end

      run do
        mailbox = helpers.mailbox_for(input[:mailbox])
        folder = helpers.folder_for(input[:folder])
        stored_link = helpers.resumable_link(mailbox, folder)

        body = if stored_link.present?
                 helpers.graph_get(stored_link, nil, mailbox)
               else
                 helpers.graph_get(helpers.messages_url(mailbox, folder),
                                   {
                                     '$select': MESSAGE_SELECT.join(','),
                                     '$orderby': MESSAGE_ORDER_BY,
                                     '$top': helpers.integer_or_default(input[:page_size], DEFAULT_PAGE_SIZE).to_s,
                                   }, mailbox)
               end
        page = body['value'] || []
        raise IPaaS::Error, 'Microsoft Graph returned a page whose value is not a list' unless page.is_a?(Array)

        messages = page.map { |message| helpers.message_summary(message) }
        next_link = helpers.next_page_link(body)
        rounds_done = iteration_state.blank? ? 0 : iteration_state[:count].to_i
        page_limit = helpers.integer_or_default(input[:page_limit], DEFAULT_PAGE_LIMIT)
        another_round = next_link.present? && (input[:all_pages] == true || (rounds_done + 1) < page_limit)
        self.iteration_state_value = another_round ? helpers.position(next_link, mailbox, folder) : nil

        [{ output: { messages: messages, has_next_page: another_round }, schema_reference: 'page' }]
      end
    end

    action '74a57eb7-eb5b-4c95-8ac1-7000eb7853b1' do
      name 'Search Emails'
      avatar '/assets/icons/microsoft-outlook.svg'

      description <<~END_OF_DESCRIPTION
        Returns the messages of a mailbox that match the criteria you give, in one bounded result set. The step runs once, so nothing is placed inside it.

        Fill the criteria you care about and leave the rest empty. A message must match every criterion you filled, and a criterion you leave empty narrows nothing. From address, To address, Subject contains, Received after, Received before, Has attachments and Is unread ask about the message itself. Search text is free text searched in the message content. To address is applied to the messages after they are read, because Microsoft Graph cannot filter on recipients.

        Result limit caps how many matching messages come back. More results exist tells you that matches were left behind, because Result limit was reached, because the run stopped after its 50 requests to Microsoft, or because Microsoft cut a free-text search short. Page size is how many messages one request to Microsoft reads, which is not how many messages come back.

        Microsoft caps a free-text search at a few hundred messages and reports the set as complete when it does. A search that fills Search text can therefore miss matches that the same criteria find without it.

        Order is not guaranteed, so bound the range with Received after and Received before when the range matters.

        The body is not part of the summary, even when Search text matched it.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              visibility: 'optional',
              hint: 'User principal name, object id or SMTP address. Empty uses the connection\'s Default mailbox.'
        field :folder, 'Folder', :string,
              visibility: 'optional',
              hint: 'Well-known name (inbox, sentitems, archive, drafts, deleteditems, junkemail) or a folder id. ' \
                    'Empty searches the whole mailbox.'
        field :from_address, 'From address', :string,
              hint: 'Only return messages sent by this address. Empty does not narrow the search.'
        field :to_address, 'To address', :string,
              hint: 'Only return messages addressed to this address. Microsoft Graph cannot filter on ' \
                    'recipients, so this is applied after the messages are read. Empty does not narrow the search.'
        field :subject_contains, 'Subject contains', :string,
              hint: 'Only return messages whose subject holds this text. Empty does not narrow the search.'
        field :received_after, 'Received after', :date_time,
              hint: 'Only return messages received at or after this moment. Empty does not narrow the search.'
        field :received_before, 'Received before', :date_time,
              hint: 'Only return messages received at or before this moment. Empty does not narrow the search.'
        field :has_attachments, 'Has attachments', :boolean,
              hint: 'On returns messages with an attachment, off returns messages without one. Empty returns both.'
        field :is_unread, 'Is unread', :boolean,
              hint: 'On returns unread messages, off returns read ones. Empty returns both.'
        field :search_text, 'Search text', :string,
              hint: 'Free text searched in the message content. Empty does not narrow the search.'
        field :page_size, 'Page size', :integer,
              visibility: 'optional',
              default: DEFAULT_PAGE_SIZE,
              min: 1,
              max: MAX_PAGE_SIZE,
              hint: 'Messages one request to Microsoft reads. This is not how many messages come back.'
        field :result_limit, 'Result limit', :integer,
              visibility: 'optional',
              default: DEFAULT_RESULT_LIMIT,
              min: 1,
              max: MAX_RESULT_LIMIT,
              hint: 'How many matching messages to return at most, and More results exist says whether more ' \
                    'were left. A run makes at most 50 requests to Microsoft, so a small Page size can stop ' \
                    'it before this many are found.'
      end

      output_schema do
        field :messages, 'Messages', :nested, array: true do
          field :message_id, 'Message ID', :string, required: true
          field :subject, 'Subject', :string
          field :from, 'From', :nested do
            field :name, 'Name', :string
            field :address, 'Address', :string
          end
          field :received_date_time, 'Received date time', :date_time
          field :has_attachments, 'Has attachments', :boolean
          field :is_read, 'Is read', :boolean
          field :importance, 'Importance', :string
          field :body_preview, 'Body preview', :string
        end
        field :more_results_exist, 'More results exist', :boolean,
              required: true,
              hint: 'True when matches were left behind: Result limit was reached, the run stopped after its ' \
                    '50 requests, or Microsoft cut a free-text search short.'
      end

      run do
        mailbox = helpers.mailbox_for(input[:mailbox])
        folder = helpers.search_folder_for(input[:folder])
        url = helpers.search_messages_url(mailbox, folder)
        limit = helpers.integer_or_default(input[:result_limit], DEFAULT_RESULT_LIMIT)
        rules = { select: helpers.search_select(input[:to_address]),
                  page_size: helpers.integer_or_default(input[:page_size], DEFAULT_PAGE_SIZE),
                  to_address: input[:to_address], limit: limit, mailbox: mailbox, }
        read = helpers.search_messages(url, helpers.search_query(input[:search_text]), helpers.search_filter(input),
                                       rules)
        found = read[:messages]

        [{ output: { messages: found.take(limit).map { |message| helpers.message_summary(message) },
                     more_results_exist: read[:left_unread] || found.length > limit, } }]
      end
    end

    action '2c220667-3750-487b-a600-dad37fa674d4' do
      name 'Get Email'
      avatar '/assets/icons/microsoft-outlook.svg'

      description <<~END_OF_DESCRIPTION
        Returns one message with its body, through the [get message API](https://learn.microsoft.com/en-us/graph/api/message-get).

        Body format chooses whether Microsoft returns the body as HTML or as plain text. A message carries one body, never both, so the format is asked for rather than picked from the answer. Microsoft treats the request as a preference, so the format it actually used comes back as its own output field.

        The message id comes from a List Emails step. Ids are never built by hand.
      END_OF_DESCRIPTION

      input_schema do
        field :message_id, 'Message ID', :string,
              required: true,
              hint: 'The Message ID an earlier step returned. Paste the raw id, not one copied ' \
                    'from a browser address bar.'
        field :mailbox, 'Mailbox', :string,
              visibility: 'optional',
              hint: 'User principal name, object id or SMTP address. Empty uses the connection\'s Default mailbox.'
        field :body_format, 'Body format', :string,
              visibility: 'optional',
              default: DEFAULT_BODY_FORMAT,
              enumeration: BODY_FORMATS.keys,
              hint: 'Ask Microsoft for the body as HTML or as plain text.'
      end

      output_schema do
        field :message_id, 'Message ID', :string, required: true
        field :subject, 'Subject', :string
        field :from, 'From', :nested do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :received_date_time, 'Received date time', :date_time
        field :has_attachments, 'Has attachments', :boolean
        field :is_read, 'Is read', :boolean
        field :importance, 'Importance', :string
        field :body_preview, 'Body preview', :string
        field :body, 'Body', :string
        field :body_format, 'Body format', :string,
              hint: 'The format Microsoft actually used. Microsoft treats the requested format as a preference.'
      end

      run do
        mailbox = helpers.mailbox_for(input[:mailbox])
        message_id = helpers.message_id_for(input[:message_id])

        response = http_get(helpers.message_url(mailbox, message_id),
                            { '$select': MESSAGE_DETAIL_SELECT.join(',') },
                            { BODY_PREFER_HEADER => helpers.body_preference(input[:body_format]) })
        backoff_if_needed(response, api_name: 'Microsoft')
        fail_job!(helpers.describe_missing_message(mailbox, message_id)) if response.status == 404

        [{ output: helpers.message_detail(helpers.parse_graph(response, mailbox)) }]
      end
    end

    # The assertion: a message id always comes from an earlier step, which hands back Microsoft's own
    # value. One carrying percent escapes was copied from somewhere that had already encoded it, and
    # encoding it again turns %2F into %252F, so Graph answers 404 for a message that exists.
    helper :message_id_for do |value|
      id = value.to_s.strip
      if id.match?(PERCENT_ESCAPE)
        fail_job!("Message ID '#{id}' is already URL encoded. Map the raw id an earlier step " \
                  'returned, not one copied from a browser address bar.')
      end

      id
    end

    # The assertion: the body format is one of the values the field offers. The field refuses an
    # unlisted value, so only a blank one can reach here, and a blank one must not build a header
    # with nothing in it: the platform refuses a header value that is not a string.
    helper :body_preference do |name|
      chosen = BODY_FORMATS[name.presence || DEFAULT_BODY_FORMAT]
      fail_job!("Body format '#{name}' is not one of #{BODY_FORMATS.keys.join(', ')}.") if chosen.blank?

      "outlook.body-content-type=\"#{chosen}\""
    end

    helper :message_url do |mailbox, message_id|
      helpers.graph_url("#{helpers.user_path(mailbox)}/messages/" \
                        "#{helpers.escape_segment(message_id)}")
    end

    helper :describe_missing_message do |mailbox, message_id|
      "Microsoft Graph has no message '#{message_id}' in mailbox '#{mailbox}'."
    end

    # message_summary already guards a message with no id and a draft with no sender. This widens it
    # rather than replacing it, so neither guard can be lost.
    helper :message_detail do |message|
      body = message['body'] || {}
      helpers.message_summary(message).merge(
        body: body['content'].to_s,
        body_format: body['contentType'].to_s,
      )
    end

    action '0c405a38-d2a3-4b45-9651-83b9b36709bc' do
      name 'Send Email'
      avatar '/assets/icons/microsoft-outlook.svg'

      description <<~END_OF_DESCRIPTION
        Sends one message from a mailbox. Microsoft delivers it straight away, so nothing is left in Drafts and there is nothing to send afterwards.

        To, Cc and Bcc each take a list of addresses. Body type picks how the body is read: text keeps the line breaks as typed, html reads the body as markup. A message carries one body and one body type, never a plain text copy beside an HTML one.

        Microsoft limits how many messages one mailbox may send in a short time. When it refuses a message for that reason, the step pauses and runs again by itself.

        Attachments are not part of this release.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              visibility: 'optional',
              hint: 'User principal name, object id or SMTP address to send from. Empty uses the connection\'s ' \
                    'Default mailbox.'
        field :to_recipients, 'To', :string,
              array: true,
              required: true,
              hint: 'The recipient addresses. Add one value per address.'
        field :cc_recipients, 'Cc', :string,
              array: true,
              visibility: 'optional',
              hint: 'The addresses that receive a copy. Add one value per address.'
        field :bcc_recipients, 'Bcc', :string,
              array: true,
              visibility: 'optional',
              hint: 'The addresses that receive a copy the other recipients do not see.'
        field :subject, 'Subject', :string,
              required: true,
              hint: 'The subject line.'
        field :body, 'Body', :string,
              required: true,
              hint: 'The text of the message.'
        field :body_type, 'Body type', :string,
              visibility: 'optional',
              default: DEFAULT_BODY_TYPE,
              enumeration: BODY_TYPES,
              hint: 'text keeps the line breaks as typed. html reads the body as markup.'
      end

      output_schema do
        field :sent, 'Sent', :boolean,
              required: true,
              hint: 'True when Microsoft accepted the message for delivery.'
        field :mailbox, 'Mailbox', :string,
              hint: 'The mailbox the message was sent from.'
        field :to_recipients, 'To', :string, array: true
        field :cc_recipients, 'Cc', :string, array: true
        field :bcc_recipients, 'Bcc', :string, array: true
        field :subject, 'Subject', :string
      end

      run do
        mailbox = helpers.mailbox_for(input[:mailbox])
        payload = helpers.send_mail_payload(input)

        response = http_post(helpers.send_mail_url(mailbox), payload.to_json, JSON_HEADERS)
        # A server error does not say the message was left unsent, and a paused step runs the whole action
        # again from the top, so only a rate limit pauses here. Microsoft rejected that request outright.
        backoff_if_needed(response, api_name: 'Microsoft', server_error_statuses: [])
        fail_job!(helpers.describe_graph_failure(response)) if response.status != SEND_MAIL_ACCEPTED_STATUS

        message = payload[:message]
        [{ output: { sent: true,
                     mailbox: mailbox,
                     to_recipients: helpers.addresses_of(message[:toRecipients]),
                     cc_recipients: helpers.addresses_of(message[:ccRecipients]),
                     bcc_recipients: helpers.addresses_of(message[:bccRecipients]),
                     subject: message[:subject], } }]
      end
    end

    action '82d33e8f-e4c2-4d12-8b15-6edac6c36e2c' do
      name 'List Attachments'
      avatar '/assets/icons/microsoft-outlook.svg'

      description <<~END_OF_DESCRIPTION
        Names the attachments of one message: the attachment id, the file name, the media type, the size and whether the attachment is shown inside the body. A message attached to a message is listed with no media type, because it holds no file.

        The file itself is not part of the list. A workflow that needs a file calls Download Attachment with the attachment id from this list.
      END_OF_DESCRIPTION

      input_schema do
        field :message_id, 'Message ID', :string,
              required: true,
              hint: 'The id of the message to read, as returned by List Emails.'
        field :mailbox, 'Mailbox', :string,
              visibility: 'optional',
              hint: 'User principal name, object id or SMTP address. Empty uses the connection\'s Default mailbox.'
      end

      output_schema do
        field :attachments, 'Attachments', :nested, array: true do
          field :attachment_id, 'Attachment ID', :string, required: true
          field :name, 'Name', :string
          field :content_type, 'Content type', :string,
                hint: 'Empty for an attachment that holds no file, such as a message attached to a message.'
          field :size_in_bytes, 'Size in bytes', :integer
          field :is_inline, 'Is inline', :boolean,
                hint: 'True for a picture shown inside the body rather than a file listed beside it.'
        end
      end

      run do
        mailbox = helpers.mailbox_for(input[:mailbox])
        body = helpers.graph_get(helpers.attachments_url(mailbox, input[:message_id]),
                                 { '$select': ATTACHMENT_SELECT.join(',') }, mailbox)
        rows = body['value'] || []
        unless rows.is_a?(Array)
          raise IPaaS::Error, 'Microsoft Graph returned an attachment list whose value is not a list'
        end

        [{ output: { attachments: rows.map { |row| helpers.attachment_summary(row) } } }]
      end
    end

    action 'a68d267e-7781-4758-b314-7ad76d97ad90' do
      name 'Download Attachment'
      avatar '/assets/icons/microsoft-outlook.svg'

      description <<~END_OF_DESCRIPTION
        Reads one attachment of one message and returns its bytes as base64 text, with the name and the media type Microsoft reports.

        Content bytes holds the same base64 text Microsoft sends, not the raw file. A step that takes a file needs the text decoded first, because a runbook carries every value as JSON and JSON cannot hold the bytes of a picture, a PDF or a zip.

        Only a file attachment carries bytes. A message attached to a message and a link to a cloud file hold none, so the step fails and says which kind it found.
      END_OF_DESCRIPTION

      input_schema do
        field :message_id, 'Message ID', :string,
              required: true,
              hint: 'The id of the message that holds the attachment, as returned by List Emails.'
        field :attachment_id, 'Attachment ID', :string,
              required: true,
              hint: 'The id of the attachment, as returned by List Attachments.'
        field :mailbox, 'Mailbox', :string,
              visibility: 'optional',
              hint: 'User principal name, object id or SMTP address. Empty uses the connection\'s Default mailbox.'
      end

      output_schema do
        field :name, 'Name', :string,
              hint: 'The file name Microsoft reports, such as report.pdf.'
        field :content_bytes, 'Content bytes', :base64,
              hint: 'The file as base64 text, exactly as Microsoft sends it. A step that takes a file ' \
                    'reads the raw bytes, so map this through Base64.decode64 before it.'
        field :content_type, 'Content type', :string,
              hint: 'The media type of the file, such as application/pdf.'
      end

      run do
        mailbox = helpers.mailbox_for(input[:mailbox])
        url = helpers.attachment_url(mailbox, input[:message_id], input[:attachment_id])

        summary = helpers.graph_get(url, { '$select': ATTACHMENT_SELECT.join(',') }, mailbox)

        kind = helpers.attachment_kind(summary)
        fail_job!("Attachment '#{summary['name']}' is #{kind} and carries no file.") if kind != FILE_ATTACHMENT_TYPE
        size = helpers.attachment_size(summary)
        if size > MAX_ATTACHMENT_BYTES
          fail_job!("Attachment '#{summary['name']}' is #{size} bytes, and this step reads at most " \
                    "#{MAX_ATTACHMENT_BYTES} bytes in one go.")
        end

        content = helpers.graph_get(url, { '$select': ATTACHMENT_CONTENT_SELECT.join(',') }, mailbox)

        [{ output: { name: content['name'], content_bytes: helpers.attachment_content(content),
                     content_type: content['contentType'], } }]
      end
    end

    action '08d4e767-e3f3-4783-a1f7-2bbc200fa24c' do
      name 'Move Email'
      avatar '/assets/icons/microsoft-outlook.svg'

      description <<~END_OF_DESCRIPTION
        Moves one or more messages into another folder of the same mailbox, through the [move message API](https://learn.microsoft.com/en-us/graph/api/message-move).

        Moving a message gives it a new id. The id that went in stops working, so a later step that reads the message uses the New message ID this action returns.

        Microsoft answers a move once per message, so one message can fail while the rest succeed. Every message id that went in comes back as its own row saying whether it moved, and the row carries Microsoft's own text when it did not. A repeated id is moved once and answered once.

        The message ids come from a List Emails step. Ids are never built by hand. At most 20 ids go in one step, because Microsoft refuses a bigger batch outright and then nothing moves.
      END_OF_DESCRIPTION

      input_schema do
        field :message_ids, 'Message IDs', :string,
              array: true,
              required: true,
              hint: 'The Message IDs an earlier step returned. Paste the raw ids, not ones copied ' \
                    'from a browser address bar. At most 20 ids in one step.'
        field :destination_folder, 'Destination folder', :string,
              required: true,
              hint: 'Well-known name (inbox, sentitems, archive, drafts, deleteditems, junkemail) or a folder id. ' \
                    'A display name such as Sent Items is not accepted, and a folder that does not exist fails ' \
                    "every row with Microsoft's 'Id is malformed'."
        field :mailbox, 'Mailbox', :string,
              visibility: 'optional',
              hint: 'User principal name, object id or SMTP address. Empty uses the connection\'s Default mailbox.'
      end

      output_schema do
        field :results, 'Results', :nested, array: true do
          field :message_id, 'Message ID', :string,
                required: true,
                hint: 'The message id that went in.'
          field :new_message_id, 'New message ID', :string,
                hint: 'The id the message has in its new folder. Empty when the move failed.'
          field :moved, 'Moved', :boolean,
                required: true,
                hint: 'True when Microsoft moved this message.'
          field :error, 'Error', :string,
                hint: 'The text Microsoft returned for this message. Empty when the move worked.'
        end
      end

      run do
        mailbox = helpers.mailbox_for(input[:mailbox])
        folder = helpers.folder_for(input[:destination_folder])
        message_ids = helpers.message_ids_for(input[:message_ids])

        [{ output: { results: helpers.move_messages(mailbox, message_ids, folder) } }]
      end
    end

    action 'adcaf794-39e7-4185-9432-4fb7de67fbf6' do
      name 'Archive Email'
      avatar '/assets/icons/microsoft-outlook.svg'

      description <<~END_OF_DESCRIPTION
        Moves one or more messages into the archive folder of the mailbox, through the same [move message API](https://learn.microsoft.com/en-us/graph/api/message-move) that Move Email uses.

        The destination is fixed to the well-known archive folder. That is the one-click Archive folder in the mailbox, not the separate online archive mailbox, which Microsoft does not reach the same way.

        Archiving a message gives it a new id, exactly as Move Email does. The id that went in stops working, so a later step that reads the message uses the New message ID this action returns.

        Microsoft answers a move once per message, so one message can fail while the rest succeed. Every message id that went in comes back as its own row saying whether it moved, and the row carries Microsoft's own text when it did not. A repeated id is moved once and answered once.

        The message ids come from a List Emails step. Ids are never built by hand. At most 20 ids go in one step, because Microsoft refuses a bigger batch outright and then nothing moves.
      END_OF_DESCRIPTION

      input_schema do
        field :message_ids, 'Message IDs', :string,
              array: true,
              required: true,
              hint: 'The Message IDs an earlier step returned. Paste the raw ids, not ones copied ' \
                    'from a browser address bar. At most 20 ids in one step.'
        field :mailbox, 'Mailbox', :string,
              visibility: 'optional',
              hint: 'User principal name, object id or SMTP address. Empty uses the connection\'s Default mailbox.'
      end

      output_schema do
        field :results, 'Results', :nested, array: true do
          field :message_id, 'Message ID', :string,
                required: true,
                hint: 'The message id that went in.'
          field :new_message_id, 'New message ID', :string,
                hint: 'The id the message has in the archive folder. Empty when the move failed.'
          field :moved, 'Moved', :boolean,
                required: true,
                hint: 'True when Microsoft moved this message.'
          field :error, 'Error', :string,
                hint: 'The text Microsoft returned for this message. Empty when the move worked.'
        end
      end

      run do
        mailbox = helpers.mailbox_for(input[:mailbox])
        message_ids = helpers.message_ids_for(input[:message_ids])

        [{ output: { results: helpers.move_messages(mailbox, message_ids, ARCHIVE_FOLDER) } }]
      end
    end

    action '01a10f63-a1f8-7eac-b111-e7ac03240ed8' do
      name 'Renew Subscriptions'
      avatar '/assets/icons/microsoft-outlook.svg'

      description <<~END_OF_DESCRIPTION
        Creates and keeps alive every Microsoft Graph subscription the triggers on this connection depend on, through the [subscription API](https://learn.microsoft.com/en-us/graph/api/resources/subscription).

        Microsoft ends a subscription after seven days unless it is renewed. Put this action in a runbook of its own, on a Scheduler trigger that runs every 15 minutes, and set that runbook's concurrency to one run at a time, so two runs never create the same subscription. Each run lists the subscriptions Microsoft holds for this application, deletes any that points at a trigger of this connection but is not recorded, creates the subscription of every recorded trigger that has none, and renews, in batches of 20, every subscription that ends within a day. So a trigger is watched within 15 minutes of its deploy, or of a change to its mailbox or folder, with no step by hand.

        A run with nothing to do ends quietly. A run in which a subscription could not be created or renewed fails after it has handled every other row, and its log names the trigger, what it watched and what Microsoft answered. The next run tries again. Use the Outlook connection the triggers use: a run on another connection finds nothing to keep alive. A Scheduler trigger keeps the recurrence it was first deployed with, so after changing it, deprovision and provision that trigger.
      END_OF_DESCRIPTION

      output_schema do
        field :results, 'Results', :nested, array: true do
          field :runbook_id, 'Runbook ID', :string,
                hint: 'The runbook whose trigger this subscription belongs to.'
          field :resource, 'Resource', :string,
                hint: 'What Microsoft watches for this subscription, as a Microsoft Graph resource path.'
          field :mailbox, 'Mailbox', :string,
                hint: 'The mailbox, for a subscription that watches one.'
          field :folder, 'Folder', :string,
                hint: 'The folder, for a subscription that watches one.'
          field :subscription_id, 'Subscription ID', :string
          field :expires_at, 'Expires at', :date_time
          field :outcome, 'Outcome', :string,
                required: true,
                hint: "'created' when the subscription was made, 'renewed' when Microsoft extended it, 'removed' " \
                      "when a subscription nobody recorded was deleted, 'skipped' when the trigger changed while " \
                      'Microsoft was answering.'
          field :error, 'Error', :string,
                hint: 'Why a skipped row was left alone. Empty otherwise.'
        end
        field :created, 'Created', :integer, required: true
        field :renewed, 'Renewed', :integer, required: true
        field :removed, 'Removed', :integer, required: true
      end

      run do
        if helpers.subscription_rows.empty?
          log(NOTHING_RECORDED)
          next [{ output: { created: 0, renewed: 0, removed: 0, results: [] } }]
        end

        held = helpers.held_subscriptions
        rows = helpers.without_shadowed_rows(helpers.subscription_rows)
        results = helpers.remove_unrecorded_subscriptions(rows, held)
        unsubscribed = rows.reject { |_key, row| helpers.held_id(row, held) }
        expiring = rows.select { |_key, row| helpers.held_id(row, held) && helpers.expiring_soon(row) }
        results += expiring.each_slice(BATCH_REQUEST_LIMIT).flat_map { |slice| helpers.renew_batch(slice) }
        results += unsubscribed.map { |key, row| helpers.create_for(key, row) }
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

    action '34857f77-8991-4c62-b02b-dd22c475b24f' do
      name 'Create Calendar Event'
      avatar '/assets/icons/microsoft-outlook.svg'

      description <<~END_OF_DESCRIPTION
        Creates one event in a calendar of a mailbox, through the [create event API](https://learn.microsoft.com/en-us/graph/api/user-post-events). Microsoft sends an invitation to every attendee.

        Start and End are the local date and time in the zone named in Time zone, such as 2026-12-01 08:00 in W. Europe Standard Time, never a time with an offset. Microsoft applies that zone's clock changes. A Start that does not exist in the zone, such as 02:30 on the night the clocks go forward, is moved later by Microsoft without an error, and Start and End in the output show the time it stored. When the moved Start falls after End, Microsoft refuses the event.

        A step that runs again creates a second event, unless it carries a Transaction ID. A second create with the same Transaction ID and the same values returns the event that exists, and one with different values fails. Map a value that is the same for one booking and different for the next, such as the delivery id of the webhook that asked for the booking.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              visibility: 'optional',
              hint: 'User principal name, object id or SMTP address of the mailbox that owns the calendar. Empty ' \
                    'uses the connection\'s Default mailbox.'
        field :calendar_id, 'Calendar ID', :string,
              visibility: 'optional',
              hint: 'The id of a calendar in the mailbox. Empty uses the default calendar of the mailbox.'
        field :subject, 'Subject', :string,
              required: true,
              hint: 'The title of the event.'
        field :start_time, 'Start', :string,
              required: true,
              hint: 'The local date and time the event starts, such as 2026-12-01 08:00, with no offset. Time zone ' \
                    "says where. Convert a time with an offset first, such as #{WALL_TIME_CONVERSION}. " \
                    "#{WALL_TIME_COLON_CAVEAT}"
        field :end_time, 'End', :string,
              required: true,
              hint: 'The local date and time the event ends, such as 2026-12-01 10:00. It may equal Start, and may ' \
                    "not be earlier. Convert a time with an offset first, such as #{WALL_TIME_CONVERSION}. " \
                    "#{WALL_TIME_COLON_CAVEAT}"
        field :time_zone, 'Time zone', :string,
              required: true,
              hint: 'The zone of Start and End, as a Windows name such as W. Europe Standard Time or an IANA name ' \
                    'such as Europe/Zurich.'
        field :body, 'Body', :string,
              visibility: 'optional',
              hint: 'The text of the event.'
        field :body_type, 'Body type', :string,
              visibility: 'optional',
              default: DEFAULT_BODY_TYPE,
              enumeration: BODY_TYPES,
              hint: 'text keeps the line breaks as typed. html reads the body as markup.'
        field :location, 'Location', :nested,
              visibility: 'optional',
              hint: 'Only the fields that hold a value are sent.' do
          field :display_name, 'Display name', :string
          field :street, 'Street', :string
          field :postal_code, 'Postal code', :string
          field :city, 'City', :string
        end
        field :attendees, 'Attendees', :string,
              array: true,
              visibility: 'optional',
              hint: 'The addresses that receive the invitation. Add one value per address.'
        field :reminder_minutes_before_start, 'Reminder minutes before start', :integer,
              visibility: 'optional',
              min: 0,
              hint: 'Turns the reminder on this many minutes before Start. Empty leaves it to Microsoft, which ' \
                    'turns a 15 minute reminder on.'
        field :transaction_id, 'Transaction ID', :string,
              visibility: 'optional',
              hint: 'A value that is the same for one booking and different for the next, such as a webhook ' \
                    'delivery id. A repeated create with it returns the existing event. Empty sends none.'
      end

      output_schema do
        field :event_id, 'Event ID', :string,
              required: true,
              hint: 'The id Delete Calendar Event takes.'
        field :web_link, 'Web link', :string,
              hint: 'Opens the event in Outlook on the web.'
        field :i_cal_uid, 'iCal UID', :string,
              hint: 'The id every calendar shares for this event, including the copies of the attendees.'
        field :subject, 'Subject', :string
        field :start_time, 'Start', :nested,
              hint: 'The start Microsoft stored, in the zone it was given.' do
          field :date_time, 'Date time', :string
          field :time_zone, 'Time zone', :string
        end
        field :end_time, 'End', :nested,
              hint: 'The end Microsoft stored, in the zone it was given.' do
          field :date_time, 'Date time', :string
          field :time_zone, 'Time zone', :string
        end
        field :organizer, 'Organizer', :nested do
          field :name, 'Name', :string
          field :address, 'Address', :string
        end
        field :attendees, 'Attendees', :nested, array: true do
          field :address, 'Address', :string
          field :name, 'Name', :string
          field :type, 'Type', :string
        end
        field :location, 'Location', :string,
              hint: 'The display name of the location.'
        field :is_reminder_on, 'Is reminder on', :boolean
        field :reminder_minutes_before_start, 'Reminder minutes before start', :integer
        field :created_date_time, 'Created date time', :date_time
        field :mailbox, 'Mailbox', :string,
              hint: 'The mailbox that owns the calendar.'
      end

      run do
        mailbox = helpers.mailbox_for(input[:mailbox])
        payload = helpers.event_payload(input)
        calendar_id = helpers.calendar_id_for(input[:calendar_id])

        response = http_post(helpers.events_url(mailbox, calendar_id), payload.to_json, JSON_HEADERS)
        # A rerun after a pause posts again, which only a Transaction ID makes safe: Microsoft then hands back
        # the event the first post created. Without one, a server error does not say no event was made.
        safe_statuses = payload[:transactionId].present? ? TRANSIENT_SERVER_ERROR_STATUSES : []
        backoff_if_needed(response, api_name: 'Microsoft', server_error_statuses: safe_statuses)
        if response.status != EVENT_CREATED_STATUS
          fail_job!(helpers.describe_event_failure(response, mailbox, payload, calendar_id))
        end

        event = helpers.parse_graph(response, mailbox, EVENT_CREATED_STATUS)
        [{ output: helpers.event_summary(event).merge(mailbox: mailbox) }]
      end
    end

    action '8ea14b2b-eaff-4350-9011-a0d5ad5b90f4' do
      name 'Delete Calendar Event'
      avatar '/assets/icons/microsoft-outlook.svg'

      description <<~END_OF_DESCRIPTION
        Deletes one event from the mailbox, through the [delete event API](https://learn.microsoft.com/en-us/graph/api/event-delete). When the mailbox organised the event, Microsoft sends a cancellation to the attendees.

        An event Microsoft does not find in the mailbox passes with Deleted false, so a cancel that arrives twice does not fail the second time. Deleted false says only that this mailbox held no such event when the step asked: an earlier delete removed it, an earlier try of this same step removed it before Microsoft answered with a server error, or the Event ID was never in this mailbox. An empty Event ID fails the step.
      END_OF_DESCRIPTION

      input_schema do
        field :event_id, 'Event ID', :string,
              required: true,
              hint: 'The Event ID that Create Calendar Event returned.'
        field :mailbox, 'Mailbox', :string,
              visibility: 'optional',
              hint: 'User principal name, object id or SMTP address of the mailbox that holds the event. Empty uses ' \
                    'the connection\'s Default mailbox.'
      end

      output_schema do
        field :deleted, 'Deleted', :boolean,
              required: true,
              hint: 'True when this step deleted the event. False when the mailbox held no event with this id ' \
                    'when the step asked: an earlier delete, or an earlier try of this step, removed it, or it ' \
                    'was never in this mailbox.'
        field :event_id, 'Event ID', :string
        field :mailbox, 'Mailbox', :string
      end

      run do
        mailbox = helpers.mailbox_for(input[:mailbox])
        event_id = helpers.event_id_for(input[:event_id])

        response = http_delete(helpers.event_url(mailbox, event_id))
        backoff_if_needed(response, api_name: 'Microsoft', server_error_statuses: TRANSIENT_SERVER_ERROR_STATUSES)
        deleted = response.status == EVENT_DELETED_STATUS
        gone = response.status == EVENT_GONE_STATUS && helpers.graph_error(response)['code'] == EVENT_GONE_CODE
        fail_job!(helpers.describe_calendar_refusal(response, mailbox)) unless deleted || gone

        [{ output: { deleted: deleted, event_id: event_id, mailbox: mailbox } }]
      end
    end

    helper :message_ids_for do |value|
      ids = Array(value).map { |message_id| message_id.to_s.strip }.reject(&:blank?).uniq
      fail_job!('No message ids to move. Map Message IDs to the Message ID an earlier step returned.') if ids.blank?
      if ids.length > BATCH_REQUEST_LIMIT
        fail_job!("#{ids.length} message ids were passed. Microsoft moves at most #{BATCH_REQUEST_LIMIT} messages " \
                  'in one request and refuses the whole batch above that, so nothing would move. Pass fewer.')
      end
      malformed = ids.detect { |message_id| !MESSAGE_ID_PATTERN.match?(message_id) }
      if malformed.present?
        fail_job!("Message id '#{malformed}' is not a Microsoft Graph message id. Map the Message ID an " \
                  'earlier step returned, not an id copied from a browser address bar.')
      end

      ids
    end

    helper :move_request_url do |mailbox, message_id|
      "#{helpers.user_path(mailbox)}/messages/" \
        "#{helpers.escape_segment(message_id)}#{MOVE_PATH_SUFFIX}"
    end

    helper :move_batch_body do |mailbox, message_ids, folder|
      requests = message_ids.each_with_index.map do |message_id, index|
        {
          id: index.to_s,
          method: 'POST',
          url: helpers.move_request_url(mailbox, message_id),
          headers: { CONTENT_TYPE_HEADER => JSON_CONTENT_TYPE },
          body: { destinationId: folder },
        }
      end

      { requests: requests }.to_json
    end

    helper :move_messages do |mailbox, message_ids, folder|
      response = http_post(helpers.graph_url(BATCH_PATH),
                           helpers.move_batch_body(mailbox, message_ids, folder),
                           { CONTENT_TYPE_HEADER => JSON_CONTENT_TYPE })
      # Only the batch itself is judged here. Microsoft answers a parseable batch 200 and reports every
      # message on its own row inside, so a row says what happened to that message and the runbook decides
      # what to do with it.
      backoff_if_needed(response, api_name: 'Microsoft')

      helpers.move_results(message_ids, helpers.parse_graph(response, mailbox))
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

    helper :move_results do |message_ids, body|
      by_id = helpers.batch_answers(body, message_ids.each_with_index.map { |_message_id, index| index.to_s })
      message_ids.each_with_index.map do |message_id, index|
        answer = by_id[index.to_s]
        moved = answer.present? && MOVE_SUCCESS_STATUSES.include?(answer['status'].to_i)
        new_message_id = moved ? answer.dig('body', 'id') : nil
        if moved && new_message_id.blank?
          raise IPaaS::Error, "Microsoft Graph moved message '#{message_id}' without naming its new id"
        end

        {
          message_id: message_id,
          new_message_id: new_message_id,
          moved: moved,
          error: moved ? nil : helpers.describe_batch_failure(answer),
        }
      end
    end

    helper :describe_batch_failure do |answer|
      if answer.blank?
        'Microsoft Graph returned no answer for this request.'
      else
        body = answer['body'].is_a?(Hash) ? answer['body'] : {}
        error = body['error'].is_a?(Hash) ? body['error'] : {}
        detail = error['message'].presence || 'no error details'
        "Microsoft Graph returned HTTP #{answer['status']} #{error['code']}: #{detail}"
      end
    end

    helper :cloud do
      name = outbound_connection.config[:cloud].presence || DEFAULT_CLOUD
      entry = CLOUDS[name]
      if entry.blank?
        fail_job!("Cloud '#{name}' is not one of #{CLOUDS.keys.join(', ')}. Open the connection and select a Cloud.")
      end
      raise IPaaS::Error, "cloud '#{name}' has no login host" if entry[:login].blank?
      raise IPaaS::Error, "cloud '#{name}' has no Graph host" if entry[:graph].blank?

      entry
    end

    helper :tenant_id do
      value = outbound_connection.config[:credentials][:tenant_id].to_s.strip
      fail_job!('Tenant ID is empty on the connection.') if value.blank?
      if TENANT_ALIASES.include?(value.downcase)
        fail_job!("Tenant ID '#{value}' is a sign-in placeholder. Use the directory (tenant) ID of your own tenant.")
      end

      value
    end

    helper :token_url do
      host = helpers.cloud[:login]
      "#{host}/#{helpers.tenant_id}#{TOKEN_PATH}"
    end

    helper :token_body do
      credentials = outbound_connection.config[:credentials]
      body = oauth2_client_credentials_body(credentials[:client_id],
                                            decrypt_secret_string(credentials[:client_secret]))
      body.merge(scope: "#{helpers.cloud[:graph]}#{TOKEN_SCOPE_SUFFIX}")
    end

    helper :graph_url do |path|
      raise IPaaS::Error, "graph path '#{path}' does not start with a slash" unless path.to_s.start_with?('/')

      "#{helpers.cloud[:graph]}/#{GRAPH_API_VERSION}#{path}"
    end

    helper :normalize_mailbox do |value, field_label = 'Mailbox'|
      mailbox = value.to_s.strip.sub(/\A#{MAILTO_PREFIX}/io, '').strip
      # Named after the field the builder filled in, because this helper reads the Mailbox field and
      # every To, Cc and Bcc address, and a message saying Mailbox sends them to the wrong field.
      if MAILBOX_ROUTING_CHARACTERS.match?(mailbox)
        fail_job!("#{field_label} '#{mailbox}' holds a slash, a backslash or a percent sign, which changes how " \
                  'Microsoft Graph reads the address. Microsoft answers a routing error that names neither the ' \
                  'value nor the problem. Use a user principal name, an object id or an SMTP address.')
      end

      mailbox
    end

    helper :mailbox_for do |value|
      mailbox = helpers.normalize_mailbox(value)
      mailbox = helpers.normalize_mailbox(outbound_connection.config[:default_mailbox]) if mailbox.blank?
      fail_job!('No mailbox. Set Mailbox on this step, or Default mailbox on the connection.') if mailbox.blank?

      mailbox
    end

    helper :folder_for do |value|
      folder = value.to_s.strip
      folder = DEFAULT_FOLDER if folder.blank?
      if folder.length > MAX_FOLDER_LENGTH
        fail_job!("Folder is #{folder.length} characters long. A folder id is about 120, so this is not one.")
      end
      unless FOLDER_PATTERN.match?(folder)
        fail_job!("Folder '#{folder}' is not a well-known name (inbox, sentitems, archive, drafts, deleteditems, " \
                  'junkemail) or a folder id. A display name such as Sent Items is not accepted.')
      end

      folder
    end

    helper :user_path do |mailbox|
      "/users/#{helpers.escape_segment(mailbox)}"
    end

    helper :escape_segment do |value|
      value.to_s.gsub('%', '%25').gsub('#', '%23').gsub('?', '%3F').gsub('/', '%2F').gsub(' ', '%20')
    end

    helper :messages_url do |mailbox, folder|
      helpers.graph_url("#{helpers.user_path(mailbox)}/mailFolders/" \
                        "#{helpers.escape_segment(folder)}/messages")
    end
    helper :folders_url do |mailbox|
      raise IPaaS::Error, 'folders_url was asked for an empty mailbox' if mailbox.to_s.strip.blank?

      helpers.graph_url("#{helpers.user_path(mailbox)}/mailFolders/delta")
    end

    helper :folder_page do |url, mailbox = nil|
      body = helpers.graph_get(url, nil, mailbox)
      unless body['value'].is_a?(Array)
        raise IPaaS::Error, 'Microsoft Graph returned a folder page whose value is not a list'
      end

      body
    end

    helper :folder_rows do |mailbox|
      url = helpers.folders_url(mailbox)
      rows = (0...MAX_FOLDER_REQUESTS).each_with_object([]) do |_, collected|
        body = helpers.folder_page(url, mailbox)
        body['value'].each { |row| collected.push(row) }
        url = helpers.next_page_link(body)
        break collected if url.blank?
      end
      if url.present?
        fail_job!("This mailbox holds more folders than the list reads in #{MAX_FOLDER_REQUESTS} requests, " \
                  'and a list that stops part-way would hide the rest. Type the folder id into Folder ' \
                  'instead of picking it from the list.')
      end

      rows
    end

    helper :folder_option_id do |row|
      identifier = row['wellKnownName'].presence || row['id'].to_s
      raise IPaaS::Error, 'Microsoft Graph returned a folder with no id' if identifier.blank?

      unless identifier.length <= MAX_FOLDER_LENGTH && FOLDER_PATTERN.match?(identifier)
        raise IPaaS::Error, "the folder list built the id '#{identifier}', which the Folder field refuses"
      end

      identifier
    end

    helper :folder_label do |row, rows_by_id|
      names = []
      current = row
      (0..MAX_FOLDER_DEPTH).each do
        names.push(current['displayName'].to_s)
        current = rows_by_id[current['parentFolderId'].to_s]
        break if current.blank?
      end
      if current.present?
        raise IPaaS::Error, "folder '#{row['id']}' sits under more than #{MAX_FOLDER_DEPTH} parents, " \
                            'so its chain of parents never reaches the top of the mailbox'
      end

      names.reverse.join(FOLDER_PATH_SEPARATOR)
    end

    helper :folder_options_from do |rows|
      rows_by_id = rows.index_by { |row| row['id'].to_s }
      options = rows.map do |row|
        { id: helpers.folder_option_id(row), label: helpers.folder_label(row, rows_by_id) }
      end
      identifiers = options.map { |option| option[:id] }
      raise IPaaS::Error, 'the folder list offers the same id twice' if identifiers.uniq.length != identifiers.length

      options
    end

    helper :fetch_folder_options do |mailbox: nil|
      address = helpers.mailbox_for(mailbox)
      options = helpers.folder_options_from(helpers.folder_rows(address))
      raise IPaaS::Error, "Microsoft Graph returned no folders at all for mailbox '#{address}'" if options.none?

      options
    end

    helper :attachments_url do |mailbox, message_id|
      helpers.graph_url("#{helpers.user_path(mailbox)}/messages/" \
                        "#{helpers.escape_segment(message_id)}/attachments")
    end

    helper :attachment_url do |mailbox, message_id, attachment_id|
      "#{helpers.attachments_url(mailbox, message_id)}/#{helpers.escape_segment(attachment_id)}"
    end

    helper :attachment_summary do |attachment|
      raise IPaaS::Error, 'Microsoft Graph returned an attachment with no id' if attachment['id'].blank?

      {
        attachment_id: attachment['id'],
        name: attachment['name'],
        content_type: attachment['contentType'],
        size_in_bytes: helpers.attachment_size(attachment),
        is_inline: attachment['isInline'],
      }
    end

    helper :attachment_size do |attachment|
      size = attachment['size']
      unless size.is_a?(Integer)
        raise IPaaS::Error, "Microsoft Graph returned attachment '#{attachment['id']}' with a size of " \
                            "'#{size}', which is not a whole number of bytes"
      end

      size
    end

    helper :attachment_kind do |attachment|
      kind = attachment['@odata.type'].to_s
      if kind.blank?
        raise IPaaS::Error, "Microsoft Graph returned attachment '#{attachment['id']}' with no '@odata.type', " \
                            'so there is nothing to tell a file from a message or a link'
      end

      kind
    end

    helper :attachment_content do |attachment|
      content = attachment['contentBytes']
      unless content.is_a?(String)
        raise IPaaS::Error, "Microsoft Graph returned attachment '#{attachment['id']}' with no contentBytes, " \
                            'although the select asked for them through the file attachment type'
      end

      # Handed back as the base64 text Microsoft sent, never decoded. Every action output is stored as
      # JSON, and JSON cannot hold bytes that are not text, so decoding here ends a run with
      # JSON::GeneratorError on a picture, a PDF or a zip.
      content
    end

    helper :graph_get do |url, params = nil, mailbox = nil|
      response = http_get(url, params)
      backoff_if_needed(response, api_name: 'Microsoft')
      helpers.parse_graph(response, mailbox)
    end

    helper :parse_graph do |response, mailbox = nil, expected_status = 200|
      fail_job!(helpers.describe_graph_failure(response, mailbox)) if response.status != expected_status

      body = parse_json_response(response.body,
                                 error_message: 'Microsoft Graph returned a response that is not JSON: ' \
                                                "'#{response.body}'")
      raise IPaaS::Error, 'Microsoft Graph returned a value that is not an object' unless body.is_a?(Hash)

      body
    end

    helper :position do |next_link, mailbox, folder|
      { next_link: next_link, mailbox: mailbox, folder: folder, graph_host: helpers.cloud[:graph] }
    end

    helper :resumable_link do |mailbox, folder|
      stored = helpers.iteration_link
      was = [iteration_state_value(:mailbox), iteration_state_value(:folder),
             iteration_state_value(:graph_host),]
      if stored.present? && was.compact.present? && was != [mailbox, folder, helpers.cloud[:graph]]
        fail_job!('The connection changed while this step was part-way through a mailbox. The pages so ' \
                  "far came from mailbox '#{was[0]}', folder '#{was[1]}', host '#{was[2]}'. Run the " \
                  'step again from the first page.')
      end

      stored
    end

    helper :iteration_link do
      iteration_state_value(:next_link).to_s
    end

    # An integer field that a step leaves unmapped arrives as nil, and one mapped to an empty value arrives as
    # the empty string, because only a value that parses as a number is converted. Both mean "use the default".
    helper :integer_or_default do |value, default|
      number = value.to_s.strip
      number.blank? ? default : number.to_i
    end

    helper :message_summary do |message|
      raise IPaaS::Error, 'Microsoft Graph returned a message with no id' if message['id'].blank?

      from = message.dig('from', 'emailAddress') || {}
      {
        message_id: message['id'],
        subject: message['subject'],
        from: { name: from['name'], address: from['address'] },
        received_date_time: message['receivedDateTime'],
        has_attachments: message['hasAttachments'],
        is_read: message['isRead'],
        importance: message['importance'],
        body_preview: message['bodyPreview'],
      }
    end

    helper :graph_error do |response|
      error = parse_json_object_or_empty(response.body.to_s)['error']
      error.is_a?(Hash) ? error : {}
    end

    helper :describe_graph_failure do |response, mailbox = nil|
      raw = response.body.to_s
      error = helpers.graph_error(response)
      detail = error['message'].presence || raw.presence || 'no response body'
      # Named only on the two statuses that mean the caller was refused, because those are the ones
      # where the mailbox is the thing to go and look at. A 400 on a malformed folder or a 404 on a
      # missing message would name a mailbox that is working, and send the reader to the wrong field.
      refused = MAILBOX_REFUSED_STATUSES.include?(response.status) && mailbox.present?
      place = refused ? " while reading mailbox '#{mailbox}'" : ''
      "Microsoft Graph returned HTTP #{response.status} #{error['code']}#{place}: #{detail}"
    end

    helper :search_folder_for do |value|
      folder = value.to_s.strip
      folder.blank? ? '' : helpers.folder_for(folder)
    end

    helper :search_messages_url do |mailbox, folder|
      raise IPaaS::Error, 'a Search Emails URL was built without a mailbox' if mailbox.to_s.strip.blank?

      if folder.to_s.strip.blank?
        helpers.graph_url("#{helpers.user_path(mailbox)}/messages")
      else
        helpers.messages_url(mailbox, folder)
      end
    end

    helper :odata_literal do |value|
      "#{ODATA_QUOTE}#{value.to_s.gsub(ODATA_QUOTE, ODATA_ESCAPED_QUOTE)}#{ODATA_QUOTE}"
    end

    helper :odata_time do |value|
      raise IPaaS::Error, 'a Search Emails date clause was built from an empty moment' if value.blank?

      Time.parse(value.to_s).utc.strftime(SEARCH_DATE_FORMAT)
    end

    helper :search_query do |value|
      text = value.to_s.strip
      if text.include?(SEARCH_QUOTE)
        fail_job!('Search text holds a double quote ("). Microsoft Graph refuses a search that carries one, ' \
                  'and a double quote cannot be escaped inside a search, so search for the words without it.')
      end

      text.blank? ? '' : "#{SEARCH_QUOTE}#{text}#{SEARCH_QUOTE}"
    end

    helper :search_select do |to_address|
      fields = MESSAGE_SELECT
      fields += [TO_RECIPIENTS_FIELD] if to_address.to_s.strip.present?
      fields.join(',')
    end

    helper :matches_to_address do |message, value|
      wanted = value.to_s.strip.downcase
      if wanted.present? && !message.key?(TO_RECIPIENTS_FIELD)
        raise IPaaS::Error, 'a To address match was asked for on a message that carries no toRecipients: the ' \
                            'request did not select the field, so every message would be dropped in silence'
      end

      addressed = (message[TO_RECIPIENTS_FIELD] || []).map do |recipient|
        recipient.dig('emailAddress', 'address').to_s.downcase
      end
      wanted.blank? || addressed.include?(wanted)
    end

    helper :search_filter do |criteria|
      clauses = []
      from = criteria[:from_address].to_s.strip
      clauses << "from/emailAddress/address eq #{helpers.odata_literal(from)}" if from.present?
      subject = criteria[:subject_contains].to_s.strip
      clauses << "contains(subject,#{helpers.odata_literal(subject)})" if subject.present?
      after = criteria[:received_after]
      clauses << "receivedDateTime ge #{helpers.odata_time(after)}" if after.present?
      before = criteria[:received_before]
      clauses << "receivedDateTime le #{helpers.odata_time(before)}" if before.present?
      attachments = criteria[:has_attachments].to_s.strip
      clauses << "hasAttachments eq #{attachments.downcase == 'true'}" if attachments.present?
      unread = criteria[:is_unread].to_s.strip
      clauses << "isRead eq #{unread.downcase != 'true'}" if unread.present?

      clauses.join(SEARCH_FILTER_JOIN)
    end

    helper :search_params do |query, filter, rules|
      params = { '$select': rules[:select], '$top': rules[:page_size].to_s }
      params[:$search] = query if query.present?
      params[:$filter] = filter if filter.present?
      if params.key?(:$search) && params.key?(:$filter)
        raise IPaaS::Error, 'Microsoft Graph answers HTTP 400 SearchWithFilter when $search and $filter travel ' \
                            'together, so one request carries one of them, never both'
      end

      params
    end

    helper :next_page_link do |body|
      link = body['@odata.nextLink'].to_s
      host = helpers.cloud[:graph]
      if link.present? && !link.start_with?("#{host}/")
        raise IPaaS::Error, "Microsoft Graph answered with a next page link that is not on #{host}: '#{link}'"
      end

      link
    end

    # Two calls, because Graph carries only one of these at a time. Verified against the live API,
    # since the docs do not say so: $search with $filter answers 'SearchWithFilter', and $search with
    # $orderby answers 'SearchWithOrderBy'. The two answers are intersected on message id.
    helper :search_messages do |url, text, filter, rules|
      if text.present? && filter.present?
        helpers.intersect_search_and_filter(url, text, filter, rules)
      else
        helpers.read_search_pages(url, helpers.search_params(text, filter, rules), MAX_SEARCH_REQUESTS, rules)
      end
    end

    helper :intersect_search_and_filter do |url, text, filter, rules|
      searched = helpers.read_search_pages(url, helpers.search_params(text, '', rules), MAX_SEARCH_REQUESTS,
                                           rules.except(:limit))
      ids = searched[:messages].map { |message| message['id'] }
      if ids.empty?
        { messages: [], left_unread: searched[:left_unread] }
      else
        matched = helpers.read_search_pages(url, helpers.search_params('', filter, rules),
                                            MAX_SEARCH_REQUESTS - searched[:requests], rules.merge(ids: ids))
        { messages: matched[:messages], left_unread: searched[:left_unread] || matched[:left_unread] }
      end
    end

    helper :read_search_pages do |url, params, budget, rules|
      messages = []
      requests = 0
      link = ''
      found_every_id = false
      limit = rules[:limit]
      ids = rules[:ids]
      to_address = rules[:to_address]
      mailbox = rules[:mailbox]

      while requests < budget
        body = link.present? ? helpers.graph_get(link, nil, mailbox) : helpers.graph_get(url, params, mailbox)
        page = body['value'] || []
        raise IPaaS::Error, 'Microsoft Graph returned a page whose value is not a list' unless page.is_a?(Array)

        kept = page.select do |message|
          (ids.nil? || ids.include?(message['id'])) && helpers.matches_to_address(message, to_address)
        end
        messages = (messages + kept).uniq { |message| message['id'] }
        requests += 1
        link = helpers.next_page_link(body)
        found_every_id = ids.present? && (ids - messages.map { |message| message['id'] }).empty?
        break if found_every_id || link.blank? || (limit.present? && messages.length > limit)
      end

      { messages: messages, requests: requests,
        left_unread: !found_every_id && (link.present? || budget < 1), }
    end

    helper :send_mail_url do |mailbox|
      raise IPaaS::Error, 'send mail URL was built without a mailbox' if mailbox.blank?

      helpers.graph_url("#{helpers.user_path(mailbox)}#{SEND_MAIL_PATH}")
    end

    helper :recipients_for do |values, field_label|
      values.to_a.map do |value|
        address = helpers.normalize_mailbox(value, field_label)
        if address.blank?
          fail_job!("#{field_label} holds an empty address. Remove the empty value, or map an address into it.")
        end
        unless RECIPIENT_PATTERN.match?(address)
          fail_job!("#{field_label} holds '#{address}', which is not an email address. Write the address on " \
                    'its own, without a display name around it.')
        end

        { emailAddress: { address: address } }
      end
    end

    # An optional field that a step leaves unmapped arrives as nil, so the default on the schema is what the
    # designer shows rather than what the run block receives.
    helper :body_type_for do |value|
      value.presence || DEFAULT_BODY_TYPE
    end

    helper :send_mail_payload do |fields|
      {
        message: {
          subject: fields[:subject],
          body: { contentType: helpers.body_type_for(fields[:body_type]), content: fields[:body] },
          toRecipients: helpers.recipients_for(fields[:to_recipients], 'To'),
          ccRecipients: helpers.recipients_for(fields[:cc_recipients], 'Cc'),
          bccRecipients: helpers.recipients_for(fields[:bcc_recipients], 'Bcc'),
        },
        saveToSentItems: SAVE_TO_SENT_ITEMS,
      }
    end

    helper :addresses_of do |recipients|
      recipients.map { |recipient| recipient[:emailAddress][:address] }
    end

    helper :calendar_id_for do |value|
      calendar_id = value.to_s.strip
      next '' if calendar_id.blank?

      unless calendar_id.length <= MAX_GRAPH_ID_LENGTH && MESSAGE_ID_PATTERN.match?(calendar_id)
        fail_job!("Calendar ID '#{calendar_id}' is not a Microsoft Graph calendar id. Map the id of a calendar in " \
                  'the mailbox, or leave Calendar ID empty to use its default calendar.')
      end

      calendar_id
    end

    helper :events_url do |mailbox, calendar_id|
      path = if calendar_id.blank?
               EVENTS_PATH
             else
               "#{CALENDARS_PATH}/#{helpers.escape_segment(calendar_id)}#{EVENTS_PATH}"
             end
      helpers.graph_url("#{helpers.user_path(mailbox)}#{path}")
    end

    helper :event_id_for do |value|
      event_id = value.to_s.strip
      unless event_id.length <= MAX_GRAPH_ID_LENGTH && MESSAGE_ID_PATTERN.match?(event_id)
        fail_job!("Event ID '#{event_id}' is not a Microsoft Graph event id. Map the Event ID an earlier step " \
                  'returned, not one copied from a browser address bar.')
      end

      event_id
    end

    helper :event_url do |mailbox, event_id|
      helpers.graph_url("#{helpers.user_path(mailbox)}#{EVENTS_PATH}/#{helpers.escape_segment(event_id)}")
    end

    helper :wall_time_for do |value, field_label|
      text = value.to_s.strip
      parts = WALL_TIME_PATTERN.match(text)
      if parts.nil?
        fail_job!("#{field_label} '#{text}' is not a local date and time such as 2026-12-01 08:00. Convert a time " \
                  "with an offset or Z first, such as #{WALL_TIME_CONVERSION}, and name the same zone in Time zone. " \
                  "#{WALL_TIME_COLON_CAVEAT}")
      end

      date, hour, minute, second = parts.captures
      begin
        Date.parse(date)
      rescue ArgumentError
        fail_job!("#{field_label} '#{text}' names a day the calendar does not have.")
      end

      "#{date}T#{hour.rjust(2, '0')}:#{minute}:#{second || '00'}"
    end

    helper :event_location do |place|
      fields = place || {}
      address = { street: fields[:street], postalCode: fields[:postal_code], city: fields[:city] }.compact_blank
      { displayName: fields[:display_name], address: address }.compact_blank.presence
    end

    helper :event_attendees do |addresses|
      helpers.recipients_for(addresses, 'Attendees').map { |attendee| attendee.merge(type: ATTENDEE_TYPE) }
    end

    helper :event_payload do |fields|
      zone = fields[:time_zone].to_s.strip
      starts = helpers.wall_time_for(fields[:start_time], 'Start')
      ends = helpers.wall_time_for(fields[:end_time], 'End')
      if ends < starts
        fail_job!("End '#{fields[:end_time]}' is earlier than Start '#{fields[:start_time]}'. An event that runs " \
                  'past midnight needs the date of the next day in End.')
      end

      reminder = helpers.integer_or_default(fields[:reminder_minutes_before_start], nil)
      body_type = helpers.body_type_for(fields[:body_type])
      body = { contentType: body_type, content: fields[:body] } if fields[:body].present?
      {
        subject: fields[:subject],
        body: body,
        start: { dateTime: starts, timeZone: zone },
        end: { dateTime: ends, timeZone: zone },
        location: helpers.event_location(fields[:location]),
        attendees: helpers.event_attendees(fields[:attendees]).presence,
        isReminderOn: reminder.nil? ? nil : true,
        reminderMinutesBeforeStart: reminder,
        transactionId: fields[:transaction_id].to_s.strip.presence,
      }.compact
    end

    helper :describe_calendar_refusal do |response, mailbox|
      text = helpers.describe_graph_failure(response)
      next text unless MAILBOX_REFUSED_STATUSES.include?(response.status)

      "#{text} Microsoft refused mailbox '#{mailbox}'. #{CALENDAR_PERMISSION_HINT}"
    end

    helper :describe_event_failure do |response, mailbox, payload, calendar_id|
      code = helpers.graph_error(response)['code']
      start = payload[:start]
      if code == DUPLICATE_TRANSACTION_CODE
        "Transaction ID '#{payload[:transactionId]}' already created an event in mailbox '#{mailbox}' with other " \
          'values, so Microsoft refused a second one. Map a Transaction ID that changes from one booking to the next.'
      elsif code == UNKNOWN_TIME_ZONE_CODE
        "Microsoft does not know the time zone '#{start[:timeZone]}'. Use a Windows name such as W. Europe " \
          'Standard Time or an IANA name such as Europe/Zurich.'
      elsif code == REFUSED_PROPERTY_CODE
        "Microsoft refused the event from #{start[:dateTime]} to #{payload[:end][:dateTime]} in #{start[:timeZone]}. " \
          'A Start in the hour the clocks skip forward is moved later, and the event is refused when that ' \
          'puts Start after End.'
      elsif code == EVENT_GONE_CODE && calendar_id.present?
        "Mailbox '#{mailbox}' has no calendar '#{calendar_id}'. Map the id of a calendar in this mailbox, or leave " \
          'Calendar ID empty to use its default calendar.'
      elsif payload[:transactionId].blank? && TRANSIENT_SERVER_ERROR_STATUSES.include?(response.status)
        "#{helpers.describe_graph_failure(response)} #{EVENT_MAY_EXIST_HINT}"
      else
        helpers.describe_calendar_refusal(response, mailbox)
      end
    end

    helper :event_time do |value|
      time = value.to_h
      { date_time: time['dateTime'], time_zone: time['timeZone'] }
    end

    helper :attendee_summary do |attendee|
      email_address = attendee['emailAddress'] || {}
      { address: email_address['address'], name: email_address['name'], type: attendee['type'] }
    end

    helper :event_summary do |event|
      raise IPaaS::Error, 'Microsoft Graph created an event without naming its id' if event['id'].blank?

      organizer = event.dig('organizer', 'emailAddress') || {}
      {
        event_id: event['id'],
        web_link: event['webLink'],
        i_cal_uid: event['iCalUId'],
        subject: event['subject'],
        start_time: helpers.event_time(event['start']),
        end_time: helpers.event_time(event['end']),
        organizer: { name: organizer['name'], address: organizer['address'] },
        attendees: (event['attendees'] || []).map { |attendee| helpers.attendee_summary(attendee) },
        location: event.dig('location', 'displayName'),
        is_reminder_on: event['isReminderOn'],
        reminder_minutes_before_start: event['reminderMinutesBeforeStart'],
        created_date_time: event['createdDateTime'],
      }
    end

    helper :url_postfix_set do
      !trigger.config[:url_postfix].nil?
    end

    helper :subscription_resource do |mailbox, folder|
      address = helpers.normalize_mailbox(mailbox)
      fail_job!('New Email Received has no mailbox to watch. Open the trigger and name one.') if address.blank?

      "users/#{helpers.escape_segment(address)}/mailFolders/" \
        "#{helpers.escape_segment(helpers.folder_for(folder))}/messages"
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
      rows = helpers.subscription_rows
      rows[trigger.runbook.uuid] || rows[trigger.endpoint] || {}
    end

    helper :store_own_row do |watch|
      rows = helpers.subscription_rows
      moved = rows.delete(trigger.endpoint)
      current = rows.delete(trigger.runbook.uuid)
      kept = current || moved || {}
      same_watch = watch.present? && kept['resource'] == watch['resource'] &&
                   kept.fetch('endpoint', watch['endpoint']) == watch['endpoint']
      row = same_watch ? kept.merge(watch) : watch
      next if moved.nil? && current == row

      rows[trigger.runbook.uuid] = row if row
      helpers.write_subscription_rows(rows)
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

    helper :created_subscription do |response|
      unless SUBSCRIPTION_CREATED_STATUSES.include?(response.status)
        fail_job!("Microsoft did not create the subscription. #{helpers.describe_graph_failure(response)} " \
                  'Microsoft checks that it can reach the trigger before it checks anything else, so it reports an ' \
                  'iPaaS it cannot reach, a runbook that is not deployed and a wrong mailbox or folder alike.')
      end
      body = parse_json_response(response.body.to_s,
                                 error_message: 'Microsoft Graph returned a subscription that is not JSON: ' \
                                                "'#{response.body}'")
      unless body.is_a?(Hash) && SUBSCRIPTION_ID_PATTERN.match?(body['id'].to_s)
        fail_job!('Microsoft Graph created a subscription with no subscription id. The next run removes it.')
      end

      body
    end

    helper :subscription_expiry do
      (MAX_SUBSCRIPTION_LIFETIME_MINUTES - CLOCK_SKEW_MARGIN_MINUTES).minutes.from_now.utc.iso8601
    end

    helper :create_subscription do |endpoint, resource|
      fail_job!('This subscription records nothing to watch. Deploy the trigger again.') if resource.blank?

      client_state = SecureRandom.uuid
      expiry = helpers.subscription_expiry
      response = http_post(helpers.graph_url(SUBSCRIPTION_PATH),
                           {
                             changeType: SUBSCRIPTION_CHANGE_TYPE,
                             notificationUrl: endpoint,
                             resource: resource,
                             clientState: client_state,
                             expirationDateTime: expiry,
                           }.to_json,
                           JSON_HEADERS)
      backoff_if_needed(response, api_name: 'Microsoft', server_error_statuses: TRANSIENT_SERVER_ERROR_STATUSES)
      subscription = helpers.created_subscription(response)
      { 'id' => subscription['id'], 'client_state' => make_secret_string(client_state).to_s,
        'expires_at' => subscription['expirationDateTime'].presence || expiry, }
    end

    helper :held_subscriptions do
      by_id = {}
      url = helpers.graph_url(SUBSCRIPTION_PATH)
      MAX_SUBSCRIPTION_LIST_REQUESTS.times do
        body = helpers.graph_get(url)
        page = body['value']
        # rubocop:disable-next Style/PredicateWithKind, Performance/RedundantEqualityComparisonBlock
        unless page.is_a?(Array) && page.all? { |subscription| subscription.is_a?(Hash) }
          raise IPaaS::Error, 'Microsoft Graph returned a subscription list that is not a list of subscriptions.'
        end

        page.each { |subscription| by_id[subscription['id'].to_s] = subscription }
        url = helpers.next_page_link(body)
        break if url.blank?
      end
      if url.present?
        log("Microsoft holds more subscriptions than #{MAX_SUBSCRIPTION_LIST_REQUESTS} pages list, so this run " \
            'trusts every stored subscription id.')
      end

      { 'by_id' => by_id, 'complete' => url.blank? }
    rescue IPaaS::Job::Outbound::CustomerCredentialsError, IPaaS::Job::RescheduleJob
      raise
    rescue IPaaS::Error => e
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

    helper :without_shadowed_rows do |rows|
      addresses = rows.reject { |key, _row| key.start_with?(ADDRESS_KEY_PREFIX) }.values.map { |row| row['endpoint'] }
      rows.reject { |key, _row| key.start_with?(ADDRESS_KEY_PREFIX) && addresses.include?(key) }
    end

    helper :runbook_id_for do |key|
      key.to_s.start_with?(ADDRESS_KEY_PREFIX) ? key.to_s.split('/').last : key
    end

    helper :remove_unrecorded_subscriptions do |rows, held|
      keys_by_endpoint = rows.to_h { |key, row| [row['endpoint'] || key, key] }
      known = rows.values.map { |row| helpers.stored_subscription_id(row) }
      held['by_id'].values.filter_map do |subscription|
        key = keys_by_endpoint[subscription['notificationUrl']]
        id = helpers.stored_subscription_id(subscription)
        next if key.nil? || id.nil? || known.include?(id)

        recorded = helpers.without_shadowed_rows(helpers.subscription_rows).values.map do |row|
          helpers.stored_subscription_id(row)
        end
        next if recorded.include?(id)

        row = { 'resource' => subscription['resource'], 'id' => id, 'expires_at' => subscription['expirationDateTime'] }
        row = rows[key].slice('mailbox', 'folder').merge(row) if subscription['resource'] == rows[key]['resource']
        helpers.delete_subscription(row)
        helpers.result(key, row, OUTCOME_REMOVED, nil)
      rescue IPaaS::Job::Outbound::CustomerCredentialsError
        raise
      rescue IPaaS::Job::FailJob => e
        helpers.result(key, row, OUTCOME_FAILED, e.message)
      end
    end

    helper :create_for do |key, row|
      created = row.merge(helpers.create_subscription(row['endpoint'] || key, row['resource']))
      next helpers.result(key, created, OUTCOME_CREATED, nil) if helpers.store_result(key, row, created)

      helpers.delete_subscription(created)
      helpers.result(key, row, OUTCOME_SKIPPED, ROW_CHANGED_WHILE_ANSWERING)
    rescue IPaaS::Job::Outbound::CustomerCredentialsError
      raise
    rescue IPaaS::Job::FailJob => e
      helpers.result(key, row, OUTCOME_FAILED, e.message)
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
      answers = helpers.batch_answers(helpers.parse_graph(response), requests.pluck(:id))
      slice.each_with_index.map do |pair, index|
        key, row = pair
        helpers.renewal_result(key, row, answers[index.to_s], expiry)
      end
    rescue IPaaS::Job::Outbound::CustomerCredentialsError, IPaaS::Job::RescheduleJob
      raise
    rescue IPaaS::Error => e
      slice.map { |pair| helpers.result(pair.first, pair.last, OUTCOME_FAILED, e.message) }
    end

    helper :renewal_result do |key, row, answer, expiry|
      status = answer.is_a?(Hash) ? answer['status'].to_s.to_i : 0
      next helpers.create_for(key, row) if SUBSCRIPTION_GONE_STATUSES.include?(status)
      unless status == SUBSCRIPTION_RENEWED_STATUS
        next helpers.result(key, row, OUTCOME_FAILED, helpers.describe_batch_failure(answer))
      end

      body = answer['body'].is_a?(Hash) ? answer['body'] : {}
      renewed = row.merge('expires_at' => body['expirationDateTime'].presence || expiry)
      next helpers.result(key, renewed, OUTCOME_RENEWED, nil) if helpers.store_result(key, row, renewed)

      helpers.result(key, row, OUTCOME_SKIPPED, ROW_CHANGED_WHILE_ANSWERING)
    end

    helper :store_result do |key, before, after|
      rows = helpers.subscription_rows
      current = rows[key]
      unchanged = rows.key?(key) && current['resource'] == before['resource'] &&
                  current['endpoint'] == before['endpoint'] &&
                  helpers.stored_subscription_id(current) == helpers.stored_subscription_id(before)
      next false unless unchanged

      helpers.write_subscription_rows(rows.merge(key => after))
      true
    end

    helper :result do |key, row, outcome, error|
      { runbook_id: helpers.runbook_id_for(key), resource: row['resource'], mailbox: row['mailbox'],
        folder: row['folder'], subscription_id: row['id'], expires_at: row['expires_at'].presence,
        outcome: outcome, error: error, }
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

    # One unsigned notification in the batch makes the whole request untrusted, so every notification
    # is checked rather than the first.
    helper :trusted_notifications do |batch, client_state|
      expected = client_state.to_s
      unless expected.present? && batch.all? { |item| OpenSSL.secure_compare(item['clientState'].to_s, expected) }
        discard_trigger_event!('A notification carried a client state this trigger did not set')
      end

      batch
    end

    helper :notification_message_id do |notification|
      resource_data = notification.is_a?(Hash) ? notification['resourceData'] : nil
      message_id = resource_data.is_a?(Hash) ? resource_data['id'] : nil
      raise IPaaS::Error, 'Microsoft Graph sent a change notification with no message id' if message_id.blank?

      message_id
    end

    helper :stored_subscription_id do |row|
      stored = row.is_a?(Hash) ? row : {}
      id = stored['id'].to_s.strip
      SUBSCRIPTION_ID_PATTERN.match?(id) ? id : nil
    end

    helper :delete_subscription do |row|
      id = helpers.stored_subscription_id(row)
      if id.present?
        response = http_delete(helpers.graph_url("#{SUBSCRIPTION_PATH}/#{id}"))
        backoff_if_needed(response, api_name: 'Microsoft')
        deleted = response.status == SUBSCRIPTION_DELETED_STATUS
        gone = SUBSCRIPTION_GONE_STATUSES.include?(response.status)
        fail_job!(helpers.describe_graph_failure(response)) unless deleted || gone
      end

      id
    end
  end
end
