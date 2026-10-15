class SlackConnector < IPaaS::Connector::Definition
  # Reject webhooks older than this (replay protection) or dated further into
  # the future than the allowed clock skew.
  MAX_REQUEST_AGE_SECONDS = 300
  CLOCK_SKEW_TOLERANCE_SECONDS = 60
  # Slack response/error bodies are truncated to this length in failure messages.
  TRUNCATED_BODY_LIMIT = 500

  connector '019d6e9d-90c5-724f-840b-13cb467ff342' do
    name 'Slack Connector'
    avatar '/assets/icons/slack.svg'
    description <<~END_OF_DESCRIPTION
      This connector enables integration with Slack for messaging, channel management, user
      lookup, and file sharing.

      # Prerequisites

      To use this connector, you need:
      * A Slack workspace with a Slack App configured
      * A Slack bot token (`xoxb-...`) with the required OAuth scopes
      * A Signing Secret (from your Slack App's Basic Info page) for webhook verification

      # Authentication

      ## Outbound (API calls)

      Sends your Slack bot token as a Bearer token on every Slack Web API call.
      Configure the outbound connection with:
      * **Slack bot token** (required): the Bot User OAuth Token of your Slack app (`xoxb-...`)

      Required OAuth scopes depend on the actions used:

      | Action | Scope |
      |--------|-------|
      | Send/Update/Delete Message | `chat:write` |
      | Add Reaction | `reactions:write` |
      | List/Get/Create/Archive public channels | `channels:read`, `channels:manage` |
      | List/Get/Create/Archive private channels | `groups:read`, `groups:write` |
      | List DMs (`im` types) | `im:read` |
      | List group DMs (`mpim` types) | `mpim:read` |
      | Invite members (public channels) | `channels:write.invites` or `channels:manage` |
      | Invite members (private channels) | `groups:write.invites` or `groups:write` |
      | Remove members (public channels) | `channels:manage` |
      | Remove members (private channels) | `groups:write` |
      | List/Get Users | `users:read` |
      | Find User by Email | `users:read.email` |
      | Upload File | `files:write` |

      ## Inbound (webhooks)

      Configure the Slack Events API to send events to the trigger endpoint. For button
      click handling, enable Interactivity in your Slack App and point the Request URL to
      the Button Click trigger endpoint. Both triggers verify requests using HMAC SHA256
      request signing with your app's Signing Secret.

      # Rate Limiting

      The connector includes built-in handling for API rate limits:
      * Automatic backoff and retry for 429 (Too Many Requests) responses
      * Respects the `Retry-After` header from Slack

      | HTTP Code | Scenario | Handling Strategy |
      |-----------|----------|-------------------|
      | 429 | Rate limit exceeded | Retry with backoff (Retry-After header) |
      | 503 | Service unavailable | Retry with backoff |
    END_OF_DESCRIPTION

    inbound_connection do
      config_schema do
        field :signing_secret, 'Signing Secret', :secret_string,
              required: true,
              hint: 'Slack app Signing Secret for verifying webhook requests. One per Slack app, ' \
                    'so it is configured on the connection and shared by all Slack triggers.'
      end

      # HMAC SHA256 request-signature verification runs here, before any trigger parse.
      # The framework rewinds the request body afterwards, so parse still sees the full body.
      validate do |request|
        helpers.verify_slack_request(request, config[:signing_secret])
      end
    end

    outbound_connection do
      config_schema do
        field :bearer, 'Slack bot token', :nested,
              required: true,
              hint: 'The Bot User OAuth Token of your Slack app, from its OAuth & Permissions page.' do
          field :bearer_token, 'Bot token', :secret_string,
                required: true,
                hint: 'Usually starts with xoxb-.'
        end
      end

      authenticate do |request|
        bearer = config[:bearer]
        next if bearer.blank?

        request.headers['Authorization'] = "Bearer #{decrypt_secret_string(bearer[:bearer_token]).strip}"
      end
    end

    # ──────────────────────────────────────────────
    # Trigger
    # ──────────────────────────────────────────────

    trigger '019d6e9d-90c5-795f-aac7-2b8c69f5b32a' do
      name 'Slack Events'
      avatar '/assets/icons/slack.svg'
      description 'Receives events from the Slack Events API.'

      output_schema do
        field :type, 'Type', :string, required: true
        field :team_id, 'Team ID', :string, required: true
        field :api_app_id, 'API App ID', :string
        field :event_id, 'Event ID', :string, required: true
        field :event_time, 'Event time', :integer, required: true
        field :event, 'Event', :nested, required: true do
          field :type, 'Type', :string, required: true
          field :channel, 'Channel', :string
          field :user, 'User', :string
          field :text, 'Text', :string
          field :ts, 'Timestamp', :string
          field :event_ts, 'Event timestamp', :string
          field :channel_type, 'Channel type', :string
        end
      end

      parse do |request|
        # Signature already verified by the inbound connection's validate block.
        body_content = helpers.read_request_body!(request)
        json = helpers.parse_slack_json(body_content)

        if json[:type] == 'url_verification'
          fail_job!('Missing challenge in url_verification request') if json[:challenge].blank?
          # Encode the challenge so respond_with can return Slack's required body shape.
          discard_trigger_event!("url_verification:#{json[:challenge]}")
        end
        discard_trigger_event!("Ignoring Slack request type: #{json[:type]}") unless json[:type] == 'event_callback'

        self.job_context_identifier = json[:team_id]
        keys_to_field_id(json)
      end

      respond_with do |context, response|
        error = context[:error]
        prefix = 'url_verification:'
        if error.is_a?(IPaaS::Job::DiscardTriggerEvent) && error.message.to_s.start_with?(prefix)
          challenge = error.message.to_s[prefix.length..]
          response[:status] = 200
          response[:headers]['content-type'] = 'application/json'
          response[:body] = { challenge: challenge }.to_json
        end
        response
      end
    end

    # ──────────────────────────────────────────────
    # Trigger: Button Click
    # ──────────────────────────────────────────────

    trigger '019d7d4c-1758-758c-93b8-f78dbd581714' do
      name 'Button Click'
      avatar '/assets/icons/slack.svg'
      description 'Receives interactive payload events when a user clicks a button in a Slack message.'

      output_schema do
        field :type, 'Type', :string, required: true
        field :trigger_id, 'Trigger ID', :string, required: true
        field :response_url, 'Response URL', :string, required: true
        field :team, 'Team', :nested do
          field :id, 'ID', :string, required: true
          field :domain, 'Domain', :string
        end
        field :user, 'User', :nested, required: true do
          field :id, 'ID', :string, required: true
          field :username, 'Username', :string
          field :name, 'Name', :string
          field :team_id, 'Team ID', :string
        end
        field :channel, 'Channel', :nested do
          field :id, 'ID', :string, required: true
          field :name, 'Name', :string
        end
        field :message, 'Message', :nested do
          field :type, 'Type', :string
          field :text, 'Text', :string
          field :ts, 'Timestamp', :string
        end
        field :actions, 'Actions', :nested, array: true, required: true do
          field :action_id, 'Action ID', :string, required: true
          field :block_id, 'Block ID', :string
          field :type, 'Type', :string, required: true
          field :text, 'Text', :hash
          field :value, 'Value', :string
          field :action_ts, 'Action timestamp', :string
        end
      end

      parse do |request|
        # Signature already verified by the inbound connection's validate block.
        body_content = helpers.read_request_body!(request)
        payload = begin
          Rack::Utils.parse_query(body_content)['payload']
        rescue Rack::QueryParser::InvalidParameterError => e
          fail_job!("Malformed form-encoded request body: #{e.message}")
        end
        fail_job!('Missing payload parameter') if payload.blank?
        json = helpers.parse_slack_json(payload, source: 'payload')

        discard_trigger_event!("Unsupported interaction type: #{json[:type]}") unless json[:type] == 'block_actions'

        team_id = json.dig(:team, :id) || json.dig(:user, :team_id)
        fail_job!('Cannot determine team ID from Slack payload') if team_id.blank?
        self.job_context_identifier = team_id
        keys_to_field_id(json)
      end
      # No respond_with: the framework returns the default response when a trigger
      # omits it (respond_with is optional), so the Button Click trigger relies on
      # that default rather than defining a no-op that returns the response unchanged.
    end

    # ──────────────────────────────────────────────
    # Helpers
    # ──────────────────────────────────────────────

    helper :slack_url do
      'https://slack.com/api'
    end

    # Reads the raw request body, failing cleanly when it is missing. Shared by
    # both trigger parse blocks and the HMAC verifier so the 'no body' behavior
    # stays consistent across them.
    helper :read_request_body! do |request|
      body_content = request.body&.read
      fail_job!('Request has no body') if body_content.blank?
      body_content
    end

    # Parses raw text as a JSON object, returning it as an indifferent-access Hash.
    # Failures are reported as "#{label}: <detail>". Rescues TypeError too, so a
    # non-String input (e.g. a duplicated form param that Rack returns as an Array)
    # fails cleanly instead of escaping as an HTTP 500.
    helper :parse_json_object do |raw, label|
      parsed = JSON.parse(raw)
      fail_job!("#{label}: expected an object, got #{parsed.class}") unless parsed.is_a?(Hash)
      parsed.with_indifferent_access
    rescue JSON::ParserError, TypeError => e
      fail_job!("#{label}: #{e.message}")
    end

    helper :parse_response do |response|
      parsed = JSON.parse(response.body)
      unless parsed.is_a?(Hash)
        fail_job!("Unexpected Slack response (not an object): #{helpers.truncate_body(response.body)}")
      end
      body = parsed.with_indifferent_access
      unless body.key?(:ok)
        fail_job!("Unexpected Slack response (no 'ok' field): #{helpers.truncate_body(response.body)}")
      end
      unless body[:ok]
        detail_parts = []
        detail_parts << "needed: #{body[:needed]}" if body[:needed].present?
        detail_parts << "provided: #{body[:provided]}" if body[:provided].present?
        messages = body.dig(:response_metadata, :messages)
        detail_parts << messages.join('; ') if messages.is_a?(Array) && messages.any?
        detail = detail_parts.empty? ? '' : " (#{detail_parts.join(', ')})"
        fail_job!("Slack API error: #{body[:error]}#{detail}")
      end
      body
    rescue JSON::ParserError
      if response.status >= 200 && response.status < 300
        fail_job!("Empty or non-JSON Slack response (status #{response.status}): " \
                  "#{helpers.truncate_body(response.body)}")
      else
        fail_job!("HTTP error: #{response.status} '#{helpers.truncate_body(response.body)}'")
      end
    end

    helper :truncate_body do |body|
      s = body.to_s
      s.length > TRUNCATED_BODY_LIMIT ? "#{s[0, TRUNCATED_BODY_LIMIT - 3]}..." : s
    end

    helper :require_nested do |result, key|
      nested = result[key]
      fail_job!("Slack response missing '#{key}' object") unless nested.is_a?(Hash)
      nested
    end

    # Shared rate-limit backoff + error parsing applied to every Slack API
    # response, so GET / JSON-POST / form-POST can't drift on the convention.
    helper :handle_slack_response do |response|
      backoff_if_needed(response, api_name: 'Slack')
      helpers.parse_response(response)
    end

    helper :slack_get do |method, params = {}|
      url = "#{helpers.slack_url}/#{method}"
      response = http_get(url, params.transform_values(&:to_s))
      helpers.handle_slack_response(response)
    end

    helper :slack_post do |method, body = {}|
      url = "#{helpers.slack_url}/#{method}"
      response = http_post(url, body.to_json, { 'Content-Type' => 'application/json' })
      helpers.handle_slack_response(response)
    end

    # Some Slack methods (e.g. files.getUploadURLExternal) only accept
    # application/x-www-form-urlencoded and silently ignore a JSON body,
    # reporting their required params as missing.
    helper :slack_post_form do |method, params = {}|
      url = "#{helpers.slack_url}/#{method}"
      body = URI.encode_www_form(params.transform_values(&:to_s))
      response = http_post(url, body, { 'Content-Type' => 'application/x-www-form-urlencoded' })
      helpers.handle_slack_response(response)
    end

    helper :slack_get_paginated do |method, params = {}|
      cursor = iteration_state_value(:cursor)
      params = params.merge(cursor: cursor) if cursor.present?
      result = helpers.slack_get(method, params)
      next_cursor = result.dig(:response_metadata, :next_cursor)
      has_more = next_cursor.present?
      self.iteration_state_value = has_more ? { cursor: next_cursor } : nil
      { result: result, has_next_page: has_more }
    end

    helper :parse_slack_owned_url do |url, label, host:|
      uri = begin
        URI.parse(url.to_s)
      rescue URI::Error
        nil
      end
      fail_job!("Invalid #{label}") unless uri.is_a?(URI::HTTPS) && uri.host == host
      uri
    end

    helper :parse_slack_json do |raw, source: 'request body'|
      helpers.parse_json_object(raw, "Invalid JSON in #{source}")
    end

    # Verifies a Slack webhook's HMAC SHA256 signature. Called from the inbound
    # connection's validate block; reads the raw body (the framework rewinds it
    # afterwards so trigger parse still sees the full body).
    helper :verify_slack_request do |request, signing_secret_config|
      signing_secret = decrypt_secret_string(signing_secret_config)
      fail_job!('Signing secret is not configured') if signing_secret.blank?

      body_content = helpers.read_request_body!(request)

      timestamp = request.headers['X-Slack-Request-Timestamp']
      fail_job!('Missing X-Slack-Request-Timestamp header') if timestamp.blank?
      fail_job!('Invalid X-Slack-Request-Timestamp header') unless timestamp.match?(/\A\d+\z/)

      # Reject stale requests (older than 5 minutes) to prevent replay attacks, and
      # implausibly future-dated requests (allowing a small clock-skew tolerance).
      now = Time.now.to_i
      request_time = timestamp.to_i
      fail_job!('Request timestamp is too old') if now - request_time > MAX_REQUEST_AGE_SECONDS
      fail_job!('Request timestamp is in the future') if request_time - now > CLOCK_SKEW_TOLERANCE_SECONDS

      signature = request.headers['X-Slack-Signature']
      fail_job!('Missing X-Slack-Signature header') if signature.blank?
      basestring = "v0:#{timestamp}:#{body_content}"
      expected = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, basestring)}"
      fail_job!('Invalid request signature') unless OpenSSL.secure_compare(expected, signature)
    end

    # ──────────────────────────────────────────────
    # Actions: Messaging
    # ──────────────────────────────────────────────

    action '019d6e9d-90c5-7d7b-b2ba-d83be61d5624' do
      name 'Send Message'
      avatar '/assets/icons/slack.svg'
      description 'Sends a message to a Slack channel using chat.postMessage.'

      input_schema do
        field :channel, 'Channel', :string, required: true,
                                            hint: 'Channel ID (e.g., C1234567890)'
        field :text, 'Text', :string, required: true,
                                      hint: 'Message text (supports Slack markdown)'
        field :thread_ts, 'Thread timestamp', :string, visibility: 'optional',
                                                       hint: 'Timestamp of the parent message to reply in a thread'
      end

      output_schema do
        field :ok, 'OK', :boolean, required: true
        field :channel, 'Channel', :string
        field :ts, 'Timestamp', :string
        field :message, 'Message', :hash
      end

      run do
        body = { channel: input[:channel], text: input[:text] }
        body[:thread_ts] = input[:thread_ts] if input[:thread_ts].present?
        result = helpers.slack_post('chat.postMessage', body)
        [{ output: result.slice(:ok, :channel, :ts, :message) }]
      end
    end

    action '019d6e9d-90c5-7de8-a9cd-32f207fa8a5e' do
      name 'Update Message'
      avatar '/assets/icons/slack.svg'
      description 'Updates an existing message using chat.update.'

      input_schema do
        field :channel, 'Channel', :string, required: true,
                                            hint: 'Channel ID containing the message'
        field :ts, 'Timestamp', :string, required: true,
                                         hint: 'Timestamp of the message to update'
        field :text, 'Text', :string, required: true,
                                      hint: 'New message text'
      end

      output_schema do
        field :ok, 'OK', :boolean, required: true
        field :channel, 'Channel', :string
        field :ts, 'Timestamp', :string
        field :text, 'Text', :string
        field :message, 'Message', :hash
      end

      run do
        result = helpers.slack_post('chat.update', {
          channel: input[:channel],
          ts: input[:ts],
          text: input[:text],
        })
        [{ output: result.slice(:ok, :channel, :ts, :text, :message) }]
      end
    end

    action '019d6e9d-90c5-7720-81f6-a7990830719b' do
      name 'Delete Message'
      avatar '/assets/icons/slack.svg'
      description 'Deletes a message using chat.delete.'

      input_schema do
        field :channel, 'Channel', :string, required: true,
                                            hint: 'Channel ID containing the message'
        field :ts, 'Timestamp', :string, required: true,
                                         hint: 'Timestamp of the message to delete'
      end

      output_schema do
        field :ok, 'OK', :boolean, required: true
        field :channel, 'Channel', :string
        field :ts, 'Timestamp', :string
      end

      run do
        result = helpers.slack_post('chat.delete', {
          channel: input[:channel],
          ts: input[:ts],
        })
        [{ output: result.slice(:ok, :channel, :ts) }]
      end
    end

    action '019d6e9d-90c5-7b8c-b4d5-95fddc454f24' do
      name 'Add Reaction'
      avatar '/assets/icons/slack.svg'
      description 'Adds an emoji reaction to a message using reactions.add.'

      input_schema do
        field :channel, 'Channel', :string, required: true,
                                            hint: 'Channel ID where the message is located'
        field :timestamp, 'Timestamp', :string, required: true,
                                                hint: 'Timestamp of the message to react to'
        field :name, 'Reaction name', :string, required: true,
                                               hint: 'Emoji name without colons (e.g., thumbsup)'
      end

      output_schema do
        field :ok, 'OK', :boolean, required: true
      end

      run do
        result = helpers.slack_post('reactions.add', {
          channel: input[:channel],
          timestamp: input[:timestamp],
          name: input[:name],
        })
        [{ output: { ok: result[:ok] } }]
      end
    end

    # ──────────────────────────────────────────────
    # Actions: Interactions
    # ──────────────────────────────────────────────

    action '019d7d4c-1758-7f73-9a76-8ffcbc1dda57' do
      name 'Respond to Button Click'
      avatar '/assets/icons/slack.svg'
      description 'Responds to a Slack button click using the response_url from the Button Click trigger.'

      input_schema do
        field :response_url, 'Response URL', :string, required: true,
                                                      hint: 'The response_url from the Button Click trigger output'
        field :text, 'Text', :string, required: true,
                                      hint: 'Response message text (supports Slack markdown)'
        field :replace_original, 'Replace original', :boolean, visibility: 'optional',
                                                               hint: 'Replace the original message (default: true)'
      end

      output_schema do
        field :ok, 'OK', :boolean, required: true
      end

      run do
        uri = helpers.parse_slack_owned_url(input[:response_url], 'response_url', host: 'hooks.slack.com')

        body = {
          text: input[:text],
          replace_original: input[:replace_original] != false,
        }
        response = http_post(uri.to_s, body.to_json,
                             { 'Content-Type' => 'application/json' },
                             skip_authentication: true)
        backoff_if_needed(response, api_name: 'Slack')
        unless response.status == 200
          fail_job!("Slack response_url error: #{response.status} '#{helpers.truncate_body(response.body)}'")
        end
        [{ output: { ok: true } }]
      end
    end

    # ──────────────────────────────────────────────
    # Actions: Channels
    # ──────────────────────────────────────────────

    action '019d6e9d-90c5-7201-bcf2-1cc1b189a11c' do
      name 'List Channels'
      avatar '/assets/icons/slack.svg'
      description 'Lists channels in the workspace using conversations.list.'
      nested true

      input_schema do
        field :types, 'Types', :string, visibility: 'optional',
                                        hint: 'Channel types: public_channel, private_channel, mpim, im',
                                        default: 'public_channel'
        field :exclude_archived, 'Exclude archived', :boolean, visibility: 'optional',
                                                               default: true
        field :limit, 'Limit', :integer, visibility: 'optional',
                                         min: 1, max: 1000, default: 200,
                                         hint: 'Number of channels per page (max 1000)'
      end

      output_schema 'page' do
        field :channels, 'Channels', :nested, array: true do
          field :id, 'ID', :string, required: true
          field :name, 'Name', :string
          field :is_channel, 'Is channel', :boolean
          field :is_private, 'Is private', :boolean
          field :is_archived, 'Is archived', :boolean
          field :num_members, 'Number of members', :integer
          field :creator, 'Creator', :string
          field :created, 'Created', :integer
        end
        field :has_next_page, 'Has next page', :boolean, required: true
      end

      iteration_state_schema do
        field :cursor, 'Cursor', :string
      end

      run do
        # Coalesce here rather than relying solely on the schema defaults: schema
        # defaults are only backfilled for ABSENT keys (resolved_mapping.rb), so an
        # optional field mapped to a variable that resolves to nil at run time is
        # present-but-nil and would otherwise send an empty param to Slack.
        params = {
          types: input[:types].presence || 'public_channel',
          exclude_archived: input[:exclude_archived] != false,
          limit: input[:limit] || 200,
        }
        page = helpers.slack_get_paginated('conversations.list', params)

        [{
          output: {
            channels: page[:result][:channels] || [],
            has_next_page: page[:has_next_page],
          },
          schema_reference: 'page',
        }]
      end
    end

    action '019d6e9d-90c5-7d5f-91e7-b0fc00905306' do
      name 'Get Channel'
      avatar '/assets/icons/slack.svg'
      description 'Gets information about a channel using conversations.info.'

      input_schema do
        field :channel, 'Channel', :string, required: true,
                                            hint: 'Channel ID (e.g., C1234567890)'
      end

      output_schema do
        field :id, 'ID', :string, required: true
        field :name, 'Name', :string
        field :is_channel, 'Is channel', :boolean
        field :is_private, 'Is private', :boolean
        field :is_archived, 'Is archived', :boolean
        field :num_members, 'Number of members', :integer
        field :topic, 'Topic', :hash
        field :purpose, 'Purpose', :hash
        field :creator, 'Creator', :string
        field :created, 'Created', :integer
      end

      run do
        result = helpers.slack_get('conversations.info', { channel: input[:channel], include_num_members: true })
        [{
          output: helpers.require_nested(result, :channel).slice(
            :id, :name, :is_channel, :is_private, :is_archived,
            :num_members, :topic, :purpose, :creator, :created,
          ),
        }]
      end
    end

    action '019d6e9d-90c5-7348-b9bf-2954d187c1e8' do
      name 'Create Channel'
      avatar '/assets/icons/slack.svg'
      description 'Creates a new channel using conversations.create.'

      input_schema do
        field :name, 'Name', :string, required: true,
                                      hint: 'Channel name (lowercase, no spaces, max 80 chars)'
        field :is_private, 'Is private', :boolean, visibility: 'optional',
                                                   hint: 'Whether to create a private channel (default: false)'
      end

      output_schema do
        field :id, 'ID', :string, required: true
        field :name, 'Name', :string
        field :is_channel, 'Is channel', :boolean
        field :is_private, 'Is private', :boolean
        field :creator, 'Creator', :string
        field :created, 'Created', :integer
      end

      run do
        body = { name: input[:name] }
        body[:is_private] = input[:is_private] unless input[:is_private].nil?
        result = helpers.slack_post('conversations.create', body)
        [{
          output: helpers.require_nested(result, :channel).slice(
            :id, :name, :is_channel, :is_private, :creator, :created,
          ),
        }]
      end
    end

    action '019d6e9d-90c5-737a-bede-4be6cf62df9a' do
      name 'Archive Channel'
      avatar '/assets/icons/slack.svg'
      description 'Archives a channel using conversations.archive.'

      input_schema do
        field :channel, 'Channel', :string, required: true,
                                            hint: 'Channel ID to archive'
      end

      output_schema do
        field :ok, 'OK', :boolean, required: true
      end

      run do
        helpers.slack_post('conversations.archive', { channel: input[:channel] })
        [{ output: { ok: true } }]
      end
    end

    action '019d6e9d-90c5-7ea5-8660-d4051ed155f5' do
      name 'Invite to Channel'
      avatar '/assets/icons/slack.svg'
      description 'Invites users to a channel using conversations.invite.'

      input_schema do
        field :channel, 'Channel', :string, required: true,
                                            hint: 'Channel ID'
        field :users, 'Users', :string, required: true,
                                        hint: 'Comma-separated user IDs to invite (max 100 per call)'
      end

      output_schema do
        field :id, 'ID', :string, required: true
        field :name, 'Name', :string
      end

      run do
        result = helpers.slack_post('conversations.invite', {
          channel: input[:channel],
          users: input[:users],
        })
        [{ output: helpers.require_nested(result, :channel).slice(:id, :name) }]
      end
    end

    action '019d6e9d-90c5-70f6-ad49-2108daee694d' do
      name 'Remove from Channel'
      avatar '/assets/icons/slack.svg'
      description 'Removes a user from a channel using conversations.kick.'

      input_schema do
        field :channel, 'Channel', :string, required: true,
                                            hint: 'Channel ID'
        field :user, 'User', :string, required: true,
                                      hint: 'User ID to remove'
      end

      output_schema do
        field :ok, 'OK', :boolean, required: true
      end

      run do
        helpers.slack_post('conversations.kick', {
          channel: input[:channel],
          user: input[:user],
        })
        [{ output: { ok: true } }]
      end
    end

    # ──────────────────────────────────────────────
    # Actions: Users
    # ──────────────────────────────────────────────

    action '019d6e9d-90c5-7ed3-91db-fec755207870' do
      name 'List Users'
      avatar '/assets/icons/slack.svg'
      description 'Lists users in the workspace using users.list.'
      nested true

      input_schema do
        field :limit, 'Limit', :integer, visibility: 'optional',
                                         min: 1, max: 1000, default: 200,
                                         hint: 'Number of users per page (max 1000)'
      end

      output_schema 'page' do
        field :members, 'Members', :nested, array: true do
          field :id, 'ID', :string, required: true
          field :name, 'Name', :string
          field :real_name, 'Real name', :string
          field :is_admin, 'Is admin', :boolean
          field :is_bot, 'Is bot', :boolean
          field :is_restricted, 'Is restricted', :boolean
          field :deleted, 'Deleted', :boolean
          field :profile, 'Profile', :hash
        end
        field :has_next_page, 'Has next page', :boolean, required: true
      end

      iteration_state_schema do
        field :cursor, 'Cursor', :string
      end

      run do
        # Coalesce nil→default: schema defaults only fill absent keys, so an
        # optional field mapped to a nil-resolving variable is present-but-nil and
        # would otherwise send an empty limit to Slack. See List Channels.
        params = { limit: input[:limit] || 200 }
        page = helpers.slack_get_paginated('users.list', params)

        [{
          output: {
            members: page[:result][:members] || [],
            has_next_page: page[:has_next_page],
          },
          schema_reference: 'page',
        }]
      end
    end

    action '019d6e9d-90c5-70f0-8fd6-24a0c91bcb00' do
      name 'Get User'
      avatar '/assets/icons/slack.svg'
      description 'Gets information about a user using users.info.'

      input_schema do
        field :user, 'User', :string, required: true,
                                      hint: 'User ID (e.g., U1234567890)'
      end

      output_schema do
        field :id, 'ID', :string, required: true
        field :name, 'Name', :string
        field :real_name, 'Real name', :string
        field :is_admin, 'Is admin', :boolean
        field :is_bot, 'Is bot', :boolean
        field :is_restricted, 'Is restricted', :boolean
        field :deleted, 'Deleted', :boolean
        field :profile, 'Profile', :hash
      end

      run do
        result = helpers.slack_get('users.info', { user: input[:user] })
        [{
          output: helpers.require_nested(result, :user).slice(
            :id, :name, :real_name, :is_admin, :is_bot, :is_restricted, :deleted, :profile,
          ),
        }]
      end
    end

    action '019d6e9d-90c5-7499-b485-c8948ce8c7a4' do
      name 'Find User by Email'
      avatar '/assets/icons/slack.svg'
      description 'Finds a user by email using users.lookupByEmail.'

      input_schema do
        field :email, 'Email', :string, required: true,
                                        hint: 'Email address to look up'
      end

      output_schema do
        field :id, 'ID', :string, required: true
        field :name, 'Name', :string
        field :real_name, 'Real name', :string
        field :is_admin, 'Is admin', :boolean
        field :is_bot, 'Is bot', :boolean
        field :deleted, 'Deleted', :boolean
        field :profile, 'Profile', :hash
      end

      run do
        result = helpers.slack_get('users.lookupByEmail', { email: input[:email] })
        [{
          output: helpers.require_nested(result, :user).slice(
            :id, :name, :real_name, :is_admin, :is_bot, :deleted, :profile,
          ),
        }]
      end
    end

    # ──────────────────────────────────────────────
    # Actions: Files
    # ──────────────────────────────────────────────

    action '019d6e9d-90c5-74c3-befd-cfb7a1040fcf' do
      name 'Upload File'
      avatar '/assets/icons/slack.svg'
      description 'Uploads a file and shares it to a channel using the files.upload v2 API.'

      input_schema do
        field :channel_id, 'Channel ID', :string, required: true,
                                                  hint: 'Channel ID to share the file in'
        field :content, 'Content', :binary, required: true,
                                            hint: 'File content (text or binary bytes)'
        field :filename, 'Filename', :string, required: true,
                                              hint: 'Name of the file (e.g., report.txt)'
        field :title, 'Title', :string, visibility: 'optional',
                                        hint: 'Title of the file'
        field :initial_comment, 'Initial comment', :string, visibility: 'optional',
                                                            hint: 'Message text to accompany the file'
      end

      output_schema do
        field :ok, 'OK', :boolean, required: true
        field :files, 'Files', :nested, array: true do
          field :id, 'ID', :string
          field :title, 'Title', :string
        end
      end

      run do
        content = input[:content]
        upload_params = {
          filename: input[:filename],
          length: content.bytesize.to_s,
        }
        upload_result = helpers.slack_post_form('files.getUploadURLExternal', upload_params)
        upload_uri = helpers.parse_slack_owned_url(upload_result[:upload_url], 'upload_url', host: 'files.slack.com')
        file_id = upload_result[:file_id]
        fail_job!('files.getUploadURLExternal did not return a file_id') if file_id.blank?

        response = http_post(upload_uri.to_s, content,
                             { 'Content-Type' => 'application/octet-stream' },
                             skip_authentication: true)
        backoff_if_needed(response, api_name: 'Slack')
        unless response.status == 200
          fail_job!("File upload failed: #{response.status} '#{helpers.truncate_body(response.body)}'")
        end

        complete_body = {
          files: [{ id: file_id, title: input[:title] || input[:filename] }],
          channel_id: input[:channel_id],
        }
        complete_body[:initial_comment] = input[:initial_comment] if input[:initial_comment].present?
        result = helpers.slack_post('files.completeUploadExternal', complete_body)

        [{ output: { ok: result[:ok], files: result[:files] } }]
      end
    end
  end
end
