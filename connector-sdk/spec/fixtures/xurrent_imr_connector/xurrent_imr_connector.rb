class XurrentImrConnector < IPaaS::Connector::Definition
  connector '019d6d9a-3230-7355-9268-3ec5c9ce502c' do
    name 'Xurrent IMR Connector - Alpha'
    avatar '/assets/icons/xurrent-imr.svg'
    description <<~END_OF_DESCRIPTION
      This connector enables integration with Xurrent IMR (formerly Zenduty) for incident
      management and response operations.

      # Prerequisites

      To use this connector, you need:
      * A Xurrent IMR account with API access
      * An API token (from Xurrent IMR account settings)

      # Authentication

      Uses token-based authentication. Configure your outbound connection with:
      * API Key: Your Xurrent IMR API token

      # Inbound Webhooks

      Configure an outgoing webhook integration in Xurrent IMR to send incident events
      to the trigger endpoint. Optionally configure an HMAC secret for signature validation.

      # Available Actions

      ## Incident Management
      1. **Create Incident** - Create a new incident
      2. **Update Incident** - Update an existing incident
      3. **Get Incident** - Retrieve incident details by number
      4. **List Incidents** - Search and filter incidents (paginated)
      5. **Add Incident Note** - Add a note to an incident

      ## Alert Management
      6. **Create Alert** - Create a new alert via the events API

      ## Team & Service Management
      7. **Get On-Call** - Retrieve on-call schedule for a team
      8. **List Teams** - List all teams
      9. **List Services** - List services for a team

      # Rate Limiting and Error Handling

      The connector includes built-in handling for API rate limits:
      * Automatic backoff and retry for 429 (Too Many Requests) responses
      * Automatic backoff and retry for 503 (Service Unavailable) responses

      | HTTP Code | Scenario | Handling Strategy |
      |-----------|----------|-------------------|
      | 400 | Bad request | Fail job with error details |
      | 401/403 | Authentication failure | Fail job immediately |
      | 429 | Rate limit exceeded | Retry with backoff |
      | 503 | Service unavailable | Retry with backoff |
    END_OF_DESCRIPTION

    inbound_connection do
      basic_auth_validator
      config_schema do
        field :webhook_secret, 'Webhook Secret', :secret_string,
              visibility: 'optional',
              hint: 'HMAC SHA256 secret for verifying webhook signatures'
      end
      validate do |request|
        webhook_secret_config = config[:webhook_secret]
        next if webhook_secret_config.blank?

        signature = request.headers['X-SIGNATURE']
        fail_job!('Missing X-SIGNATURE header.') if signature.blank?
        body_content = request.body&.read
        fail_job!('Request has no body.') if body_content.blank?
        secret = decrypt_secret_string(webhook_secret_config)
        expected = Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', secret, body_content))
        fail_job!('Invalid webhook signature.') unless OpenSSL.secure_compare(expected, signature)
      end
    end

    outbound_connection do
      config_schema do
        field :credentials, 'Credentials', :nested, required: true do
          field :api_key, 'API Key', :secret_string,
                required: true,
                hint: 'Xurrent IMR API token'
        end
        field :base_url, 'Base URL', :string,
              visibility: 'optional',
              hint: 'Override the default Xurrent IMR base URL (e.g. https://staging.zenduty.com). Defaults to https://www.zenduty.com.'
      end

      authenticate do |request|
        api_key = decrypt_secret_string(config.dig(:credentials, :api_key))
        request.headers['Authorization'] = "Token #{api_key}"
        request.headers['Content-Type'] = 'application/json'
      end
    end

    trigger '019d6d9a-3230-708c-91d2-fac5a18ac9d0' do
      name 'Incident Webhook'
      avatar '/assets/icons/xurrent-imr.svg'
      description <<~END_OF_DESCRIPTION
        Receives incident lifecycle events from Xurrent IMR (formerly Zenduty) outgoing webhooks.

        Supported event types: triggered, acknowledged, resolved.

        Configure one of the following to secure the endpoint (both are optional; if neither is
        set, the endpoint accepts any request):

        * **HMAC SHA256 signature** — set a webhook secret on the inbound connection. Xurrent IMR
          signs each request and sends the digest in the `X-SIGNATURE` header.
        * **Basic auth** — configure username and password on the inbound connection. Xurrent IMR
          sends credentials in the `Authorization: Basic …` header.
      END_OF_DESCRIPTION

      output_schema do
        field :event_type, 'Event Type', :string,
              required: true,
              enumeration: %w[triggered acknowledged resolved]
        field :incident_number, 'Incident Number', :integer, required: true
        field :unique_id, 'Unique ID', :string, required: true
        field :title, 'Title', :string
        field :summary, 'Summary', :string
        field :incident_key, 'Incident Key', :string
        field :status, 'Status', :integer
        field :priority, 'Priority', :integer
        field :urgency, 'Urgency', :integer
        field :creation_date, 'Creation Date', :string
        field :resolved_date, 'Resolved Date', :string
        field :acknowledged_date, 'Acknowledged Date', :string
        field :assigned_to, 'Assigned To', :nested do
          field :username, 'Username', :string
          field :first_name, 'First Name', :string
          field :last_name, 'Last Name', :string
          field :email, 'Email', :string
        end
        field :merged_with, 'Merged With', :string
        field :context_window_start, 'Context Window Start', :string
        field :context_window_end, 'Context Window End', :string
        field :service, 'Service', :nested do
          field :name, 'Name', :string
          field :unique_id, 'Unique ID', :string
          field :escalation_policy, 'Escalation Policy', :string
          field :team, 'Team', :string
          field :status, 'Status', :integer
          field :summary, 'Summary', :string
          field :description, 'Description', :string
          field :creation_date, 'Creation Date', :string
          field :auto_resolve_timeout, 'Auto Resolve Timeout', :integer
          field :acknowledgement_timeout, 'Acknowledgement Timeout', :integer
          field :created_by, 'Created By', :string
        end
      end

      parse do |request|
        body_content = request.body&.read
        fail_job!('Request has no body.') if body_content.blank?

        begin
          json = JSON.parse(body_content)
        rescue JSON::ParserError => e
          fail_job!("Invalid JSON in request body: #{e.message}")
        end
        fail_job!('Expected a JSON object.') unless json.is_a?(Hash)
        json = json.with_indifferent_access

        payload = json[:payload] || json
        incident = payload[:incident]
        fail_job!('Missing incident data in webhook payload.') if incident.blank?

        self.job_context_identifier = incident[:unique_id]

        {
          event_type: payload[:event_type],
          incident_number: incident[:incident_number],
          unique_id: incident[:unique_id],
          title: incident[:title],
          summary: incident[:summary],
          incident_key: incident[:incident_key],
          status: incident[:status],
          priority: incident[:priority],
          urgency: incident[:urgency],
          creation_date: incident[:creation_date],
          resolved_date: incident[:resolved_date],
          acknowledged_date: incident[:acknowledged_date],
          merged_with: incident[:merged_with],
          context_window_start: incident[:context_window_start],
          context_window_end: incident[:context_window_end],
          assigned_to: incident[:assigned_to],
          service: incident[:service],
        }
      end
    end

    action '019d6d9a-3230-789a-90ce-0132dc0cf9c2' do
      name 'Create Incident'
      avatar '/assets/icons/xurrent-imr.svg'
      description 'Creates a new incident in Xurrent IMR.'

      input_schema do
        field :title, 'Title', :string, required: true
        field :summary, 'Summary', :string
        field :service_id, 'Service ID', :string, required: true,
                                                  hint: 'Unique ID of the IMR service'
        field :escalation_policy_id, 'Escalation Policy ID', :string,
              hint: 'Unique ID of the escalation policy'
        field :assigned_to, 'Assigned To', :string, visibility: 'optional',
                                                    hint: 'Username to assign the incident to'
        field :status, 'Status', :integer, visibility: 'optional',
                                           enumeration: [
                                             { id: 1, label: 'Triggered' },
                                             { id: 2, label: 'Acknowledged' },
                                             { id: 3, label: 'Resolved' },
                                           ]
        field :priority_id, 'Priority ID', :string, visibility: 'optional',
                                                    hint: 'Unique ID of the team priority'
        field :urgency, 'Urgency', :integer, visibility: 'optional',
                                             enumeration: [{ id: 0, label: 'Low' }, { id: 1, label: 'High' }]
      end

      output_schema do
        field :unique_id, 'Unique ID', :string, required: true
        field :incident_number, 'Incident Number', :integer, required: true
        field :title, 'Title', :string
        field :summary, 'Summary', :string
        field :status, 'Status', :integer
        field :creation_date, 'Creation Date', :string
        field :urgency, 'Urgency', :integer
        field :assigned_to, 'Assigned To', :string
        field :assigned_to_name, 'Assigned To Name', :string
        field :incident_key, 'Incident Key', :string
      end

      run do
        payload = helpers.build_incident_payload(input)
        response = http_post(helpers.imr_url('incidents/'), payload.to_json)
        backoff_if_needed(response, api_name: 'Xurrent IMR')
        result = helpers.parse_response(response, expected_status: 201)

        [{
          output: {
            unique_id: result[:unique_id],
            incident_number: result[:incident_number],
            title: result[:title],
            summary: result[:summary],
            status: result[:status],
            creation_date: result[:creation_date],
            urgency: result[:urgency],
            assigned_to: result[:assigned_to],
            assigned_to_name: result[:assigned_to_name],
            incident_key: result[:incident_key],
          },
        }]
      end
    end

    action '019d6d9a-3230-7ca5-b963-a4363fda7dc1' do
      name 'Update Incident'
      avatar '/assets/icons/xurrent-imr.svg'
      description 'Updates an existing incident in Xurrent IMR.'

      input_schema do
        field :unique_id, 'Unique ID', :string, required: true,
                                                hint: 'Unique ID of the incident to update'
        field :title, 'Title', :string
        field :summary, 'Summary', :string
        field :assigned_to, 'Assigned To', :string, visibility: 'optional',
                                                    hint: 'Username to assign the incident to'
        field :status, 'Status', :integer, visibility: 'optional',
                                           enumeration: [
                                             { id: 1, label: 'Triggered' },
                                             { id: 2, label: 'Acknowledged' },
                                             { id: 3, label: 'Resolved' },
                                           ]
        field :escalation_policy_id, 'Escalation Policy ID', :string, visibility: 'optional',
                                                                      hint: 'Unique ID of the escalation policy'
        field :priority_id, 'Priority ID', :string, visibility: 'optional',
                                                    hint: 'Unique ID of the team priority'
        field :urgency, 'Urgency', :integer, visibility: 'optional',
                                             enumeration: [{ id: 0, label: 'Low' }, { id: 1, label: 'High' }]
      end

      output_schema do
        field :unique_id, 'Unique ID', :string, required: true
        field :incident_number, 'Incident Number', :integer, required: true
        field :title, 'Title', :string
        field :summary, 'Summary', :string
        field :status, 'Status', :integer
        field :creation_date, 'Creation Date', :string
        field :urgency, 'Urgency', :integer
        field :assigned_to, 'Assigned To', :string
        field :assigned_to_name, 'Assigned To Name', :string
        field :incident_key, 'Incident Key', :string
      end

      run do
        payload = helpers.build_incident_payload(input)
        response = http_patch(helpers.imr_url("incidents/#{input[:unique_id]}/"), payload.to_json)
        backoff_if_needed(response, api_name: 'Xurrent IMR')
        result = helpers.parse_response(response, expected_status: 200)

        [{
          output: {
            unique_id: result[:unique_id],
            incident_number: result[:incident_number],
            title: result[:title],
            summary: result[:summary],
            status: result[:status],
            creation_date: result[:creation_date],
            urgency: result[:urgency],
            assigned_to: result[:assigned_to],
            assigned_to_name: result[:assigned_to_name],
            incident_key: result[:incident_key],
          },
        }]
      end
    end

    action '019d6d9a-3230-7bdc-b7f8-c8edb073f0dd' do
      name 'Get Incident'
      avatar '/assets/icons/xurrent-imr.svg'
      description 'Retrieves incident details by incident number from Xurrent IMR.'

      input_schema do
        field :incident_number, 'Incident Number', :integer, required: true,
                                                             hint: 'The incident number to retrieve'
      end

      output_schema do
        field :unique_id, 'Unique ID', :string, required: true
        field :incident_number, 'Incident Number', :integer, required: true
        field :title, 'Title', :string
        field :summary, 'Summary', :string
        field :status, 'Status', :integer
        field :creation_date, 'Creation Date', :string
        field :urgency, 'Urgency', :integer
        field :assigned_to, 'Assigned To', :string
        field :assigned_to_name, 'Assigned To Name', :string
        field :incident_key, 'Incident Key', :string
      end

      run do
        response = http_get(helpers.imr_url("incidents/#{input[:incident_number]}/"))
        backoff_if_needed(response, api_name: 'Xurrent IMR')
        result = helpers.parse_response(response, expected_status: 200)

        [{
          output: {
            unique_id: result[:unique_id],
            incident_number: result[:incident_number],
            title: result[:title],
            summary: result[:summary],
            status: result[:status],
            creation_date: result[:creation_date],
            urgency: result[:urgency],
            assigned_to: result[:assigned_to],
            assigned_to_name: result[:assigned_to_name],
            incident_key: result[:incident_key],
          },
        }]
      end
    end

    action '019d6d9a-3230-726a-8739-21d20b569a55' do
      name 'List Incidents'
      nested true
      avatar '/assets/icons/xurrent-imr.svg'
      description 'Lists incidents from Xurrent IMR with filtering and pagination.'

      input_schema do
        field :status, 'Status', :integer,
              visibility: 'optional',
              enumeration: [
                { id: -1, label: 'Open (triggered + acknowledged)' },
                { id: 0, label: 'All' },
                { id: 1, label: 'Triggered' },
                { id: 2, label: 'Acknowledged' },
                { id: 3, label: 'Resolved' },
              ]
        field :team_ids, 'Team IDs', :string,
              array: true, visibility: 'optional',
              hint: 'Filter by team unique IDs'
        field :service_ids, 'Service IDs', :string,
              array: true, visibility: 'optional',
              hint: 'Filter by service unique IDs'
        field :escalation_policy_ids, 'Escalation Policy IDs', :string,
              array: true, visibility: 'optional',
              hint: 'Filter by escalation policy unique IDs'
        field :user_ids, 'User IDs', :string,
              array: true, visibility: 'optional',
              hint: 'Filter by usernames'
        field :from_date, 'From Date', :date_time, visibility: 'optional'
        field :to_date, 'To Date', :date_time, visibility: 'optional'
        field :priority_ids, 'Priority IDs', :string,
              array: true, visibility: 'optional',
              hint: 'Filter by priority unique IDs'
        field :tag_ids, 'Tag IDs', :string,
              array: true, visibility: 'optional',
              hint: 'Filter by tag unique IDs'
        field :all_teams, 'All Teams', :integer, visibility: 'optional',
                                                 enumeration: [{ id: 0, label: 'No' }, { id: 1, label: 'Yes' }],
                                                 hint: 'Include incidents from all teams'
      end

      output_schema 'page' do
        field :has_next_page, 'Has Next Page', :boolean, required: true
        field :incidents, 'Incidents', :nested, array: true do
          field :unique_id, 'Unique ID', :string
          field :incident_number, 'Incident Number', :integer
          field :title, 'Title', :string
          field :summary, 'Summary', :string
          field :status, 'Status', :integer
          field :urgency, 'Urgency', :integer
          field :creation_date, 'Creation Date', :string
          field :resolved_date, 'Resolved Date', :string
          field :acknowledged_date, 'Acknowledged Date', :string
          field :assigned_to, 'Assigned To', :string
          field :assigned_to_name, 'Assigned To Name', :string
          field :service, 'Service', :string
          field :escalation_policy, 'Escalation Policy', :string
          field :incident_key, 'Incident Key', :string
        end
      end

      iteration_state_schema do
        field :page, 'Page', :integer, required: true
      end

      run do
        page = iteration_state_value(:page) || 1

        filter_fields = [:status, :team_ids, :service_ids, :escalation_policy_ids, :user_ids, :from_date, :to_date,
                         :priority_ids, :tag_ids, :all_teams,]
        filter_payload = filter_fields.each_with_object({}) { |f, h| h[f] = input[f] if input[f].present? }

        response = http_post(helpers.imr_url("incidents/filter/?page=#{page}"), filter_payload.to_json)
        backoff_if_needed(response, api_name: 'Xurrent IMR')
        result = helpers.parse_response(response)

        incidents = result[:results] || []
        has_next = result[:next].present?
        self.iteration_state_value = has_next ? { page: page + 1 } : nil

        [{
          output: { has_next_page: has_next, incidents: incidents },
          schema_reference: 'page',
        }]
      end
    end

    action '019d6d9a-3230-76d1-be11-716ea42d26e8' do
      name 'Add Incident Note'
      avatar '/assets/icons/xurrent-imr.svg'
      description 'Adds a note to an existing incident in Xurrent IMR.'

      input_schema do
        field :incident_number, 'Incident Number', :integer, required: true
        field :note, 'Note', :string, required: true, hint: 'Note content'
      end

      output_schema do
        field :unique_id, 'Unique ID', :string, required: true
        field :note, 'Note', :string
        field :creation_date, 'Creation Date', :string
        field :user, 'User', :string
      end

      run do
        response = http_post(helpers.imr_url("incidents/#{input[:incident_number]}/note/"),
                             { note: input[:note] }.to_json)
        backoff_if_needed(response, api_name: 'Xurrent IMR')
        result = helpers.parse_response(response, expected_status: 201)

        [{
          output: {
            unique_id: result[:unique_id],
            note: result[:note],
            creation_date: result[:creation_date],
            user: result[:user],
          },
        }]
      end
    end

    action '019d6d9a-3230-7581-a1e0-0e8eae4bee91' do
      name 'Create Alert'
      avatar '/assets/icons/xurrent-imr.svg'
      description 'Creates an alert in Xurrent IMR via the Events API.'

      input_schema do
        field :integration_key, 'Integration Key', :string, required: true,
                                                            hint: 'Integration key for the target service integration'
        field :message, 'Message', :string, required: true,
                                            hint: 'Alert message (becomes incident title)'
        field :alert_type, 'Alert Type', :string, required: true,
                                                  enumeration: [
                                                    { id: 'critical', label: 'Critical' },
                                                    { id: 'error', label: 'Error' },
                                                    { id: 'warning', label: 'Warning' },
                                                    { id: 'info', label: 'Info' },
                                                    { id: 'acknowledged', label: 'Acknowledged' },
                                                    { id: 'resolved', label: 'Resolved' },
                                                  ]
        field :summary, 'Summary', :string, visibility: 'optional'
        field :entity_id, 'Entity ID', :string, visibility: 'optional',
                                                hint: 'Deduplication key (groups alerts into one incident)'
        field :payload, 'Payload', :hash, visibility: 'optional',
                                          hint: 'Additional JSON metadata to include with the alert'
        field :urls, 'URLs', :nested, array: true, visibility: 'optional',
                                      hint: 'Related links' do
          field :link_url, 'URL', :string
          field :link_text, 'Link Text', :string
        end
      end

      output_schema do
        field :unique_id, 'Unique ID', :string
        field :incident, 'Incident Number', :integer
        field :incident_created, 'Incident Created', :boolean
        field :entity_id, 'Entity ID', :string
        field :alert_type, 'Alert Type', :integer
        field :message, 'Message', :string
      end

      run do
        payload = {
          message: input[:message],
          alert_type: input[:alert_type],
          summary: input[:summary],
          entity_id: input[:entity_id],
          payload: input[:payload],
          urls: input[:urls],
        }.compact
        response = http_post(helpers.imr_url("events/#{input[:integration_key]}/"), payload.to_json)
        backoff_if_needed(response, api_name: 'Xurrent IMR')
        result = helpers.parse_response(response, expected_status: 201)

        [{
          output: {
            unique_id: result[:unique_id],
            incident: result[:incident],
            incident_created: result[:incident_created],
            entity_id: result[:entity_id],
            alert_type: result[:alert_type],
            message: result[:message],
          },
        }]
      end
    end

    action '019d6d9a-3230-7255-96c5-194b12acb53d' do
      name 'Get On-Call'
      avatar '/assets/icons/xurrent-imr.svg'
      description 'Retrieves the current on-call users for a team in Xurrent IMR.'

      input_schema do
        field :team_id, 'Team ID', :string, required: true,
                                            hint: 'Unique ID of the team'
      end

      output_schema do
        field :escalation_policies, 'Escalation Policies', :nested, array: true do
          field :unique_id, 'Unique ID', :string
          field :name, 'Name', :string
          field :oncalls, 'On-Call Rules', :nested, array: true do
            field :position, 'Position', :integer
            field :delay, 'Delay', :integer
            field :oncalls, 'On-Call Users', :nested, array: true do
              field :username, 'Username', :string
              field :first_name, 'First Name', :string
              field :last_name, 'Last Name', :string
              field :email, 'Email', :string
            end
          end
        end
      end

      run do
        response = http_get(helpers.imr_url("v2/account/teams/#{input[:team_id]}/oncall/"))
        backoff_if_needed(response, api_name: 'Xurrent IMR')
        result = helpers.parse_response(response)
        [{ output: { escalation_policies: result } }]
      end
    end

    action '019d6d9a-3230-79a4-82e0-6e399b045498' do
      name 'List Teams'
      avatar '/assets/icons/xurrent-imr.svg'
      description 'Lists all teams in the Xurrent IMR account.'

      output_schema do
        field :teams, 'Teams', :nested, array: true do
          field :unique_id, 'Unique ID', :string
          field :name, 'Name', :string
          field :owner, 'Owner', :string
          field :creation_date, 'Creation Date', :string
        end
      end

      run do
        response = http_get(helpers.imr_url('account/teams/'))
        backoff_if_needed(response, api_name: 'Xurrent IMR')
        result = helpers.parse_response(response)
        teams = result.map do |team|
          { unique_id: team[:unique_id], name: team[:name], owner: team[:owner], creation_date: team[:creation_date] }
        end
        [{ output: { teams: teams } }]
      end
    end

    action '019d6d9a-3230-76c3-99c4-2bdace47066c' do
      name 'List Services'
      avatar '/assets/icons/xurrent-imr.svg'
      description 'Lists all services for a team in Xurrent IMR.'

      input_schema do
        field :team_id, 'Team ID', :string, required: true,
                                            hint: 'Unique ID of the team'
      end

      output_schema do
        field :services, 'Services', :nested, array: true do
          field :unique_id, 'Unique ID', :string
          field :name, 'Name', :string
          field :team, 'Team', :string
          field :status, 'Status', :integer
          field :escalation_policy, 'Escalation Policy', :string
          field :summary, 'Summary', :string
        end
      end

      run do
        response = http_get(helpers.imr_url("account/teams/#{input[:team_id]}/services/"))
        backoff_if_needed(response, api_name: 'Xurrent IMR')
        result = helpers.parse_response(response)
        services = result.map do |svc|
          {
            unique_id: svc[:unique_id], name: svc[:name], team: svc[:team],
            status: svc[:status], escalation_policy: svc[:escalation_policy], summary: svc[:summary],
          }
        end
        [{ output: { services: services } }]
      end
    end

    helper :api_endpoint do
      (outbound_connection.config[:base_url].presence || 'https://www.zenduty.com').chomp('/')
    end

    helper :imr_url do |path|
      "#{helpers.api_endpoint}/api/#{path}"
    end

    helper :parse_response do |response, expected_status: [200, 201]|
      statuses = Array(expected_status)
      unless statuses.include?(response.status)
        fail_job!("Xurrent IMR API error (HTTP #{response.status}): '#{response.body}'")
      end
      body = parse_json_response(response.body,
                                 error_message: "Xurrent IMR response is not valid JSON: '#{response.body}'")
      body.is_a?(Array) ? body.map(&:with_indifferent_access) : body.with_indifferent_access
    end

    helper :build_incident_payload do |params|
      {
        title: params[:title],
        summary: params[:summary],
        service: params[:service_id],
        escalation_policy: params[:escalation_policy_id],
        assigned_to: params[:assigned_to],
        status: params[:status],
        team_priority: params[:priority_id],
        urgency: params[:urgency],
      }.compact
    end
  end
end
