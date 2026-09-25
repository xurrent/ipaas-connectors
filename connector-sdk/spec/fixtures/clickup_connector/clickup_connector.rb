class ClickupConnector < IPaaS::Connector::Definition
  BASE_URL = 'https://api.clickup.com/api/v2'.freeze
  TRUNCATED_BODY_LIMIT = 500
  MAX_OPTION_PAGES = 10

  # The full ClickUp v2 webhook event catalogue. One trigger subscribes to one or more of these.
  WEBHOOK_EVENTS = %w[
    taskCreated taskUpdated taskDeleted taskPriorityUpdated taskStatusUpdated
    taskAssigneeUpdated taskDueDateUpdated taskTagUpdated taskMoved
    taskCommentPosted taskCommentUpdated taskTimeEstimateUpdated taskTimeTrackedUpdated
    listCreated listUpdated listDeleted
    folderCreated folderUpdated folderDeleted
    spaceCreated spaceUpdated spaceDeleted
    goalCreated goalUpdated goalDeleted
    keyResultCreated keyResultUpdated keyResultDeleted
  ].freeze

  PRIORITIES = [
    { id: 1, label: 'Urgent' }, { id: 2, label: 'High' },
    { id: 3, label: 'Normal' }, { id: 4, label: 'Low' },
  ].freeze

  connector '019fed58-1d55-741b-b14d-c9366049dd7d' do
    name 'ClickUp'
    avatar '/assets/icons/clickup.svg'
    description <<~END_OF_DESCRIPTION
      Integrate ClickUp with Xurrent iPaaS to manage ClickUp tasks and react to ClickUp events. The connector exposes task, comment, attachment, and structure actions plus a single event-driven trigger.

      # Authentication

      Configure the outbound connection with a **ClickUp API token** and a **Workspace**. Use either a personal token (starts with `pk_`, generated in ClickUp under Settings > Apps > API Token) or an OAuth2 access token. The connector detects the type automatically: a personal token is sent as `Authorization: <token>` and an OAuth token as `Authorization: Bearer <token>`. Tokens are stored encrypted and never shown after saving.

      Save the token first, then pick the Workspace from the list, which the connector reads with that token. Every trigger and action on the connection works in that one Workspace, so no step asks for it again. To work in a second Workspace, create a second connection.

      # Actions

      Task: **Create Task**, **Get Task**, **Update Task**, **Delete Task**, **Update Task Status**, **Assign User To Task**. Comments: **Create Task Comment**, **Get Task Comments**. Attachments: **Upload Task Attachment**, **Get Task Attachments**. Structure: **Create List**, **Create Folderless List**, **Create Folder**. Reads (to look up ids at run time, since the fields above are filled from dropdowns while authoring): **Get Authorized User**, **Get Workspaces**, **Get Spaces**, **Get Folders**, **Get Lists**, **Get Folderless Lists**, **Get List Members**, **Get Workspace Members**.

      # Trigger

      **ClickUp Event** subscribes to one or more ClickUp webhook events selected in the trigger config (any of the 28 task, list, folder, space, goal, or key-result events). One subscription covers every event you select, and the workflow starts once per delivery with the `event` output field naming which one fired. The webhook is registered on the Workspace the connection carries. ClickUp signs every delivery, and the trigger verifies the signature before running. Task events are enriched with the full task via a follow-up Get Task call; other events pass their payload through. Optional filters restrict which deliveries start a workflow: a location filter (list, folder, or space) is enforced by ClickUp at the source, and the status and assignee filters are applied by the trigger to the one event each can judge (`taskStatusUpdated` and `taskAssigneeUpdated`). Every other selected event is delivered unfiltered, so keep a narrowly filtered trigger to a small event selection.

      # Best Practices

      Select only the events the workflow acts on, and branch on the `event` output field when you select more than one. Give a trigger its own runbook when the handling differs per event. Pick the Space, Folder, and List from their dropdowns rather than hard-coding ids; each list is read from the connection's Workspace. Prefer a location filter over a broad subscription on busy workspaces so ClickUp delivers only the events you need. Remember that the status and assignee filters judge one event each, so pair either filter with a matching event selection rather than a broad one.

      # Common Use Cases

      Create a ClickUp task when a Xurrent request is submitted. Post Xurrent updates as ClickUp comments. Start a Xurrent workflow when a ClickUp task changes status. Synchronise attachments between systems.

      # Rate Limiting

      ClickUp allows 100 requests per minute per token on most plans (more on Business Plus and Enterprise). The connector backs off and retries on HTTP 429. It waits for the number of seconds in the Retry-After response header, and for 60 seconds when that header is absent.

      # References

      * ClickUp API reference: https://developer.clickup.com/reference
      * ClickUp webhooks: https://developer.clickup.com/docs/webhooks
      * Webhook signature: https://developer.clickup.com/docs/webhooksignature
    END_OF_DESCRIPTION

    inbound_connection do
      # ClickUp mints the signing secret per webhook (not per connection), so the HMAC check
      # runs in the trigger's parse, which can read that per-webhook secret from the trigger
      # store. The framework requires a validate block, so this one is a deliberate no-op:
      # unverifiable or forged deliveries are discarded (HTTP 200) in parse rather than rejected
      # with an error here, so junk traffic to the public endpoint cannot drive ClickUp's
      # webhook fail_count to the suspension threshold.
      validate do |_request|
        nil
      end
    end

    outbound_connection do
      config_schema do
        field :api_token, 'ClickUp API token', :secret_string, required: true,
                                                               hint: 'A ClickUp personal token (starts with pk_, ' \
                                                                     'from Settings > Apps > API Token) or an OAuth2 ' \
                                                                     'access token.'
        field :workspace_id, 'Workspace/Team', :string, required: true,
                                                        hint: 'The ClickUp Workspace every trigger and action on ' \
                                                              'this connection works in. Save the token first, ' \
                                                              'then select from the list.' do
          options do
            helpers.fetch_workspace_options
          end
        end
      end

      authenticate do |request|
        token = decrypt_secret_string(config[:api_token]).to_s.strip
        # ClickUp sends a personal token raw, but an OAuth access token with the Bearer scheme.
        request.headers['Authorization'] = token.start_with?('pk_') ? token : "Bearer #{token}"
      end
    end

    helper :truncate_body do |body|
      s = body.to_s
      s.length > TRUNCATED_BODY_LIMIT ? "#{s[0, TRUNCATED_BODY_LIMIT - 3]}..." : s
    end

    helper :parse_json_object do |raw, label|
      parsed = JSON.parse(raw)
      fail_job!("#{label}: expected a JSON object, got #{parsed.class}") unless parsed.is_a?(Hash)
      parsed.with_indifferent_access
    rescue JSON::ParserError => e
      fail_job!("#{label}: #{e.message}")
    end

    # Applies rate-limit backoff, then parses the ClickUp response. ClickUp returns a JSON
    # error body { err, ECODE, message } on failure and 204 with an empty body on delete.
    helper :handle_clickup_response do |response|
      backoff_if_needed(response, api_name: 'ClickUp')
      status = response.status
      text = response.body.to_s
      parsed =
        if text.blank?
          {}
        else
          begin
            JSON.parse(text)
          rescue JSON::ParserError
            fail_job!("ClickUp returned HTTP #{status} with a non-JSON body: #{helpers.truncate_body(text)}")
          end
        end
      unless parsed.is_a?(Hash)
        fail_job!("ClickUp returned HTTP #{status} with a JSON #{parsed.class}, expected an object: " \
                  "#{helpers.truncate_body(text)}")
      end
      body = parsed.with_indifferent_access
      unless status >= 200 && status < 300
        detail = if body[:err].present?
                   "#{body[:err]} (#{body[:ECODE]})"
                 else
                   helpers.truncate_body(text)
                 end
        fail_job!("ClickUp API error (HTTP #{status}): #{detail}")
      end
      body
    end

    helper :clickup_get do |path, params = {}|
      helpers.handle_clickup_response(http_get("#{BASE_URL}/#{path}", params.transform_values(&:to_s)))
    end

    helper :clickup_post do |path, body = {}|
      helpers.handle_clickup_response(http_post("#{BASE_URL}/#{path}", body.to_json,
                                                { 'Content-Type' => 'application/json' }))
    end

    helper :clickup_put do |path, body = {}|
      helpers.handle_clickup_response(http_put("#{BASE_URL}/#{path}", body.to_json,
                                               { 'Content-Type' => 'application/json' }))
    end

    helper :clickup_delete do |path|
      helpers.handle_clickup_response(http_delete("#{BASE_URL}/#{path}"))
    end

    helper :comma_ints do |value, label|
      helpers.comma_strings(value).map do |part|
        fail_job!("#{label} must be numeric ClickUp user ids, got '#{part}'") unless part.match?(/\A\d+\z/)

        part.to_i
      end
    end

    helper :comma_strings do |value|
      value.to_s.split(',').map(&:strip).reject(&:blank?)
    end

    helper :fetch_workspace_options do
      helpers.fetch_options_keyed('team', 'teams')
    end

    # Deprovisioning is the one caller that forgets the id straight afterwards, so the stored row is
    # the last thing that can still reach this webhook. A 429 escapes as a reschedule and keeps the
    # row, because the retry is the only way the webhook ever comes down. A refusal ClickUp will
    # give again is logged and the row goes, so deprovisioning is not blocked for ever.
    helper :delete_webhook_or_reschedule do |webhook_id, reason|
      helpers.clickup_delete("webhook/#{helpers.safe_id(webhook_id, 'webhook id')}")
    rescue IPaaS::Job::FailJob => e
      log('Could not delete ClickUp webhook %<id>s (%<reason>s): %<error>s',
          { id: webhook_id, reason: reason, error: e.message })
    end

    # Answers whether the webhook is gone, so provision can decide what to keep. A refusal and a
    # rate limit both answer false: the caller holds the only remaining copy of the id and has to
    # keep it until ClickUp confirms the delete.
    helper :webhook_deleted? do |webhook_id, reason|
      helpers.clickup_delete("webhook/#{helpers.safe_id(webhook_id, 'webhook id')}")
      true
    rescue IPaaS::Job::FailJob, IPaaS::Job::RescheduleJob => e
      log('Could not delete ClickUp webhook %<id>s (%<reason>s): %<error>s',
          { id: webhook_id, reason: reason, error: e.message })
      false
    end

    helper :connection_workspace_id do
      id = outbound_connection.config[:workspace_id].presence ||
           fail_job!('This ClickUp connection has no Workspace selected. Select one on the connection.')
      helpers.safe_id(id, 'workspace_id')
    end

    helper :fetch_space_options do
      helpers.fetch_options_keyed("team/#{helpers.connection_workspace_id}/space", 'spaces')
    end

    helper :fetch_folder_options do |space_id:|
      helpers.fetch_options_keyed("space/#{helpers.safe_id(space_id, 'space_id')}/folder", 'folders')
    end

    helper :fetch_list_options do |space_id: nil, folder_id: nil|
      next [] if folder_id.blank? && space_id.blank?

      path = if folder_id.present?
               "folder/#{helpers.safe_id(folder_id, 'folder_id')}/list"
             else
               "space/#{helpers.safe_id(space_id, 'space_id')}/list"
             end
      helpers.fetch_options_keyed(path, 'lists')
    end

    # Tasks are the one ClickUp collection that pages, and a dropdown that stops at the first page
    # drops the saved task off its own list. The page cap bounds the fetch inside the deadline.
    helper :fetch_task_options do |list_id:|
      path = "list/#{helpers.safe_id(list_id, 'list_id')}/task"
      (0...MAX_OPTION_PAGES).each_with_object([]) do |page, options|
        body = helpers.clickup_get(path, { page: page })
        helpers.options_from(body, 'tasks', path).each { |option| options.push(option) }
        break options if body[:last_page]
      end
    end

    helper :fetch_options_keyed do |path, collection, id_key = 'id', label_key = 'name'|
      helpers.options_from(helpers.clickup_get(path), collection, path, id_key, label_key)
    end

    helper :options_from do |body, collection, path, id_key = 'id', label_key = 'name'|
      items = body[collection]
      unless items.is_a?(Array)
        err = body[:err].presence
        code = body[:ECODE].presence
        detail = err && (code ? "#{err} (#{code})" : err)
        message = "ClickUp options request to #{path} returned no '#{collection}' list"
        fail_job!(detail ? "#{message}: #{detail}" : message)
      end

      items.map { |item| { id: item[id_key].to_s, label: (item[label_key] || item[id_key]).to_s } }
    end

    # Every id that reaches a URL passes through here first. Checking the assembled path instead
    # would pass a slash-bearing id as a run of legal segments and silently retarget the request.
    helper :safe_id do |value, label|
      id = value.to_s
      fail_job!("ClickUp #{label} is not path safe: '#{id}'") unless id.match?(/\A[\w-]+\z/)

      id
    end

    helper :fetch_assignee_options do |list_id:|
      helpers.fetch_options_keyed("list/#{helpers.safe_id(list_id, 'list_id')}/member", 'members', 'id', 'username')
    end

    helper :fetch_status_options do |list_id:|
      helpers.fetch_options_keyed("list/#{helpers.safe_id(list_id, 'list_id')}", 'statuses', 'status', 'status')
    end

    helper :fetch_tag_options do |space_id:|
      helpers.fetch_options_keyed("space/#{helpers.safe_id(space_id, 'space_id')}/tag", 'tags', 'name', 'name')
    end

    trigger '019fed58-1d55-76d4-bdfc-16fcf316c40c' do
      name 'ClickUp Event'
      avatar '/assets/icons/clickup.svg'
      description 'Starts a workflow when one of the selected ClickUp webhook events fires. Verifies the ' \
                  'signature, applies optional filters, and enriches task events with the full task.'
      outbound_traffic true

      config_schema do
        field :event, 'Events', :string, array: true, required: true, enumeration: WEBHOOK_EVENTS,
                                         hint: 'The ClickUp events to subscribe to. Add one or more; the run ' \
                                               'reports which one fired in the Event output field.'
        field :space_id, 'Space filter', :string, visibility: 'optional',
                                                  hint: 'Optional. Deliver only events for this Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder filter', :string, visibility: 'optional',
                                                    hint: 'Optional. Deliver only events for this Folder. Select ' \
                                                          'from the list once a Space is chosen.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
        field :list_id, 'List filter', :string, visibility: 'optional',
                                                hint: 'Optional. Deliver only events for this List (most specific ' \
                                                      'location scope). Select from the list once a Space or ' \
                                                      'Folder is chosen.' do
          options do |space_id: nil, folder_id: nil|
            helpers.fetch_list_options(space_id: space_id, folder_id: folder_id)
          end
        end
        field :status_filter, 'Status filter', :string, visibility: 'optional',
                                                        hint: 'Optional. Fire only when the new status matches ' \
                                                              '(taskStatusUpdated only). Select a List filter to ' \
                                                              'populate the statuses.' do
          options do |list_id:|
            helpers.fetch_status_options(list_id: list_id)
          end
        end
        field :assignee_filter, 'Assignee filter', :string, visibility: 'optional',
                                                            hint: 'Optional. Fire only when this assignee is added ' \
                                                                  'or removed (taskAssigneeUpdated only). Select a ' \
                                                                  'List filter to populate the members.' do
          options do |list_id:|
            helpers.fetch_assignee_options(list_id: list_id)
          end
        end
      end

      output_schema do
        field :event, 'Event', :string, required: true
        field :webhook_id, 'Webhook ID', :string
        field :task_id, 'Task ID', :string
        field :list_id, 'List ID', :string
        field :folder_id, 'Folder ID', :string
        field :space_id, 'Space ID', :string
        field :goal_id, 'Goal ID', :string
        field :key_result_id, 'Key Result ID', :string
        field :history_items, 'History items', :nested, array: true do
          field :id, 'ID', :string
          field :type, 'Type', :integer
          field :date, 'Date', :string
          field :field, 'Field', :string
        end
        field :task, 'Task', :hash
      end

      provision do
        raw_events = trigger.config[:event]
        events = (raw_events.is_a?(Array) ? raw_events : [raw_events]).compact.sort
        fail_job!('No event selected for the trigger') if events.empty?

        scope =
          if trigger.config[:list_id].present?
            { list_id: trigger.config[:list_id] }
          elsif trigger.config[:folder_id].present?
            { folder_id: trigger.config[:folder_id] }
          elsif trigger.config[:space_id].present?
            { space_id: trigger.config[:space_id] }
          else
            {}
          end

        workspace_id = helpers.connection_workspace_id
        # Everything the subscription is made of belongs in the signature. Leaving the workspace or
        # the endpoint out means a trigger moved to another Workspace matches its own stored entry
        # and keeps the webhook it should have replaced.
        signature = { workspace_id: workspace_id, endpoint: trigger.endpoint,
                      events: events, scope: scope, }.to_json
        stored = trigger.store.read('webhook')

        # A run that created the new webhook but could not delete the one it replaced left that id
        # in the row. Draining it has to happen before the signature check below, because once the
        # signature matches every line after it is skipped and nothing would name that webhook
        # again. The id stays in the row until ClickUp confirms the delete.
        replaced = stored.is_a?(Hash) ? stored[:replaces] : nil
        if replaced.present? && helpers.webhook_deleted?(replaced, 'left behind by an earlier provision')
          stored = stored.merge('replaces' => nil)
          trigger.store.write('webhook', stored)
        end

        next if stored.is_a?(Hash) && stored[:signature] == signature

        created = helpers.clickup_post("team/#{workspace_id}/webhook",
                                       { endpoint: trigger.endpoint, events: events }.merge(scope))
        # ClickUp returns the created webhook's id and signing secret nested under a "webhook"
        # object (with the id also echoed at the top level); read both from there.
        webhook = created[:webhook].presence || created
        if webhook[:id].blank?
          fail_job!('ClickUp did not return a webhook id')
        elsif webhook[:secret].blank?
          # The webhook is already live at ClickUp and unusable without its secret, so take it back
          # down rather than leave it delivering to an endpoint that can never verify it.
          helpers.webhook_deleted?(webhook[:id], 'created without a signing secret')
          fail_job!('ClickUp did not return a webhook secret')
        end

        previous_id = stored.is_a?(Hash) ? stored[:id] : nil

        # Written before the old webhook is removed: a failed delete then costs a stale
        # subscription, where a failed write would lose the new webhook's id and secret for good.
        # The id being replaced is written with the row rather than kept in a local, because the
        # delete below can be rate limited and the signature check above would skip this block on
        # every later run.
        row = {
          'id' => webhook[:id],
          'secret' => make_secret_string(webhook[:secret]).to_s,
          'signature' => signature,
          'replaces' => previous_id,
        }
        trigger.store.write('webhook', row)

        next if previous_id.blank?

        trigger.store.write('webhook', row.merge('replaces' => nil)) if
          helpers.webhook_deleted?(previous_id, 'replaced by a new subscription')
      end

      deprovision do
        stored = trigger.store.read('webhook')
        next unless stored.is_a?(Hash) && stored[:id].present?

        if stored[:replaces].present?
          helpers.delete_webhook_or_reschedule(stored[:replaces], 'left behind by an earlier provision')
        end
        helpers.delete_webhook_or_reschedule(stored[:id], 'trigger deprovisioned')
        trigger.store.delete('webhook')
      end

      parse do |request|
        # ClickUp's secret is per-webhook, verified here because parse can read the trigger store.
        # Verification failures are DISCARDED (HTTP 200, no job), not failed, so junk or forged
        # requests to the public endpoint never accrue ClickUp fail_count toward suspension.
        # X-Signature is a hex HMAC-SHA256 of the raw body keyed by the webhook secret.
        raw_body = request.body&.read
        discard_trigger_event!('Webhook request has no body') if raw_body.blank?
        stored = trigger.store.read('webhook')
        unless stored.is_a?(Hash) && stored[:secret].present?
          discard_trigger_event!('Trigger is not subscribed (no stored webhook secret)')
        end
        signature = request.headers['X-Signature']
        discard_trigger_event!('Missing X-Signature header') if signature.blank?
        expected = OpenSSL::HMAC.hexdigest('SHA256', decrypt_secret_string(stored[:secret]).to_s, raw_body)
        discard_trigger_event!('Invalid webhook signature') unless OpenSSL.secure_compare(expected, signature.to_s)

        json = helpers.parse_json_object(raw_body, 'Invalid ClickUp webhook body')
        event = json[:event]
        fail_job!('Webhook payload has no event') if event.blank?
        history = json[:history_items] || []

        # Attribute filters run before hydration so a filtered-out event costs no Get Task call.
        # A status change carries the new status at after.status; an assignee change names the user
        # at after.id when added and before.id when removed, so both sides are collected.
        # ClickUp sends a bare string for before/after on text fields such as name and content, so
        # each side is read only where it is an object: digging into a string raises TypeError,
        # which is neither FailJob nor DiscardTriggerEvent and would escape as a 500.
        hash_items = history.select { |h| h.is_a?(Hash) }

        status_filter = trigger.config[:status_filter]
        if status_filter.present? && event == 'taskStatusUpdated'
          new_status = hash_items.filter_map { |h| h[:after][:status] if h[:after].is_a?(Hash) }.first
          unless new_status.to_s.downcase == status_filter.to_s.downcase
            discard_trigger_event!("Status '#{new_status}' does not match filter '#{status_filter}'")
          end
        end

        assignee_filter = trigger.config[:assignee_filter]
        if assignee_filter.present? && event == 'taskAssigneeUpdated'
          befores = hash_items.map { |h| h[:before][:id] if h[:before].is_a?(Hash) }
          afters = hash_items.map { |h| h[:after][:id] if h[:after].is_a?(Hash) }
          involved = (befores + afters).compact.map(&:to_s)
          unless involved.include?(assignee_filter.to_s)
            discard_trigger_event!("Assignee '#{assignee_filter}' not involved in this change")
          end
        end

        task = nil
        if event.to_s.start_with?('task') && event != 'taskDeleted' && json[:task_id].present?
          task = helpers.clickup_get("task/#{helpers.safe_id(json[:task_id], 'task_id')}")
        end

        # webhook_id is the same for every delivery this trigger receives, so it identifies the
        # subscription rather than the thing that changed. Name the resource the event is about and
        # fall back only when the payload carries none.
        self.job_context_identifier = json[:task_id].presence || json[:list_id].presence ||
                                      json[:folder_id].presence || json[:space_id].presence ||
                                      json[:goal_id].presence || json[:key_result_id].presence ||
                                      json[:webhook_id]

        {
          event: event,
          webhook_id: json[:webhook_id],
          task_id: json[:task_id],
          list_id: json[:list_id],
          folder_id: json[:folder_id],
          space_id: json[:space_id],
          goal_id: json[:goal_id],
          key_result_id: json[:key_result_id],
          history_items: history.map { |h| h.is_a?(Hash) ? h.slice(:id, :type, :date, :field) : {} },
          task: task,
        }
      end
    end

    # Actions: Tasks

    action '019fed58-1d55-7372-9b84-a744947b9368' do
      name 'Create Task'
      avatar '/assets/icons/clickup.svg'
      description 'Creates a task in a ClickUp List.'

      input_schema do
        field :space_id, 'Space', :string, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder', :string, visibility: 'optional',
                                             hint: 'Optional. Select a Folder once a Space is chosen; leave empty ' \
                                                   'for a folderless List.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
        field :list_id, 'List', :string, required: true,
                                         hint: 'The List the task is created in. Select a Space (and optionally a ' \
                                               'Folder) to populate.' do
          options do |space_id: nil, folder_id: nil|
            helpers.fetch_list_options(space_id: space_id, folder_id: folder_id)
          end
        end
        field :name, 'Name', :string, required: true
        field :description, 'Description', :string, visibility: 'optional'
        field :markdown_content, 'Markdown description', :string, visibility: 'optional'
        field :assignees, 'Assignees', :string, visibility: 'optional',
                                                hint: 'Pick a user. Use Proc mode for multiple comma-separated ids.' do
          options do |list_id:|
            helpers.fetch_assignee_options(list_id: list_id)
          end
        end
        field :status, 'Status', :string, visibility: 'optional' do
          options do |list_id:|
            helpers.fetch_status_options(list_id: list_id)
          end
        end
        field :priority, 'Priority', :integer, visibility: 'optional', enumeration: PRIORITIES
        field :due_date, 'Due date', :integer, visibility: 'optional', hint: 'Unix time in milliseconds.'
        field :tags, 'Tags', :string, visibility: 'optional',
                                      hint: 'Pick a tag. Use Proc mode for multiple comma-separated names. ' \
                                            'A ClickUp tag is identified by its name, so a tag whose name ' \
                                            'contains a comma cannot be set from this field.' do
          options do |space_id:|
            helpers.fetch_tag_options(space_id: space_id)
          end
        end
      end

      output_schema do
        field :id, 'Task ID', :string, required: true
        field :name, 'Name', :string
        field :url, 'URL', :string
        field :status, 'Status', :hash
        field :date_created, 'Created date', :string
      end

      run do
        body = { name: input[:name] }
        body[:description] = input[:description] if input[:description].present?
        body[:markdown_content] = input[:markdown_content] if input[:markdown_content].present?
        body[:assignees] = helpers.comma_ints(input[:assignees], 'Assignees') if input[:assignees].present?
        body[:status] = input[:status] if input[:status].present?
        body[:priority] = input[:priority] unless input[:priority].nil?
        body[:due_date] = input[:due_date] unless input[:due_date].nil?
        body[:tags] = helpers.comma_strings(input[:tags]) if input[:tags].present?
        result = helpers.clickup_post("list/#{helpers.safe_id(input[:list_id], 'list_id')}/task", body)
        [{ output: result.slice(:id, :name, :url, :status, :date_created) }]
      end
    end

    action '019fed58-1d55-7773-8358-bf1cb9ce6a4c' do
      name 'Get Task'
      avatar '/assets/icons/clickup.svg'
      description 'Retrieves the full details of a ClickUp task.'

      input_schema do
        field :space_id, 'Space', :string, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder', :string, visibility: 'optional',
                                             hint: 'Optional. Select a Folder; leave empty for a folderless List.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
        field :list_id, 'List', :string,
              hint: 'Select a List once a Space (and optionally a Folder) is chosen.' do
          options do |space_id: nil, folder_id: nil|
            helpers.fetch_list_options(space_id: space_id, folder_id: folder_id)
          end
        end
        field :task_id, 'Task', :string, required: true,
                                         hint: 'The task to act on. Select a List to populate the tasks.' do
          options do |list_id:|
            helpers.fetch_task_options(list_id: list_id)
          end
        end
      end

      output_schema do
        field :task, 'Task', :hash, required: true
      end

      run do
        [{ output: { task: helpers.clickup_get("task/#{helpers.safe_id(input[:task_id], 'task_id')}") } }]
      end
    end

    action '019fed58-1d55-7d7c-bac8-f7cf4bb76eef' do
      name 'Update Task'
      avatar '/assets/icons/clickup.svg'
      description 'Updates fields on an existing ClickUp task.'

      input_schema do
        field :space_id, 'Space', :string, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder', :string, visibility: 'optional',
                                             hint: 'Optional. Select a Folder; leave empty for a folderless List.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
        field :list_id, 'List', :string,
              hint: 'Select a List once a Space (and optionally a Folder) is chosen.' do
          options do |space_id: nil, folder_id: nil|
            helpers.fetch_list_options(space_id: space_id, folder_id: folder_id)
          end
        end
        field :task_id, 'Task', :string, required: true,
                                         hint: 'The task to act on. Select a List to populate the tasks.' do
          options do |list_id:|
            helpers.fetch_task_options(list_id: list_id)
          end
        end
        field :name, 'Name', :string, visibility: 'optional'
        field :description, 'Description', :string, visibility: 'optional'
        field :status, 'Status', :string, visibility: 'optional' do
          options do |list_id:|
            helpers.fetch_status_options(list_id: list_id)
          end
        end
        field :priority, 'Priority', :integer, visibility: 'optional', enumeration: PRIORITIES
        field :due_date, 'Due date', :integer, visibility: 'optional', hint: 'Unix time in milliseconds.'
        field :add_assignees, 'Add assignees', :string, visibility: 'optional',
                                                        hint: 'Pick a user. Use Proc mode for multiple ' \
                                                              'comma-separated ids.' do
          options do |list_id:|
            helpers.fetch_assignee_options(list_id: list_id)
          end
        end
        field :remove_assignees, 'Remove assignees', :string, visibility: 'optional',
                                                              hint: 'Pick a user. Use Proc mode for multiple ' \
                                                                    'comma-separated ids.' do
          options do |list_id:|
            helpers.fetch_assignee_options(list_id: list_id)
          end
        end
      end

      output_schema do
        field :id, 'Task ID', :string, required: true
        field :name, 'Name', :string
        field :status, 'Status', :hash
      end

      run do
        body = {}
        body[:name] = input[:name] if input[:name].present?
        body[:description] = input[:description] if input[:description].present?
        body[:status] = input[:status] if input[:status].present?
        body[:priority] = input[:priority] unless input[:priority].nil?
        body[:due_date] = input[:due_date] unless input[:due_date].nil?
        if input[:add_assignees].present? || input[:remove_assignees].present?
          body[:assignees] = { add: helpers.comma_ints(input[:add_assignees], 'Add assignees'),
                               rem: helpers.comma_ints(input[:remove_assignees], 'Remove assignees'), }
        end
        fail_job!('Fill in at least one field to update on the task') if body.empty?

        result = helpers.clickup_put("task/#{helpers.safe_id(input[:task_id], 'task_id')}", body)
        [{ output: result.slice(:id, :name, :status) }]
      end
    end

    action '019fed58-1d55-758f-a078-4caabf1d8c39' do
      name 'Delete Task'
      avatar '/assets/icons/clickup.svg'
      description 'Deletes a ClickUp task.'

      input_schema do
        field :space_id, 'Space', :string, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder', :string, visibility: 'optional',
                                             hint: 'Optional. Select a Folder; leave empty for a folderless List.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
        field :list_id, 'List', :string,
              hint: 'Select a List once a Space (and optionally a Folder) is chosen.' do
          options do |space_id: nil, folder_id: nil|
            helpers.fetch_list_options(space_id: space_id, folder_id: folder_id)
          end
        end
        field :task_id, 'Task', :string, required: true,
                                         hint: 'The task to act on. Select a List to populate the tasks.' do
          options do |list_id:|
            helpers.fetch_task_options(list_id: list_id)
          end
        end
      end

      output_schema do
        field :success, 'Success', :boolean, required: true
      end

      run do
        helpers.clickup_delete("task/#{helpers.safe_id(input[:task_id], 'task_id')}")
        [{ output: { success: true } }]
      end
    end

    action '019fed58-1d55-7bc2-98b2-646bd1b1cb5e' do
      name 'Update Task Status'
      avatar '/assets/icons/clickup.svg'
      description 'Updates only the status of a ClickUp task.'

      input_schema do
        field :space_id, 'Space', :string, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder', :string, visibility: 'optional',
                                             hint: 'Optional. Select a Folder; leave empty for a folderless List.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
        field :list_id, 'List', :string,
              hint: 'Select a List once a Space (and optionally a Folder) is chosen.' do
          options do |space_id: nil, folder_id: nil|
            helpers.fetch_list_options(space_id: space_id, folder_id: folder_id)
          end
        end
        field :task_id, 'Task', :string, required: true,
                                         hint: 'The task to act on. Select a List to populate the tasks.' do
          options do |list_id:|
            helpers.fetch_task_options(list_id: list_id)
          end
        end
        field :status, 'Status', :string, required: true do
          options do |list_id:|
            helpers.fetch_status_options(list_id: list_id)
          end
        end
      end

      output_schema do
        field :id, 'Task ID', :string, required: true
        field :status, 'Status', :hash
      end

      run do
        result = helpers.clickup_put("task/#{helpers.safe_id(input[:task_id], 'task_id')}", { status: input[:status] })
        [{ output: result.slice(:id, :status) }]
      end
    end

    action '019fed58-1d55-7baa-9e21-a405beea7954' do
      name 'Assign User To Task'
      avatar '/assets/icons/clickup.svg'
      description 'Adds or removes assignees on a ClickUp task.'

      input_schema do
        field :space_id, 'Space', :string, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder', :string, visibility: 'optional',
                                             hint: 'Optional. Select a Folder; leave empty for a folderless List.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
        field :list_id, 'List', :string,
              hint: 'Select a List once a Space (and optionally a Folder) is chosen.' do
          options do |space_id: nil, folder_id: nil|
            helpers.fetch_list_options(space_id: space_id, folder_id: folder_id)
          end
        end
        field :task_id, 'Task', :string, required: true,
                                         hint: 'The task to act on. Select a List to populate the tasks.' do
          options do |list_id:|
            helpers.fetch_task_options(list_id: list_id)
          end
        end
        field :add_assignees, 'Add assignees', :string, visibility: 'optional',
                                                        hint: 'Pick a user. Use Proc mode for multiple ' \
                                                              'comma-separated ids.' do
          options do |list_id:|
            helpers.fetch_assignee_options(list_id: list_id)
          end
        end
        field :remove_assignees, 'Remove assignees', :string, visibility: 'optional',
                                                              hint: 'Pick a user. Use Proc mode for multiple ' \
                                                                    'comma-separated ids.' do
          options do |list_id:|
            helpers.fetch_assignee_options(list_id: list_id)
          end
        end
      end

      output_schema do
        field :id, 'Task ID', :string, required: true
        field :assignees, 'Assignees', :hash, array: true
      end

      run do
        add = helpers.comma_ints(input[:add_assignees], 'Add assignees')
        remove = helpers.comma_ints(input[:remove_assignees], 'Remove assignees')
        fail_job!('Select at least one assignee to add or to remove') if add.empty? && remove.empty?

        result = helpers.clickup_put("task/#{helpers.safe_id(input[:task_id], 'task_id')}",
                                     { assignees: { add: add, rem: remove } })
        [{ output: { id: result[:id], assignees: result[:assignees] || [] } }]
      end
    end

    # Actions: Comments

    action '019fed58-1d55-7f62-9847-9936f4e99520' do
      name 'Create Task Comment'
      avatar '/assets/icons/clickup.svg'
      description 'Adds a comment to a ClickUp task.'

      input_schema do
        field :space_id, 'Space', :string, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder', :string, visibility: 'optional',
                                             hint: 'Optional. Select a Folder; leave empty for a folderless List.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
        field :list_id, 'List', :string,
              hint: 'Select a List once a Space (and optionally a Folder) is chosen.' do
          options do |space_id: nil, folder_id: nil|
            helpers.fetch_list_options(space_id: space_id, folder_id: folder_id)
          end
        end
        field :task_id, 'Task', :string, required: true,
                                         hint: 'The task to act on. Select a List to populate the tasks.' do
          options do |list_id:|
            helpers.fetch_task_options(list_id: list_id)
          end
        end
        field :comment_text, 'Comment text', :string, required: true
        field :notify_all, 'Notify all', :boolean, visibility: 'optional', default: false
        field :assignee, 'Assignee', :integer, visibility: 'optional',
                                               hint: 'Pick a user to assign the comment to.' do
          options do |list_id:|
            helpers.fetch_assignee_options(list_id: list_id)
          end
        end
      end

      output_schema do
        field :id, 'Comment ID', :string, required: true
        field :hist_id, 'History ID', :string
        field :date, 'Date', :integer
      end

      run do
        body = { comment_text: input[:comment_text], notify_all: input[:notify_all] == true }
        body[:assignee] = input[:assignee] unless input[:assignee].nil?
        result = helpers.clickup_post("task/#{helpers.safe_id(input[:task_id], 'task_id')}/comment", body)
        [{ output: result.slice(:id, :hist_id, :date) }]
      end
    end

    action '019fed58-1d55-7c16-af21-36d4d6ec2a9a' do
      name 'Get Task Comments'
      avatar '/assets/icons/clickup.svg'
      description 'Retrieves the most recent comments on a ClickUp task (newest first).'

      input_schema do
        field :space_id, 'Space', :string, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder', :string, visibility: 'optional',
                                             hint: 'Optional. Select a Folder; leave empty for a folderless List.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
        field :list_id, 'List', :string,
              hint: 'Select a List once a Space (and optionally a Folder) is chosen.' do
          options do |space_id: nil, folder_id: nil|
            helpers.fetch_list_options(space_id: space_id, folder_id: folder_id)
          end
        end
        field :task_id, 'Task', :string, required: true,
                                         hint: 'The task to act on. Select a List to populate the tasks.' do
          options do |list_id:|
            helpers.fetch_task_options(list_id: list_id)
          end
        end
        field :start, 'Start (Unix ms)', :integer, visibility: 'optional',
                                                   hint: 'Date of the last comment from a previous page.'
        field :start_id, 'Start id', :string, visibility: 'optional',
                                              hint: 'Id of the last comment from a previous page.'
      end

      output_schema do
        field :comments, 'Comments', :hash, array: true
      end

      run do
        params = {}
        params[:start] = input[:start] unless input[:start].nil?
        params[:start_id] = input[:start_id] if input[:start_id].present?
        result = helpers.clickup_get("task/#{helpers.safe_id(input[:task_id], 'task_id')}/comment", params)
        [{ output: { comments: result[:comments] || [] } }]
      end
    end

    # Actions: Attachments

    action '019fed58-1d55-73d5-b66f-32bdaa7d2c07' do
      name 'Upload Task Attachment'
      avatar '/assets/icons/clickup.svg'
      description 'Uploads a file attachment to a ClickUp task.'

      input_schema do
        field :space_id, 'Space', :string, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder', :string, visibility: 'optional',
                                             hint: 'Optional. Select a Folder; leave empty for a folderless List.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
        field :list_id, 'List', :string,
              hint: 'Select a List once a Space (and optionally a Folder) is chosen.' do
          options do |space_id: nil, folder_id: nil|
            helpers.fetch_list_options(space_id: space_id, folder_id: folder_id)
          end
        end
        field :task_id, 'Task', :string, required: true,
                                         hint: 'The task to act on. Select a List to populate the tasks.' do
          options do |list_id:|
            helpers.fetch_task_options(list_id: list_id)
          end
        end
        field :content, 'File content', :binary, required: true
        field :filename, 'Filename', :string, required: true
      end

      output_schema do
        field :id, 'Attachment ID', :string, required: true
        field :title, 'Title', :string
        field :url, 'URL', :string
        field :date, 'Date', :string
      end

      run do
        parts = { attachment: IPaaS::Job::Outbound::HTTP.create_binary_part(
          input[:filename], IPaaS::Job::ContentType.detect_content_type(input[:filename]),
          input[:content]
        ) }
        response = multipart_post("#{BASE_URL}/task/#{helpers.safe_id(input[:task_id], 'task_id')}/attachment", parts)
        result = helpers.handle_clickup_response(response)
        [{ output: result.slice(:id, :title, :url, :date) }]
      end
    end

    action '019fed58-1d55-7c7f-b3d2-c32f3014c0d0' do
      name 'Get Task Attachments'
      avatar '/assets/icons/clickup.svg'
      description 'Retrieves the attachments on a ClickUp task (read from the task, since v2 has no dedicated ' \
                  'endpoint).'

      input_schema do
        field :space_id, 'Space', :string, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder', :string, visibility: 'optional',
                                             hint: 'Optional. Select a Folder; leave empty for a folderless List.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
        field :list_id, 'List', :string,
              hint: 'Select a List once a Space (and optionally a Folder) is chosen.' do
          options do |space_id: nil, folder_id: nil|
            helpers.fetch_list_options(space_id: space_id, folder_id: folder_id)
          end
        end
        field :task_id, 'Task', :string, required: true,
                                         hint: 'The task to act on. Select a List to populate the tasks.' do
          options do |list_id:|
            helpers.fetch_task_options(list_id: list_id)
          end
        end
      end

      output_schema do
        field :attachments, 'Attachments', :hash, array: true
      end

      run do
        task = helpers.clickup_get("task/#{helpers.safe_id(input[:task_id], 'task_id')}")
        [{ output: { attachments: task[:attachments] || [] } }]
      end
    end

    # Actions: Structure

    action '019fed58-1d55-7102-9a3f-0dc10258cf9d' do
      name 'Create List'
      avatar '/assets/icons/clickup.svg'
      description 'Creates a List inside a Folder.'

      input_schema do
        field :space_id, 'Space', :string, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder', :string, required: true,
                                             hint: 'Select a Folder once a Space is chosen.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
        field :name, 'Name', :string, required: true
        field :content, 'Description', :string, visibility: 'optional'
      end

      output_schema do
        field :id, 'List ID', :string, required: true
        field :name, 'Name', :string
      end

      run do
        body = { name: input[:name] }
        body[:content] = input[:content] if input[:content].present?
        result = helpers.clickup_post("folder/#{helpers.safe_id(input[:folder_id], 'folder_id')}/list", body)
        [{ output: result.slice(:id, :name) }]
      end
    end

    action '019fed58-1d55-7ad9-bfd9-1bb431685509' do
      name 'Create Folderless List'
      avatar '/assets/icons/clickup.svg'
      description 'Creates a List directly inside a Space (not in a Folder).'

      input_schema do
        field :space_id, 'Space', :string, required: true, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :name, 'Name', :string, required: true
        field :content, 'Description', :string, visibility: 'optional'
      end

      output_schema do
        field :id, 'List ID', :string, required: true
        field :name, 'Name', :string
      end

      run do
        body = { name: input[:name] }
        body[:content] = input[:content] if input[:content].present?
        result = helpers.clickup_post("space/#{helpers.safe_id(input[:space_id], 'space_id')}/list", body)
        [{ output: result.slice(:id, :name) }]
      end
    end

    action '019fed58-1d55-7663-b616-b55eca70cfea' do
      name 'Create Folder'
      avatar '/assets/icons/clickup.svg'
      description 'Creates a Folder inside a Space.'

      input_schema do
        field :space_id, 'Space', :string, required: true, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :name, 'Name', :string, required: true
      end

      output_schema do
        field :id, 'Folder ID', :string, required: true
        field :name, 'Name', :string
      end

      run do
        space_id = helpers.safe_id(input[:space_id], 'space_id')
        result = helpers.clickup_post("space/#{space_id}/folder", { name: input[:name] })
        [{ output: result.slice(:id, :name) }]
      end
    end

    # Actions: Reads

    action '019fed58-1d55-7ffb-904b-0db1ad928e7d' do
      name 'Get Authorized User'
      avatar '/assets/icons/clickup.svg'
      description 'Returns the ClickUp user that owns the connected token.'

      input_schema {}

      output_schema do
        field :user, 'User', :hash, required: true
      end

      run do
        [{ output: { user: helpers.clickup_get('user')[:user] } }]
      end
    end

    action '019fed58-1d55-7170-b75a-6f1137a70146' do
      name 'Get Workspaces'
      avatar '/assets/icons/clickup.svg'
      description 'Lists every ClickUp Workspace (team) the token can access, not only the one on ' \
                  'the connection. Use it to find the id for a second connection.'

      input_schema {}

      output_schema do
        field :teams, 'Workspaces', :nested, array: true do
          field :id, 'ID', :string
          field :name, 'Name', :string
        end
      end

      run do
        teams = (helpers.clickup_get('team')[:teams] || []).map { |t| t.slice(:id, :name) }
        [{ output: { teams: teams } }]
      end
    end

    action '019fed58-1d55-731e-9835-548b75a983bb' do
      name 'Get Spaces'
      avatar '/assets/icons/clickup.svg'
      description "Lists the Spaces in the connection's Workspace."

      input_schema {}

      output_schema do
        field :spaces, 'Spaces', :nested, array: true do
          field :id, 'ID', :string
          field :name, 'Name', :string
        end
      end

      run do
        spaces = (helpers.clickup_get("team/#{helpers.connection_workspace_id}/space")[:spaces] || []).map do |s|
          s.slice(:id, :name)
        end
        [{ output: { spaces: spaces } }]
      end
    end

    action '019fed58-1d55-7e94-a3f3-18140d8cbb73' do
      name 'Get Folders'
      avatar '/assets/icons/clickup.svg'
      description 'Lists the Folders in a Space.'

      input_schema do
        field :space_id, 'Space', :string, required: true, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
      end

      output_schema do
        field :folders, 'Folders', :nested, array: true do
          field :id, 'ID', :string
          field :name, 'Name', :string
        end
      end

      run do
        space_id = helpers.safe_id(input[:space_id], 'space_id')
        folders = (helpers.clickup_get("space/#{space_id}/folder")[:folders] || []).map do |f|
          f.slice(:id, :name)
        end
        [{ output: { folders: folders } }]
      end
    end

    action '019fed58-1d55-7629-8d49-d13b8987b76f' do
      name 'Get Lists'
      avatar '/assets/icons/clickup.svg'
      description 'Lists the Lists in a Folder.'

      input_schema do
        field :space_id, 'Space', :string, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder', :string, required: true,
                                             hint: 'Select a Folder once a Space is chosen.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
      end

      output_schema do
        field :lists, 'Lists', :nested, array: true do
          field :id, 'ID', :string
          field :name, 'Name', :string
        end
      end

      run do
        folder_id = helpers.safe_id(input[:folder_id], 'folder_id')
        lists = (helpers.clickup_get("folder/#{folder_id}/list")[:lists] || []).map { |l| l.slice(:id, :name) }
        [{ output: { lists: lists } }]
      end
    end

    action '019fed58-1d55-7727-aa7a-090d2ba1615f' do
      name 'Get Folderless Lists'
      avatar '/assets/icons/clickup.svg'
      description 'Lists the Lists that sit directly in a Space (not in a Folder).'

      input_schema do
        field :space_id, 'Space', :string, required: true, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
      end

      output_schema do
        field :lists, 'Lists', :nested, array: true do
          field :id, 'ID', :string
          field :name, 'Name', :string
        end
      end

      run do
        space_id = helpers.safe_id(input[:space_id], 'space_id')
        lists = (helpers.clickup_get("space/#{space_id}/list")[:lists] || []).map { |l| l.slice(:id, :name) }
        [{ output: { lists: lists } }]
      end
    end

    action '019fed58-1d55-7a04-a80d-c496de4a2061' do
      name 'Get List Members'
      avatar '/assets/icons/clickup.svg'
      description 'Lists the members of a ClickUp List.'

      input_schema do
        field :space_id, 'Space', :string, hint: 'Select a Space.' do
          options do
            helpers.fetch_space_options
          end
        end
        field :folder_id, 'Folder', :string, visibility: 'optional',
                                             hint: 'Optional. Select a Folder; leave empty for a folderless List.' do
          options do |space_id:|
            helpers.fetch_folder_options(space_id: space_id)
          end
        end
        field :list_id, 'List', :string, required: true,
                                         hint: 'Select a List once a Space (and optionally a Folder) is chosen.' do
          options do |space_id: nil, folder_id: nil|
            helpers.fetch_list_options(space_id: space_id, folder_id: folder_id)
          end
        end
      end

      output_schema do
        field :members, 'Members', :nested, array: true do
          field :id, 'ID', :integer
          field :username, 'Username', :string
          field :email, 'Email', :string
        end
      end

      run do
        list_id = helpers.safe_id(input[:list_id], 'list_id')
        members = (helpers.clickup_get("list/#{list_id}/member")[:members] || []).map do |m|
          m.slice(:id, :username, :email)
        end
        [{ output: { members: members } }]
      end
    end

    action '019fed58-1d55-76e0-bb83-a5c20e75de8f' do
      name 'Get Workspace Members'
      avatar '/assets/icons/clickup.svg'
      description "Lists the members of the connection's Workspace (read from the Get Workspaces response, since " \
                  'v2 has no standalone roster endpoint).'

      input_schema {}

      output_schema do
        field :members, 'Members', :nested, array: true do
          field :id, 'ID', :integer
          field :username, 'Username', :string
          field :email, 'Email', :string
        end
      end

      run do
        workspace_id = helpers.connection_workspace_id
        team = (helpers.clickup_get('team')[:teams] || []).detect { |t| t[:id].to_s == workspace_id.to_s }
        if team.nil?
          fail_job!("ClickUp did not return Workspace #{workspace_id} for this token. Check that the token " \
                    'still has access to the Workspace on the connection.')
        end

        members = (team[:members] || []).map { |m| (m[:user] || {}).slice(:id, :username, :email) }
        [{ output: { members: members } }]
      end
    end
  end
end
