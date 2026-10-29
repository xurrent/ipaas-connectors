class JiraConnector < IPaaS::Connector::Definition
  GATEWAY = 'https://api.atlassian.com'.freeze
  API_PATH = 'rest/api/3'.freeze
  WEBHOOK_PATH = 'rest/webhooks/1.0/webhook'.freeze
  TENANT_INFO_PATH = '_edge/tenant_info'.freeze
  CLOUD_ID_STORE_PREFIX = 'cloud_id:'.freeze
  CLOUD_ID_PATTERN = /\A[A-Za-z0-9-]+\z/
  SITE_HOST_PATTERN = /\A[a-z0-9][a-z0-9.-]*\z/
  SAFE_ID_PATTERN = /\A[A-Za-z0-9_-]+\z/
  DIGITS_PATTERN = /\A\d+\z/
  TIMESTAMP_PATTERN = /\A-?\d+\z/
  EMAIL_QUERY_PATTERN = /\A[^@\s]+@[^@\s]*\.[^@\s]*\z/
  ISSUE_KEY_PATTERN = /\A[A-Za-z][A-Za-z0-9_]*-\d+\z/
  PROJECT_KEY_PATTERN = /\A(?:[A-Za-z][A-Za-z0-9_]*|\d+)\z/
  JQL_ESCAPED_CHARACTERS = /["\\]/
  JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze
  SHORT_OPEN_TIMEOUT = 2
  SHORT_TIMEOUT = 3
  ACTION_TIMEOUT = 60
  READ_RETRY_STATUSES = [500, 502, 503, 504].freeze
  NETWORK_ERRORS = %w[Faraday::TimeoutError Faraday::ConnectionFailed].freeze
  UNCONFIRMED_CHANGE = 'The change may have been made, so check Jira before you run the step again.'.freeze
  SCOPE_MISMATCH = /scope does not match/i
  TEST_FAILED_STATUSES = [401, 403, 404].freeze
  PERMISSION_WORD = /permission/i
  PERMISSIONS_REFUSED_WITH_400 = [
    'Transition Issues', 'Edit Own Comments', 'Edit All Comments', 'Edit All Comments or Edit Own Comments',
  ].freeze
  EDIT_OWN_COMMENTS = 'Edit Own Comments'.freeze
  EDIT_ALL_COMMENTS = 'Edit All Comments'.freeze
  EDIT_ANY_COMMENTS = 'Edit All Comments or Edit Own Comments'.freeze
  TRUNCATED_BODY_LIMIT = 500
  DEFAULT_PAGE_SIZE = 50
  MAX_PAGE_SIZE = 100
  MAX_OPTION_PAGES = 5
  SCHEMA_PAGE_SIZE = 200
  MAX_SCHEMA_PAGES = 10
  MAX_DOWNLOAD_BYTES = 3_145_728
  UNSAFE_FILENAME_CHARACTERS = /["\x00-\x1F\x7F]/
  ATTACHMENT_TOO_LARGE = 'The file is over the attachment size limit of the site, or the issue has reached its ' \
                         'limit of attachments.'.freeze
  USER_SEARCH_LIMIT = 1000
  WORD_SEPARATOR = /[^[:alnum:]]+/
  NON_LETTER_MARK = /[\p{M}&&[^[:alnum:]]]/
  ACCENTED_LETTERS = 'àáâãäåāăąçćčďđèéêëēėęěğìíîïīįıłñńňòóôõöøōőŕřśšşťùúûüūůűųýÿźżž'.freeze
  PLAIN_LETTERS = 'aaaaaaaaacccddeeeeeeeegiiiiiiilnnnoooooooorrssstuuuuuuuuyyzzz'.freeze
  PRIORITY_HINT = 'Pick one, or give a priority name or ID. The list holds every priority of the site, and a ' \
                  'project whose priority scheme lacks the one given refuses it.'.freeze
  USER_PRODUCTS = %w[jira-core jira-servicedesk jira-product-discovery jira-software].freeze
  CREATE_USER_FORBIDDEN = 'The connection account must be an organization admin and have the Administer Jira ' \
                          'permission. Each new user takes a paid licence seat.'.freeze
  REST_METHODS = %w[GET POST PUT DELETE].freeze
  REST_BODY_METHODS = %w[POST PUT].freeze
  REST_PATH_PREFIX = %r{\A/rest/}
  UNSAFE_REST_PATH = %r{\.\.|//|\\|[?#@]|[^!-~]|%(?:2[EFef5]|5[Cc])|%(?![0-9A-Fa-f]{2})}
  DROPPED_REST_HEADERS = %w[authorization proxy-authorization cookie host].freeze
  SMALLEST_MILLISECOND_TIMESTAMP = 10_000_000_000
  MILLISECONDS_PER_SECOND = 1000
  MARKDOWN_BULLET = /\A- /
  MARKDOWN_EMPHASIS = /((?<![^\s(\["])(?:\*[^*\s](?:[^*]*[^*\s])?\*|_[^_\s](?:[^_]*[^_\s])?_)(?![^\s.,;:!?)\]"]))/
  MARKDOWN_MARKS = { '*' => 'strong', '_' => 'em' }.freeze
  ADF_INLINE_TYPES = %w[text hardBreak mention emoji status date inlineCard mediaInline placeholder].freeze
  ADF_LIST_TYPES = %w[bulletList orderedList].freeze
  WIKI_HEADING = /^h[1-6]\.\s*/
  WIKI_BLOCK_MACRO = /\{(?:code|noformat|quote|panel|color)(?::[^}]*)?\}/
  WIKI_MENTION = /\[~accountid:([^\]]+)\]/
  WIKI_LINK = /\[([^|\]]+)\|([^\]]+)\]/
  WIKI_BULLET = /^[*#-]+ /
  WIKI_BOLD = /(?<![[:alnum:]*])\*([^*\n]+)\*(?![[:alnum:]*])/
  WIKI_ITALIC = /(?<![[:alnum:]_])_([^_\n]+)_(?![[:alnum:]_])/
  PARAGRAPH_BREAK = "\n\n".freeze
  LINE_BREAK = "\n".freeze
  PROJECT_DEFAULT_ASSIGNEE = '-1'.freeze
  ALL_FIELDS = '*all'.freeze
  DEFAULT_SEARCH_FIELDS = ['*navigable'].freeze
  DEFAULT_ISSUE_FIELDS = %w[
    summary description status priority issuetype project assignee reporter
    created updated resolution resolutiondate labels components attachment comment
  ].freeze
  SEARCH_SUMMARY_FIELDS = %w[summary status priority assignee updated].freeze
  EXPANDED_ISSUE_PARTS = %w[
    renderedFields names schema transitions operations editmeta changelog versionedRepresentations
  ].freeze
  FIELD_VALUE_PARTS = %w[renderedFields versionedRepresentations].freeze
  ISSUE_FIELD_INPUTS = {
    summary: :summary,
    description: :description,
    description_adf: :description,
    assignee_account_id: :assignee,
    reporter_account_id: :reporter,
    priority: :priority,
    labels: :labels,
    components: :components,
    due_date: :duedate,
    parent_key: :parent,
  }.freeze
  CREATE_ISSUE_FIELDS = [:project, :issuetype].freeze
  CLEARABLE_ISSUE_INPUTS = [:description, :assignee_account_id, :priority, :labels, :components, :due_date].freeze
  LIST_ISSUE_INPUTS = [:labels, :components].freeze
  JQL_FILTERS = { issue_type: 'issuetype', status: 'status', assignee_account_id: 'assignee', label: 'labels' }.freeze
  JQL_DATE_BOUNDS = {
    created_after: 'created >=',
    created_before: 'created <',
    updated_after: 'updated >=',
    updated_before: 'updated <',
  }.freeze
  SEARCH_ORDER = 'ORDER BY updated DESC'.freeze
  ISSUE_EVENTS = [
    { id: 'jira:issue_created', label: 'Created' },
    { id: 'jira:issue_updated', label: 'Updated' },
  ].freeze
  COMMENT_EVENTS = [
    { id: 'comment_created', label: 'Created' },
    { id: 'comment_updated', label: 'Updated' },
  ].freeze
  STATUS_CATEGORY_NAMES = {
    'new' => 'To Do',
    'indeterminate' => 'In Progress',
    'done' => 'Done',
    'undefined' => 'No Category',
  }.freeze
  WEBHOOK_STORE_KEY = 'webhook'.freeze
  WEBHOOK_FILTER_KEY = 'issue-related-events-section'.freeze
  HTTPS_PREFIX = 'https://'.freeze
  WEBHOOK_MAX_AGE_SECONDS = 86_400
  WEBHOOK_REFUSED_STATUSES = [401, 403].freeze
  WEBHOOK_TOKEN_ADVICE = 'The API token is wrong, revoked or expired, or it is a scoped or service-account token: ' \
                         'Jira manages webhooks only for a classic API token of a user with the Administer Jira ' \
                         'permission.'.freeze
  EVENT_TEXT_TIMEOUT = 5
  DROPPED_EVENT_RETRY_AFTER = '60'.freeze
  PLATFORM_DROP = 'IPaaS::Job::DiscardTriggerEvent'.freeze
  TEXT_NOT_VISIBLE_STATUSES = [403, 404].freeze
  TEXT_NOT_VISIBLE = 'not_visible'.freeze
  TEXT_FETCH_FAILED = 'fetch_failed'.freeze
  COMMENT_FIELD = 'comment'.freeze
  POLL_MAX_PAGES = 5
  POLL_TIME_BUDGET_SECONDS = 20
  POLL_SEARCH_TIMEOUT = 30
  POLL_SETTLE_SECONDS = 300
  POLL_LOCK_KEY = 'poll'.freeze
  POLL_LOCK_TTL_SECONDS = 120
  POLL_CURSOR_STORE_KEY = 'poll_cursor'.freeze
  POLL_STAGED_STORE_KEY = 'poll_staged'.freeze
  POLL_MAX_UNSAVED_CHECKS = 3
  POLL_CURSOR_STARTED = 'The Jira trigger saved its starting point. The next check delivers issues from there.'.freeze
  POLL_SETUP_STORE_KEY = 'poll_setup'.freeze
  POLL_SETUP_GRACE_SECONDS = 60
  POLL_SETTINGS_CHANGED = 'The trigger settings changed less than a minute ago. ' \
                          'A later check uses the new settings.'.freeze
  SCHEDULE_STORE_KEY = 'schedule'.freeze
  SCHEDULE_FREQUENCY = 'minutely'.freeze
  SCHEDULE_TIME_ZONE = 'UTC'.freeze
  SCHEDULE_NOT_FOUND = 'Schedule not found'.freeze
  DEFAULT_POLL_MINUTES = 5
  SCHEDULER_PATH_PREFIX = '/inbound/'.freeze
  POLL_PREVIEW_PREFIX = 'preview-'.freeze

  connector '01a13f2d-b655-7332-952d-145b7c29f5c3' do
    name 'Jira Connector'
    avatar '/assets/icons/jira.svg'
    description <<~END_OF_DESCRIPTION
      Create, update, search and transition issues in Jira Cloud, manage their comments and attachments, look up and create users, read the fields an issue takes, call any Jira REST API path, and start runbooks the moment an issue or a comment is created or updated, or on a schedule with the issues created or changed since the last check.

      # Prerequisites

      * A Jira **Cloud** site. Jira Data Center, Jira Server and Jira Service Management are not supported: Data Center has a different API (no enhanced issue search, users named rather than account IDs, wiki markup instead of Atlassian Document Format) and needs a connector of its own.
      * An Atlassian API token of an account that has the Jira permissions the actions need. The real-time triggers also need a **classic** API token of a user with the Administer Jira permission. Every trigger needs the Browse Projects permission on the project it watches.

      # Authentication

      Uses the **Jira site** (for example acme.atlassian.net), the **Atlassian account email** and its **API token**. Create the token at id.atlassian.com under Security, then API tokens. A scoped token needs `read:jira-user` for the connection test, `read:jira-work` to check the default project or read the project list, and the scopes of the actions it runs.

      For automation that should not depend on one person, use a service account: give it access to the projects it works in, and enter its email and one of its API tokens. A service account has scoped tokens only, so it runs every action and the scheduled triggers, but not the real-time triggers, for which Jira accepts only a classic token.

      An API token expires 1 to 365 days after it is created. Replace it on the connection before that date.

      In a solution with more than one Jira connection, the triggers use the first one.

      # Rate limiting

      When Jira limits the request rate, an action waits as long as Jira asks and then tries again. The comment that Update Issue Status adds after the move is not tried again, and the triggers do not wait; their descriptions say what they do instead. When Jira is briefly unavailable or does not answer within 60 seconds, a read is tried again later and a write fails with a warning that the change may have been made, so a change is never made twice.

      # Known limitations

      * An issue search page token expires after 7 days.
      * Download Attachment and Execute Jira REST API Action refuse a file or a response over 10 MB.
      * The lists of projects, issue types and priorities to pick from stop at 500 entries. Type a project key or ID, or an issue type or priority name or ID, that is not listed. The triggers take an issue type ID only.
    END_OF_DESCRIPTION

    inbound_connection do
      validate do |_request|
        nil
      end
    end

    outbound_connection do
      config_schema do
        field :site, 'Jira site', :string,
              required: true,
              hint: 'The host of your Jira Cloud site, for example acme.atlassian.net.'
        field :email, 'Atlassian account email', :string,
              required: true,
              hint: 'The account the API token belongs to.'
        field :api_token, 'API token', :secret_string,
              required: true,
              hint: 'Create one at id.atlassian.com under Security, then API tokens.'
        field :default_project, 'Default project', :string,
              visibility: 'optional',
              hint: 'The connection test checks that the account can open this project. Save the site, ' \
                    'email and token first, then pick a project.' do
          options do
            helpers.fetch_project_options
          end
        end
      end

      authenticate do |request|
        email = config[:email].to_s.strip
        token = decrypt_secret_string(config[:api_token]).to_s.strip
        if email.blank? || token.blank?
          fail_job!('The Jira connection has no email or API token. Enter both on the connection.')
        end

        request.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{email}:#{token}")}"
        request.headers['Accept'] = 'application/json'
      end

      config_tester do
        host = helpers.site_host
        cloud_id = helpers.store_cloud_id(host)
        base = helpers.gateway_url(cloud_id, API_PATH)
        response = http_get("#{base}/myself", nil, nil, open_timeout: SHORT_OPEN_TIMEOUT, timeout: SHORT_TIMEOUT)
        next helpers.test_failure(response) unless helpers.success_status?(response.status)

        project_failure = helpers.default_project_failure(base)
        next project_failure if project_failure

        me = helpers.parse_jira_body(response)
        {
          status: :success,
          message: "Connected to Jira site #{host} as #{me[:displayName].presence || me[:accountId]} " \
                   "(account ID #{me[:accountId]}).",
        }
      end
    end

    helper :account_field do |target, field_id, label|
      target.field field_id, label, :nested do
        field :account_id, 'Account ID', :string
        field :display_name, 'Display name', :string
        field :email_address, 'Email address', :string
      end
    end

    helper :attachment_fields do |target|
      target.field :attachments, 'Attachments', :nested, array: true
      attachments = target.field(:attachments)
      attachments.field :attachment_id, 'Attachment ID', :string, required: true
      attachments.field :filename, 'File name', :string
      attachments.field :size, 'Size', :integer
      attachments.field :content_type, 'Content type', :string
      attachments.field :created, 'Created', :string
      helpers.account_field(attachments, :author, 'Author')
    end

    helper :issue_fields do |target, detail: false|
      target.field :issue_id, 'Issue ID', :string, required: true
      target.field :issue_key, 'Issue key', :string, required: true
      target.field :self, 'API URL', :string
      target.field :browse_url, 'Browse URL', :string
      target.field :summary, 'Summary', :string
      target.field :description, 'Description', :string
      target.field :status, 'Status', :string
      target.field :status_category, 'Status category', :string
      target.field :priority, 'Priority', :string
      target.field :issue_type, 'Issue type', :string
      target.field :issue_type_id, 'Issue type ID', :string
      target.field :project, 'Project key', :string
      helpers.account_field(target, :assignee, 'Assignee')
      helpers.account_field(target, :reporter, 'Reporter')
      target.field :created, 'Created', :string
      target.field :updated, 'Updated', :string
      target.field :resolution, 'Resolution', :string
      target.field :resolution_date, 'Resolution date', :string
      target.field :labels, 'Labels', :string, array: true
      target.field :components, 'Components', :nested, array: true do
        field :id, 'Component ID', :string
        field :name, 'Name', :string
      end
      helpers.attachment_fields(target)
      target.field :comment_count, 'Comment count', :integer if detail
      target.field :fields, 'Fields', :hash
      target.field :expanded, 'Expanded', :hash if detail
    end

    helper :comment_fields do |target|
      target.field :comment_id, 'Comment ID', :string, required: true
      target.field :self, 'API URL', :string
      target.field :comment_body, 'Comment body', :string, hint: 'The comment as plain text.'
      helpers.account_field(target, :author, 'Author')
      target.field :created, 'Created', :string
      target.field :updated, 'Updated', :string
      target.field :visibility, 'Visibility', :nested do
        field :type, 'Type', :string
        field :value, 'Value', :string
        field :identifier, 'Identifier', :string
      end
    end

    helper :changelog_item_fields do |target|
      target.field :field, 'Field', :string
      target.field :field_id, 'Field ID', :string
      target.field :from, 'Old ID', :string
      target.field :from_string, 'Old value', :string
      target.field :to, 'New ID', :string
      target.field :to_string, 'New value', :string
    end

    helper :user_fields do |target|
      target.field :account_id, 'Account ID', :string, required: true
      target.field :display_name, 'Display name', :string
      target.field :email_address, 'Email address', :string
      target.field :active, 'Active', :boolean
      target.field :account_type, 'Account type', :string
      target.field :time_zone, 'Time zone', :string
    end

    helper :paging_inputs do |target|
      target.field :page_size, 'Page size', :integer,
                   visibility: 'optional',
                   min: 1, max: MAX_PAGE_SIZE, default: DEFAULT_PAGE_SIZE
      target.field :page_token, 'Page token', :string,
                   visibility: 'optional',
                   hint: 'A Next page token from an earlier run. Empty starts at the first page.'
    end

    helper :paging_outputs do |target|
      target.field :next_page_token, 'Next page token', :string
      target.field :is_last, 'Is last page', :boolean, required: true
    end

    trigger '01a13f2d-b655-7c0d-be71-eec8ecb4ea91' do
      name 'New/Updated Issue (real-time)'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Starts the runbook the moment an issue is created or updated in one Jira project.

        Pick the **Project**, and an **Issue type** to watch only that type. **Fire on** picks new issues, changed issues, or both. Each run gets the issue and its fields, named as in Get Issue, plus **Changed fields**, which lists every field the event changed with its old and new value. Promoting fails when this account cannot open the project or the project has no such issue type.

        The **Description** is read from Jira as plain text when the event arrives, so a later edit can show in it, and **Fields** does not repeat it. Reading it needs the Browse Projects permission on the project. When the issue was deleted or the connection account cannot see it, Description is empty and **Text unavailable reason** is `not_visible`. When the read fails, for example because Jira limits the rate or the API token has expired, Description holds the text that came with the event, turned from Jira's wiki markup into plain text, and the reason is `fetch_failed`.

        Promoting the runbook registers a webhook in Jira, which needs a classic API token of a user with the Administer Jira permission: Jira refuses a scoped or service-account token for webhooks. A Jira site holds at most 100 webhooks. Each promote checks that the webhook is still enabled, signed, filtered on the project and sending the events picked to this trigger, and registers it again when it is not. When a promote changes the Project or the Issue type and Jira refuses the new webhook, the events of the old one are dropped until a promote succeeds. **Deprovision** (the pause button) deletes the webhook; deleting the trigger, the runbook or the solution does not, so delete such a webhook in Jira under System, WebHooks. The webhook does not expire. Jira signs each event, and an event without a valid signature, or sent more than a day ago, is dropped.

        When the **Concurrency limit** of the runbook drops an event because an earlier job still runs, iPaaS asks Jira to send it again, and Jira tries up to five more times over about an hour. The event is still lost when that earlier job runs for longer, when a promote with changed settings replaces the webhook, or when every delivery fails for 30 minutes, after which Jira tries each event only once; for long jobs use the concurrency limit None. Jira can also send the same event more than once, and iPaaS does not drop repeats. Every copy of one event has the same **Deduplication ID**, so a runbook that creates records or sends mail can skip a repeat.
      END_OF_DESCRIPTION
      outbound_traffic true

      config_schema do
        field :project_key, 'Project', :string,
              required: true,
              hint: 'The Jira project to watch.' do
          options do
            helpers.fetch_project_options
          end
        end
        field :issue_type, 'Issue type', :string,
              visibility: 'optional',
              hint: 'Empty watches every issue type.' do
          options do |project_key: nil|
            helpers.fetch_issue_type_options(project_key: project_key)
          end
        end
        field :fire_on, 'Fire on', :string,
              required: true,
              array: true,
              enumeration: ISSUE_EVENTS,
              default: ISSUE_EVENTS.pluck(:id)
      end

      output_schema do
        field :webhook_event, 'Event', :string, required: true, hint: 'jira:issue_created or jira:issue_updated.'
        field :issue_event_type_name, 'Event type', :string, hint: 'What changed, for example issue_assigned.'
        helpers.issue_fields(self)
        field :text_unavailable_reason, 'Text unavailable reason', :string,
              hint: 'not_visible when the account cannot see the description; fetch_failed when it could not be ' \
                    'read and comes from the event.'
        field :changelog, 'Changed fields', :nested, array: true
        helpers.changelog_item_fields(field(:changelog))
        helpers.account_field(self, :actor, 'Changed by')
        field :timestamp, 'Timestamp', :integer
      end

      provision do
        helpers.provision_webhook(ISSUE_EVENTS)
      end

      deprovision do
        helpers.remove_webhook
      end

      parse do |request|
        json = helpers.verified_delivery(request, ISSUE_EVENTS)
        issue = json[:issue].presence || {}
        self.job_context_identifier = issue[:key].presence || json[:timestamp].to_s
        description, reason = helpers.event_description(issue)
        helpers.payload_issue_output(issue).merge(
          helpers.delivery_output(request, json, issue[:id]),
          description: description,
          text_unavailable_reason: reason,
          issue_event_type_name: json[:issue_event_type_name],
          changelog: Array(json.dig(:changelog, :items)).map { |item| helpers.changelog_item_output(item) },
          actor: helpers.account_output(json[:user])
        )
      end

      respond_with do |context, response|
        helpers.resend_dropped_event(context, response)
      end
    end

    trigger '01a13f2d-b655-70c4-97fa-7c335f215c06' do
      name 'New/Updated Comment (real-time)'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Starts the runbook the moment a comment is added or edited on an issue in one Jira project.

        Pick the **Project**, and an **Issue type** to watch only issues of that type. **Fire on** picks new comments, edited comments, or both. Each run gets the comment with the same outputs as Create Comment, plus who last edited it, and the key, ID, summary, status, priority, type, project and assignee of its issue. Read the rest of the issue with Get Issue. Promoting fails when this account cannot open the project or the project has no such issue type.

        The **Comment body** is read from Jira as plain text when the event arrives, so a later edit can show in it. Reading it needs the Browse Projects permission on the project. When the comment was deleted or is limited to a role or group the connection account is not in, Comment body is empty and **Text unavailable reason** is `not_visible`. When the read fails, for example because Jira limits the rate or the API token has expired, Comment body holds the text that came with the event, turned from Jira's wiki markup into plain text, and the reason is `fetch_failed`.

        Promoting the runbook registers a webhook in Jira, which needs a classic API token of a user with the Administer Jira permission: Jira refuses a scoped or service-account token for webhooks. A Jira site holds at most 100 webhooks. Each promote checks that the webhook is still enabled, signed, filtered on the project and sending the events picked to this trigger, and registers it again when it is not. When a promote changes the Project or the Issue type and Jira refuses the new webhook, the events of the old one are dropped until a promote succeeds. **Deprovision** (the pause button) deletes the webhook; deleting the trigger, the runbook or the solution does not, so delete such a webhook in Jira under System, WebHooks. The webhook does not expire. Jira signs each event, and an event without a valid signature, or sent more than a day ago, is dropped.

        When the **Concurrency limit** of the runbook drops an event because an earlier job still runs, iPaaS asks Jira to send it again, and Jira tries up to five more times over about an hour. The event is still lost when that earlier job runs for longer, when a promote with changed settings replaces the webhook, or when every delivery fails for 30 minutes, after which Jira tries each event only once; for long jobs use the concurrency limit None. Jira can also send the same event more than once, and iPaaS does not drop repeats. Every copy of one event has the same **Deduplication ID**, so a runbook that creates records or sends mail can skip a repeat.
      END_OF_DESCRIPTION
      outbound_traffic true

      config_schema do
        field :project_key, 'Project', :string,
              required: true,
              hint: 'The Jira project to watch.' do
          options do
            helpers.fetch_project_options
          end
        end
        field :issue_type, 'Issue type', :string,
              visibility: 'optional',
              hint: 'Empty watches the comments on every issue type.' do
          options do |project_key: nil|
            helpers.fetch_issue_type_options(project_key: project_key)
          end
        end
        field :fire_on, 'Fire on', :string,
              required: true,
              array: true,
              enumeration: COMMENT_EVENTS,
              default: COMMENT_EVENTS.pluck(:id)
      end

      output_schema do
        field :webhook_event, 'Event', :string, required: true, hint: 'comment_created or comment_updated.'
        helpers.comment_fields(self)
        field :text_unavailable_reason, 'Text unavailable reason', :string,
              hint: 'not_visible when the account cannot see the comment; fetch_failed when it could not be read ' \
                    'and comes from the event.'
        helpers.account_field(self, :update_author, 'Last edited by')
        field :issue_id, 'Issue ID', :string, required: true
        field :issue_key, 'Issue key', :string, required: true
        field :browse_url, 'Browse URL', :string
        field :summary, 'Summary', :string
        field :status, 'Status', :string
        field :priority, 'Priority', :string
        field :issue_type, 'Issue type', :string
        field :project, 'Project key', :string
        helpers.account_field(self, :assignee, 'Assignee')
        field :timestamp, 'Timestamp', :integer
      end

      provision do
        helpers.provision_webhook(COMMENT_EVENTS)
      end

      deprovision do
        helpers.remove_webhook
      end

      parse do |request|
        json = helpers.verified_delivery(request, COMMENT_EVENTS)
        issue = json[:issue].presence || {}
        comment = json[:comment].presence || {}
        self.job_context_identifier = issue[:key].presence || json[:timestamp].to_s
        fields = issue[:fields].presence || {}
        helpers.issue_summary_output(issue).merge(
          helpers.event_comment(issue, comment),
          helpers.delivery_output(request, json, comment[:id]),
          issue_type: fields.dig(:issuetype, :name),
          project: fields.dig(:project, :key)
        )
      end

      respond_with do |context, response|
        helpers.resend_dropped_event(context, response)
      end
    end

    trigger '01a13f2d-b655-7530-856c-b254c3d964f4' do
      name 'New Issue'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Starts the runbook on a schedule with the issues created in one Jira project since the last check. One run gets all the new issues that one check finds, and a check that finds none starts nothing.

        Pick the **Project**, an **Issue type** to watch only that type, and the minutes between two checks under **Check every (minutes)**. Each issue in **Issues** has the outputs of Get Issue except **Comment count** and **Expanded**, and its **Fields** leave out the description. Read other fields with Get Issue. Promoting fails when this account cannot open the project or the project has no such issue type, because Jira's search answers such a filter with no issues instead of an error.

        Jira search can take minutes to show a new issue, so a check looks only at issues created more than five minutes ago. One check reads up to 500 issues, and the next check goes on from there. When Jira limits the rate or is briefly unavailable, the check does not wait: it delivers the issues it already read, or starts nothing, and the next check reads the rest. The trigger keeps its place when the runbook is promoted again. A changed project or issue type starts it again from five minutes before the promotion. When it takes over from a real-time Jira trigger it starts at the promotion, and when a real-time trigger takes over from it, the issues of the last five minutes before that promotion are not delivered.

        Reading the issues needs the Browse Projects permission on the project. The trigger moves on only once iPaaS has started the job, so the issues of a check that the **Concurrency limit** of the runbook drops come again with a later check. When the issues of one check cannot be delivered in three checks in a row, the trigger logs their keys and goes on after them. A designer run shows the issues that the next check would find, and the next check still delivers them.

        **Deprovision** (the pause button) stops the checks. Deleting or replacing the trigger leaves its schedule running, and each check then fails, so deprovision first. Deleting the runbook stops the checks at once, even when only its Draft is deleted, until the next promote.
      END_OF_DESCRIPTION
      outbound_traffic true
      internal_only true

      config_schema do
        field :project_key, 'Project', :string,
              required: true,
              hint: 'The Jira project to watch.' do
          options do
            helpers.fetch_project_options
          end
        end
        field :issue_type, 'Issue type', :string,
              visibility: 'optional',
              hint: 'Empty watches every issue type.' do
          options do |project_key: nil|
            helpers.fetch_issue_type_options(project_key: project_key)
          end
        end
        field :poll_minutes, 'Check every (minutes)', :integer,
              required: true,
              min: 1,
              default: DEFAULT_POLL_MINUTES
      end

      output_schema do
        field :issues, 'Issues', :nested, array: true
        helpers.issue_fields(field(:issues))
      end

      provision do
        helpers.provision_poll('created')
      end

      deprovision do
        helpers.remove_poll_schedule
      end

      parse do |request|
        output = helpers.poll_issues(request, 'created')
        self.job_context_identifier = output[:deduplication_id]
        output
      end

      respond_with do |context, response|
        helpers.settle_staged_poll(context)
        response
      end
    end

    trigger '01a13f2d-b655-7516-8277-0b0b29316e63' do
      name 'Updated Issue'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Starts the runbook on a schedule with the issues changed in one Jira project since the last check. One run gets all the changed issues that one check finds, and a check that finds none starts nothing. A new issue counts as changed. An issue changed several times between two checks comes once.

        Pick the **Project**, an **Issue type** to watch only that type, and the minutes between two checks under **Check every (minutes)**. Each issue in **Issues** has the outputs of Get Issue except **Comment count** and **Expanded**, and its **Fields** leave out the description. Read other fields with Get Issue. Promoting fails when this account cannot open the project or the project has no such issue type, because Jira's search answers such a filter with no issues instead of an error.

        Jira search can take minutes to show a change, so a check looks only at issues changed more than five minutes ago. One check reads up to 500 issues, and the next check goes on from there. When Jira limits the rate or is briefly unavailable, the check does not wait: it delivers the issues it already read, or starts nothing, and the next check reads the rest. The trigger keeps its place when the runbook is promoted again. A changed project or issue type starts it again from five minutes before the promotion. When it takes over from a real-time Jira trigger it starts at the promotion, and when a real-time trigger takes over from it, the issues of the last five minutes before that promotion are not delivered.

        Reading the issues needs the Browse Projects permission on the project. The trigger moves on only once iPaaS has started the job, so the issues of a check that the **Concurrency limit** of the runbook drops come again with a later check. When the issues of one check cannot be delivered in three checks in a row, the trigger logs their keys and goes on after them. A designer run shows the issues that the next check would find, and the next check still delivers them.

        **Deprovision** (the pause button) stops the checks. Deleting or replacing the trigger leaves its schedule running, and each check then fails, so deprovision first. Deleting the runbook stops the checks at once, even when only its Draft is deleted, until the next promote.
      END_OF_DESCRIPTION
      outbound_traffic true
      internal_only true

      config_schema do
        field :project_key, 'Project', :string,
              required: true,
              hint: 'The Jira project to watch.' do
          options do
            helpers.fetch_project_options
          end
        end
        field :issue_type, 'Issue type', :string,
              visibility: 'optional',
              hint: 'Empty watches every issue type.' do
          options do |project_key: nil|
            helpers.fetch_issue_type_options(project_key: project_key)
          end
        end
        field :poll_minutes, 'Check every (minutes)', :integer,
              required: true,
              min: 1,
              default: DEFAULT_POLL_MINUTES
      end

      output_schema do
        field :issues, 'Issues', :nested, array: true
        helpers.issue_fields(field(:issues))
      end

      provision do
        helpers.provision_poll('updated')
      end

      deprovision do
        helpers.remove_poll_schedule
      end

      parse do |request|
        output = helpers.poll_issues(request, 'updated')
        self.job_context_identifier = output[:deduplication_id]
        output
      end

      respond_with do |context, response|
        helpers.settle_staged_poll(context)
        response
      end
    end

    action '01a13f2d-b655-77ed-8ce9-829f4c4eea1d' do
      name 'Create Issue'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Creates an issue in a Jira project.

        Pick the project and the issue type from the lists, or map a project key and an issue type name or ID. When Project is empty, the Default project of the connection is used.

        In **Description**, a blank line starts a new paragraph, `*bold*` and `_italic_` are formatted, and lines starting with "- " become a bulleted list. Use **Description (ADF)** for richer content.

        Put any other field in **Additional fields**, keyed by field ID, for example `{"customfield_10234": "value"}`. Custom field IDs differ per Jira site; **Get Issue Schema** shows them.

        Jira returns only the ID, key and API URL of the new issue. The browse URL is built from the site and the key.
      END_OF_DESCRIPTION

      input_schema do
        field :project_key, 'Project', :string,
              hint: 'Empty uses the Default project of the connection.' do
          options do
            helpers.fetch_project_options
          end
        end
        field :issue_type, 'Issue type', :string,
              required: true,
              hint: 'Pick one, or give an issue type name such as Task, or its ID.' do
          options do |project_key: nil|
            helpers.fetch_issue_type_options(project_key: project_key)
          end
        end
        field :summary, 'Summary', :string, required: true
        field :description, 'Description', :string,
              visibility: 'optional',
              hint: 'Plain text. A blank line starts a paragraph, *bold*, _italic_ and lines starting ' \
                    'with "- " are formatted.'
        field :description_adf, 'Description (ADF)', :hash,
              visibility: 'optional',
              hint: 'A pre-built Atlassian Document Format object. Takes precedence over Description.'
        field :priority, 'Priority', :string, visibility: 'optional', hint: PRIORITY_HINT do
          options do
            helpers.fetch_priority_options
          end
        end
        field :assignee_account_id, 'Assignee account ID', :string,
              visibility: 'optional',
              hint: 'Jira Cloud identifies users by account ID, not by name or email.'
        field :reporter_account_id, 'Reporter account ID', :string, visibility: 'optional'
        field :labels, 'Labels', :string, array: true, visibility: 'optional'
        field :components, 'Components', :string, array: true, visibility: 'optional', hint: 'Component names.'
        field :due_date, 'Due date', :date, visibility: 'optional'
        field :parent_key, 'Parent issue key', :string,
              visibility: 'optional',
              hint: 'Required by Jira for a sub-task.'
        field :additional_fields, 'Additional fields', :hash,
              visibility: 'optional',
              hint: 'Other fields keyed by field ID, for example {"customfield_10234": "value"}.'
      end

      output_schema do
        field :issue_id, 'Issue ID', :string, required: true
        field :issue_key, 'Issue key', :string, required: true
        field :self, 'API URL', :string
        field :browse_url, 'Browse URL', :string
      end

      run do
        fields = helpers.issue_fields_payload(input, set_by_action: CREATE_ISSUE_FIELDS)
        fields[:project] = helpers.id_or_name_reference(helpers.project_key_or_default(input[:project_key]), :key)
        fields[:issuetype] = helpers.id_or_name_reference(input[:issue_type])
        result = helpers.jira_post('issue', { fields: fields }, permission: 'Create Issues')
        [{ output: {
          issue_id: result[:id],
          issue_key: result[:key],
          self: result[:self],
          browse_url: helpers.browse_url(result[:key]),
        } }]
      end
    end

    action '01a13f2d-b655-7acd-872d-e5582b5e3d4d' do
      name 'Update Issue'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Changes fields on an existing issue.

        Only the fields you map are sent, and the fields you leave unmapped stay as they are. A mapped Description, Assignee account ID, Priority, Labels, Components or Due date that is empty clears that field. Labels and Components replace the whole list.

        Description is formatted the same way as in Create Issue. Put any other field in **Additional fields**, keyed by field ID.

        Jira refuses a field the account may not edit, or one that does not belong to the project and issue type, and names it in the error. Jira returns no issue, so read the new state with Get Issue.
      END_OF_DESCRIPTION

      input_schema do
        field :issue_id_or_key, 'Issue ID or key', :string, required: true
        field :summary, 'Summary', :string, visibility: 'optional'
        field :description, 'Description', :string, visibility: 'optional'
        field :description_adf, 'Description (ADF)', :hash, visibility: 'optional'
        field :priority, 'Priority', :string, visibility: 'optional', hint: PRIORITY_HINT do
          options do
            helpers.fetch_priority_options
          end
        end
        field :assignee_account_id, 'Assignee account ID', :string, visibility: 'optional'
        field :reporter_account_id, 'Reporter account ID', :string, visibility: 'optional'
        field :labels, 'Labels', :string, array: true, visibility: 'optional'
        field :components, 'Components', :string, array: true, visibility: 'optional'
        field :due_date, 'Due date', :date, visibility: 'optional'
        field :additional_fields, 'Additional fields', :hash, visibility: 'optional'
      end

      output_schema do
        field :issue_key, 'Issue key', :string, hint: 'Empty when the issue was given by its ID.'
        field :issue_id, 'Issue ID', :string, hint: 'Empty when the issue was given by its key.'
        field :updated, 'Updated', :boolean, required: true
      end

      run do
        fields = helpers.issue_fields_payload(input, clear_blank: true)
        fail_job!('Update Issue was given no fields to change.') if fields.empty?

        issue = helpers.safe_id(input[:issue_id_or_key], 'issue_id_or_key')
        helpers.jira_put("issue/#{issue}", { fields: fields }, permission: 'Edit Issues', resource: "Issue #{issue}")
        [{ output: helpers.issue_reference_output(issue).merge(updated: true) }]
      end
    end

    action '01a13f2d-b655-774a-9dc7-9000aa60a67c' do
      name 'Update Issue Status'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Moves an issue to another status through one of its workflow transitions.

        Pick the transition from the list, which needs an issue key typed into **Issue ID or key** and shows the transitions open to that issue now. Or give a transition ID or name. A name is matched without regard to case, and a name that matches no open transition fails with the list of the open ones. Transition IDs differ between workflows, so a runbook that has to travel gives the transition name.

        A transition with a screen can require fields, for example a resolution. Supply them in **Fields**, keyed by field ID.

        A **Comment** is added after the move and needs the Add Comments permission. When Jira does not add it, the job fails and the issue keeps its new status.
      END_OF_DESCRIPTION

      input_schema do
        field :issue_id_or_key, 'Issue ID or key', :string, required: true
        field :transition, 'Transition', :string,
              required: true,
              hint: 'Pick one, or give a transition ID or name.' do
          options do |issue_id_or_key:|
            helpers.fetch_transition_options(issue_id_or_key: issue_id_or_key)
          end
        end
        field :fields, 'Fields', :hash,
              visibility: 'optional',
              hint: 'Values the transition screen needs, keyed by field ID, for example ' \
                    '{"resolution": {"name": "Done"}}.'
        field :comment, 'Comment', :string,
              visibility: 'optional',
              hint: 'Added to the issue after the move. Formatted the same way as a comment body.'
      end

      output_schema do
        field :issue_key, 'Issue key', :string, hint: 'Empty when the issue was given by its ID.'
        field :issue_id, 'Issue ID', :string, hint: 'Empty when the issue was given by its key.'
        field :transition_id, 'Transition ID', :string, required: true
        field :transitioned, 'Transitioned', :boolean, required: true
      end

      run do
        issue = helpers.safe_id(input[:issue_id_or_key], 'issue_id_or_key')
        transition_id = helpers.resolve_transition_id(issue, input[:transition])

        body = { transition: { id: transition_id } }
        body[:fields] = input[:fields] if input[:fields].present?
        helpers.jira_post("issue/#{issue}/transitions", body,
                          permission: 'Transition Issues', resource: "Issue #{issue}")
        helpers.add_transition_comment(issue, transition_id, input[:comment]) if input[:comment].present?
        [{ output: helpers.issue_reference_output(issue).merge(transition_id: transition_id, transitioned: true) }]
      end
    end

    action '01a13f2d-b655-7749-8870-fea1abc5bdc9' do
      name 'Assign User to Issue'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Sets the assignee of an issue, replacing the one it had.

        Give the account ID of a user who can be assigned issues in the project. Jira Cloud identifies users by account ID, not by name or email. The value `-1` hands the issue to the default assignee of the project, which can be nobody.

        Turn on **Unassign** to remove the assignee.
      END_OF_DESCRIPTION

      input_schema do
        field :issue_id_or_key, 'Issue ID or key', :string, required: true
        field :account_id, 'Assignee account ID', :string,
              hint: 'Required unless Unassign is on. -1 means the default assignee of the project.'
        field :unassign, 'Unassign', :boolean,
              visibility: 'optional',
              default: false,
              hint: 'Removes the assignee. Assignee account ID is ignored.'
      end

      output_schema do
        field :issue_key, 'Issue key', :string, hint: 'Empty when the issue was given by its ID.'
        field :issue_id, 'Issue ID', :string, hint: 'Empty when the issue was given by its key.'
        field :account_id, 'Assignee account ID', :string
        field :unassigned, 'Unassigned', :boolean, required: true
        field :to_project_default, 'Sent to the project default assignee', :boolean, required: true
      end

      run do
        unassign = input[:unassign] == true
        account_id = unassign ? nil : input[:account_id].to_s.strip.presence
        if account_id.nil? && !unassign
          fail_job!('Assign User to Issue needs an assignee account ID. Turn on Unassign to remove the assignee.')
        end

        issue = helpers.safe_id(input[:issue_id_or_key], 'issue_id_or_key')
        named_account = account_id.present? && account_id != PROJECT_DEFAULT_ASSIGNEE
        helpers.jira_put("issue/#{issue}/assignee", { accountId: account_id },
                         permission: 'Assign Issues',
                         resource: named_account ? "Issue #{issue} or account #{account_id}" : "Issue #{issue}")
        [{ output: helpers.issue_reference_output(issue).merge(
          account_id: account_id,
          unassigned: unassign,
          to_project_default: account_id == PROJECT_DEFAULT_ASSIGNEE
        ) }]
      end
    end

    action '01a13f2d-b655-7009-a59c-1550a7382d9d' do
      name 'Get Issue'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Reads one issue by its key or ID.

        By default it reads the summary, description, status, priority, issue type, project, assignee, reporter, dates, labels, components, attachments and the number of comments. Name other fields in **Fields**, or turn on **All fields**. The **Fields** output holds every field that was read except the comments, so a custom field is in it only when **Fields** names it or **All fields** is on. Read the comments with Get Issue Comments.

        The description comes back as plain text. **Expand** asks Jira for more, for example `renderedFields` or `changelog`, and the result is in the **Expanded** output.

        Moving an issue to another project changes its key and keeps its ID.
      END_OF_DESCRIPTION

      input_schema do
        field :issue_id_or_key, 'Issue ID or key', :string, required: true
        field :fields, 'Fields', :string,
              array: true,
              visibility: 'optional',
              hint: 'Field IDs to read instead of the default set, for example customfield_10234.'
        field :all_fields, 'All fields', :boolean, visibility: 'optional', default: false
        field :expand, 'Expand', :string,
              array: true,
              visibility: 'optional',
              hint: 'For example renderedFields, changelog, transitions.'
      end

      output_schema do
        helpers.issue_fields(self, detail: true)
      end

      run do
        issue = helpers.safe_id(input[:issue_id_or_key], 'issue_id_or_key')
        params = {
          fields: helpers.requested_fields(input, DEFAULT_ISSUE_FIELDS).join(','),
          expand: helpers.requested_expand(input),
        }
        result = helpers.jira_get("issue/#{issue}", params, permission: 'Browse Projects', resource: "Issue #{issue}")
        [{ output: helpers.issue_output(result) }]
      end
    end

    action '01a13f2d-b655-71bd-ae40-093304bf2ade' do
      name 'Search Issues'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Finds the issues of one project that match the filters you fill, most recently updated first, one page per run. No JQL is needed.

        An issue must match every filter you fill, and an empty filter narrows nothing. When Project is empty, the Default project of the connection is used.

        Each issue comes with its key, ID, summary, status, priority, assignee and last update. Read the rest with Get Issue. The **JQL** output shows the query that ran, which Search Issues by JQL can take further.

        Steps inside this step run once per page. To go on in a later run, map **Next page token** into **Page token**. A page token expires after 7 days. Jira can take a few seconds to find an issue that just changed.
      END_OF_DESCRIPTION
      nested true

      input_schema do
        field :project_key, 'Project', :string,
              hint: 'Empty uses the Default project of the connection.' do
          options do
            helpers.fetch_project_options
          end
        end
        field :issue_type, 'Issue type', :string, visibility: 'optional' do
          options do |project_key: nil|
            helpers.fetch_issue_type_options(project_key: project_key)
          end
        end
        field :status, 'Status', :string, visibility: 'optional', hint: 'Status name or ID, for example In Progress.'
        field :assignee_account_id, 'Assignee account ID', :string, visibility: 'optional'
        field :label, 'Label', :string, visibility: 'optional'
        field :created_after, 'Created after', :date_time, visibility: 'optional'
        field :created_before, 'Created before', :date_time, visibility: 'optional'
        field :updated_after, 'Updated after', :date_time, visibility: 'optional'
        field :updated_before, 'Updated before', :date_time, visibility: 'optional'
        helpers.paging_inputs(self)
      end

      output_schema 'page' do
        field :issues, 'Issues', :nested, array: true
        issues = field(:issues)
        issues.field :issue_id, 'Issue ID', :string, required: true
        issues.field :issue_key, 'Issue key', :string, required: true
        issues.field :browse_url, 'Browse URL', :string
        issues.field :summary, 'Summary', :string
        issues.field :status, 'Status', :string
        issues.field :priority, 'Priority', :string
        helpers.account_field(issues, :assignee, 'Assignee')
        issues.field :updated, 'Updated', :string
        field :jql, 'JQL', :string
        helpers.paging_outputs(self)
      end

      iteration_state_schema do
        field :page_token, 'Page token', :string
      end

      run do
        jql = helpers.structured_jql(input)
        result, paging = helpers.search_page({ jql: jql, maxResults: helpers.requested_page_size,
                                               fields: SEARCH_SUMMARY_FIELDS, })
        page = { issues: Array(result[:issues]).map { |issue| helpers.issue_summary_output(issue) }, jql: jql }
        [{ output: page.merge(paging), schema_reference: 'page' }]
      end
    end

    action '01a13f2d-b655-736a-8fe6-443987c6ea2e' do
      name 'Search Issues by JQL'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Finds issues with a JQL query, one page per run.

        The query needs at least one restriction, such as `project = KAN`, because Jira refuses a query without one. Each issue comes with the same outputs as Get Issue. **Fields** and **All fields** work as in Get Issue, and the default is the fields Jira shows in its issue list.

        Steps inside this step run once per page. To go on in a later run, map **Next page token** into **Page token**. A page token expires after 7 days. Jira does not report how many issues match.

        Jira can take a few seconds to find an issue that just changed. To read back an issue you just wrote, use Get Issue.
      END_OF_DESCRIPTION
      nested true

      input_schema do
        field :jql, 'JQL', :string,
              required: true,
              hint: 'For example: project = KAN AND status != Done ORDER BY created DESC'
        field :fields, 'Fields', :string,
              array: true,
              visibility: 'optional',
              hint: 'Field IDs to read. Defaults to the fields of the issue list.'
        field :all_fields, 'All fields', :boolean, visibility: 'optional', default: false
        field :expand, 'Expand', :string,
              array: true,
              visibility: 'optional',
              hint: 'For example names, schema or changelog. With changelog, Jira returns at most 40 changes per ' \
                    'issue; Get Changelog of an Issue returns them all.'
        helpers.paging_inputs(self)
      end

      output_schema 'page' do
        field :issues, 'Issues', :nested, array: true
        helpers.issue_fields(field(:issues), detail: true)
        field :expanded, 'Expanded', :hash, hint: 'Field names and schemas, when Expand asks for them.'
        helpers.paging_outputs(self)
      end

      iteration_state_schema do
        field :page_token, 'Page token', :string
      end

      run do
        body = {
          jql: input[:jql].to_s.strip,
          maxResults: helpers.requested_page_size,
          fields: helpers.requested_fields(input, DEFAULT_SEARCH_FIELDS),
          expand: helpers.requested_expand(input),
        }
        result, paging = helpers.search_page(body.compact)
        page = {
          issues: Array(result[:issues]).map { |issue| helpers.issue_output(issue) },
          expanded: result.slice(:names, :schema).presence,
        }
        [{ output: page.merge(paging), schema_reference: 'page' }]
      end
    end

    action '01a13f2d-b655-7c06-b0d0-33b304241bc9' do
      name 'Get Changelog of an Issue'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Lists the change history of an issue, oldest first, one page per run.

        Each entry says who made the change, when, and which fields changed, with the old and the new value as Jira shows them. Where a field holds an ID, such as a status or a user, the old and new IDs come too.

        Steps inside this step run once per page. To go on in a later run, map **Next page token** into **Page token**.
      END_OF_DESCRIPTION
      nested true

      input_schema do
        field :issue_id_or_key, 'Issue ID or key', :string, required: true
        helpers.paging_inputs(self)
      end

      output_schema 'page' do
        field :entries, 'Entries', :nested, array: true
        entries = field(:entries)
        entries.field :id, 'Entry ID', :string, required: true
        helpers.account_field(entries, :author, 'Author')
        entries.field :created, 'Created', :string
        entries.field :items, 'Changed fields', :nested, array: true
        helpers.changelog_item_fields(entries.field(:items))
        helpers.paging_outputs(self)
      end

      iteration_state_schema do
        field :page_token, 'Page token', :string
      end

      run do
        issue = helpers.safe_id(input[:issue_id_or_key], 'issue_id_or_key')
        entries, paging = helpers.offset_page("issue/#{issue}/changelog", {}, :values, "Issue #{issue}")
        page = { entries: entries.map { |entry| helpers.changelog_output(entry) } }
        [{ output: page.merge(paging), schema_reference: 'page' }]
      end
    end

    action '01a13f2d-b655-7b6d-89bb-38d0d9057f81' do
      name 'Create Comment'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Adds a comment to an issue.

        In **Body**, a blank line starts a new paragraph, `*bold*` and `_italic_` are formatted, and lines starting with "- " become a bulleted list. Use **Body (ADF)** instead for links, mentions or other rich content.

        **Visibility type** and **Visibility value** limit the comment to a project role or a group. Give both, or neither for a comment that everyone who can see the issue can read.
      END_OF_DESCRIPTION

      input_schema do
        field :issue_id_or_key, 'Issue ID or key', :string, required: true
        field :body, 'Body', :string,
              visibility: 'optional',
              hint: 'Plain text. A blank line starts a paragraph, *bold*, _italic_ and lines starting ' \
                    'with "- " are formatted.'
        field :body_adf, 'Body (ADF)', :hash,
              visibility: 'optional',
              hint: 'A pre-built Atlassian Document Format object. Takes precedence over Body.'
        field :visibility_type, 'Visibility type', :string,
              visibility: 'optional',
              enumeration: %w[role group]
        field :visibility_value, 'Visibility value', :string,
              visibility: 'optional',
              hint: 'The role or group name, for example Administrators.'
      end

      output_schema do
        helpers.comment_fields(self)
      end

      run do
        body = helpers.comment_payload(input)
        issue = helpers.safe_id(input[:issue_id_or_key], 'issue_id_or_key')
        result = helpers.jira_post("issue/#{issue}/comment", body,
                                   permission: 'Add Comments', resource: "Issue #{issue}")
        [{ output: helpers.comment_output(result) }]
      end
    end

    action '01a13f2d-b655-732a-bfcf-6437a2df8179' do
      name 'Update Comment'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Replaces the body of an existing comment.

        The comment keeps its author, and keeps its visibility unless you give a new one. Editing the comment of another user needs the Edit All Comments permission; Edit Own Comments covers only the comments of the connection account.
      END_OF_DESCRIPTION

      input_schema do
        field :issue_id_or_key, 'Issue ID or key', :string, required: true
        field :comment_id, 'Comment ID', :string, required: true
        field :body, 'Body', :string, visibility: 'optional'
        field :body_adf, 'Body (ADF)', :hash, visibility: 'optional'
        field :visibility_type, 'Visibility type', :string,
              visibility: 'optional',
              enumeration: %w[role group]
        field :visibility_value, 'Visibility value', :string, visibility: 'optional'
      end

      output_schema do
        helpers.comment_fields(self)
      end

      run do
        body = helpers.comment_payload(input)
        issue = helpers.safe_id(input[:issue_id_or_key], 'issue_id_or_key')
        comment = helpers.safe_id(input[:comment_id], 'comment_id')
        path = "issue/#{issue}/comment/#{comment}"
        response = helpers.jira_write(:put, helpers.jira_url(path), body)
        result = helpers.handle_jira_response(response, write: true,
                                                        permission: helpers.comment_edit_permission(path, response),
                                                        resource: "Comment #{comment} on issue #{issue}")
        [{ output: helpers.comment_output(result) }]
      end
    end

    action '01a13f2d-b655-787a-a7b3-e1a913b9af22' do
      name 'List Transitions'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Lists the workflow transitions open to an issue right now.

        Transition IDs differ between workflows, so they cannot be fixed in a runbook that has to travel. Use this action to look one up by name, then give its ID to Update Issue Status.

        Only the transitions open from the current status of the issue are returned. Includes target status details and transition screen fields. Screen fields are also returned by field ID so their values can be passed to Update Issue Status.
      END_OF_DESCRIPTION

      input_schema do
        field :issue_id_or_key, 'Issue ID or key', :string, required: true
      end

      output_schema do
        field :transitions, 'Transitions', :nested, array: true do
          field :transition_id, 'Transition ID', :string, required: true
          field :name, 'Name', :string
          field :to_status_id, 'Target status ID', :string
          field :to_status_name, 'Target status', :string
          field :has_screen, 'Has screen', :boolean
          field :is_available, 'Is available', :boolean
          field :to_status, 'Target status details', :nested do
            field :id, 'Status ID', :string
            field :name, 'Status name', :string
            field :description, 'Description', :string
            field :icon_url, 'Icon URL', :string
            field :self, 'API URL', :string
            field :status_category, 'Status category', :nested do
              field :color_name, 'Color name', :string
              field :id, 'Category ID', :integer
              field :key, 'Category key', :string
              field :name, 'Category name', :string
              field :self, 'API URL', :string
            end
          end
          field :is_conditional, 'Is conditional', :boolean
          field :is_global, 'Is global', :boolean
          field :is_initial, 'Is initial', :boolean
          field :fields, 'Transition screen fields by ID', :hash,
                hint: 'The unmodified Jira field metadata, keyed by field ID.'
          field :screen_fields, 'Transition screen field details', :nested, array: true do
            field :field_id, 'Field ID', :string, required: true
            field :key, 'Field key', :string
            field :name, 'Field name', :string
            field :required, 'Required', :boolean
            field :has_default_value, 'Has default value', :boolean
            field :default_value, 'Default value', :any_value_type
            field :allowed_values, 'Allowed values', :any_value_type,
                  hint: 'Jira may return strings, objects, or other JSON values.'
            field :operations, 'Operations', :string, array: true
            field :schema, 'Field schema', :nested do
              field :type, 'Type', :string
              field :items, 'Item type', :string
              field :custom, 'Custom field type', :string
              field :custom_id, 'Custom field ID', :integer
              field :system, 'System field', :string
            end
          end
        end
      end

      run do
        issue = helpers.safe_id(input[:issue_id_or_key], 'issue_id_or_key')
        transitions = helpers.available_transitions(issue, expand_fields: true)
        [{ output: { transitions: transitions.map { |transition| helpers.transition_output(transition) } } }]
      end
    end

    action '01a13f2d-b655-75db-a5f2-3059c5573d6c' do
      name 'Get Issue Comments'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Lists the comments of an issue, oldest first unless **Order by** says otherwise, one page per run.

        Each body comes as plain text. A comment limited to a role or a group is listed only when the connection account belongs to it.

        Steps inside this step run once per page. To go on in a later run, map **Next page token** into **Page token**.
      END_OF_DESCRIPTION
      nested true

      input_schema do
        field :issue_id_or_key, 'Issue ID or key', :string, required: true
        field :order_by, 'Order by', :string,
              visibility: 'optional',
              enumeration: %w[created -created +created],
              hint: 'created or +created is oldest first, -created is newest first.'
        helpers.paging_inputs(self)
      end

      output_schema 'page' do
        field :comments, 'Comments', :nested, array: true
        helpers.comment_fields(field(:comments))
        helpers.paging_outputs(self)
      end

      iteration_state_schema do
        field :page_token, 'Page token', :string
      end

      run do
        issue = helpers.safe_id(input[:issue_id_or_key], 'issue_id_or_key')
        comments, paging = helpers.offset_page("issue/#{issue}/comment", { orderBy: input[:order_by].presence },
                                               :comments, "Issue #{issue}")
        page = { comments: comments.map { |comment| helpers.comment_output(comment) } }
        [{ output: page.merge(paging), schema_reference: 'page' }]
      end
    end

    action '01a13f2d-b655-72af-bb3b-2f4cbb96b4fb' do
      name 'Upload Attachment'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Attaches one file to an issue.

        **File name**, **Content** and **Content type** take the outputs of Download Attachment as they are, so a file can be copied from one issue to another.

        Before it sends the file, the action checks that the Jira site accepts attachments and that the file fits the size limit of the site. A double quote or a control character in the file name becomes `_`, which is how Jira stores such a name.
      END_OF_DESCRIPTION

      input_schema do
        field :issue_id_or_key, 'Issue ID or key', :string, required: true
        field :filename, 'File name', :string,
              required: true,
              hint: 'Include the extension, for example report.csv.'
        field :content_bytes, 'Content', :base64, hint: 'The file as base64 text. An empty text uploads an empty file.'
        field :content_type, 'Content type', :string,
              visibility: 'optional',
              hint: 'Detected from the file name when empty, for pdf, png, jpg, gif, svg, webp, json, xml, csv, ' \
                    'txt and zip; any other file goes as application/octet-stream.'
      end

      output_schema do
        helpers.attachment_fields(self)
      end

      run do
        issue = helpers.safe_id(input[:issue_id_or_key], 'issue_id_or_key')
        fail_job!('Upload Attachment needs Content, the file as base64 text.') if input[:content_bytes].nil?

        bytes = Base64.decode64(input[:content_bytes])
        helpers.check_attachment_settings(bytes.bytesize)
        content_type = input[:content_type].presence || IPaaS::Job::ContentType.detect_content_type(input[:filename])
        filename = input[:filename].to_s.gsub(UNSAFE_FILENAME_CHARACTERS, '_')
        parts = { 'file' => IPaaS::Job::Outbound::HTTP.create_binary_part(filename, content_type, bytes) }
        response = helpers.jira_write(:multipart, helpers.jira_url("issue/#{issue}/attachments"), parts,
                                      { 'X-Atlassian-Token' => 'no-check' })
        helpers.refuse_status(response, 413, 'Jira refused the file as too large', ATTACHMENT_TOO_LARGE)
        result = helpers.handle_jira_response(response, write: true, permission: 'Create Attachments',
                                                        resource: "Issue #{issue}")
        [{ output: { attachments: Array(result).map { |attachment| helpers.attachment_metadata_output(attachment) } } }]
      end
    end

    action '01a13f2d-b655-747c-81ac-7bfb9c128a0a' do
      name 'Download Attachment'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Downloads one attachment by its ID. The file comes back as base64 text, with its name, content type and size.

        The outputs map straight into Upload Attachment. Get the attachment ID from Get Issue Attachments, Get Issue or Upload Attachment.

        A file over 10 MB is refused before it is downloaded.
      END_OF_DESCRIPTION

      input_schema do
        field :attachment_id, 'Attachment ID', :string, required: true
      end

      output_schema do
        field :filename, 'File name', :string
        field :content_bytes, 'Content', :base64
        field :content_type, 'Content type', :string
        field :size, 'Size', :integer
      end

      run do
        attachment = helpers.safe_id(input[:attachment_id], 'attachment_id')
        resource = "Attachment #{attachment}"
        metadata = helpers.jira_get("attachment/#{attachment}", permission: 'Browse Projects', resource: resource)
        helpers.refuse_oversized(metadata[:size].to_i, resource)
        response = helpers.jira_read(helpers.jira_url("attachment/content/#{attachment}"),
                                     query: { 'redirect' => 'false' })
        helpers.ensure_jira_success(response, permission: 'Browse Projects', resource: resource)
        body = response.body.to_s
        [{ output: {
          filename: metadata[:filename],
          content_bytes: Base64.strict_encode64(body),
          content_type: metadata[:mimeType],
          size: body.bytesize,
        } }]
      end
    end

    action '01a13f2d-b655-7f6b-8ed3-47b6e372444b' do
      name 'Get Issue Attachments'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Lists the attachments of an issue without downloading them.

        Each attachment comes with its ID, file name, size, content type, creation date and author. Give the ID to Download Attachment to get the file.
      END_OF_DESCRIPTION

      input_schema do
        field :issue_id_or_key, 'Issue ID or key', :string, required: true
      end

      output_schema do
        field :issue_id, 'Issue ID', :string, required: true
        field :issue_key, 'Issue key', :string, required: true
        helpers.attachment_fields(self)
      end

      run do
        issue = helpers.safe_id(input[:issue_id_or_key], 'issue_id_or_key')
        result = helpers.jira_get("issue/#{issue}", { fields: 'attachment' },
                                  permission: 'Browse Projects', resource: "Issue #{issue}")
        attachments = Array(result.dig(:fields, :attachment)).map do |attachment|
          helpers.attachment_metadata_output(attachment)
        end
        [{ output: { issue_id: result[:id], issue_key: result[:key], attachments: attachments } }]
      end
    end

    action '01a13f2d-b655-7b18-9252-e50c6296560a' do
      name 'Get User Details'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Reads one Jira user, by account ID or by a name or email address.

        Give **Account ID** or **Query**, not both. A query must lead to exactly one active user. A query that is one email address, such as jo@acme.com, finds only the user with exactly that address: Jira also returns users whose shown address merely starts with it, and those are not taken. A user whose address is hidden can be taken, because Jira matches a hidden address only in full. Any other query matches a user when it holds a letter or digit and each of its words starts a word of the display name or of the shown email address, so `jo smi` finds Jo Smith. Accents on common Latin letters do not count, so `jose` finds José. When several users match, the one whose display name or email address equals the query is taken. No match, or several, fails the job. When Jira finds 100 users or more, only an equal display name or email address is taken.

        The account needs the Browse users and groups permission; without it, a query finds nobody. **Email address** is empty unless the profile of the user shows it.
      END_OF_DESCRIPTION

      input_schema do
        field :account_id, 'Account ID', :string, visibility: 'optional'
        field :query, 'Query', :string,
              visibility: 'optional',
              hint: 'A full email address, or the start of words in a display name, for example jo smi.'
      end

      output_schema do
        helpers.user_fields(self)
      end

      run do
        account_id = input[:account_id].to_s.strip
        query = input[:query].to_s.strip
        fail_job!('Get User Details needs an account ID or a query, not both.') if account_id.present? == query.present?

        user = if account_id.present?
                 helpers.jira_get('user', { accountId: account_id },
                                  permission: 'Browse users and groups', resource: "User #{account_id}")
               else
                 helpers.find_one_user(query)
               end
        [{ output: helpers.user_output(user) }]
      end
    end

    action '01a13f2d-b655-7b0d-baf8-36b28915899b' do
      name 'Create User'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Creates a Jira user for an email address and gives the user the products you pick.

        **Each new user takes a paid licence seat** of the Atlassian subscription. Guard this step so that a runbook cannot run it by mistake.

        The connection account must be an organization admin and have the Administer Jira permission. With no **Products**, the user gets no product access. A display name cannot be given. When the user already exists with that access, the job also succeeds.
      END_OF_DESCRIPTION

      input_schema do
        field :email_address, 'Email address', :string, required: true
        field :products, 'Products', :string,
              array: true,
              visibility: 'optional',
              enumeration: USER_PRODUCTS,
              hint: 'The products the user may use. Empty gives no product access.'
      end

      output_schema do
        helpers.user_fields(self)
        field :self, 'API URL', :string
      end

      run do
        products = Array(input[:products]).reject(&:blank?).uniq
        body = { emailAddress: input[:email_address].to_s.strip, products: products }
        response = helpers.jira_write(:post, helpers.jira_url('user'), body)
        helpers.refuse_status(response, 403, 'Jira refused to create the user', CREATE_USER_FORBIDDEN)
        result = helpers.handle_jira_response(response, write: true)
        [{ output: helpers.user_output(result).merge(self: result[:self]) }]
      end
    end

    action '01a13f2d-b655-7eeb-aa38-633093dde9cd' do
      name 'Search Assignable Users'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Lists the users who can be assigned issues of a project, or one issue, one page per run.

        Give **Issue ID or key** or **Project**, not both. When both are empty, the Default project of the connection is used. An issue also applies its own security level. **Query** keeps the users whose display name or email address starts with it.

        Jira looks at no more than the first 1,000 users and leaves out the ones that cannot be assigned, so a page can be short or empty while a later page still holds users. The last page is the one that reaches the 1,000th user, or an empty page after which nobody up to the 1,000th user can be assigned.

        Steps inside this step run once per page. To go on in a later run, map **Next page token** into **Page token**.
      END_OF_DESCRIPTION
      nested true

      input_schema do
        field :issue_id_or_key, 'Issue ID or key', :string, visibility: 'optional'
        field :project_key, 'Project', :string,
              hint: 'Empty uses the Default project of the connection.' do
          options do
            helpers.fetch_project_options
          end
        end
        field :query, 'Query', :string,
              visibility: 'optional',
              hint: 'The start of a display name or email address.'
        helpers.paging_inputs(self)
      end

      output_schema 'page' do
        field :users, 'Users', :nested, array: true do
          field :account_id, 'Account ID', :string, required: true
          field :display_name, 'Display name', :string
          field :email_address, 'Email address', :string
        end
        helpers.paging_outputs(self)
      end

      iteration_state_schema do
        field :page_token, 'Page token', :string
      end

      run do
        scope, resource = helpers.assignable_scope(input)
        scope[:query] = input[:query].strip if input[:query].present?
        start_at = helpers.current_page_start
        page_size = helpers.requested_page_size
        users = helpers.assignable_users(scope, start_at, page_size, resource)
        page = { users: users.map { |user| helpers.account_output(user) } }
        paging = helpers.advance_page(helpers.assignable_next_token(scope, users, start_at + page_size, resource))
        [{ output: page.merge(paging), schema_reference: 'page' }]
      end
    end

    action '01a13f2d-b655-70bd-91ce-b19b81b37e5c' do
      name 'Get Issue Schema'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Lists the fields an issue can have, with the ID, name and type of each field, whether it is required and the values it allows.

        For Create Issue, give a **Project** and an **Issue type**, and the action reads the fields of the create screen. For Update Issue, give an **Issue ID or key** instead, and the action reads the fields this account may edit on that issue.

        Use the field IDs as keys in **Additional fields** of Create Issue and Update Issue. A field that is on no screen is not listed; Execute Jira REST API Action with GET `/rest/api/3/field` lists every field of the site.
      END_OF_DESCRIPTION

      input_schema do
        field :project_key, 'Project', :string,
              hint: 'Empty uses the Default project of the connection.' do
          options do
            helpers.fetch_project_options
          end
        end
        field :issue_type, 'Issue type', :string,
              hint: 'Pick one, or give an issue type name or ID.' do
          options do |project_key: nil|
            helpers.fetch_issue_type_options(project_key: project_key)
          end
        end
        field :issue_id_or_key, 'Issue ID or key', :string,
              visibility: 'optional',
              hint: 'Reads the fields that can be edited on this issue, instead of the create screen.'
      end

      output_schema do
        field :fields, 'Fields', :nested, array: true do
          field :field_id, 'Field ID', :string, required: true
          field :field_name, 'Name', :string
          field :field_type, 'Type', :string
          field :item_type, 'Item type', :string, hint: 'The type of each value when Type is array.'
          field :required, 'Required', :boolean
          field :allowed_values, 'Allowed values', :nested, array: true do
            field :id, 'ID', :string
            field :name, 'Name', :string
          end
        end
      end

      run do
        issue = input[:issue_id_or_key].to_s.strip
        issue_type = input[:issue_type].to_s.strip
        if issue.present? == issue_type.present?
          fail_job!('Get Issue Schema needs an issue type, or an issue ID or key, not both.')
        end

        fields = issue.present? ? helpers.edit_schema(issue) : helpers.create_schema(input[:project_key], issue_type)
        [{ output: { fields: fields } }]
      end
    end

    action '01a13f2d-b655-7093-8b62-995924004c8f' do
      name 'Execute Jira REST API Action'
      avatar '/assets/icons/jira.svg'
      description <<~END_OF_DESCRIPTION
        Sends one request to a Jira Cloud REST API path with the credentials of the connection, for a call that has no action of its own.

        **API path** starts with `/rest/`, for example `/rest/api/3/project/search` or `/rest/agile/1.0/board`. Put query parameters in **Query parameters**, not in the path, and give a list for a parameter that Jira takes more than once. Headers that carry credentials, cookies or a host are ignored.

        A JSON response comes back in **Body**. Any other response comes back as base64 text in **Content**, up to 10 MB. For the content of an attachment, use Download Attachment, which checks the size before it downloads the file. When the response holds a page token or an offset, it is copied into the page outputs, so that a later run can ask for the next page.

        A request that Jira refuses fails the job with the words of Jira. Jira checks the permissions of the account only when the request runs. A GET is tried again later when Jira is briefly unavailable. POST, PUT and DELETE are not, so a change is never made twice, and that includes a search sent as POST.
      END_OF_DESCRIPTION

      input_schema do
        field :method, 'HTTP method', :string, required: true, enumeration: REST_METHODS, default: 'GET'
        field :path, 'API path', :string, required: true, hint: 'For example /rest/api/3/project/search.'
        field :query, 'Query parameters', :hash,
              visibility: 'optional',
              hint: 'For example {"maxResults": 50, "id": ["10000", "10001"]}.'
        field :headers, 'Headers', :hash, visibility: 'optional'
        field :body, 'Request body', :any_value_type,
              visibility: 'optional',
              hint: 'JSON sent with POST and PUT: an object, a list, a text or a number.'
      end

      output_schema do
        field :status, 'Status', :integer, required: true
        field :content_type, 'Content type', :string
        field :body, 'Body', :any_value_type, hint: 'The response, when it is JSON.'
        field :content_bytes, 'Content', :base64, hint: 'The response as base64 text, when it is not JSON.'
        field :next_page_token, 'Next page token', :string
        field :is_last, 'Is last page', :boolean
        field :start_at, 'Start at', :integer
        field :max_results, 'Page size', :integer
        field :total, 'Total', :integer
      end

      run do
        http_method = input[:method]
        path = helpers.rest_path(input[:path])
        query = helpers.rest_query(input[:query])
        body = input[:body]
        body = nil if body.is_a?(String) && body.blank?
        unless body.nil? || REST_BODY_METHODS.include?(http_method)
          fail_job!("A request body is sent with POST and PUT only, not with #{http_method}.")
        end

        connection = http_connection(helpers.gateway_url(helpers.cloud_id(in_action: true), path[1..]),
                                     array_params: :flat, timeout: ACTION_TIMEOUT)
        headers = helpers.rest_headers(input[:headers], body)
        response = helpers.rest_send(connection, http_method, query, headers, body)
        helpers.ensure_jira_success(response, write: http_method != 'GET', resource: "Jira path #{path}")
        [{ output: helpers.rest_output(response) }]
      end
    end

    helper :transition_output do |transition|
      status = transition[:to]
      category = status && status[:statusCategory]
      fields = transition[:fields] || {}
      screen_fields = fields.map do |field_id, field|
        schema = field[:schema]
        {
          field_id: field_id.to_s,
          key: field[:key],
          name: field[:name],
          required: field[:required],
          has_default_value: field[:hasDefaultValue],
          default_value: field[:defaultValue],
          allowed_values: field[:allowedValues],
          operations: field[:operations],
          schema: schema && {
            type: schema[:type],
            items: schema[:items],
            custom: schema[:custom],
            custom_id: schema[:customId],
            system: schema[:system],
          },
        }
      end
      {
        transition_id: transition[:id].to_s,
        name: transition[:name],
        to_status_id: transition.dig(:to, :id).to_s.presence,
        to_status_name: transition.dig(:to, :name),
        has_screen: transition[:hasScreen],
        is_available: transition[:isAvailable],
        to_status: status && {
          id: status[:id].to_s.presence,
          name: status[:name],
          description: status[:description],
          icon_url: status[:iconUrl],
          self: status[:self],
          status_category: category && {
            color_name: category[:colorName],
            id: category[:id],
            key: category[:key],
            name: category[:name],
            self: category[:self],
          },
        },
        is_conditional: transition[:isConditional],
        is_global: transition[:isGlobal],
        is_initial: transition[:isInitial],
        fields: fields,
        screen_fields: screen_fields,
      }
    end

    helper :site_host do
      site = outbound_connection.config[:site].to_s.strip.sub(%r{\Ahttps?://}i, '')
      host = site.split('/').first.to_s.downcase
      next host if host.match?(SITE_HOST_PATTERN)

      fail_job!("The Jira site '#{site}' on the connection is not a host name. Enter it like acme.atlassian.net.")
    end

    helper :lookup_cloud_id do |host, in_action: false|
      response = http_get("https://#{host}/#{TENANT_INFO_PATH}", nil, nil,
                          skip_authentication: true,
                          open_timeout: in_action ? nil : SHORT_OPEN_TIMEOUT,
                          timeout: in_action ? ACTION_TIMEOUT : SHORT_TIMEOUT)
      helpers.jira_backoff(response)
      parsed = helpers.success_status?(response.status) ? helpers.parse_json(response.body) : nil
      cloud_id = parsed.is_a?(Hash) ? parsed['cloudId'].to_s : ''
      next cloud_id if cloud_id.match?(CLOUD_ID_PATTERN)

      helpers.refuse_site(host)
    rescue StandardError => e
      raise if e.is_a?(IPaaS::Error)

      helpers.retry_read(e) if in_action && helpers.network_error?(e)
      helpers.refuse_site(host, e.message)
    end

    helper :refuse_site do |host, reason = nil|
      cause = reason ? " (#{reason})" : ''
      fail_job!("No Jira Cloud site answers at #{host}#{cause}. Check the Jira site on the connection.")
    end

    helper :cloud_id do |site = nil, in_action: false|
      host = site.presence || helpers.site_host
      stored = outbound_connection.store.read("#{CLOUD_ID_STORE_PREFIX}#{host}")
      next stored if stored.present?

      helpers.store_cloud_id(host, in_action: in_action)
    end

    helper :store_cloud_id do |host, in_action: false|
      cloud_id = helpers.lookup_cloud_id(host, in_action: in_action)
      outbound_connection.store.write("#{CLOUD_ID_STORE_PREFIX}#{host}", cloud_id)
      cloud_id
    end

    helper :gateway_url do |cloud_id, path|
      "#{GATEWAY}/ex/jira/#{cloud_id}/#{path}"
    end

    helper :jira_url do |path|
      helpers.gateway_url(helpers.cloud_id(in_action: true), "#{API_PATH}/#{path}")
    end

    helper :webhook_url do |host|
      helpers.gateway_url(helpers.cloud_id(host), WEBHOOK_PATH)
    end

    helper :browse_url do |key|
      next nil if key.blank?

      "https://#{helpers.site_host}/browse/#{key}"
    end

    helper :safe_id do |value, field_name|
      text = value.to_s.strip
      fail_job!("Jira #{field_name} is required.") if text.blank?
      fail_job!("Jira #{field_name} is not path safe: '#{text}'") unless text.match?(SAFE_ID_PATTERN)
      next text.upcase if text.match?(ISSUE_KEY_PATTERN)

      text
    end

    helper :issue_reference_output do |issue|
      issue.match?(ISSUE_KEY_PATTERN) ? { issue_key: issue } : { issue_id: issue }
    end

    helper :success_status? do |status|
      status >= 200 && status < 300
    end

    helper :truncate_body do |text|
      body = text.to_s
      body.length > TRUNCATED_BODY_LIMIT ? "#{body[0, TRUNCATED_BODY_LIMIT]}..." : body
    end

    helper :parse_json do |text|
      JSON.parse(text.to_s)
    rescue JSON::ParserError
      nil
    end

    helper :parse_jira_body do |response|
      text = response.body.to_s
      next {}.with_indifferent_access if text.blank?

      parsed = helpers.parse_json(text)
      next parsed.with_indifferent_access if parsed.is_a?(Hash)
      next parsed.map { |entry| entry.is_a?(Hash) ? entry.with_indifferent_access : entry } if parsed.is_a?(Array)

      fail_job!("Jira returned HTTP #{response.status} with a body that is not a JSON object or list: " \
                "#{helpers.truncate_body(text)}")
    end

    helper :jira_error_detail do |response|
      text = response.body.to_s
      parsed = helpers.parse_json(text)
      next helpers.truncate_body(text).presence || 'no response body' unless parsed.is_a?(Hash)

      errors = parsed['errors'].is_a?(Hash) ? parsed['errors'].map { |field, message| "#{field}: #{message}" } : []
      messages = Array(parsed['messages']).map { |message| helpers.admin_message_text(message) }
      detail = (Array(parsed['errorMessages']) + errors + messages + [parsed['message']]).map(&:to_s).reject(&:blank?)
      detail.any? ? detail.join('; ') : helpers.truncate_body(text)
    end

    helper :admin_message_text do |message|
      next message.to_s unless message.is_a?(Hash)

      [message['key'], Array(message['arguments']).join(' ')].map(&:to_s).reject(&:blank?).join(': ')
    end

    helper :jira_failure_message do |response, permission, resource|
      detail = helpers.jira_error_detail(response)
      sentence = "#{detail.chomp('.')}."
      case response.status
      when 401
        if detail.match?(SCOPE_MISMATCH)
          next "Jira refused the request (HTTP 401): #{sentence} The scoped API token on the connection lacks a " \
               'scope this call needs. Add the scope to the token, or use a classic API token.'
        end

        "Jira rejected the credentials (HTTP 401): #{sentence} The email or API token on the connection is wrong, " \
          'revoked or past its expiry date. API tokens last 1 to 365 days. A scoped token may also be missing a ' \
          'scope this call needs.'
      when 403
        needed = permission ? " The account needs the #{permission} permission." : ''
        "Jira refused the request (HTTP 403): #{sentence}#{needed}"
      when 400
        refused = PERMISSIONS_REFUSED_WITH_400.include?(permission) && helpers.permission_refusal?(response)
        next "Jira API error (HTTP 400): #{detail}" unless refused

        "Jira refused the request (HTTP 400): #{sentence} The account needs the #{permission} permission."
      when 404
        "#{resource || 'The requested Jira item'} was not found, or this account cannot see it (HTTP 404): #{detail}"
      when 409
        "Jira refused the change because of a conflicting change (HTTP 409): #{sentence} It was not tried again, " \
        'so nothing is applied twice. Read the item and run the step again.'
      else
        "Jira API error (HTTP #{response.status}): #{detail}"
      end
    end

    helper :jira_backoff do |response, write: false|
      reason = response.headers['RateLimit-Reason']
      log("Jira rate limit reached (#{reason}); backing off.") if reason.present?
      backoff_if_needed(response, api_name: 'Jira', server_error_statuses: write ? [] : READ_RETRY_STATUSES)
    end

    helper :ensure_jira_success do |response, write: false, permission: nil, resource: nil|
      helpers.jira_backoff(response, write: write)
      next response if helpers.success_status?(response.status)
      fail_job!(helpers.unconfirmed_write_message(response)) if write && READ_RETRY_STATUSES.include?(response.status)

      fail_job!(helpers.jira_failure_message(response, permission, resource))
    end

    helper :unconfirmed_write_message do |response|
      "Jira answered the change with HTTP #{response.status}: #{helpers.jira_error_detail(response).chomp('.')}. " \
        "#{UNCONFIRMED_CHANGE}"
    end

    helper :refuse_status do |response, status, refusal, advice|
      next unless response.status == status

      fail_job!("#{refusal} (HTTP #{status}): #{helpers.jira_error_detail(response).chomp('.')}. #{advice}")
    end

    helper :handle_jira_response do |response, write: false, permission: nil, resource: nil|
      helpers.ensure_jira_success(response, write: write, permission: permission, resource: resource)
      helpers.parse_jira_body(response)
    end

    helper :jira_read do |url, query: nil, body: nil, open_timeout: nil, timeout: ACTION_TIMEOUT|
      if body.nil?
        http_get(url, query, nil, open_timeout: open_timeout, timeout: timeout)
      else
        http_post(url, body.to_json, JSON_HEADERS, open_timeout: open_timeout, timeout: timeout)
      end
    rescue StandardError => e
      helpers.retry_read(e)
    end

    helper :retry_read do |error|
      raise error if error.is_a?(IPaaS::Error) || error.is_a?(ArgumentError)
      fail_job!("The request to Jira failed (#{error.message}).") unless helpers.network_error?(error)

      backoff("Jira did not answer (#{error.message}). The read is tried again later.")
    end

    helper :network_error? do |error|
      NETWORK_ERRORS.include?(error.class.name)
    end

    helper :jira_get do |path, params = nil, permission: nil, resource: nil|
      query = (params || {}).compact.transform_values(&:to_s)
      helpers.handle_jira_response(helpers.jira_read(helpers.jira_url(path), query: query),
                                   permission: permission, resource: resource)
    end

    helper :jira_post do |path, body, permission: nil, resource: nil|
      helpers.handle_jira_response(helpers.jira_write(:post, helpers.jira_url(path), body),
                                   write: true, permission: permission, resource: resource)
    end

    helper :jira_put do |path, body, permission: nil, resource: nil|
      helpers.handle_jira_response(helpers.jira_write(:put, helpers.jira_url(path), body),
                                   write: true, permission: permission, resource: resource)
    end

    helper :jira_write do |verb, url, body, headers = JSON_HEADERS, open_timeout: nil, timeout: ACTION_TIMEOUT|
      case verb
      when :post then http_post(url, body.to_json, headers, open_timeout: open_timeout, timeout: timeout)
      when :put then http_put(url, body.to_json, headers, open_timeout: open_timeout, timeout: timeout)
      when :delete then http_delete(url, nil, nil, open_timeout: open_timeout, timeout: timeout)
      when :multipart then multipart_post(url, body, headers)
      end
    rescue StandardError => e
      helpers.refuse_unanswered_write(e)
    end

    helper :refuse_unanswered_write do |error|
      raise error if error.is_a?(IPaaS::Error) || error.is_a?(ArgumentError)

      fail_job!("Jira did not answer (#{error.message}). #{UNCONFIRMED_CHANGE}")
    end

    helper :test_failure do |response, resource = nil|
      status = TEST_FAILED_STATUSES.include?(response.status) ? :failed : :error
      { status: status, message: helpers.jira_failure_message(response, nil, resource) }
    end

    helper :default_project_failure do |base|
      project = outbound_connection.config[:default_project].presence
      path, params, resource = if project
                                 key = helpers.safe_id(project, 'default project').upcase
                                 ["project/#{key}", nil, "The default project #{key}"]
                               else
                                 ['project/search', { maxResults: '1' }, 'The project list']
                               end
      response = http_get("#{base}/#{path}", params, nil, open_timeout: SHORT_OPEN_TIMEOUT, timeout: SHORT_TIMEOUT)
      next helpers.test_failure(response, resource) unless helpers.success_status?(response.status)
      next nil if project || Array(helpers.parse_jira_body(response)[:values]).any?

      { status: :failed, message: 'The account can see no Jira project. Add it to the projects it works in.' }
    end

    helper :paged_values do |path, params, list_key: :values, permission: nil, resource: nil|
      (0...MAX_OPTION_PAGES).each_with_object([]) do |_page, values|
        start_at = values.size
        result = helpers.jira_get(path, params.merge(startAt: start_at, maxResults: MAX_PAGE_SIZE),
                                  permission: permission, resource: resource)
        page_values = Array(result[list_key])
        page_values.each { |value| values.push(value) }
        break values if helpers.next_offset_token(result, page_values.size, start_at, MAX_PAGE_SIZE).nil?
      end
    end

    helper :option_list do |items|
      Array(items).map { |item| { id: item[:id].to_s, label: item[:name].to_s } }
    end

    helper :fetch_project_options do
      helpers.paged_values('project/search', { orderBy: 'key' }).map do |project|
        { id: project[:key].to_s, label: "#{project[:name]} (#{project[:key]})" }
      end
    end

    helper :fetch_issue_type_options do |project_key:|
      helpers.option_list(helpers.creatable_issue_types(helpers.project_key_or_default(project_key)))
    end

    helper :creatable_issue_types do |key|
      helpers.paged_values("issue/createmeta/#{key}/issuetypes", {}, list_key: :issueTypes,
                                                                     permission: 'Create Issues',
                                                                     resource: "Project #{key}")
    end

    helper :fetch_priority_options do
      helpers.option_list(helpers.paged_values('priority/search', {}))
    end

    helper :fetch_transition_options do |issue_id_or_key:|
      issue = helpers.safe_id(issue_id_or_key, 'issue_id_or_key')
      helpers.option_list(helpers.available_transitions(issue))
    end

    helper :available_transitions do |issue, expand_fields: false|
      params = expand_fields ? { expand: 'transitions.fields' } : nil
      result = helpers.jira_get("issue/#{issue}/transitions", params, permission: 'Browse Projects',
                                                                      resource: "Issue #{issue}")
      Array(result[:transitions])
    end

    helper :page_start do |token|
      text = token.to_s.strip
      next 0 if text.blank?
      next text.to_i if text.match?(DIGITS_PATTERN)

      fail_job!("The page token '#{text}' was not returned by this action.")
    end

    helper :current_page_token do
      iteration_state_value(:page_token).presence || input[:page_token].to_s.strip.presence
    end

    helper :current_page_start do
      helpers.page_start(helpers.current_page_token)
    end

    helper :requested_page_size do
      input[:page_size] || DEFAULT_PAGE_SIZE
    end

    helper :advance_page do |next_token|
      self.iteration_state_value = next_token ? { page_token: next_token } : nil
      { next_page_token: next_token, is_last: next_token.nil? }
    end

    helper :offset_page do |path, params, list_key, resource|
      start_at = helpers.current_page_start
      page_size = helpers.requested_page_size
      result = helpers.jira_get(path, params.merge(startAt: start_at, maxResults: page_size),
                                permission: 'Browse Projects', resource: resource)
      entries = Array(result[list_key])
      [entries, helpers.advance_page(helpers.next_offset_token(result, entries.size, start_at, page_size))]
    end

    helper :search_page do |body|
      token = helpers.current_page_token
      request = token ? body.merge(nextPageToken: token) : body
      response = helpers.jira_read(helpers.jira_url('search/jql'), body: request)
      result = helpers.handle_jira_response(response, permission: 'Browse Projects')
      [result, helpers.advance_page(result[:isLast] ? nil : result[:nextPageToken].presence)]
    end

    helper :requested_fields do |action_input, default_fields|
      next [ALL_FIELDS] if action_input[:all_fields]

      Array(action_input[:fields]).reject(&:blank?).presence || default_fields
    end

    helper :requested_expand do |action_input|
      Array(action_input[:expand]).reject(&:blank?).join(',').presence
    end

    helper :project_key_or_default do |value|
      key = value.to_s.strip.presence || outbound_connection.config[:default_project].to_s.strip
      fail_job!('Pick a Jira project, or set a Default project on the connection.') if key.blank?

      helpers.checked_project_key(key)
    end

    helper :checked_project_key do |key|
      fail_job!("'#{key}' is not a Jira project key or ID.") unless key.match?(PROJECT_KEY_PATTERN)

      key.upcase
    end

    helper :structured_jql do |criteria|
      clauses = ["project = #{helpers.jql_value(helpers.project_key_or_default(criteria[:project_key]))}"]
      JQL_FILTERS.each do |input_name, jql_field|
        clauses.push("#{jql_field} = #{helpers.jql_value(criteria[input_name])}") if criteria[input_name].present?
      end
      JQL_DATE_BOUNDS.each do |input_name, comparison|
        next if criteria[input_name].blank?

        clauses.push("#{comparison} #{helpers.epoch_milliseconds(criteria[input_name])}")
      end
      "#{clauses.join(' AND ')} #{SEARCH_ORDER}"
    end

    helper :jql_value do |value|
      text = value.to_s.strip
      next text if text.match?(DIGITS_PATTERN)

      "\"#{text.gsub(JQL_ESCAPED_CHARACTERS) { |character| "\\#{character}" }}\""
    end

    helper :epoch_milliseconds do |value|
      value.to_datetime.strftime('%Q').to_i
    end

    helper :next_offset_token do |page, returned, start_at, page_size|
      next nil if returned < 1

      details = page.is_a?(Hash) ? page : {}
      last = details[:isLast]
      next_start = start_at + returned
      more = if !last.nil?
               !last
             elsif details[:total].present?
               next_start < details[:total].to_i
             else
               returned >= (details[:maxResults] || page_size).to_i
             end
      more ? next_start.to_s : nil
    end

    helper :markdown_to_adf do |text|
      blocks = text.to_s.gsub("\r\n", "\n").split(/\n(?:[ \t]*\n)+/).reject(&:blank?)
      { version: 1, type: 'doc', content: blocks.flat_map { |block| helpers.markdown_block(block) } }
    end

    helper :markdown_block do |block|
      runs = block.split("\n").each_with_object([]) do |line, groups|
        bullet = line.match?(MARKDOWN_BULLET)
        groups.push({ bullet: bullet, lines: [] }) unless groups.last && groups.last[:bullet] == bullet
        groups.last[:lines].push(line.sub(MARKDOWN_BULLET, ''))
      end
      runs.map { |run| run[:bullet] ? helpers.adf_bullet_list(run[:lines]) : helpers.adf_paragraph(run[:lines]) }
    end

    helper :adf_paragraph do |lines|
      content = lines.flat_map.with_index do |line, index|
        (index > 0 ? [{ type: 'hardBreak' }] : []) + helpers.markdown_inline(line)
      end
      { type: 'paragraph', content: content }
    end

    helper :adf_bullet_list do |items|
      list_items = items.map do |item|
        { type: 'listItem', content: [{ type: 'paragraph', content: helpers.markdown_inline(item) }] }
      end
      { type: 'bulletList', content: list_items }
    end

    helper :markdown_inline do |line|
      line.split(MARKDOWN_EMPHASIS).each_slice(2).flat_map do |plain, marked|
        nodes = plain.empty? ? [] : [{ type: 'text', text: plain }]
        nodes.push({ type: 'text', text: marked[1..-2], marks: [{ type: MARKDOWN_MARKS[marked[0]] }] }) if marked
        nodes
      end
    end

    helper :adf_to_text do |node|
      next node.map { |child| helpers.adf_to_text(child) }.join if node.is_a?(Array)
      next node.to_s unless node.is_a?(Hash)

      element = node.with_indifferent_access
      next helpers.adf_text_with_link(element) unless element[:text].nil?

      type = element[:type].to_s
      attrs = element[:attrs] || {}
      inline = helpers.adf_inline_text(type, attrs)
      next inline unless inline.nil?

      children = Array(element[:content])
      next helpers.adf_list_text(type, children, attrs) if ADF_LIST_TYPES.include?(type)

      texts = children.map { |child| helpers.adf_to_text(child) }
      next texts.join unless children.any? { |child| helpers.adf_block?(child) }

      texts.reject(&:blank?).join(type == 'listItem' ? LINE_BREAK : PARAGRAPH_BREAK)
    end

    helper :adf_text_with_link do |element|
      text = element[:text].to_s
      link = Array(element[:marks]).detect { |mark| mark.is_a?(Hash) && mark[:type] == 'link' }
      url = link ? link.dig(:attrs, :href).to_s : ''
      url.blank? || url == text ? text : "#{text} (#{url})"
    end

    helper :adf_block? do |node|
      node.is_a?(Hash) && !ADF_INLINE_TYPES.include?(node.with_indifferent_access[:type].to_s)
    end

    helper :adf_inline_text do |type, attrs|
      case type
      when 'hardBreak' then "\n"
      when 'mention' then attrs[:text].presence || "@#{attrs[:id]}"
      when 'emoji' then (attrs[:text].presence || attrs[:shortName]).to_s
      when 'status' then attrs[:text].to_s
      when 'date' then helpers.adf_date(attrs[:timestamp])
      when 'inlineCard', 'blockCard', 'embedCard' then (attrs[:url].presence || attrs.dig(:data, :url)).to_s
      end
    end

    helper :adf_date do |timestamp|
      digits = timestamp.to_s
      next digits unless digits.match?(TIMESTAMP_PATTERN)

      value = digits.to_i
      seconds = value.abs >= SMALLEST_MILLISECOND_TIMESTAMP ? value / MILLISECONDS_PER_SECOND : value
      Time.at(seconds).utc.strftime('%Y-%m-%d')
    end

    helper :adf_list_text do |type, items, attrs|
      first_number = (attrs[:order] || 1).to_i
      lines = items.map.with_index do |item, index|
        marker = type == 'orderedList' ? "#{first_number + index}. " : '- '
        "#{marker}#{helpers.adf_to_text(item).strip}"
      end
      lines.join(LINE_BREAK)
    end

    helper :comment_visibility do |action_input|
      type = action_input[:visibility_type].presence
      value = action_input[:visibility_value].presence
      next nil if type.nil? && value.nil?

      fail_job!('Comment visibility needs both a type and a value. Nothing was sent.') if type.nil? || value.nil?

      { type: type, value: value }
    end

    helper :comment_body do |action_input|
      adf = action_input[:body_adf]
      next adf if adf.present?

      text = action_input[:body]
      fail_job!('A comment needs either Body or Body (ADF).') if text.blank?

      helpers.markdown_to_adf(text)
    end

    helper :comment_payload do |action_input|
      { body: helpers.comment_body(action_input), visibility: helpers.comment_visibility(action_input) }.compact
    end

    helper :permission_refusal? do |response|
      next true if response.status == 403
      next false unless response.status == 400

      parsed = helpers.parse_json(response.body.to_s)
      Array(parsed.is_a?(Hash) ? parsed['errorMessages'] : nil).join(' ').match?(PERMISSION_WORD)
    end

    helper :comment_edit_permission do |path, response|
      next nil unless helpers.permission_refusal?(response)

      author = helpers.account_id_at(path, :author)
      account = helpers.account_id_at('myself')
      next EDIT_ANY_COMMENTS if author.blank? || account.blank?

      author == account ? EDIT_OWN_COMMENTS : EDIT_ALL_COMMENTS
    end

    helper :account_id_at do |path, key = nil|
      response = http_get(helpers.jira_url(path), nil, nil, open_timeout: SHORT_OPEN_TIMEOUT, timeout: SHORT_TIMEOUT)
      next nil unless helpers.success_status?(response.status)

      body = helpers.parse_json(response.body)
      body = body[key.to_s] if key && body.is_a?(Hash)
      body['accountId'] if body.is_a?(Hash)
    rescue StandardError => e
      raise if e.is_a?(IPaaS::Error)

      nil
    end

    helper :id_or_name_reference do |value, name_key = :name|
      text = value.to_s.strip
      text.match?(DIGITS_PATTERN) ? { id: text } : { name_key => text }
    end

    helper :issue_fields_payload do |action_input, clear_blank: false, set_by_action: []|
      fields = {}
      ISSUE_FIELD_INPUTS.each do |input_name, jira_name|
        value = action_input[input_name]
        value = Array(value).reject(&:blank?) if LIST_ISSUE_INPUTS.include?(input_name)
        if value.present?
          fields[jira_name] = helpers.issue_field_value(input_name, value)
        elsif clear_blank && CLEARABLE_ISSUE_INPUTS.include?(input_name) && action_input.key?(input_name)
          fields[jira_name] = LIST_ISSUE_INPUTS.include?(input_name) ? [] : nil
        end
      end
      additional = action_input[:additional_fields].presence || {}
      helpers.refuse_field_clash(fields.keys, additional, set_by_action)
      additional.each { |key, value| fields[key.to_sym] = value }
      fields
    end

    helper :refuse_field_clash do |sent, additional, set_by_action|
      taken = set_by_action.select { |jira_name| additional.key?(jira_name) }
      unless taken.empty?
        fail_job!("Additional fields cannot set #{taken.join(', ')}, which this action sets from its own inputs. " \
                  'Nothing was sent.')
      end

      clash = sent.select { |jira_name| additional.key?(jira_name) }
      next if clash.empty?

      fail_job!("Additional fields and an input both set #{clash.join(', ')}. Give each field in one place only. " \
                'Nothing was sent.')
    end

    helper :issue_field_value do |input_name, value|
      case input_name
      when :description then helpers.markdown_to_adf(value)
      when :assignee_account_id, :reporter_account_id then { id: value }
      when :priority then helpers.id_or_name_reference(value)
      when :labels then Array(value)
      when :components then Array(value).map { |name| { name: name } }
      when :due_date then value.to_s
      when :parent_key then helpers.id_or_name_reference(value.to_s.upcase, :key)
      else value
      end
    end

    helper :account_output do |user|
      next nil if user.blank?

      { account_id: user[:accountId], display_name: user[:displayName], email_address: user[:emailAddress] }
    end

    helper :visibility_output do |visibility|
      next nil if visibility.blank?

      { type: visibility[:type], value: visibility[:value], identifier: visibility[:identifier] }
    end

    helper :issue_summary_output do |issue|
      fields = issue[:fields].presence || {}
      {
        issue_id: issue[:id],
        issue_key: issue[:key],
        browse_url: helpers.browse_url(issue[:key]),
        summary: fields[:summary],
        status: fields.dig(:status, :name),
        priority: fields.dig(:priority, :name),
        assignee: helpers.account_output(fields[:assignee]),
        updated: fields[:updated],
      }
    end

    helper :issue_output do |issue|
      fields = issue[:fields].presence || {}
      helpers.issue_summary_output(issue).merge(
        self: issue[:self],
        description: helpers.adf_to_text(fields[:description]).strip.presence,
        status_category: fields.dig(:status, :statusCategory, :name),
        issue_type: fields.dig(:issuetype, :name),
        issue_type_id: fields.dig(:issuetype, :id),
        project: fields.dig(:project, :key),
        reporter: helpers.account_output(fields[:reporter]),
        created: fields[:created],
        resolution: fields.dig(:resolution, :name),
        resolution_date: fields[:resolutiondate],
        labels: Array(fields[:labels]),
        components: Array(fields[:components]).map { |component| { id: component[:id], name: component[:name] } },
        attachments: Array(fields[:attachment]).map { |attachment| helpers.attachment_metadata_output(attachment) },
        comment_count: fields.dig(:comment, :total),
        fields: fields.except(:comment),
        expanded: helpers.expanded_without_comments(issue)
      )
    end

    helper :expanded_without_comments do |issue|
      issue.slice(*EXPANDED_ISSUE_PARTS).to_h do |part, value|
        [part, FIELD_VALUE_PARTS.include?(part) && value.is_a?(Hash) ? value.except(:comment) : value]
      end.presence
    end

    helper :comment_output do |comment|
      {
        comment_id: comment[:id].to_s,
        self: comment[:self],
        comment_body: helpers.adf_to_text(comment[:body]).strip,
        author: helpers.account_output(comment[:author]),
        created: comment[:created],
        updated: comment[:updated],
        visibility: helpers.visibility_output(comment[:visibility]),
      }
    end

    helper :changelog_output do |entry|
      {
        id: entry[:id].to_s,
        author: helpers.account_output(entry[:author]),
        created: entry[:created],
        items: Array(entry[:items]).map { |item| helpers.changelog_item_output(item) },
      }
    end

    helper :changelog_item_output do |item|
      {
        field: item[:field],
        field_id: item[:fieldId],
        from: item[:from],
        from_string: item[:fromString],
        to: item[:to],
        to_string: item[:toString],
      }
    end

    helper :attachment_metadata_output do |attachment|
      {
        attachment_id: attachment[:id].to_s,
        filename: attachment[:filename],
        size: attachment[:size],
        content_type: attachment[:mimeType],
        created: attachment[:created],
        author: helpers.account_output(attachment[:author]),
      }
    end

    helper :user_output do |user|
      (helpers.account_output(user) || {}).merge(
        active: user[:active],
        account_type: user[:accountType],
        time_zone: user[:timeZone]
      )
    end

    helper :schema_field_output do |field_id, field|
      {
        field_id: field_id.to_s,
        field_name: field[:name],
        field_type: field.dig(:schema, :type),
        item_type: field.dig(:schema, :items),
        required: field[:required],
        allowed_values: Array(field[:allowedValues]).map { |value| helpers.allowed_value_output(value) },
      }
    end

    helper :allowed_value_output do |value|
      next { id: nil, name: value.to_s } unless value.is_a?(Hash)

      { id: value[:id].to_s.presence, name: (value[:name] || value[:value]).to_s.presence }
    end

    helper :create_schema do |project_value, issue_type|
      project = helpers.project_key_or_default(project_value)
      type_id = helpers.safe_id(helpers.issue_type_id(project, issue_type), 'issue type ID')
      fields = helpers.create_meta_fields("issue/createmeta/#{project}/issuetypes/#{type_id}",
                                          "Issue type #{type_id} of project #{project}", 0, MAX_SCHEMA_PAGES)
      fields.map { |field| helpers.schema_field_output(field[:fieldId], field) }
    end

    helper :create_meta_fields do |path, resource, start_at, pages_left|
      if pages_left < 1
        fail_job!("#{resource} has more than #{start_at} fields on its create screen, more than Get Issue " \
                  'Schema can return.')
      end

      result = helpers.jira_get(path, { startAt: start_at, maxResults: SCHEMA_PAGE_SIZE },
                                permission: 'Create Issues', resource: resource)
      page = Array(result[:fields].presence || result[:results])
      next_start = helpers.next_offset_token(result, page.size, start_at, SCHEMA_PAGE_SIZE)
      next page if next_start.nil?

      page + helpers.create_meta_fields(path, resource, next_start.to_i, pages_left - 1)
    end

    helper :edit_schema do |issue_value|
      issue = helpers.safe_id(issue_value, 'issue_id_or_key')
      result = helpers.jira_get("issue/#{issue}/editmeta", permission: 'Browse Projects', resource: "Issue #{issue}")
      (result[:fields] || {}).map { |field_id, field| helpers.schema_field_output(field_id, field) }
    end

    helper :issue_type_id do |project, value|
      next value if value.match?(DIGITS_PATTERN)

      helpers.id_by_name(value, helpers.creatable_issue_types(project),
                         "Project #{project} has no issue type named '#{value}' that this account can create.")
    end

    helper :id_by_name do |value, candidates, missing|
      match = candidates.detect { |candidate| candidate[:name].to_s.downcase == value.downcase }
      next match[:id].to_s if match

      names = candidates.map { |candidate| candidate[:name] }.reject(&:blank?)
      fail_job!("#{missing} Available: #{names.any? ? names.join(', ') : 'none'}.")
    end

    helper :check_attachment_settings do |size|
      settings = helpers.jira_get('attachment/meta')
      fail_job!('Attachments are turned off on this Jira site. Nothing was uploaded.') if settings[:enabled] == false

      limit = settings[:uploadLimit].to_i
      next if limit < 1 || size <= limit

      fail_job!("The file is #{size} bytes, over the #{limit}-byte attachment size limit of this Jira site. " \
                'Nothing was uploaded.')
    end

    helper :refuse_oversized do |size, subject|
      next if size <= MAX_DOWNLOAD_BYTES

      fail_job!("#{subject} is #{size} bytes, over the #{MAX_DOWNLOAD_BYTES}-byte limit of one runbook step.")
    end

    helper :find_one_user do |query|
      found = Array(helpers.jira_get('user/search', { query: query, maxResults: MAX_PAGE_SIZE },
                                     permission: 'Browse users and groups'))
      email_query = query.match?(EMAIL_QUERY_PATTERN)
      users = found.select do |user|
        email_query ? helpers.user_matches_email?(user, query) : helpers.user_matches_words?(user, query)
      end
      complete = found.size < MAX_PAGE_SIZE
      next users.first if complete && users.size == 1

      if complete && users.empty?
        fail_job!("No active Jira user matches '#{query}'. The search finds active users only, and finds nobody " \
                  'when the account lacks the Browse users and groups permission.')
      end

      exact = users.select do |user|
        [user[:displayName], user[:emailAddress]].any? { |value| value.to_s.downcase == query.downcase }
      end
      next exact.first if exact.size == 1

      advice = 'Give the account ID or the full email address.'
      fail_job!("Jira finds #{found.size} or more users for '#{query}'. #{advice}") unless complete

      fail_job!("#{(exact.presence || users).size} Jira users match '#{query}'. #{advice}")
    end

    helper :user_matches_email? do |user, query|
      shown = user[:emailAddress].to_s
      next shown.downcase == query.downcase if shown.present?

      display = user[:displayName].to_s.downcase
      display == query.downcase || !display.include?(query.downcase)
    end

    helper :user_matches_words? do |user, query|
      words = helpers.search_words("#{user[:displayName]} #{user[:emailAddress]}")
      parts = helpers.search_words(query)
      parts.any? && parts.all? { |part| words.any? { |word| word.start_with?(part) } }
    end

    helper :search_words do |text|
      folded = text.to_s.downcase.tr(ACCENTED_LETTERS, PLAIN_LETTERS)
      folded.gsub(NON_LETTER_MARK, '').split(WORD_SEPARATOR).reject(&:empty?)
    end

    helper :assignable_users do |scope, start_at, page_size, resource|
      Array(helpers.jira_get('user/assignable/search', scope.merge(startAt: start_at, maxResults: page_size),
                             permission: 'Assign Issues or Browse users and groups', resource: resource))
    end

    helper :assignable_next_token do |scope, users, next_start, resource|
      next nil if next_start >= USER_SEARCH_LIMIT
      next next_start.to_s if users.any?
      next nil if helpers.assignable_users(scope, next_start, USER_SEARCH_LIMIT - next_start, resource).empty?

      next_start.to_s
    end

    helper :assignable_scope do |action_input|
      issue = action_input[:issue_id_or_key].to_s.strip
      if issue.blank?
        project = helpers.project_key_or_default(action_input[:project_key])
        next [{ project: project }, "Project #{project}"]
      end
      fail_job!('Search Assignable Users takes an issue or a project, not both.') if action_input[:project_key].present?

      key = helpers.safe_id(issue, 'issue_id_or_key')
      [key.match?(DIGITS_PATTERN) ? { issueId: key } : { issueKey: key }, "Issue #{key}"]
    end

    helper :rest_path do |value|
      path = value.to_s.strip
      unless path.match?(REST_PATH_PREFIX)
        fail_job!("The API path '#{path}' must start with /rest/, for example /rest/api/3/project/search.")
      end
      next path unless path.match?(UNSAFE_REST_PATH)

      fail_job!("The API path '#{path}' may not hold '..', '//', '?', '#', '@', a backslash, a space, a character " \
                "outside ASCII, a '%' without two hex digits after it, or an encoded dot, slash, backslash or '%'. " \
                'Encode other characters as %XX. Put query parameters in Query parameters.')
    end

    helper :rest_query do |query|
      given = query.presence || {}
      given.each do |name, value|
        next unless value.is_a?(Hash) || Array(value).any? { |item| item.is_a?(Hash) || item.is_a?(Array) }

        fail_job!("Query parameter #{name} holds an object or a nested list. Give a text, a number or a list of them.")
      end
      given
    end

    helper :rest_headers do |headers, body|
      given = (headers.presence || {}).reject { |name, _value| DROPPED_REST_HEADERS.include?(name.to_s.downcase) }
      (body.nil? ? {} : JSON_HEADERS).merge(given.transform_values(&:to_s))
    end

    helper :rest_send do |connection, http_method, query, headers, body|
      connection.http_send(http_method.downcase) do |request|
        request.params = query if query.present?
        request.headers.merge!(headers)
        request.body = body.to_json unless body.nil?
      end
    rescue StandardError => e
      http_method == 'GET' ? helpers.retry_read(e) : helpers.refuse_unanswered_write(e)
    end

    helper :rest_output do |response|
      text = response.body.to_s
      helpers.refuse_oversized(text.bytesize, 'The Jira response')
      content_type = response.headers['Content-Type']
      body = content_type.to_s.include?('json') ? helpers.parse_json(text) : nil
      paging = body.is_a?(Hash) ? camel_to_snake(body).with_indifferent_access : {}
      {
        status: response.status,
        content_type: content_type,
        body: body,
        content_bytes: (Base64.strict_encode64(text) if body.nil? && text.present?),
      }.merge(paging)
    end

    helper :add_transition_comment do |issue, transition_id, text|
      moved = "Issue #{issue} moved through transition #{transition_id}, but"
      response = http_post(helpers.jira_url("issue/#{issue}/comment"), { body: helpers.markdown_to_adf(text) }.to_json,
                           JSON_HEADERS, timeout: ACTION_TIMEOUT)
      next if helpers.success_status?(response.status)

      added = if READ_RETRY_STATUSES.include?(response.status)
                'the comment may or may not have been added'
              else
                'the comment was not added'
              end
      fail_job!("#{moved} #{added}. #{helpers.jira_failure_message(response, 'Add Comments', "Issue #{issue}")}")
    rescue StandardError => e
      raise if e.is_a?(IPaaS::Error)

      fail_job!("#{moved} Jira did not answer the comment request (#{e.message}), so the comment may or may " \
                'not have been added.')
    end

    helper :resolve_transition_id do |issue, transition|
      wanted = transition.to_s.strip
      next wanted if wanted.match?(DIGITS_PATTERN)

      helpers.id_by_name(wanted, helpers.available_transitions(issue),
                         "Jira has no transition named '#{wanted}' available on #{issue} right now.")
    end

    helper :trigger_scope_jql do |config|
      jql = "project = #{helpers.jql_value(helpers.checked_project_key(config[:project_key].to_s.strip))}"
      issue_type = config[:issue_type].to_s.strip
      next jql if issue_type.blank?
      next "#{jql} AND issuetype = #{issue_type}" if issue_type.match?(DIGITS_PATTERN)

      fail_job!("'#{issue_type}' is not a Jira issue type ID. Pick the issue type from the list.")
    end

    helper :verify_trigger_project do |config|
      key = helpers.checked_project_key(config[:project_key].to_s.strip)
      url = helpers.gateway_url(helpers.cloud_id, "#{API_PATH}/project/#{key}")
      response = helpers.jira_read(url, open_timeout: SHORT_OPEN_TIMEOUT, timeout: SHORT_TIMEOUT)
      project = helpers.handle_jira_response(response, resource: "Project #{key}")
      issue_type = config[:issue_type].to_s.strip
      next if issue_type.blank? || Array(project[:issueTypes]).any? { |type| type[:id].to_s == issue_type }

      fail_job!("Project #{key} has no issue type with ID #{issue_type}. Pick the issue type from the list.")
    end

    helper :selected_events do |events|
      chosen = Array(trigger.config[:fire_on])
      events.pluck(:id).select { |event| chosen.include?(event) }
    end

    helper :webhook_endpoint do
      endpoint = trigger.endpoint.to_s
      next endpoint if endpoint.start_with?(HTTPS_PREFIX)

      fail_job!("Jira sends webhooks to HTTPS addresses only, and the address of this trigger is #{endpoint}.")
    end

    helper :provision_webhook do |events|
      selected = helpers.selected_events(events)
      fail_job!('Pick Created, Updated or both under Fire on.') if selected.empty?

      jql = helpers.trigger_scope_jql(trigger.config)
      helpers.verify_trigger_project(trigger.config)
      endpoint = helpers.webhook_endpoint
      host = helpers.site_host
      signature = { host: host, endpoint: endpoint, events: selected, jql: jql }.to_json
      helpers.remove_poll_schedule
      helpers.delete_replaced_webhook
      stored = helpers.stored_row(WEBHOOK_STORE_KEY)
      if stored[:signature] == signature && helpers.webhook_healthy?(stored, endpoint, selected)
        next helpers.delete_unheld_webhooks(host, endpoint, stored[:id])
      end

      row = helpers.create_webhook(host, endpoint, selected, jql)
      replaced = stored[:id].present? ? stored.slice(:id, :host) : nil
      trigger.store.write(WEBHOOK_STORE_KEY, row.merge(signature: signature, replaces: replaced).compact)
      trigger.store.delete(POLL_CURSOR_STORE_KEY)
      helpers.delete_replaced_webhook
      helpers.delete_unheld_webhooks(host, endpoint, row[:id])
    end

    helper :webhook_healthy? do |webhook, endpoint, events|
      url = "#{helpers.webhook_url(webhook[:host])}/#{webhook[:id]}"
      response = http_get(url, nil, nil, open_timeout: SHORT_OPEN_TIMEOUT, timeout: SHORT_TIMEOUT)
      next false if response.status == 404

      found = helpers.success_status?(response.status) ? helpers.parse_json(response.body) : nil
      next true unless found.is_a?(Hash)

      found['enabled'] != false && found['isSigned'] == true &&
        found.dig('filters', WEBHOOK_FILTER_KEY) == webhook[:filter] &&
        found['url'] == endpoint && Array(found['events']).sort == events.sort
    rescue StandardError => e
      raise if e.is_a?(IPaaS::Error)

      log("Jira did not answer the check of webhook #{webhook[:id]} (#{e.message}), so the webhook is kept.")
      true
    end

    helper :delete_unheld_webhooks do |host, endpoint, held|
      base = helpers.webhook_url(host)
      response = http_get(base, nil, nil, open_timeout: SHORT_OPEN_TIMEOUT, timeout: SHORT_TIMEOUT)
      found = helpers.success_status?(response.status) ? helpers.parse_json(response.body) : nil
      Array(found).each do |webhook|
        id = webhook.is_a?(Hash) && webhook['url'] == endpoint ? webhook['self'].to_s.split('/').last.to_s : ''
        next if id == held || !id.match?(DIGITS_PATTERN)

        deleted = http_delete("#{base}/#{id}", nil, nil, open_timeout: SHORT_OPEN_TIMEOUT, timeout: SHORT_TIMEOUT)
        log("Jira webhook #{id} also sent to this trigger without iPaaS holding it; deleting it answered " \
            "HTTP #{deleted.status}.")
      end
    rescue StandardError => e
      raise if e.is_a?(IPaaS::Error)

      log("Jira did not answer the search for webhooks iPaaS does not hold (#{e.message}).")
    end

    helper :delete_replaced_webhook do
      stored = helpers.stored_row(WEBHOOK_STORE_KEY)
      next if stored[:replaces].blank?

      helpers.delete_webhook(stored[:replaces])
      trigger.store.write(WEBHOOK_STORE_KEY, stored.except(:replaces))
    end

    helper :remove_webhook do
      helpers.delete_replaced_webhook
      stored = helpers.stored_row(WEBHOOK_STORE_KEY)
      next if stored.empty?

      helpers.delete_webhook(stored)
      trigger.store.delete(WEBHOOK_STORE_KEY)
    end

    helper :delete_webhook do |webhook|
      cloud = helpers.webhook_cloud_id(webhook)
      next helpers.forget_webhook(webhook, 'no Jira Cloud site answers there') if cloud.nil?

      response = helpers.jira_write(:delete, "#{helpers.gateway_url(cloud, WEBHOOK_PATH)}/#{webhook[:id]}", nil,
                                    open_timeout: SHORT_OPEN_TIMEOUT, timeout: SHORT_TIMEOUT)
      helpers.jira_backoff(response, write: true)
      next if response.status == 404 || helpers.success_status?(response.status)

      moved = WEBHOOK_REFUSED_STATUSES.include?(response.status) && cloud != helpers.cloud_id
      next helpers.forget_webhook(webhook, "Jira there refused to delete it (HTTP #{response.status})") if moved

      helpers.refuse_webhook_delete(response, webhook)
    end

    helper :webhook_cloud_id do |webhook|
      helpers.cloud_id(webhook[:host])
    rescue IPaaS::Job::FailJob
      raise if webhook[:host] == helpers.site_host

      nil
    end

    helper :forget_webhook do |webhook, reason|
      log("iPaaS forgets webhook #{webhook[:id]} on #{webhook[:host]}, because #{reason} and the connection now " \
          "points to #{helpers.site_host}. Delete the webhook in Jira on #{webhook[:host]} under System, WebHooks.")
    end

    helper :refuse_webhook_delete do |response, webhook|
      advice = if response.status == 401
                 "#{WEBHOOK_TOKEN_ADVICE} Delete webhook #{webhook[:id]} in Jira on #{webhook[:host]} under System, " \
                   'WebHooks, then try again.'
               elsif READ_RETRY_STATUSES.include?(response.status)
                 'Jira is briefly unavailable. Try again in a few minutes.'
               else
                 'Delete it in Jira under System, WebHooks, then try again.'
               end
      fail_job!("Jira did not delete webhook #{webhook[:id]} (HTTP #{response.status}): " \
                "#{helpers.jira_error_detail(response).chomp('.')}. #{advice}")
    end

    helper :create_webhook do |host, endpoint, events, jql|
      secret = SecureRandom.uuid
      body = {
        name: "iPaaS #{endpoint}",
        url: endpoint,
        events: events,
        filters: { WEBHOOK_FILTER_KEY => jql },
        excludeBody: false,
        secret: secret,
      }
      response = helpers.jira_write(:post, helpers.webhook_url(host), body,
                                    open_timeout: SHORT_OPEN_TIMEOUT, timeout: SHORT_TIMEOUT)
      helpers.refuse_status(response, 401, 'Jira refused to register the webhook', WEBHOOK_TOKEN_ADVICE)
      result = helpers.handle_jira_response(response, write: true, permission: 'Administer Jira')
      row = { id: result[:self].to_s.split('/').last.to_s, host: host,
              filter: result.dig(:filters, WEBHOOK_FILTER_KEY), }.with_indifferent_access
      unless row[:id].match?(DIGITS_PATTERN)
        fail_job!('Jira registered the webhook but returned no webhook ID, so iPaaS cannot delete it later. ' \
                  'Delete it in Jira under System, WebHooks.')
      end

      problem = helpers.webhook_problem(result)
      next row.merge(secret: make_secret_string(secret).to_s) if problem.nil?

      trigger.store.write(WEBHOOK_STORE_KEY, helpers.stored_row(WEBHOOK_STORE_KEY).merge(replaces: row))
      helpers.delete_replaced_webhook
      fail_job!("Jira registered webhook #{row[:id]} #{problem}, so iPaaS deleted it again.")
    end

    helper :webhook_problem do |result|
      next 'without the JQL filter' if result.dig(:filters, WEBHOOK_FILTER_KEY).blank?
      next 'without the secret, so its events are not signed' unless result[:isSigned] == true
    end

    helper :verified_delivery do |request, events|
      raw_body = request.body&.read
      discard_trigger_event!('Jira webhook request has no body') if raw_body.blank?

      stored = helpers.stored_row(WEBHOOK_STORE_KEY)
      secret = stored[:secret]
      if secret.blank?
        discard_trigger_event!('This Jira trigger has no stored webhook secret, so the delivery cannot be ' \
                               'verified. Promote the runbook again to register the webhook again.')
      end

      signature = request.headers['X-Hub-Signature'].to_s
      discard_trigger_event!('Missing X-Hub-Signature header') if signature.blank?
      expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', decrypt_secret_string(secret).to_s, raw_body)}"
      discard_trigger_event!('Invalid Jira webhook signature') unless OpenSSL.secure_compare(expected, signature)

      json = helpers.parse_trigger_json(raw_body)
      event = json[:webhookEvent].to_s
      discard_trigger_event!('Jira payload carries no webhookEvent') if event.blank?
      unless helpers.selected_events(events).include?(event)
        discard_trigger_event!("Event #{event} is not selected on this trigger")
      end
      helpers.refuse_old_delivery(json[:timestamp])
      if helpers.webhook_scope_changed?(stored)
        discard_trigger_event!('This event comes from a Jira webhook registered for other trigger settings. Promote ' \
                               'the runbook again so that iPaaS registers one for the current settings.')
      end

      json
    end

    helper :webhook_scope_changed? do |stored|
      registered = helpers.parse_json(stored[:signature].to_s)
      !registered.is_a?(Hash) || registered['jql'] != helpers.trigger_scope_jql(trigger.config)
    rescue IPaaS::Job::FailJob
      true
    end

    helper :refuse_old_delivery do |timestamp|
      next if timestamp.blank?

      oldest = helpers.epoch_milliseconds(Time.now) - (WEBHOOK_MAX_AGE_SECONDS * MILLISECONDS_PER_SECOND)
      next if timestamp.to_i >= oldest

      discard_trigger_event!('Jira sent this event more than a day ago, so it is dropped as a possible replay.')
    end

    helper :delivery_output do |request, json, subject_id|
      event = json[:webhookEvent]
      {
        deduplication_id: request.headers['X-Atlassian-Webhook-Identifier'].presence ||
          "#{event}-#{subject_id}-#{json[:timestamp]}",
        webhook_event: event,
        timestamp: json[:timestamp],
      }
    end

    helper :fetch_event_text do |path, params|
      cloud_id = outbound_connection.store.read("#{CLOUD_ID_STORE_PREFIX}#{helpers.site_host}")
      if cloud_id.blank?
        log('The event text was not read, because the cloud ID of the Jira site is not known yet.')
        next [nil, TEXT_FETCH_FAILED]
      end

      response = http_get(helpers.gateway_url(cloud_id, "#{API_PATH}/#{path}"), params, nil,
                          open_timeout: SHORT_OPEN_TIMEOUT, timeout: EVENT_TEXT_TIMEOUT)
      next [nil, TEXT_NOT_VISIBLE] if TEXT_NOT_VISIBLE_STATUSES.include?(response.status)

      parsed = helpers.success_status?(response.status) ? helpers.parse_json(response.body) : nil
      next [parsed.with_indifferent_access, nil] if parsed.is_a?(Hash)

      log("The event text was not read. #{helpers.jira_failure_message(response, 'Browse Projects', nil)}")
      [nil, TEXT_FETCH_FAILED]
    rescue IPaaS::Job::FailJob => e
      log("The event text was not read: #{e.message}")
      [nil, TEXT_FETCH_FAILED]
    rescue StandardError => e
      raise if e.is_a?(IPaaS::Error)

      log("The event text was not read, because Jira did not answer (#{e.message}).")
      [nil, TEXT_FETCH_FAILED]
    end

    helper :event_description do |issue|
      sent = issue.dig(:fields, :description)
      next [nil, nil] if sent.blank?

      fetched, reason = helpers.fetch_event_text("issue/#{helpers.safe_id(issue[:id], 'issue_id')}",
                                                 { fields: 'description' })
      next [nil, reason] if reason == TEXT_NOT_VISIBLE
      next [helpers.payload_text(sent), reason] if fetched.nil?

      [helpers.adf_to_text(fetched.dig(:fields, :description)).strip.presence, nil]
    end

    helper :payload_text do |value|
      next helpers.adf_to_text(value).strip.presence unless value.is_a?(String)

      value.gsub(WIKI_HEADING, '')
           .gsub(WIKI_BLOCK_MACRO, '')
           .gsub(WIKI_MENTION, '@\1')
           .gsub(WIKI_LINK, '\1 (\2)')
           .gsub(WIKI_BULLET, '- ')
           .gsub(WIKI_BOLD, '\1')
           .gsub(WIKI_ITALIC, '\1')
           .strip.presence
    end

    helper :event_comment do |issue, comment|
      path = "issue/#{helpers.safe_id(issue[:id], 'issue_id')}/comment/#{helpers.safe_id(comment[:id], 'comment_id')}"
      fetched, reason = helpers.fetch_event_text(path, nil)
      source = fetched || comment
      output = helpers.comment_output(source).merge(
        update_author: helpers.account_output(source[:updateAuthor]),
        text_unavailable_reason: reason
      )
      next output if fetched

      output.merge(comment_body: reason == TEXT_NOT_VISIBLE ? nil : helpers.payload_text(comment[:body]))
    end

    helper :parse_trigger_json do |raw_body|
      parsed = helpers.parse_json(raw_body)
      discard_trigger_event!('Jira webhook body is not a JSON object') unless parsed.is_a?(Hash)
      parsed.with_indifferent_access
    end

    helper :provision_poll do |time_field|
      scope = helpers.trigger_scope_jql(trigger.config)
      helpers.verify_trigger_project(trigger.config)
      took_over = helpers.stored_row(WEBHOOK_STORE_KEY).present?
      helpers.remove_webhook
      helpers.ensure_poll_schedule
      helpers.start_poll_cursor(scope, time_field, at: took_over ? helpers.current_second : nil)
    end

    helper :stored_row do |key|
      row = trigger.store.read(key)
      row.is_a?(Hash) ? row : {}
    end

    helper :start_poll_cursor do |scope, time_field, check: false, at: nil|
      initial = helpers.initial_poll_cursor(scope, time_field, at)
      next false if helpers.same_poll_setup?(helpers.stored_row(POLL_CURSOR_STORE_KEY), initial)
      discard_trigger_event!(POLL_SETTINGS_CHANGED) if check && helpers.poll_setup_recent?

      trigger.store.write(POLL_SETUP_STORE_KEY, { at: Time.now.to_f })
      trigger.store.write(POLL_CURSOR_STORE_KEY, initial)
      true
    end

    helper :poll_setup_recent? do
      Time.now.to_f - helpers.stored_row(POLL_SETUP_STORE_KEY)[:at].to_f < POLL_SETUP_GRACE_SECONDS
    end

    helper :ensure_poll_schedule do
      attributes = {
        frequency: SCHEDULE_FREQUENCY,
        interval: trigger.config[:poll_minutes],
        time_zone: SCHEDULE_TIME_ZONE,
      }
      reference = helpers.stored_row(SCHEDULE_STORE_KEY)[:reference]
      next helpers.create_poll_schedule(attributes) if reference.blank?

      result = update_schedule(reference, attributes)
      next if result[:success]
      next helpers.create_poll_schedule(attributes) if result[:error] == SCHEDULE_NOT_FOUND

      fail_job!("The schedule of this Jira trigger was not updated: #{result[:error]}")
    end

    helper :create_poll_schedule do |attributes|
      result = create_schedule!(runbook.uuid, attributes.merge(reference: SecureRandom.uuid))
      fail_job!("The schedule of this Jira trigger was not created: #{result[:error]}") unless result[:success]

      trigger.store.write(SCHEDULE_STORE_KEY, { reference: result[:schedule_reference] })
    end

    helper :remove_poll_schedule do
      reference = helpers.stored_row(SCHEDULE_STORE_KEY)[:reference]
      next if reference.blank?

      soft_delete_schedule(reference)
      trigger.store.delete(SCHEDULE_STORE_KEY)
    end

    helper :poll_issues do |request, time_field|
      scope = helpers.trigger_scope_jql(trigger.config)
      scheduled = request.path.to_s.start_with?(SCHEDULER_PATH_PREFIX)
      next helpers.poll_batch(scope, time_field, POLL_PREVIEW_PREFIX)[:output] unless scheduled

      trigger.with_lock(POLL_LOCK_KEY, ttl: POLL_LOCK_TTL_SECONDS) do
        discard_trigger_event!(POLL_CURSOR_STARTED) if helpers.start_poll_cursor(scope, time_field, check: true)
        helpers.skip_undelivered_batch
        batch = helpers.poll_batch(scope, time_field)
        helpers.stage_poll_cursor(batch)
        batch[:output]
      end
    end

    helper :stage_poll_cursor do |batch|
      staged = helpers.stored_row(POLL_STAGED_STORE_KEY)
      checks = staged[:from] == batch[:start][:at] ? staged[:checks].to_i + 1 : 1
      trigger.store.write(POLL_STAGED_STORE_KEY,
                          { cursor: batch[:cursor], from: batch[:start][:at], checks: checks, keys: batch[:keys] })
    end

    helper :skip_undelivered_batch do
      staged = helpers.stored_row(POLL_STAGED_STORE_KEY)
      next if staged[:checks].to_i < POLL_MAX_UNSAVED_CHECKS

      log("Jira issues #{Array(staged[:keys]).join(', ')} were found by #{staged[:checks]} checks in a row and " \
          'never delivered, so the trigger goes on after them.')
      helpers.commit_poll_cursor(staged[:cursor])
      trigger.store.delete(POLL_STAGED_STORE_KEY)
    end

    helper :settle_staged_poll do |context|
      next unless context[:request]&.path.to_s.start_with?(SCHEDULER_PATH_PREFIX)

      staged = helpers.stored_row(POLL_STAGED_STORE_KEY)
      next if staged.empty?

      if context[:job_uuid].present?
        helpers.commit_poll_cursor(staged[:cursor])
        trigger.store.delete(POLL_STAGED_STORE_KEY)
      elsif helpers.dropped_by_platform?(context)
        trigger.store.write(POLL_STAGED_STORE_KEY, staged.merge(checks: 0))
      end
    end

    helper :dropped_by_platform? do |context|
      error = context[:error]
      error.is_a?(IPaaS::Job::DiscardTriggerEvent) && error.message == PLATFORM_DROP
    end

    helper :resend_dropped_event do |context, response|
      next response unless helpers.dropped_by_platform?(context)

      log('The concurrency limit of the runbook dropped this event, so Jira is asked to send it again.')
      response.merge(status: 503, headers: response[:headers].merge('Retry-After' => DROPPED_EVENT_RETRY_AFTER))
    end

    helper :poll_batch do |scope, time_field, id_prefix = ''|
      start = helpers.poll_cursor(scope, time_field)
      found = helpers.poll_pages(scope, time_field, start)
      issues = found[:issues]
      discard_trigger_event!('Jira has no new or changed issues since the last check.') if issues.empty?

      log("Jira issues found: #{issues.map { |issue| issue[:key] }.join(', ')}")
      output = {
        deduplication_id: "#{id_prefix}#{time_field}-#{start[:at]}-#{issues.first[:key]}-#{issues.size}",
        issues: issues.map { |issue| helpers.issue_output_without_description(issue) },
      }
      { cursor: found[:cursor], start: start, keys: issues.map { |issue| issue[:key] }, output: output }
    end

    helper :poll_pages do |scope, time_field, start|
      upper = helpers.settled_second
      deadline = Time.now.to_f + POLL_TIME_BUDGET_SECONDS
      (0...POLL_MAX_PAGES).each_with_object({ cursor: start, issues: [] }) do |_page, found|
        result = helpers.poll_page(helpers.poll_jql(scope, time_field, found[:cursor], upper), found[:issues])
        page = Array(result && result[:issues]).reject { |issue| helpers.issue_second(issue, time_field) > upper }
        page.each { |issue| found[:issues].push(issue) }
        found[:cursor] = helpers.next_poll_cursor(found[:cursor], page, time_field)
        break found if page.empty? || result[:isLast] != false || Time.now.to_f >= deadline
      end
    end

    helper :poll_page do |jql, collected|
      body = { jql: jql, maxResults: MAX_PAGE_SIZE, fields: DEFAULT_ISSUE_FIELDS - [COMMENT_FIELD] }
      response = helpers.jira_read(helpers.jira_url('search/jql'),
                                   body: body, open_timeout: SHORT_OPEN_TIMEOUT, timeout: POLL_SEARCH_TIMEOUT)
      helpers.handle_jira_response(response, permission: 'Browse Projects')
    rescue IPaaS::Job::RescheduleJob
      raise if collected.empty?

      nil
    end

    helper :poll_jql do |scope, time_field, cursor, upper|
      at = cursor[:at]
      clauses = [scope, "#{time_field} >= #{at}", "#{time_field} <= #{upper}"]
      keys = cursor[:keys].map { |key| helpers.jql_value(key) }
      clauses.push("NOT (#{time_field} < #{at + MILLISECONDS_PER_SECOND} AND key in (#{keys.join(', ')}))") if keys.any?
      "#{clauses.join(' AND ')} ORDER BY #{time_field} ASC, key ASC"
    end

    helper :poll_cursor do |scope, time_field|
      initial = helpers.initial_poll_cursor(scope, time_field)
      stored = helpers.stored_row(POLL_CURSOR_STORE_KEY)
      next initial unless helpers.same_poll_setup?(stored, initial)

      initial.merge(at: stored[:at].to_i, keys: Array(stored[:keys]))
    end

    helper :initial_poll_cursor do |scope, time_field, at = nil|
      { at: at || helpers.settled_second, keys: [], scope: scope, time_field: time_field }
    end

    helper :same_poll_setup? do |stored, cursor|
      stored[:scope] == cursor[:scope] && stored[:time_field] == cursor[:time_field]
    end

    helper :next_poll_cursor do |cursor, issues, time_field|
      next cursor if issues.empty?

      at = helpers.issue_second(issues.last, time_field)
      keys = issues.select { |issue| helpers.issue_second(issue, time_field) == at }.map { |issue| issue[:key] }
      cursor.merge(at: at, keys: at == cursor[:at] ? cursor[:keys] | keys : keys)
    end

    helper :commit_poll_cursor do |cursor|
      stored = helpers.stored_row(POLL_CURSOR_STORE_KEY)
      next unless helpers.same_poll_setup?(stored, cursor) && stored[:at].to_i <= cursor[:at]

      trigger.store.write(POLL_CURSOR_STORE_KEY, cursor)
    end

    helper :issue_second do |issue, time_field|
      helpers.floor_second(helpers.epoch_milliseconds(Time.parse(issue.dig(:fields, time_field).to_s)))
    end

    helper :settled_second do
      helpers.current_second - (POLL_SETTLE_SECONDS * MILLISECONDS_PER_SECOND)
    end

    helper :current_second do
      helpers.floor_second(helpers.epoch_milliseconds(Time.now))
    end

    helper :floor_second do |milliseconds|
      milliseconds - (milliseconds % MILLISECONDS_PER_SECOND)
    end

    helper :issue_output_without_description do |issue|
      output = helpers.issue_output(issue)
      output.merge(fields: output[:fields].except(:description))
    end

    helper :payload_issue_output do |issue|
      category = issue.dig(:fields, :status, :statusCategory) || {}
      helpers.issue_output_without_description(issue).merge(
        status_category: STATUS_CATEGORY_NAMES.fetch(category[:key].to_s, category[:name])
      )
    end
  end
end
