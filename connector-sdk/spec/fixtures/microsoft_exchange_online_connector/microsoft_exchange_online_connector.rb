class MicrosoftExchangeOnlineConnector < IPaaS::Connector::Definition
  # One entry per Microsoft cloud. The Exchange host is both the resource the token is requested for and the
  # environment the runner connects to; the two must name the same cloud or Exchange refuses the token.
  CLOUDS = {
    'Global' => {
      login: 'https://login.microsoftonline.com',
      graph: 'https://graph.microsoft.com',
      exchange: 'https://outlook.office365.com',
      exchange_environment: 'O365Default',
    }.freeze,
    'US Government GCC High' => {
      login: 'https://login.microsoftonline.us',
      graph: 'https://graph.microsoft.us',
      exchange: 'https://outlook.office365.us',
      exchange_environment: 'O365USGovGCCHigh',
    }.freeze,
    'US Government DoD' => {
      login: 'https://login.microsoftonline.us',
      graph: 'https://dod-graph.microsoft.us',
      exchange: 'https://webmail.apps.mil',
      exchange_environment: 'O365USGovDoD',
    }.freeze,
    'China' => {
      login: 'https://login.chinacloudapi.cn',
      graph: 'https://microsoftgraph.chinacloudapi.cn',
      exchange: 'https://partner.outlook.cn',
      exchange_environment: 'O365China',
    }.freeze,
  }.freeze
  DEFAULT_CLOUD = 'Global'.freeze

  TOKEN_PATH         = '/oauth2/v2.0/token'.freeze
  TOKEN_SCOPE_SUFFIX = '/.default'.freeze
  BEARER_PREFIX      = /\ABearer\s+/i
  TENANT_ALIASES     = %w[common organizations consumers].freeze
  GRAPH_API_VERSION  = 'v1.0'.freeze
  JSON_HEADERS       = { 'Content-Type' => 'application/json' }.freeze

  RUNNER_PATH         = '/v1/cmdlets'.freeze
  RUNNER_OPEN_TIMEOUT = 5
  # Exchange cmdlets answer in seconds, and connecting a session for a tenant the runner has not seen yet
  # adds several more, so the read timeout leaves room for both.
  RUNNER_TIMEOUT      = 65
  RUNNER_URL_ENV      = :exchange_runner_url
  RUNNER_API_KEY_ENV  = :exchange_runner_api_key

  # The runner refuses any cmdlet outside this list; naming it here as well keeps a typo in an action from
  # reaching the network, and documents the full surface the runner has to allow.
  RUNNER_CMDLETS = %w[
    Get-Mailbox Set-Mailbox New-Mailbox Get-MailboxStatistics
    Get-MailboxPermission Add-MailboxPermission Remove-MailboxPermission
    Get-RecipientPermission Add-RecipientPermission Remove-RecipientPermission
    Get-Recipient Get-AcceptedDomain
    Get-DistributionGroup Add-DistributionGroupMember Remove-DistributionGroupMember
    Get-MailboxFolderStatistics Get-MailboxFolderPermission Add-MailboxFolderPermission
    Set-MailboxFolderPermission
  ].freeze

  # Exchange's FullyQualifiedErrorId carries the exception name; these are the ones that mean the state the
  # step asked for already holds, or that a lookup found nothing.
  ALREADY_MEMBER_ERROR       = 'MemberAlreadyExistsException'.freeze
  NOT_MEMBER_ERROR           = 'MemberNotFoundException'.freeze
  OBJECT_NOT_FOUND_ERROR     = 'ManagementObjectNotFoundException'.freeze
  NO_PERMISSION_ENTRY_ERROR  = 'UserNotFoundInPermissionEntryException'.freeze

  FULL_ACCESS   = 'FullAccess'.freeze
  SEND_AS       = 'SendAs'.freeze
  ALLOW_CONTROL = 'Allow'.freeze

  SHARED_MAILBOX_TYPE = 'SharedMailbox'.freeze
  USER_MAILBOX_TYPE   = 'UserMailbox'.freeze
  ACTIVE_ARCHIVE      = 'Active'.freeze
  # An unlicensed shared mailbox holds at most 50 GB; above that it needs a licence of its own.
  SHARED_MAILBOX_LIMIT_BYTES = 53_687_091_200 # 50 GiB
  ITEM_SIZE_BYTES_PATTERN    = /\(([\d,.\s]+) bytes\)/
  CLOSED_JOIN_RESTRICTION    = 'Closed'.freeze

  SMTP_PREFIX       = 'smtp:'.freeze
  ADDRESS_PATTERN   = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
  ROUTING_CHARACTER = %r{[/\\%]}

  CALENDAR_FOLDER_TYPE = 'Calendar'.freeze
  FOLDER_ACCESS_RIGHTS = %w[
    Owner PublishingEditor Editor PublishingAuthor Author NonEditingAuthor Reviewer Contributor
    AvailabilityOnly LimitedDetails
  ].freeze
  SHARING_PERMISSIONS = {
    'None' => nil,
    'Delegate' => 'Delegate',
    'Delegate and private items' => 'Delegate,CanViewPrivateItems',
  }.freeze
  DEFAULT_SHARING_PERMISSION = 'None'.freeze
  DELEGATE_ACCESS_RIGHT      = 'Editor'.freeze

  UNLIMITED_HOLD = 'Unlimited'.freeze

  AUTO_REPLY_STATUSES = {
    'Enabled' => 'alwaysEnabled',
    'Scheduled' => 'scheduled',
    'Disabled' => 'disabled',
  }.freeze
  EXTERNAL_AUDIENCES = {
    'All' => 'all',
    'Contacts only' => 'contactsOnly',
    'None' => 'none',
  }.freeze
  DEFAULT_EXTERNAL_AUDIENCE = 'All'.freeze
  GRAPH_TIME_FORMAT         = '%Y-%m-%dT%H:%M:%S'.freeze
  GRAPH_TIME_ZONE           = 'UTC'.freeze

  connector '01a1f2c3-0276-7a6d-88ab-3d9d74512014' do
    name 'Microsoft Exchange Online'
    avatar '/assets/icons/microsoft-exchange-online.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Runs Exchange Online administration from a runbook: mailbox access (Full Access, Send As, Send on Behalf, calendar delegates), distribution list membership, shared mailboxes, mail forwarding, automatic replies, address list visibility, email aliases and litigation hold.

      Exchange Online offers most of these tasks only as PowerShell cmdlets; Microsoft Graph cannot change mailbox permissions or distribution list membership. The connector therefore sends each cmdlet to the Xurrent Exchange runner, which runs it with the official Exchange Online PowerShell module and returns the result. Set automatic replies is the exception: it calls Microsoft Graph directly.

      Every action is idempotent. When the mailbox already is in the state a step asks for, the step succeeds and reports `changed: false` instead of failing, so a runbook can be run again safely.

      ## Prerequisites
      - A Microsoft Entra ID tenant with Exchange Online.
      - An app registration in Microsoft Entra (single tenant, no redirect URI). Obtain:
        - **Directory (tenant) ID** and **Application (client) ID**, from the app's Overview page.
        - **Client secret**: created under **Certificates & secrets → Client secrets**. Copy the **Value** at creation time; it is not shown again.
      - API permissions on the app registration, each with admin consent:
        - **Office 365 Exchange Online → Exchange.ManageAsApp** (application), for every action except Set automatic replies.
        - **Microsoft Graph → MailboxSettings.ReadWrite** (application), for Set automatic replies.
      - An Exchange role for the app's service principal: the **Exchange Recipient Administrator** Entra role, or an Exchange role group with **Mail Recipients**, **Mail Recipient Creation**, **Distribution Groups** and, for litigation hold, **Legal Hold**. RBAC for Applications scoped to a management scope narrows the mailboxes the app may change.

      ## Authentication
      The connector signs in as the application (OAuth 2.0 client credentials). No user logs in. Tokens come from `{login host}/{tenant_id}/oauth2/v2.0/token`: one for the Exchange host of the selected **Cloud** (sent to the runner with each cmdlet) and one for Microsoft Graph. The runner keeps no credentials of its own; it uses the token it receives for that one cmdlet.

      **Organization** is the tenant's initial domain, for example `contoso.onmicrosoft.com`. The Exchange PowerShell module needs it to open a session with an app token.

      ## Actions
      Each action notes the risk tier and the action that undoes it, from the Xurrent ITSM action library. Approvals are set on the request or runbook that runs the step; the connector does not enforce them.

      | Action | What it does | Tier | Undo |
      |--------|--------------|------|------|
      | Grant shared mailbox Full Access | Add-MailboxPermission -AccessRights FullAccess | T2 | Remove shared mailbox Full Access |
      | Remove shared mailbox Full Access | Remove-MailboxPermission -AccessRights FullAccess | T1 | Grant shared mailbox Full Access |
      | Grant Send As | Add-RecipientPermission -AccessRights SendAs | T2 | Remove Send As |
      | Remove Send As | Remove-RecipientPermission -AccessRights SendAs | T1 | Grant Send As |
      | Grant Send on Behalf | Set-Mailbox -GrantSendOnBehalfTo @{Add} | T2 | |
      | Add member to distribution list | Add-DistributionGroupMember | T1 | Remove member from distribution list |
      | Remove member from distribution list | Remove-DistributionGroupMember | T1 | Add member to distribution list |
      | Create shared mailbox | New-Mailbox -Shared, then Full Access for its owners | T2 | |
      | Convert mailbox to shared | Set-Mailbox -Type Shared | T3 | |
      | Set mail forwarding | Set-Mailbox -ForwardingSmtpAddress | T3 | |
      | Set automatic replies | Microsoft Graph mailboxSettings | T2 | |
      | Hide from address list | Set-Mailbox -HiddenFromAddressListsEnabled | T2 | |
      | Grant calendar delegate access | Add- or Set-MailboxFolderPermission on the calendar | T2 | |
      | Add email alias | Set-Mailbox -EmailAddresses @{Add} | T2 | |
      | Enable litigation hold | Set-Mailbox -LitigationHoldEnabled | T3 | |

      ## References
      - [App-only authentication in Exchange Online PowerShell](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2)
      - [Role Based Access Control for Applications in Exchange Online](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)
      - [Update mailboxSettings](https://learn.microsoft.com/en-us/graph/api/user-update-mailboxsettings)
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

        field :organization, 'Organization', :string,
              required: true,
              hint: 'The tenant\'s initial domain, for example contoso.onmicrosoft.com.'

        field :cloud, 'Cloud', :string,
              required: true,
              default: DEFAULT_CLOUD,
              enumeration: CLOUDS.keys,
              hint: 'Selects the Microsoft login, Exchange and Graph hosts together.'

        field :runner, 'Exchange runner', :nested,
              visibility: 'optional' do
          field :url, 'Runner URL', :uri,
                hint: 'Leave empty to use the Xurrent Exchange runner. Set only for a runner you host yourself.'
          field :api_key, 'Runner API key', :secret_string,
                hint: 'The key of the runner named in Runner URL.'
        end
      end

      # Only Microsoft Graph calls go through this block. Runner calls skip it and carry the runner key, with
      # the Exchange token in the body, because the runner and Graph accept different credentials.
      authenticate do |request|
        request.headers['Authorization'] = oauth2_authorization_header(helpers.token_url,
                                                                       helpers.token_body(helpers.cloud[:graph]))
      end

      config_tester do
        helpers.exchange_cmdlet('Get-Mailbox', { ResultSize: 1 })
        { status: :success,
          message: "Connection successful. The runner opened Exchange Online for #{helpers.organization}.", }
      rescue IPaaS::Job::FailJob => e
        { status: :failed, message: e.message }
      end
    end

    # --- Mailbox access ------------------------------------------------------------------------------------

    action '01a1f2c3-0279-7d47-9565-a937427dd458' do
      name 'Grant shared mailbox Full Access'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Gives a user Full Access to a mailbox, with optional auto-mapping so the mailbox appears in the user's Outlook. Action library EXO-001, tier T2. Undo with Remove shared mailbox Full Access.

        When the user already holds an explicit Full Access permission, nothing changes and `changed` is false.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              required: true,
              hint: 'The mailbox to open up: its SMTP address, user principal name or alias.'
        field :user, 'User', :string,
              required: true,
              hint: 'The user who gets Full Access.'
        field :auto_mapping, 'Auto-mapping', :boolean,
              visibility: 'optional',
              default: true,
              hint: 'True adds the mailbox to the user\'s Outlook automatically.'
      end

      output_schema do
        field :mailbox, 'Mailbox', :string, required: true
        field :user, 'User', :string, required: true
        field :auto_mapping, 'Auto-mapping', :boolean
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the user already had Full Access.'
      end

      run do
        mailbox = helpers.identity_for(input[:mailbox], 'Mailbox')
        user = helpers.identity_for(input[:user], 'User')
        auto_mapping = input[:auto_mapping] != false
        changed = helpers.grant_full_access(mailbox, user, auto_mapping)
        [{ output: { mailbox: mailbox, user: user, auto_mapping: auto_mapping, changed: changed } }]
      end
    end

    action '01a1f2c3-027b-7ef9-8990-ccb8b03904eb' do
      name 'Remove shared mailbox Full Access'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Takes a user's Full Access permission off a mailbox. Action library EXO-002, tier T1. Undo with Grant shared mailbox Full Access.

        When the user holds no explicit Full Access permission, nothing changes and `changed` is false. A permission the user inherits, for example from an organization-wide grant, is not removed by this step.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              required: true,
              hint: 'The mailbox: its SMTP address, user principal name or alias.'
        field :user, 'User', :string,
              required: true,
              hint: 'The user whose Full Access is removed.'
      end

      output_schema do
        field :mailbox, 'Mailbox', :string, required: true
        field :user, 'User', :string, required: true
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the user had no Full Access to remove.'
      end

      run do
        mailbox = helpers.identity_for(input[:mailbox], 'Mailbox')
        user = helpers.identity_for(input[:user], 'User')
        changed = helpers.full_access?(mailbox, user)
        if changed
          helpers.exchange_cmdlet('Remove-MailboxPermission',
                                  { Identity: mailbox, User: user, AccessRights: [FULL_ACCESS],
                                    InheritanceType: 'All', Confirm: false, })
        end
        [{ output: { mailbox: mailbox, user: user, changed: changed } }]
      end
    end

    action '01a1f2c3-027e-7153-9f6d-ecb2c8a560cd' do
      name 'Grant Send As'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Lets a user send mail as a mailbox or group, so the message shows the mailbox as its sender. Action library EXO-003, tier T2. Undo with Remove Send As.

        When the user already holds Send As, nothing changes and `changed` is false.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              required: true,
              hint: 'The mailbox or group to send as: its SMTP address, user principal name or alias.'
        field :user, 'User', :string,
              required: true,
              hint: 'The user who gets Send As.'
      end

      output_schema do
        field :mailbox, 'Mailbox', :string, required: true
        field :user, 'User', :string, required: true
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the user already had Send As.'
      end

      run do
        mailbox = helpers.identity_for(input[:mailbox], 'Mailbox')
        user = helpers.identity_for(input[:user], 'User')
        changed = !helpers.send_as?(mailbox, user)
        if changed
          helpers.exchange_cmdlet('Add-RecipientPermission',
                                  { Identity: mailbox, Trustee: user, AccessRights: [SEND_AS], Confirm: false })
        end
        [{ output: { mailbox: mailbox, user: user, changed: changed } }]
      end
    end

    action '01a1f2c3-0280-7471-9ac6-d5e0b9808eff' do
      name 'Remove Send As'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Takes a user's Send As permission off a mailbox or group. Action library EXO-004, tier T1. Undo with Grant Send As.

        When the user holds no Send As permission, nothing changes and `changed` is false.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              required: true,
              hint: 'The mailbox or group: its SMTP address, user principal name or alias.'
        field :user, 'User', :string,
              required: true,
              hint: 'The user whose Send As is removed.'
      end

      output_schema do
        field :mailbox, 'Mailbox', :string, required: true
        field :user, 'User', :string, required: true
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the user had no Send As to remove.'
      end

      run do
        mailbox = helpers.identity_for(input[:mailbox], 'Mailbox')
        user = helpers.identity_for(input[:user], 'User')
        changed = helpers.send_as?(mailbox, user)
        if changed
          helpers.exchange_cmdlet('Remove-RecipientPermission',
                                  { Identity: mailbox, Trustee: user, AccessRights: [SEND_AS], Confirm: false })
        end
        [{ output: { mailbox: mailbox, user: user, changed: changed } }]
      end
    end

    action '01a1f2c3-0283-7a28-a20d-7151e9003538' do
      name 'Grant Send on Behalf'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Lets a user send on behalf of a mailbox; recipients see "user on behalf of mailbox". Typical for executive assistants. Action library EXO-005, tier T2.

        The user is added to the mailbox's Send on Behalf list; the people already on it stay. When the user already is on the list, nothing changes and `changed` is false.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              required: true,
              hint: 'The mailbox: its SMTP address, user principal name or alias.'
        field :user, 'User', :string,
              required: true,
              hint: 'The user who may send on behalf of the mailbox.'
      end

      output_schema do
        field :mailbox, 'Mailbox', :string, required: true
        field :user, 'User', :string, required: true
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the user already was on the Send on Behalf list.'
      end

      run do
        mailbox = helpers.identity_for(input[:mailbox], 'Mailbox')
        user = helpers.identity_for(input[:user], 'User')
        current = helpers.mailbox_details(mailbox)
        delegates = helpers.list_of(current['GrantSendOnBehalfTo'])
        recipient = helpers.recipient_details(user)
        changed = !helpers.names_recipient?(delegates, recipient, user)
        helpers.exchange_cmdlet('Set-Mailbox', { Identity: mailbox, GrantSendOnBehalfTo: { add: [user] } }) if changed
        [{ output: { mailbox: mailbox, user: user, changed: changed } }]
      end
    end

    # --- Distribution lists --------------------------------------------------------------------------------

    action '01a1f2c3-0285-7f9d-96c4-3b6ffa0cd5ad' do
      name 'Add member to distribution list'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Adds a user to a distribution list or mail-enabled security group. Microsoft Graph cannot change their membership, so this runs Add-DistributionGroupMember. Action library EXO-006, tier T1. Undo with Remove member from distribution list.

        Tier T1 auto-approves because people may join a self-service list on their own. A list whose join restriction is Closed is not self-service, so the step refuses it unless **Allow closed list** is set; set it only on a runbook that already holds an approval from the list's owner.

        When the user already is a member, nothing changes and `changed` is false.
      END_OF_DESCRIPTION

      input_schema do
        field :list, 'List', :string,
              required: true,
              hint: 'The distribution list: its SMTP address, name or alias.'
        field :user, 'User', :string,
              required: true,
              hint: 'The user to add.'
        field :allow_closed_list, 'Allow closed list', :boolean,
              visibility: 'optional',
              default: false,
              hint: 'True also adds to a list whose join restriction is Closed.'
      end

      output_schema do
        field :list, 'List', :string, required: true
        field :user, 'User', :string, required: true
        field :member_join_restriction, 'Member join restriction', :string,
              hint: 'Open, ApprovalRequired or Closed, as set on the list.'
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the user already was a member.'
      end

      run do
        list = helpers.identity_for(input[:list], 'List')
        user = helpers.identity_for(input[:user], 'User')
        group = helpers.first_object(helpers.exchange_cmdlet('Get-DistributionGroup', { Identity: list }),
                                     "Distribution list '#{list}'")
        restriction = group['MemberJoinRestriction'].to_s
        if restriction == CLOSED_JOIN_RESTRICTION && input[:allow_closed_list] != true
          fail_job!("Distribution list '#{list}' is Closed to new members, so it is not self-service. Set Allow " \
                    'closed list on a runbook that holds the approval of the list\'s owner.')
        end

        result = helpers.run_cmdlet('Add-DistributionGroupMember',
                                    { Identity: list, Member: user, BypassSecurityGroupManagerCheck: true })
        changed = !helpers.error_named?(result, ALREADY_MEMBER_ERROR)
        helpers.require_success!(result, 'Add-DistributionGroupMember') if changed
        [{ output: { list: list, user: user, member_join_restriction: restriction.presence, changed: changed } }]
      end
    end

    action '01a1f2c3-0288-7626-b93b-25a8f0608152' do
      name 'Remove member from distribution list'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Removes a user from a distribution list or mail-enabled security group. Action library EXO-007, tier T1. Undo with Add member to distribution list.

        When the user is not a member, nothing changes and `changed` is false.
      END_OF_DESCRIPTION

      input_schema do
        field :list, 'List', :string,
              required: true,
              hint: 'The distribution list: its SMTP address, name or alias.'
        field :user, 'User', :string,
              required: true,
              hint: 'The user to remove.'
      end

      output_schema do
        field :list, 'List', :string, required: true
        field :user, 'User', :string, required: true
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the user was not a member.'
      end

      run do
        list = helpers.identity_for(input[:list], 'List')
        user = helpers.identity_for(input[:user], 'User')
        result = helpers.run_cmdlet('Remove-DistributionGroupMember',
                                    { Identity: list, Member: user, BypassSecurityGroupManagerCheck: true,
                                      Confirm: false, })
        changed = !helpers.error_named?(result, NOT_MEMBER_ERROR)
        helpers.require_success!(result, 'Remove-DistributionGroupMember') if changed
        [{ output: { list: list, user: user, changed: changed } }]
      end
    end

    # --- Mailbox lifecycle ---------------------------------------------------------------------------------

    action '01a1f2c3-028a-71f2-95e8-12d120e87bed' do
      name 'Create shared mailbox'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Creates a shared mailbox and gives each owner Full Access with auto-mapping. Action library EXO-008, tier T2.

        When a shared mailbox with the address already exists, it is not created again and `created` is false; its owners still get Full Access where they lack it. When the address belongs to any other recipient, the step fails and creates nothing.
      END_OF_DESCRIPTION

      input_schema do
        field :name, 'Name', :string,
              required: true,
              max_length: 64,
              hint: 'The unique Exchange name of the mailbox.'
        field :display_name, 'Display name', :string,
              visibility: 'optional',
              hint: 'The name shown in the address list. Empty uses Name.'
        field :address, 'Address', :string,
              required: true,
              hint: 'The primary SMTP address, for example support@contoso.com. Its domain must be accepted by ' \
                    'the tenant.'
        field :alias, 'Alias', :string,
              visibility: 'optional',
              hint: 'The mail alias. Empty lets Exchange derive one from the address.'
        field :owners, 'Owners', :string,
              array: true,
              visibility: 'optional',
              hint: 'The users who get Full Access with auto-mapping.'
      end

      output_schema do
        field :mailbox, 'Mailbox', :string, required: true,
                                            hint: 'The primary SMTP address of the mailbox.'
        field :created, 'Created', :boolean, required: true,
                                             hint: 'False when the shared mailbox already existed.'
        field :owners_granted, 'Owners granted', :string, array: true,
                                                          hint: 'The owners who got Full Access in this step.'
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the mailbox existed and every owner had access.'
      end

      run do
        address = helpers.address_for(input[:address], 'Address')
        name = helpers.identity_for(input[:name], 'Name')
        owners = helpers.list_of(input[:owners]).map { |owner| helpers.identity_for(owner, 'Owner') }
        existing = helpers.find_recipient(address)
        created = existing.nil?
        if existing && existing['RecipientTypeDetails'].to_s != SHARED_MAILBOX_TYPE
          fail_job!("Address '#{address}' already belongs to #{existing['RecipientTypeDetails']} " \
                    "'#{existing['Name']}'. Pick another address.")
        end
        if created
          parameters = { Shared: true, Name: name, DisplayName: input[:display_name].to_s.strip.presence || name,
                         PrimarySmtpAddress: address, Alias: input[:alias].to_s.strip.presence, }
          helpers.exchange_cmdlet('New-Mailbox', parameters.compact)
        end

        granted = owners.select { |owner| helpers.grant_full_access(address, owner, true) }
        [{ output: { mailbox: address, created: created, owners_granted: granted,
                     changed: created || granted.present?, } }]
      end
    end

    action '01a1f2c3-028c-7e7f-bcbe-18649dceec02' do
      name 'Convert mailbox to shared'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Converts a user mailbox to a shared mailbox, so a leaver's mail is kept without a licence. Action library EXO-009, tier T3. Run it before the licence is removed: removing an Exchange licence deletes the mailbox's data after 30 days.

        An unlicensed shared mailbox holds at most 50 GB and keeps no archive or hold, so the step refuses a mailbox that is larger, has an active archive, or is on litigation or in-place hold. Keep that mailbox licensed instead.

        When the mailbox already is shared, nothing changes and `changed` is false.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              required: true,
              hint: 'The user mailbox: its SMTP address, user principal name or alias.'
      end

      output_schema do
        field :mailbox, 'Mailbox', :string, required: true
        field :previous_type, 'Previous type', :string,
              hint: 'The mailbox type before this step, for example UserMailbox.'
        field :total_item_size_bytes, 'Total item size (bytes)', :integer
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the mailbox already was shared.'
      end

      run do
        mailbox = helpers.identity_for(input[:mailbox], 'Mailbox')
        current = helpers.mailbox_details(mailbox)
        type = current['RecipientTypeDetails'].to_s
        next [{ output: { mailbox: mailbox, previous_type: type, changed: false } }] if type == SHARED_MAILBOX_TYPE

        if type != USER_MAILBOX_TYPE
          fail_job!("Mailbox '#{mailbox}' is a #{type.presence || 'mailbox of unknown type'}; only a UserMailbox " \
                    'is converted.')
        end
        helpers.refuse_retained_mailbox!(mailbox, current)
        size = helpers.mailbox_size_bytes(mailbox)
        if size > SHARED_MAILBOX_LIMIT_BYTES
          fail_job!("Mailbox '#{mailbox}' holds #{size} bytes, more than the 50 GB an unlicensed shared mailbox " \
                    'may hold. Keep it licensed.')
        end

        helpers.exchange_cmdlet('Set-Mailbox', { Identity: mailbox, Type: 'Shared' })
        [{ output: { mailbox: mailbox, previous_type: type, total_item_size_bytes: size, changed: true } }]
      end
    end

    # --- Mail flow -----------------------------------------------------------------------------------------

    action '01a1f2c3-028f-7dd1-8674-5b535937d270' do
      name 'Set mail forwarding'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Forwards a mailbox's mail to another address in the organization, for example a leaver's mail to their manager. Action library EXO-010, tier T3.

        The target must be in one of the tenant's accepted domains. Forwarding outside the organization is a path for data to leave it, so the step refuses an external address.

        When the mailbox already forwards to the target with the same Keep a copy setting, nothing changes and `changed` is false.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              required: true,
              hint: 'The mailbox to forward: its SMTP address, user principal name or alias.'
        field :target, 'Target', :string,
              required: true,
              hint: 'The SMTP address that receives the mail. Its domain must be accepted by the tenant.'
        field :keep_copy, 'Keep a copy', :boolean,
              visibility: 'optional',
              default: true,
              hint: 'True also delivers each message to the mailbox itself.'
      end

      output_schema do
        field :mailbox, 'Mailbox', :string, required: true
        field :target, 'Target', :string, required: true
        field :keep_copy, 'Keep a copy', :boolean
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the mailbox already forwarded this way.'
      end

      run do
        mailbox = helpers.identity_for(input[:mailbox], 'Mailbox')
        target = helpers.address_for(input[:target], 'Target')
        keep_copy = input[:keep_copy] != false
        helpers.refuse_external_address!(target)

        current = helpers.mailbox_details(mailbox)
        forwarding = current['ForwardingSmtpAddress'].to_s.downcase
        same = forwarding == "#{SMTP_PREFIX}#{target}".downcase &&
               helpers.truthy?(current['DeliverToMailboxAndForward']) == keep_copy
        unless same
          helpers.exchange_cmdlet('Set-Mailbox', { Identity: mailbox, ForwardingSmtpAddress: "#{SMTP_PREFIX}#{target}",
                                                   DeliverToMailboxAndForward: keep_copy, })
        end
        [{ output: { mailbox: mailbox, target: target, keep_copy: keep_copy, changed: !same } }]
      end
    end

    action '01a1f2c3-0291-76fa-936f-5446fad43616' do
      name 'Set automatic replies'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Turns a mailbox's automatic replies (out of office) on, schedules them, or turns them off. Calls Microsoft Graph directly and needs the MailboxSettings.ReadWrite permission. Action library EXO-011, tier T2.

        - **Enabled** sends replies until they are turned off.
        - **Scheduled** sends replies between Start and End only; both are required.
        - **Disabled** turns replies off; the messages are kept for next time.

        External audience picks who outside the organization gets the external message.
      END_OF_DESCRIPTION

      input_schema do
        field :user, 'User', :string,
              required: true,
              hint: 'The mailbox: its user principal name, object id or SMTP address.'
        field :status, 'Status', :string,
              required: true,
              enumeration: AUTO_REPLY_STATUSES.keys,
              hint: 'Enabled, Scheduled or Disabled.'
        field :internal_message, 'Internal message', :string,
              visibility: 'optional',
              hint: 'The reply to senders inside the organization. HTML is accepted.'
        field :external_message, 'External message', :string,
              visibility: 'optional',
              hint: 'The reply to senders outside the organization. HTML is accepted.'
        field :external_audience, 'External audience', :string,
              visibility: 'optional',
              default: DEFAULT_EXTERNAL_AUDIENCE,
              enumeration: EXTERNAL_AUDIENCES.keys,
              hint: 'All, Contacts only or None.'
        field :scheduled_start, 'Start', :date_time,
              visibility: 'optional',
              hint: 'When Scheduled replies start.'
        field :scheduled_end, 'End', :date_time,
              visibility: 'optional',
              hint: 'When Scheduled replies stop.'
      end

      output_schema do
        field :user, 'User', :string, required: true
        field :status, 'Status', :string, required: true
        field :external_audience, 'External audience', :string
        field :scheduled_start, 'Start', :date_time
        field :scheduled_end, 'End', :date_time
      end

      run do
        user = helpers.identity_for(input[:user], 'User')
        setting = helpers.auto_reply_setting(input)
        url = helpers.graph_url("/users/#{helpers.escape_segment(user)}/mailboxSettings")
        response = http_patch(url, { automaticRepliesSetting: setting }.to_json, JSON_HEADERS)
        backoff_if_needed(response, api_name: 'Microsoft Graph')
        fail_job!(helpers.describe_graph_failure(response, user)) if response.status != 200

        scheduled = setting[:status] == AUTO_REPLY_STATUSES['Scheduled']
        [{ output: { user: user, status: input[:status],
                     external_audience: input[:external_audience].presence || DEFAULT_EXTERNAL_AUDIENCE,
                     scheduled_start: (input[:scheduled_start] if scheduled),
                     scheduled_end: (input[:scheduled_end] if scheduled), } }]
      end
    end

    action '01a1f2c3-0294-7e3d-9944-974c8aad81e5' do
      name 'Hide from address list'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Hides a mailbox from the global address list, or shows it again. Typical for a leaver. Action library EXO-012, tier T2.

        A mailbox synchronized from on-premises Active Directory takes this setting from there: set msExchHideFromAddressLists on the on-premises account instead. The step refuses such a mailbox, because Exchange Online would overwrite the change at the next synchronization.

        When the mailbox already is hidden (or shown), nothing changes and `changed` is false.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              required: true,
              hint: 'The mailbox: its SMTP address, user principal name or alias.'
        field :hidden, 'Hidden', :boolean,
              visibility: 'optional',
              default: true,
              hint: 'True hides the mailbox; false shows it again.'
      end

      output_schema do
        field :mailbox, 'Mailbox', :string, required: true
        field :hidden, 'Hidden', :boolean, required: true
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the mailbox already was in that state.'
      end

      run do
        mailbox = helpers.identity_for(input[:mailbox], 'Mailbox')
        hidden = input[:hidden] != false
        current = helpers.mailbox_details(mailbox)
        helpers.refuse_synced_mailbox!(mailbox, current, 'msExchHideFromAddressLists')
        changed = helpers.truthy?(current['HiddenFromAddressListsEnabled']) != hidden
        helpers.exchange_cmdlet('Set-Mailbox', { Identity: mailbox, HiddenFromAddressListsEnabled: hidden }) if changed
        [{ output: { mailbox: mailbox, hidden: hidden, changed: changed } }]
      end
    end

    action '01a1f2c3-0296-72c4-a69e-0d7cfcaed557' do
      name 'Grant calendar delegate access'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Gives a user access to a mailbox's calendar, for example an assistant to a manager's calendar. Action library EXO-013, tier T2; the mailbox owner approves.

        The calendar is found by its folder type, so the step works whatever language the mailbox uses. A user who already has access gets the new access rights instead of a second entry.

        Sharing permission **Delegate** also sends the mailbox's meeting requests to the user, and **Delegate and private items** lets them see private appointments. Both need the Editor access right.

        When the user already has exactly these rights, nothing changes and `changed` is false.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              required: true,
              hint: 'The mailbox whose calendar is shared: its SMTP address, user principal name or alias.'
        field :user, 'User', :string,
              required: true,
              hint: 'The user who gets access.'
        field :access_rights, 'Access rights', :string,
              required: true,
              enumeration: FOLDER_ACCESS_RIGHTS,
              hint: 'For example Reviewer to read, Editor to change items.'
        field :sharing_permission, 'Sharing permission', :string,
              visibility: 'optional',
              default: DEFAULT_SHARING_PERMISSION,
              enumeration: SHARING_PERMISSIONS.keys,
              hint: 'None, Delegate, or Delegate and private items. Delegate needs Editor.'
      end

      output_schema do
        field :mailbox, 'Mailbox', :string, required: true
        field :user, 'User', :string, required: true
        field :calendar, 'Calendar', :string,
              hint: 'The calendar folder, as Exchange names it.'
        field :access_rights, 'Access rights', :string
        field :sharing_permission, 'Sharing permission', :string
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the user already had these rights.'
      end

      run do
        mailbox = helpers.identity_for(input[:mailbox], 'Mailbox')
        user = helpers.identity_for(input[:user], 'User')
        rights = input[:access_rights].to_s
        sharing_name = input[:sharing_permission].presence || DEFAULT_SHARING_PERMISSION
        sharing = SHARING_PERMISSIONS[sharing_name]
        if sharing && rights != DELEGATE_ACCESS_RIGHT
          fail_job!("Sharing permission #{sharing_name} needs the Editor access right, not #{rights}.")
        end

        calendar = helpers.calendar_folder(mailbox)
        existing = helpers.folder_permission(calendar, user)
        changed = existing.nil? || !helpers.same_folder_permission?(existing, rights, sharing)
        if changed
          cmdlet = existing.nil? ? 'Add-MailboxFolderPermission' : 'Set-MailboxFolderPermission'
          parameters = { Identity: calendar, User: user, AccessRights: [rights], SharingPermissionFlags: sharing }
          helpers.exchange_cmdlet(cmdlet, parameters.compact)
        end
        [{ output: { mailbox: mailbox, user: user, calendar: calendar, access_rights: rights,
                     sharing_permission: sharing_name, changed: changed, } }]
      end
    end

    action '01a1f2c3-0299-7db0-9ea4-2dc1de74b7ef' do
      name 'Add email alias'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Adds a secondary SMTP address to a mailbox, for example after a name change. The primary address stays as it is. Action library EXO-014, tier T2.

        The alias must be unused across the organization and in one of its accepted domains. A mailbox synchronized from on-premises Active Directory takes its addresses from there: edit proxyAddresses on the on-premises account instead.

        When the mailbox already carries the alias, nothing changes and `changed` is false.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              required: true,
              hint: 'The mailbox: its SMTP address, user principal name or alias.'
        field :alias, 'Alias', :string,
              required: true,
              hint: 'The SMTP address to add, for example jane.doe@contoso.com.'
      end

      output_schema do
        field :mailbox, 'Mailbox', :string, required: true
        field :alias, 'Alias', :string, required: true
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the mailbox already carried the alias.'
      end

      run do
        mailbox = helpers.identity_for(input[:mailbox], 'Mailbox')
        address = helpers.address_for(input[:alias], 'Alias')
        current = helpers.mailbox_details(mailbox)
        helpers.refuse_synced_mailbox!(mailbox, current, 'proxyAddresses')
        carried = helpers.list_of(current['EmailAddresses']).any? do |entry|
          helpers.smtp_address(entry) == address.downcase
        end
        unless carried
          helpers.refuse_external_address!(address)
          owner = helpers.find_recipient(address)
          if owner
            fail_job!("Address '#{address}' already belongs to #{owner['RecipientTypeDetails']} '#{owner['Name']}'.")
          end
          helpers.exchange_cmdlet('Set-Mailbox',
                                  { Identity: mailbox, EmailAddresses: { add: ["#{SMTP_PREFIX}#{address}"] } })
        end
        [{ output: { mailbox: mailbox, alias: address, changed: !carried } }]
      end
    end

    # --- Compliance ----------------------------------------------------------------------------------------

    action '01a1f2c3-029b-71e5-95cc-bb9dabb2aafa' do
      name 'Enable litigation hold'
      avatar '/assets/icons/microsoft-exchange-online.svg'
      description <<~END_OF_DESCRIPTION
        Places a mailbox on litigation hold, so nothing in it can be purged, for a number of days or without end. Action library EXO-015, tier T3; needs legal approval, and Exchange Online Plan 2 or an E3 or higher licence on the mailbox.

        When the mailbox already is on hold for the same duration, nothing changes and `changed` is false. A hold with another duration is changed to this one.
      END_OF_DESCRIPTION

      input_schema do
        field :mailbox, 'Mailbox', :string,
              required: true,
              hint: 'The mailbox: its SMTP address, user principal name or alias.'
        field :duration_days, 'Duration (days)', :integer,
              visibility: 'optional',
              min: 1,
              hint: 'How long items are held, counted from when each was received. Empty holds without end.'
        field :owner, 'Owner', :string,
              visibility: 'optional',
              hint: 'Who placed the hold, recorded on the mailbox. Empty records the app.'
        field :comment, 'Comment', :string,
              visibility: 'optional',
              hint: 'A note shown to the mailbox user in Outlook, for example the case reference.'
      end

      output_schema do
        field :mailbox, 'Mailbox', :string, required: true
        field :duration, 'Duration', :string, required: true,
                                              hint: 'The number of days, or Unlimited.'
        field :changed, 'Changed', :boolean, required: true,
                                             hint: 'False when the mailbox already was on this hold.'
      end

      run do
        mailbox = helpers.identity_for(input[:mailbox], 'Mailbox')
        days = input[:duration_days].presence
        duration = days ? days.to_i : UNLIMITED_HOLD
        current = helpers.mailbox_details(mailbox)
        same = helpers.truthy?(current['LitigationHoldEnabled']) &&
               helpers.hold_days(current['LitigationHoldDuration']) == duration.to_s
        unless same
          parameters = { Identity: mailbox, LitigationHoldEnabled: true, LitigationHoldDuration: duration,
                         LitigationHoldOwner: input[:owner].to_s.strip.presence,
                         RetentionComment: input[:comment].to_s.strip.presence, }
          helpers.exchange_cmdlet('Set-Mailbox', parameters.compact)
        end
        [{ output: { mailbox: mailbox, duration: duration.to_s, changed: !same } }]
      end
    end

    # --- Connection and transport --------------------------------------------------------------------------

    helper :cloud do
      name = outbound_connection.config[:cloud].presence || DEFAULT_CLOUD
      entry = CLOUDS[name]
      if entry.blank?
        fail_job!("Cloud '#{name}' is not one of #{CLOUDS.keys.join(', ')}. Open the connection and select a Cloud.")
      end

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

    helper :organization do
      value = outbound_connection.config[:organization].to_s.strip.downcase
      if value.blank?
        fail_job!('Organization is empty on the connection. Enter the initial domain, such as contoso.onmicrosoft.com.')
      end

      value
    end

    helper :token_url do
      "#{helpers.cloud[:login]}/#{helpers.tenant_id}#{TOKEN_PATH}"
    end

    helper :token_body do |resource|
      credentials = outbound_connection.config[:credentials]
      body = oauth2_client_credentials_body(credentials[:client_id],
                                            decrypt_secret_string(credentials[:client_secret]))
      body.merge(scope: "#{resource}#{TOKEN_SCOPE_SUFFIX}")
    end

    helper :exchange_access_token do
      header = oauth2_authorization_header(helpers.token_url, helpers.token_body(helpers.cloud[:exchange]))
      header.to_s.sub(BEARER_PREFIX, '')
    end

    helper :runner_endpoint do
      configured = (outbound_connection.config[:runner] || {})[:url].to_s.strip
      base = configured.presence || environment[RUNNER_URL_ENV].to_s.strip
      if base.blank?
        fail_job!('No Exchange runner is configured for this environment. Ask Xurrent support to enable it.')
      end

      "#{base.chomp('/')}#{RUNNER_PATH}"
    end

    helper :runner_api_key do
      configured = (outbound_connection.config[:runner] || {})[:api_key]
      secret = configured.presence || environment[RUNNER_API_KEY_ENV].presence
      fail_job!('The Exchange runner has no API key configured. Set Runner API key on the connection.') if secret.blank?

      decrypt_secret_string(secret)
    end

    # Sends one cmdlet to the runner and answers what came back, success or not, so a caller can treat an
    # Exchange error that means "already so" as success. Rate limits and an unavailable runner pause the step.
    helper :run_cmdlet do |cmdlet, parameters|
      raise IPaaS::Error, "cmdlet '#{cmdlet}' is not on the runner allow-list" unless RUNNER_CMDLETS.include?(cmdlet)

      payload = { organization: helpers.organization, exchange_environment: helpers.cloud[:exchange_environment],
                  access_token: helpers.exchange_access_token, cmdlet: cmdlet, parameters: parameters, }
      headers = JSON_HEADERS.merge('Authorization' => "Bearer #{helpers.runner_api_key}")
      response = http_post(helpers.runner_endpoint, payload.to_json, headers,
                           skip_authentication: true, open_timeout: RUNNER_OPEN_TIMEOUT, timeout: RUNNER_TIMEOUT)
      backoff_if_needed(response, api_name: 'Exchange runner')
      body = parse_json_object_or_empty(response.body.to_s)
      if response.status == 200
        output = body['output']
        raise IPaaS::Error, "Exchange runner answered #{cmdlet} without an output list" unless output.is_a?(Array)

        { ok: true, output: output }
      else
        error = body['error'].is_a?(Hash) ? body['error'] : {}
        { ok: false, status: response.status, category: error['category'].to_s, error_id: error['error_id'].to_s,
          message: error['message'].presence || response.body.to_s.presence || 'no response body', }
      end
    end

    helper :exchange_cmdlet do |cmdlet, parameters|
      result = helpers.run_cmdlet(cmdlet, parameters)
      helpers.require_success!(result, cmdlet)
      result[:output]
    end

    helper :require_success! do |result, cmdlet|
      fail_job!(helpers.describe_runner_failure(result, cmdlet)) unless result[:ok]

      result
    end

    helper :describe_runner_failure do |result, cmdlet|
      case result[:status]
      when 401
        'The Exchange runner refused its API key. Check Runner API key on the connection, or ask Xurrent support.'
      when 403
        "Exchange Online refused #{cmdlet}: #{result[:message]} Check that the app holds Exchange.ManageAsApp " \
        'and an Exchange role that includes this cmdlet.'
      else
        category = result[:category].presence ? " (#{result[:category]})" : ''
        "#{cmdlet} failed with HTTP #{result[:status]}#{category}: #{result[:message]}"
      end
    end

    helper :error_named? do |result, exception_name|
      !result[:ok] && result[:error_id].to_s.include?(exception_name)
    end

    # --- Exchange objects ----------------------------------------------------------------------------------

    helper :identity_for do |value, label|
      identity = value.to_s.strip
      fail_job!("#{label} is empty.") if identity.blank?
      if ROUTING_CHARACTER.match?(identity)
        fail_job!("#{label} '#{identity}' holds a slash, a backslash or a percent sign. Use an SMTP address, a " \
                  'user principal name or an alias.')
      end

      identity
    end

    helper :address_for do |value, label|
      address = helpers.identity_for(value, label).sub(/\A#{SMTP_PREFIX}/io, '')
      unless ADDRESS_PATTERN.match?(address)
        fail_job!("#{label} '#{address}' is not an SMTP address such as jane@contoso.com.")
      end

      address
    end

    helper :list_of do |value|
      next value.compact if value.is_a?(Array)
      next [] if value.blank?

      [value]
    end

    helper :first_object do |output, subject|
      object = output.first
      fail_job!("#{subject} was not found in Exchange Online.") unless object.is_a?(Hash)

      object
    end

    helper :truthy? do |value|
      value == true || value.to_s.downcase == 'true'
    end

    helper :mailbox_details do |mailbox|
      helpers.first_object(helpers.exchange_cmdlet('Get-Mailbox', { Identity: mailbox }), "Mailbox '#{mailbox}'")
    end

    # Answers the recipient that holds an address, or nil when no recipient does.
    helper :find_recipient do |address|
      result = helpers.run_cmdlet('Get-Recipient', { Identity: address })
      next nil if helpers.error_named?(result, OBJECT_NOT_FOUND_ERROR)

      helpers.require_success!(result, 'Get-Recipient')
      result[:output].first
    end

    helper :recipient_details do |identity|
      helpers.first_object(helpers.exchange_cmdlet('Get-Recipient', { Identity: identity }), "User '#{identity}'")
    end

    # Exchange lists delegates by name or identity, not by the address the step was given, so a delegate entry
    # matches when it equals any of the names the recipient goes by.
    helper :names_recipient? do |entries, recipient, given|
      names = [given, recipient['Name'], recipient['Identity'], recipient['Alias'], recipient['DisplayName'],
               recipient['PrimarySmtpAddress'], recipient['ExternalDirectoryObjectId'],]
      known = names.map { |name| name.to_s.strip.downcase }.reject(&:blank?)
      entries.any? { |entry| known.include?(entry.to_s.strip.downcase) }
    end

    helper :access_rights_of do |entry|
      rights = entry['AccessRights']
      rights = rights.to_s.split(',') unless rights.is_a?(Array)
      rights.map { |right| right.to_s.strip }
    end

    helper :full_access? do |mailbox, user|
      entries = helpers.exchange_cmdlet('Get-MailboxPermission', { Identity: mailbox, User: user })
      entries.any? do |entry|
        helpers.access_rights_of(entry).include?(FULL_ACCESS) && !helpers.truthy?(entry['Deny']) &&
          !helpers.truthy?(entry['IsInherited'])
      end
    end

    # Answers true when it granted the permission, false when the user already held it.
    helper :grant_full_access do |mailbox, user, auto_mapping|
      next false if helpers.full_access?(mailbox, user)

      helpers.exchange_cmdlet('Add-MailboxPermission',
                              { Identity: mailbox, User: user, AccessRights: [FULL_ACCESS], InheritanceType: 'All',
                                AutoMapping: auto_mapping, })
      true
    end

    helper :send_as? do |mailbox, user|
      entries = helpers.exchange_cmdlet('Get-RecipientPermission',
                                        { Identity: mailbox, Trustee: user, AccessRights: SEND_AS })
      entries.any? do |entry|
        helpers.access_rights_of(entry).include?(SEND_AS) && entry['AccessControlType'].to_s == ALLOW_CONTROL &&
          !helpers.truthy?(entry['IsInherited'])
      end
    end

    helper :refuse_retained_mailbox! do |mailbox, current|
      if helpers.truthy?(current['LitigationHoldEnabled']) || helpers.list_of(current['InPlaceHolds']).present?
        fail_job!("Mailbox '#{mailbox}' is on hold. A shared mailbox without a licence keeps no hold, so keep it " \
                  'licensed.')
      end
      if current['ArchiveStatus'].to_s == ACTIVE_ARCHIVE
        fail_job!("Mailbox '#{mailbox}' has an active archive. A shared mailbox without a licence keeps no " \
                  'archive, so keep it licensed.')
      end
    end

    # Exchange writes a mailbox size as "1.2 GB (1,288,490,188 bytes)"; only the byte count is exact.
    helper :mailbox_size_bytes do |mailbox|
      statistics = helpers.first_object(helpers.exchange_cmdlet('Get-MailboxStatistics', { Identity: mailbox }),
                                        "Statistics of mailbox '#{mailbox}'")
      match = ITEM_SIZE_BYTES_PATTERN.match(statistics['TotalItemSize'].to_s)
      unless match
        fail_job!("The size of mailbox '#{mailbox}' could not be read from '#{statistics['TotalItemSize']}', so " \
                  'the 50 GB limit of a shared mailbox cannot be checked.')
      end

      match[1].gsub(/[^\d]/, '').to_i
    end

    helper :refuse_synced_mailbox! do |mailbox, current, attribute|
      if helpers.truthy?(current['IsDirSynced'])
        fail_job!("Mailbox '#{mailbox}' is synchronized from on-premises Active Directory, which would undo this " \
                  "change. Set #{attribute} on the on-premises account instead.")
      end
    end

    helper :refuse_external_address! do |address|
      domain = address.split('@').last.to_s.downcase
      accepted = helpers.exchange_cmdlet('Get-AcceptedDomain', {}).map { |entry| entry['DomainName'].to_s.downcase }
      unless accepted.include?(domain)
        fail_job!("Address '#{address}' is outside the organization: #{domain} is not one of its accepted domains " \
                  "(#{accepted.join(', ')}).")
      end
    end

    helper :smtp_address do |entry|
      value = entry.to_s.strip
      value.downcase.start_with?(SMTP_PREFIX) ? value[SMTP_PREFIX.length..].downcase : ''
    end

    # Litigation hold duration comes back as "Unlimited" or as a TimeSpan such as "365.00:00:00".
    helper :hold_days do |value|
      text = value.to_s.strip
      text.downcase == UNLIMITED_HOLD.downcase ? UNLIMITED_HOLD : text.split('.').first.to_s
    end

    # The calendar's name depends on the mailbox language (Calendar, Kalender, Agenda), so it is found by type.
    helper :calendar_folder do |mailbox|
      folders = helpers.exchange_cmdlet('Get-MailboxFolderStatistics',
                                        { Identity: mailbox, FolderScope: CALENDAR_FOLDER_TYPE })
      folder = folders.detect { |entry| entry.is_a?(Hash) && entry['FolderType'].to_s == CALENDAR_FOLDER_TYPE }
      fail_job!("Mailbox '#{mailbox}' has no calendar folder.") if folder.nil? || folder['Name'].blank?

      "#{mailbox}:\\#{folder['Name']}"
    end

    # Answers the user's permission entry on the folder, or nil when the user has none.
    helper :folder_permission do |folder, user|
      result = helpers.run_cmdlet('Get-MailboxFolderPermission', { Identity: folder, User: user })
      next nil if helpers.error_named?(result, NO_PERMISSION_ENTRY_ERROR)

      helpers.require_success!(result, 'Get-MailboxFolderPermission')
      result[:output].first
    end

    helper :same_folder_permission? do |entry, rights, sharing|
      flags = entry['SharingPermissionFlags'].to_s.split(',').map(&:strip)
      flags = flags.reject { |flag| flag.blank? || flag == 'None' }
      wanted = sharing.to_s.split(',')
      helpers.access_rights_of(entry) == [rights] && flags.sort == wanted.sort
    end

    # --- Microsoft Graph -----------------------------------------------------------------------------------

    helper :graph_url do |path|
      "#{helpers.cloud[:graph]}/#{GRAPH_API_VERSION}#{path}"
    end

    helper :escape_segment do |value|
      value.to_s.gsub('%', '%25').gsub('#', '%23').gsub('?', '%3F').gsub('/', '%2F').gsub(' ', '%20')
    end

    helper :graph_time do |value|
      { dateTime: value.utc.strftime(GRAPH_TIME_FORMAT), timeZone: GRAPH_TIME_ZONE }
    end

    helper :auto_reply_setting do |fields|
      status = AUTO_REPLY_STATUSES[fields[:status].to_s]
      next { status: status } if status == AUTO_REPLY_STATUSES['Disabled']

      audience = EXTERNAL_AUDIENCES[fields[:external_audience].presence || DEFAULT_EXTERNAL_AUDIENCE]
      setting = { status: status, internalReplyMessage: fields[:internal_message].to_s,
                  externalReplyMessage: fields[:external_message].to_s, externalAudience: audience, }
      next setting if status == AUTO_REPLY_STATUSES['Enabled']

      start = fields[:scheduled_start]
      finish = fields[:scheduled_end]
      fail_job!('Scheduled replies need both Start and End.') if start.blank? || finish.blank?
      fail_job!('End must be after Start.') if finish <= start

      setting.merge(scheduledStartDateTime: helpers.graph_time(start), scheduledEndDateTime: helpers.graph_time(finish))
    end

    helper :describe_graph_failure do |response, user|
      error = parse_json_object_or_empty(response.body.to_s)['error']
      error = {} unless error.is_a?(Hash)
      detail = error['message'].presence || response.body.to_s.presence || 'no response body'
      hint = [401, 403].include?(response.status) ? ' Check that the app holds MailboxSettings.ReadWrite.' : ''
      "Microsoft Graph returned HTTP #{response.status} #{error['code']} for mailbox '#{user}': #{detail}#{hint}"
    end
  end
end
