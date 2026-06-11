class XurrentAppConnector < IPaaS::Connector::Definition
  INLINE_MEDIA_REGEX = /!\[((?:\\.|[^\]])*)\]\(([^)]+)\)(?:{:([^}]*)})?/
  # Scopes the provider OAuth Application needs. Used by the credentials hint and the
  # setup_info deep-link, so both stay in sync. Format: "model:RCUD" with hyphenated
  # model names (Xurrent's URL-encoded shorthand).
  PROVIDER_OAUTH_SCOPES = %w[
    account:R
    app-instance:RU
    app-offering:CRU
    app-offering-automation-rule:CRUD
    app-offering-scope:CRU
    attachment:R
    service-instance:R
    ui-extension:CRU
    webhook:CRU
    webhook-policy:CRU
  ].freeze
  SCOPE_ACTION_LABELS = { 'C' => 'Create', 'R' => 'Read', 'U' => 'Update', 'D' => 'Delete' }.freeze
  PROVIDER_OAUTH_SCOPES_PROSE = PROVIDER_OAUTH_SCOPES.map do |scope|
    model, actions = scope.split(':')
    model_label = model.split('-').map(&:capitalize).join(' ')
    action_labels = actions.chars.map { |c| SCOPE_ACTION_LABELS.fetch(c) }
    "   - #{model_label} (#{action_labels.join(', ')})"
  end.join("\n").freeze
  APP_OFFERING_FIELDS = <<-GRAPHQL.freeze
    id
    name
    reference
    cardDescription
    description
    descriptionAttachments(first: 100) {
       nodes {
         key
         inline
         expiringUrl
       }
    }
    pictureUri
    features
    featuresAttachments(first: 100) {
       nodes {
         key
         inline
         expiringUrl
       }
    }
    compliance
    serviceInstance { name }
    webhookUriTemplate
    configurationUriTemplate
    oauthAuthorizationEndpoints
    policyJwtAlg
    policyJwtAudience
    policyJwtClaimExpiresIn
    requiresEnabledOauthPerson
    openidConnectDiscovery
    scopes { id actions effect grantType }
    uiExtensionVersion {
      id
      css
      html
      javascript
      formDefinition
      uiExtension {
        id
        category
        description
        name
        title
      }
    }
    automationRules(first: 100) {
      nodes {
        actions { name value }
        id
        condition
        description
        expressions { name value }
        generic
        name
        trigger
      }
    }
  GRAPHQL

  connector '01946424-c2ed-7fef-8202-fafd3751278c' do
    name 'Xurrent App Connector'
    avatar '/assets/icons/x-logo-app.svg'
    description <<~END_OF_DESCRIPTION
       This connector serves as the foundation for integration code that powers a custom Xurrent App.

       # Secrets Changed Runbook (A)
       Each iPaaS solution linked to a Xurrent App requires a single **Secrets Changed** runbook, triggered by the `Secrets Changed` event. When enabled, this runbook securely configures the provider's Xurrent account to send secrets to the iPaaS solution.

       # Automation Webhook Runbook (B)
       For handling integration logic, create a runbook using the `Automation Webhook` trigger. This runbook executes whenever the webhook is invoked by the automation rules tied to the App offering.

       # Installation Changed Runbook (C)
       To implement business logic during a customer's App installation, use the `Installation Changed` trigger. This trigger can be configured to respond to:
        - New installations
        - Updates
        - App removals

      # Available Actions
      Runbooks starting with the `Installation Changed` or `Automation Webhook` triggers can leverage the following actions to access App-related configuration data:

      ## Client Credentials Token (1)
      Outputs the client ID and secret for API access to the customer's Xurrent account.

      Runbooks starting with the `Installation Changed` or `Automation Webhook` triggers can use this action without any further configuration to retrieve the correct credentials.

      When using this action in another context the following 2 fields must be provided:
       - `customer_account_id`: The account ID of the customer’s Xurrent account.
       - `app_reference`: The reference of the app offering.

      ## Retrieve App Config (2)
      Outputs secrets and configuration values provided by the customer in Xurrent. The fields depend on the UI extension for the App offering.

      All fields that need to be retrieved must be added to the `Configuration schema`. Secret values in the UI extension should be defined using the `secret_string`-type.

      Runbooks starting with the `Installation Changed` or `Automation Webhook` triggers can use this action without any further configuration to retrieve the configuration details.

      When using this action in another context the following 2 fields must be provided:
       - `customer_account_id`: The account ID of the customer’s Xurrent account.
       - `app_reference`: The reference of the app offering.

      ## Authorization Code Token (3)
      Outputs the client ID and secret for GUI access to the customer's Xurrent account.

      Runbooks starting with the `Installation Changed` or `Automation Webhook` triggers can use this action without any further configuration to retrieve the correct credentials.

      When using this action in another context the following 2 fields must be provided:
       - `customer_account_id`: The account ID of the customer’s Xurrent account.
       - `app_reference`: The reference of the app offering.

      ## Update App Config (4)
      Update the configuration values visible to the customer in Xurrent. The available fields depend on the UI extension related to the App offering.

      Next to the custom fields it is also possible to update the disabled status of the App instance or to suspend the integration with a specific comment.

      Runbooks starting with the `Installation Changed` or `Automation Webhook` triggers can use this action without any further configuration to update the configuration details.

      When using this action in another context the following 2 fields must be provided:
       - `customer_account_id`: The account ID of the customer’s Xurrent account.
       - `app_reference`: The reference of the app offering.

      ## Async URLs
      Poll multiple URLs and return data when available. This action will check each URL and return the first one that has data available. Subsequent iterations will poll remaining URLs until all URLs have been processed.

      # External Application
      To respond to changes in the external application additional runbooks can be created. When the trigger output schema includes the following 2 fields the available actions above can be used to retrieve the App configuration details.
       - `customer_account_id`: The account ID of the customer’s Xurrent account.
       - `app_reference`: The reference of the app offering.
    END_OF_DESCRIPTION

    inbound_connection do
      validate do |_request|
        # validation is done when parsing requests in the triggers as the JWT tokens will differ
        true
      end
    end

    # Outbound connection back to Xurrent in the providers account
    outbound_connection do
      config_schema do
        field :credentials, 'Credentials', :nested,
              hint: <<~END_OF_HINT,
                Provide the credentials for the Xurrent provider account defining the App offerings.

                These credentials will be used by the `Secrets Changed`, `Automation Webhook` and
                `Installation Changed` triggers to link the providers' Xurrent account to the runbooks
                using those triggers.

                Use the **Quick setup** link above to open the OAuth Application form in Xurrent
                pre-filled with the application name, grant type, and required scopes — press Save
                in Xurrent, then copy the Client ID and Client Secret here.

                # Manual setup
                1. Login to the provider Xurrent account as a user with the administrator role.
                2. Navigate to the OAuth Applications console within the settings section.
                3. Create a new application using 'Client credentials grant'.
                4. The following scopes that allow:
                #{PROVIDER_OAUTH_SCOPES_PROSE}
                5. Save the new OAuth Application and copy the Client ID and secret token to this connection.
              END_OF_HINT
              required: true do
          field :account_id, 'Account ID', :string,
                hint: 'The Xurrent provider account identifier. ' \
                      'Leave blank to use the current iPaaS account.',
                visibility: 'optional'
          field :client_id, 'Client ID', :string,
                hint: 'Provider client ID',
                required: true
          field :client_secret, 'Client secret', :secret_string,
                hint: 'Provider client secret',
                required: true
        end

        # Stage and region fall back to the current iPaaS environment via
        # xurrent_domain at runtime, so neither is required. Custom OAuth and
        # GraphQL endpoints must be paired (or both blank) when stage is also
        # blank, to avoid cross-environment mismatches.
        env_validator = ->(value) do
          return true if value.blank?
          return true if value[:stage].present?

          value[:graphql_endpoint].present? == value[:oauth2_endpoint].present?
        end
        field :environment, 'Environment', :nested,
              hint: 'Override the Xurrent environment to connect to. ' \
                    'Stage and region default to the current iPaaS environment when left blank. ' \
                    'Use custom endpoints only when connecting to a non-standard environment.',
              visibility: 'optional',
              validator: env_validator do
          field :stage, 'Stage', :string,
                hint: 'Leave blank to use the current iPaaS stage.',
                enumeration: %w[Demo QA Prod]
          field :region, 'Region', :string,
                hint: 'Leave blank to use the current iPaaS region.',
                enumeration: %w[au ch uk us]
          field :oauth2_endpoint, 'OAuth2 Endpoint', :uri,
                visibility: 'optional'
          field :graphql_endpoint, 'GraphQL Endpoint', :uri,
                visibility: 'optional'
          field :rest_endpoint, 'REST Endpoint', :uri,
                visibility: 'optional'
        end
      end

      authenticate do |request|
        credentials_config = config[:credentials] || {}
        account_id = credentials_config[:account_id].presence || helpers.system_account_id
        request.headers['X-Xurrent-Account'] = account_id

        body = oauth2_client_credentials_body(credentials_config[:client_id],
                                              decrypt_secret_string(credentials_config[:client_secret]))
        request.headers['Authorization'] = oauth2_authorization_header(helpers.oauth_endpoint,
                                                                       body,
                                                                       account_id: account_id)
      end

      config_tester do
        response = http_get(helpers.introspect_endpoint, nil, nil, open_timeout: 1, timeout: 2)
        if response.status == 200
          parsed = helpers.parse_introspection_response(response)
          scopes = Array(parsed['scopes'])
          if scopes.any?
            { status: :success, message: "Connection successful. Token scopes: #{scopes.join(', ')}." }
          else
            { status: :failed, message: 'Token is valid but has no scopes.' }
          end
        elsif [401, 403].include?(response.status)
          { status: :failed, message: "Xurrent rejected the credentials (HTTP #{response.status})." }
        elsif response.status == 400
          parsed = helpers.parse_introspection_response(response)
          { status: :failed, message: parsed['message'].presence || 'Xurrent rejected the request (HTTP 400).' }
        else
          {
            status: :error,
            message: "Token introspection failed (HTTP #{response.status}): '#{response.body}'",
          }
        end
      rescue IPaaS::Job::Outbound::CustomerCredentialsError => e
        { status: :failed, message: e.message }
      rescue JSON::ParserError
        { status: :error, message: "Token introspection returned an unparseable response (HTTP #{response.status})." }
      end

      helper :parse_introspection_response do |response|
        parsed = JSON.parse(response.body)
        raise JSON::ParserError unless parsed.is_a?(Hash)
        parsed
      end

      # Introspect lives on the oauth host; rebuild from the resolved oauth endpoint
      # so stage/region/custom-endpoint resolution is reused.
      helper :introspect_endpoint do
        uri = URI.parse(helpers.oauth_endpoint)
        port = uri.port == uri.default_port ? '' : ":#{uri.port}"
        "#{uri.scheme}://#{uri.host}#{port}/introspect"
      end

      setup_info do
        credentials_config = config[:credentials] || {}
        account_id = credentials_config[:account_id].presence || helpers.system_account_id
        next nil if account_id.blank?

        app_name = solution&.name&.presence || 'iPaaS Integration'
        query = URI.encode_www_form(
          name: app_name,
          grant_type: 'client_credentials',
          scopes: PROVIDER_OAUTH_SCOPES.join(','),
        )
        url = "https://#{account_id}.#{helpers.xurrent_domain}/oauth_applications/new?#{query}"

        {
          'Quick setup': {
            'Create OAuth Application in Xurrent': {
              hint: 'Opens Xurrent with the application name, grant type, and required scopes ' \
                    'pre-filled. Press Save in Xurrent, then copy the Client ID and Client Secret here.',
              href: url,
              value: url,
            },
          },
        }
      end
    end

    trigger '01946446-ceac-7bca-84a0-0a00db534678' do
      name 'Secrets Changed'
      avatar '/assets/icons/key.svg'
      description <<~END_OF_DESCRIPTION
         # Secrets Changed Runbook (A)
        Each iPaaS solution linked to a Xurrent App requires a single **Secrets Changed** runbook, triggered by the `Secrets Changed` event. When enabled, this runbook securely configures the provider's Xurrent account to send secrets to the iPaaS solution.

        Note that the mandatory action can be a simple log action that shows a secret has been processed.

        When this runbook is enabled it will create an `app_instance.secrets-update` webhook in the provider account protected with a webhook policy. All secrets sent using that webhook, will be stored in the (outbound) connection store scoped by customer account ID and App reference.

        The secrets can be accessed from other runbooks in this solution using one of the following actions:
        ## Client Credentials Token (1)
        Outputs the client ID and secret for API access to the customer's Xurrent account.

        ## Retrieve App Config (2)
        Outputs secrets and configuration values provided by the customer in Xurrent. The fields depend on the UI extension for the App offering.

        ## Authorization Code Token (3)
        Outputs the client ID and secret for GUI access to the customer's Xurrent account.
      END_OF_DESCRIPTION
      outbound_traffic true

      config_schema do
        field :app_references, 'App References', :string,
              array: true,
              hint: 'The references of the Apps that are part of the current solution.'

        field :discard_filter, 'Discard filter', :ruby,
              hint: 'Ruby code to execute to determine whether to discard a webhook received.',
              sample: "input.dig(:webhook, :person_name) == 'My App'"
      end

      output_schema do
        field :customer_account_id, 'Customer account ID', :string,
              hint: 'The account ID of the customer’s Xurrent account.'

        field :app_reference, 'App Reference', :string,
              hint: 'The reference of the app offering.'

        field :webhook, 'Webhook', :nested,
              hint: 'Details of the webhook delivery received.' do
          field :event, 'Event', :string,
                hint: 'The type of event causing the webhook to be triggered.'

          field :delivery, 'Delivery', :string,
                hint: 'The webhook delivery received (header `x-xurrent-delivery`).'

          field :delivery_origin, 'Delivery origin', :string,
                hint: 'The origin of the webhook delivery received (header `x-xurrent_delivery-origin`).'

          field :person, 'Person', :nested,
                hint: 'Details of the person who performed the update causing the webhook to be triggered.' do
            field :id, 'ID', :integer,
                  hint: 'The ID of the person.'

            field :nodeID, 'Node ID', :string,
                  hint: 'The Node ID of the person.'

            field :name, 'Name', :string,
                  hint: 'The name of the person.'
          end
        end
      end

      parse do |request|
        fail_job!('Request has no body') if request.body.blank?

        secrets_webhook = helpers.extract_webhook_body(request, helpers.provider_webhook_policy)
        helpers.handle_webhook_verification(secrets_webhook) if helpers.webhook_verification?(secrets_webhook)
        base_output = helpers.process_secrets_webhook(secrets_webhook)
        helpers.finish_trigger_output(trigger.config, request, secrets_webhook, base_output)
      end

      respond_with do |context, response|
        helpers.webhook_response_with_verification(context, response)
      end

      ##################################################################################
      # Processing of secrets webhook

      helper :process_secrets_webhook do |secrets_webhook|
        payload = secrets_webhook[:payload]
        customer_account_id = payload[:customer_account_id]
        app_reference = payload.dig(:app_offering, :reference)
        if config[:app_references] == [app_reference]
          helpers.store_job_context_identifier(customer_account_id, nil)
        else
          helpers.store_job_context_identifier(customer_account_id, app_reference)
        end

        helpers.process_customer_client_credentials_token(payload, customer_account_id, app_reference)
        helpers.process_customer_authorization_code_token(payload, customer_account_id, app_reference)
        helpers.process_customer_webhook_policy(payload, customer_account_id, app_reference)
        helpers.process_customer_secrets(payload, customer_account_id, app_reference)

        {
          customer_account_id: customer_account_id,
          app_reference: app_reference,
        }
      end

      helper :process_customer_client_credentials_token do |payload, customer_account_id, app_reference|
        client_credentials_token = payload[:application]
        next unless client_credentials_token

        helpers.write_oauth_token(helpers.customer_client_credentials_token_key(customer_account_id, app_reference),
                                  client_credentials_token[:nodeID],
                                  client_credentials_token[:client_id],
                                  client_credentials_token[:client_secret])
      end

      helper :process_customer_authorization_code_token do |payload, customer_account_id, app_reference|
        authorization_code_token = payload[:authorization_application]
        next unless authorization_code_token

        helpers.write_oauth_token(helpers.customer_authorization_code_token_key(customer_account_id, app_reference),
                                  authorization_code_token[:nodeID],
                                  authorization_code_token[:client_id],
                                  authorization_code_token[:client_secret])
      end

      helper :process_customer_webhook_policy do |payload, customer_account_id, app_reference|
        policy = payload[:policy]
        next unless policy

        helpers.write_webhook_policy(helpers.customer_webhook_policy_key(customer_account_id, app_reference),
                                     policy['nodeID'],
                                     policy['algorithm'],
                                     policy['public_key'],
                                     policy['issuer'] || helpers.issuer(customer_account_id),
                                     policy['audience'])
      end

      helper :process_customer_secrets do |payload, customer_account_id, app_reference|
        secrets = payload[:secrets]
        next unless secrets

        secrets.each do |key, secret|
          secrets[key] = make_secret_string(secret)
        end
        existing_secrets = helpers.read_customer_secrets(customer_account_id, app_reference)
        outbound_connection.store.write(helpers.customer_secrets_key(customer_account_id, app_reference),
                                        existing_secrets.merge(secrets).to_json)
      end

      ##################################################################################
      # Managing `app_instance.secrets-update` webhook in provider account

      provision do
        helpers.enable_or_create_provider_webhook_policy
        helpers.enable_or_create_provider_secrets_webhook
      end

      deprovision do
        helpers.toggle_provider_secrets_webhook(false)
      end

      helper :enable_or_create_provider_secrets_webhook do
        helpers.toggle_provider_secrets_webhook(true) || helpers.create_provider_secrets_webhook
      end

      helper :toggle_provider_secrets_webhook do |flag|
        secrets_webhook_id = outbound_connection.store.read('provider_secrets_webhook_id')
        next false unless secrets_webhook_id

        references = trigger.config[:app_references] || []
        helpers.toggle_webhook(secrets_webhook_id, flag, 'app_instance.secrets-update', references)
      end

      helper :create_provider_secrets_webhook do
        webhook_id = helpers.create_provider_webhook(
          event: 'app_instance.secrets-update',
          app_reference: trigger.config[:app_references],
          endpoint: trigger.endpoint,
          name: 'Secrets Changed',
        )
        outbound_connection.store.write('provider_secrets_webhook_id', webhook_id)
      end
    end

    trigger '01947404-86a5-7db4-aac3-ab54573f9b6d' do
      name 'Installation Changed'
      avatar '/assets/icons/cart-plus.svg'
      description <<~END_OF_DESCRIPTION
        # Installation Changed Runbook (C)
        To implement business logic during a customer's App installation, use this `Installation Changed` trigger. It can be configured to respond to:
         - New installations
         - Updates
         - App removals

        The configuration/secrets of the customer can be accessed using one of the following actions:

        ## Client Credentials Token (1)
        Outputs the client ID and secret for API access to the customer's Xurrent account.

        ## Retrieve App Config (2)
        Outputs secrets and configuration values provided by the customer in Xurrent. The fields depend on the UI extension for the App offering.

        ## Authorization Code Token (3)
        Outputs the client ID and secret for GUI access to the customer's Xurrent account.
      END_OF_DESCRIPTION
      outbound_traffic true

      config_schema do
        field :event, 'Event', :string,
              hint: 'The type of event to respond to.',
              required: true,
              enumeration: [
                { id: 'app_instance.create', label: 'App installed' },
                { id: 'app_instance.update', label: 'App updated' },
                { id: 'app_instance.delete', label: 'App removed' },
              ]

        field :app_reference, 'App Reference', :string,
              hint: 'The reference of the app offering.'

        configuration_uri_validator = ->(value) do
          next unless value.present?

          config[:app_reference].present? && value.start_with?('https://')
        end

        field :configuration_uri_template, 'Configuration Uri Template', :uri,
              hint: 'The configuration uri template to set in the app offering.',
              validator: configuration_uri_validator

        field :discard_filter, 'Discard filter', :ruby,
              hint: 'Ruby code to execute to determine whether to discard a webhook received.',
              sample: "input.dig(:webhook, :person_name) == 'My App'"
      end

      output_schema do
        field :customer_account_id, 'Customer account ID', :string,
              hint: 'The account ID of the customer’s Xurrent account.',
              required: true

        field :app_reference, 'App Reference', :string,
              hint: 'The reference of the app offering.',
              required: true

        field :disabled, 'Disabled', :boolean,
              hint: 'Whether or not the App is disabled.'

        field :enabled_by_customer, 'Enabled by customer', :boolean,
              hint: 'Whether or not the App is enabled by the customer.'

        field :suspended, 'Suspended', :boolean,
              hint: 'Whether or not the App is suspended.'

        field :customer_representative, 'Customer representative', :nested,
              hint: 'The customer representative.' do
          field :id, 'ID', :integer,
                hint: 'The ID of the customer representative.'

          field :disabled, 'Disabled', :boolean,
                hint: 'True if the customer representative is disabled.'

          field :sourceID, 'Source ID', :string,
                hint: 'The Source ID of the customer representative.'

          field :nodeID, 'Node ID', :string,
                hint: 'The Node ID of the customer representative.'

          field :name, 'Name', :string,
                hint: 'The name of the customer representative.'

          field :account, 'Account', :nested,
                hint: 'The Xurrent account of the customer representative.' do
            field :id, 'ID', :string,
                  hint: 'The account ID of the customer representative.'

            field :name, 'Name', :string,
                  hint: 'The account name of the customer representative.'
          end
        end

        field :app_offering, 'App offering', :nested,
              hint: 'The currently linked App offering.' do
          field :reference, 'Reference', :string,
                hint: 'The reference of the app offering.'

          field :id, 'ID', :integer,
                hint: 'The ID of the app offering.'

          field :nodeID, 'Node ID', :string,
                hint: 'The Node ID of the app offering.'

          field :updated, 'Updated', :boolean,
                hint: 'Whether or not the App has been updated to a new version.'
        end

        field :webhook, 'Webhook', :nested,
              hint: 'Details of the webhook delivery received.' do
          field :event, 'Event', :string,
                hint: 'The type of event causing the webhook to be triggered.'

          field :delivery, 'Delivery', :string,
                hint: 'The webhook delivery received (header `x-xurrent-delivery`).'

          field :delivery_origin, 'Delivery origin', :string,
                hint: 'The origin of the webhook delivery received (header `x-xurrent_delivery-origin`).'

          field :person, 'Person', :nested,
                hint: 'Details of the person who performed the update causing the webhook to be triggered.' do
            field :id, 'ID', :integer,
                  hint: 'The ID of the person.'

            field :nodeID, 'Node ID', :string,
                  hint: 'The Node ID of the person.'

            field :name, 'Name', :string,
                  hint: 'The name of the person.'
          end
        end
      end

      parse do |request|
        fail_job!('Request has no body') if request.body.blank?

        webhook_body = helpers.extract_webhook_body(request, helpers.provider_webhook_policy)
        helpers.handle_webhook_verification(webhook_body) if helpers.webhook_verification?(webhook_body)
        payload = webhook_body[:payload]

        customer_account_id = payload[:customer_account_id]
        app_reference = payload.dig(:app_offering, :reference)
        if config[:app_reference].present?
          helpers.store_job_context_identifier(customer_account_id, nil)
        else
          helpers.store_job_context_identifier(customer_account_id, app_reference)
        end

        if trigger.config[:app_reference].present? && trigger.config[:app_reference] != app_reference
          message = "App reference '#{app_reference}' is different from '#{trigger.config[:app_reference]}'."
          discard_trigger_event!(message)
        end

        base_output = {
          customer_account_id: customer_account_id,
          app_reference: app_reference,
          disabled: payload[:disabled],
          enabled_by_customer: payload[:enabled_by_customer],
          suspended: payload[:suspended],
          customer_representative: payload[:customer_representative],
          app_offering: payload[:app_offering],
        }
        helpers.finish_trigger_output(trigger.config, request, webhook_body, base_output)
      end

      respond_with do |context, response|
        helpers.webhook_response_with_verification(context, response)
      end

      ##################################################################################
      # Provisioning:
      #  - Use blueprint to sync App Offering.
      #  - Manage `app_instance.create/update/delete` webhook in provider account.

      blueprint_filenames %w[app_offering.json app_offering_automation_rules.json app_offering_ui_extension.json]

      extract_blueprint do
        helpers.extract_app_offering
      end

      provision do
        app_offering = helpers.apply_app_offering
        helpers.set_configuration_uri_template(app_offering['id']) if app_offering
        helpers.enable_or_create_provider_webhook_policy
        helpers.enable_or_create_app_instance_webhook
      end

      deprovision do
        helpers.toggle_app_instance_webhook(false)
      end

      helper :enable_or_create_app_instance_webhook do
        helpers.toggle_app_instance_webhook(true) || helpers.create_app_instance_webhook
      end

      helper :app_instance_webhook_id do
        "app_instance_webhook_id-#{trigger.runbook.uuid}"
      end

      helper :toggle_app_instance_webhook do |flag|
        webhook_id = inbound_connection.store.read(helpers.app_instance_webhook_id)
        next false unless webhook_id

        app_reference = trigger.config[:app_reference]
        references = app_reference.present? ? [app_reference] : []
        helpers.toggle_webhook(webhook_id, flag, trigger.config[:event], references)
      end

      helper :create_app_instance_webhook do
        webhook_id = helpers.create_provider_webhook(
          event: trigger.config[:event],
          app_reference: trigger.config[:app_reference],
          endpoint: trigger.endpoint,
          runbook_uuid: trigger.runbook.uuid,
        )
        inbound_connection.store.write(helpers.app_instance_webhook_id, webhook_id)
      end

      helper :set_configuration_uri_template do |app_offering_id|
        config_uri = trigger.config[:configuration_uri_template]
        next unless config_uri.present?

        new_values = {
          configurationUriTemplate: config_uri,
        }
        helpers.update_app_offering(
          app_offering_id, new_values,
          context: 'set Configuration URI Template on App Offering'
        )
      end
    end

    trigger '01946f8e-ade1-7251-8638-1834d7b8382c' do
      name 'Automation Webhook'
      avatar '/assets/icons/x-logo-webhook.svg'
      description <<~END_OF_DESCRIPTION
        # Automation Webhook Runbook (B)
        For handling integration logic, create a runbook using this `Automation Webhook` trigger. This runbook executes whenever the webhook is invoked by the automation rules tied to the App offering.

        When this runbook is enabled, the URI field of the App Offering with the specified reference will automatically be set to the endpoint of this runbook. Incoming webhooks are validated automatically, provided a `Secrets Changed` runbook has been created and enabled in this solution.

        You can define a **payload schema** to automatically parse payload data into the correct types. This is especially useful when webhook payloads are consistent or similar across all App Offering automation rules.

        **Important**: Do not create or enable more than one of these runbooks for the same App Reference, as they will override the same App Offering.

        The configuration/secrets of the customer can be accessed using one of the following actions:

        ## Client Credentials Token (1)
        Outputs the client ID and secret for API access to the customer's Xurrent account.

        ## Retrieve App Config (2)
        Outputs secrets and configuration values provided by the customer in Xurrent. The fields depend on the UI extension for the App offering.

        ## Authorization Code Token (3)
        Outputs the client ID and secret for GUI access to the customer's Xurrent account.
      END_OF_DESCRIPTION
      outbound_traffic true

      config_schema do
        field :app_reference, 'App Reference', :string,
              hint: 'The reference of the app offering.',
              required: true

        field :payload_schema, 'Payload Schema', [:schema_field],
              hint: 'The schema of the webhook payload. If left empty the payload is defined as a hash.'

        field :discard_filter, 'Discard filter', :ruby,
              hint: 'Ruby code to execute to determine whether to discard a webhook received.',
              sample: "input.dig(:webhook, :person_name) == 'My App'"

        after_update do
          regenerate_schema(output_schema)
        end
      end

      output_schema do
        field :app_reference, 'App Reference', :string,
              hint: 'The reference of the app offering.',
              required: true

        field :customer_account_id, 'Customer account ID', :string,
              hint: 'The account ID of the customer’s Xurrent account.',
              required: true

        payload_schema = trigger.config[:payload_schema]
        field :payload, 'Payload', payload_schema.present? ? :nested : :hash,
              hint: 'The payload from the automation rule.',
              fields: payload_schema.presence,
              required: true

        field :webhook, 'Webhook', :nested,
              hint: 'Details of the webhook delivery received.' do
          field :event, 'Event', :string,
                hint: 'The type of event causing the webhook to be triggered.'

          field :delivery, 'Delivery', :string,
                hint: 'The webhook delivery received (header `x-xurrent-delivery`).'

          field :delivery_origin, 'Delivery origin', :string,
                hint: 'The origin of the webhook delivery received (header `x-xurrent_delivery-origin`).'

          field :person, 'Person', :nested,
                hint: 'Details of the person who performed the update causing the webhook to be triggered.' do
            field :id, 'ID', :integer,
                  hint: 'The ID of the person.'

            field :nodeID, 'Node ID', :string,
                  hint: 'The Node ID of the person.'

            field :name, 'Name', :string,
                  hint: 'The name of the person.'
          end
        end
      end

      parse do |request|
        fail_job!('Request has no body') if request.body.blank?

        customer_account_id = request.params['customer_account_id']
        fail_job!('Missing customer_account_id parameter') if customer_account_id.blank?

        automation_webhook = helpers.extract_webhook_body(request, helpers.triggered_customer_webhook_policy(request))
        helpers.handle_webhook_verification(automation_webhook) if helpers.webhook_verification?(automation_webhook)

        app_reference = trigger.config[:app_reference]
        helpers.store_job_context_identifier(customer_account_id, nil)

        base_output = {
          app_reference: app_reference,
          customer_account_id: customer_account_id,
          payload: automation_webhook[:payload].except(:app_offering, :customer_account_id),
        }
        helpers.finish_trigger_output(trigger.config, request, automation_webhook, base_output)
      end

      respond_with do |context, response|
        helpers.webhook_response_with_verification(context, response)
      end

      helper :triggered_customer_webhook_policy do |request|
        customer_account_id = request.params['customer_account_id']
        app_reference = trigger.config[:app_reference]
        helpers.customer_webhook_policy(customer_account_id, app_reference)
      end

      ##################################################################################
      # Provisioning:
      #  - Use blueprint to sync App Offering.
      #  - Managing webhookUriTemplate of the App Offering.

      blueprint_filenames %w[app_offering.json app_offering_automation_rules.json app_offering_ui_extension.json]

      extract_blueprint do
        helpers.extract_app_offering
      end

      provision do
        app_offering = helpers.apply_app_offering
        app_offering ||= helpers.find_app_offering(id_only: true)

        app_offering_id = app_offering&.dig('id')
        # TODO: fail_provisioning! instead of fail_job! or something similar?
        fail_job!("No App offering found with reference '#{trigger.config[:app_reference]}'") unless app_offering_id
        helpers.set_webhook_uri_template(app_offering_id)
      end

      helper :set_webhook_uri_template do |app_offering_id|
        new_values = {
          webhookUriTemplate: "#{trigger.endpoint}?customer_account_id={account}",
        }
        helpers.update_app_offering(app_offering_id, new_values, context: 'set Webhook URI Template on App Offering')
      end
    end

    action '01946f7d-f7bd-789b-b718-4db4c8d71764' do
      name 'Client Credentials Token'
      avatar '/assets/icons/person-lock.svg'
      description <<~END_OF_DESCRIPTION
        ## Client Credentials Token (1)
        Outputs the client ID and secret for API access to the customer's Xurrent account.

        Runbooks starting with the `Installation Changed` or `Automation Webhook` triggers can use this action without any further configuration to retrieve the correct credentials.

        When using this action in another context the following 2 fields must be provided:
         - `customer_account_id`: The account ID of the customer’s Xurrent account.
         - `app_reference`: The reference of the app offering.
      END_OF_DESCRIPTION

      input_schema do
        field :customer_account_id, 'Customer Account ID', :string,
              hint: 'The Xurrent account ID of the customer that installed the App. Defaults to the current customer.',
              visibility: 'optional'

        field :app_reference, 'App Reference', :string,
              hint: 'The reference of the App installed by the customer. Defaults to the current App.',
              visibility: 'optional'
      end

      output_schema do
        field :oauth_application_nodeID, 'OAuth Application ID', :string,
              hint: 'The node ID of the related OAuth Application in Xurrent.'

        field :client_id, 'Client ID', :string,
              hint: 'The OAuth client ID.'

        field :client_secret, 'Client Secret', :secret_string,
              hint: 'The OAuth client secret.'
      end

      run do
        customer_account_id = action.input[:customer_account_id] || trigger_output[:customer_account_id]
        app_reference = action.input[:app_reference] || trigger_output[:app_reference]
        [{ output: helpers.customer_client_credentials_token(customer_account_id, app_reference) }]
      end
    end

    action '01947433-41e3-77fb-a340-11c1ec6f2039' do
      name 'Authorization Code Token'
      avatar '/assets/icons/terminal.svg'
      description <<~END_OF_DESCRIPTION
        ## Authorization Code Token (3)
        Outputs the client ID and secret for GUI access to the customer's Xurrent account.

        Runbooks starting with the `Installation Changed` or `Automation Webhook` triggers can use this action without any further configuration to retrieve the correct credentials.

        When using this action in another context the following 2 fields must be provided:
         - `customer_account_id`: The account ID of the customer’s Xurrent account.
         - `app_reference`: The reference of the app offering.
      END_OF_DESCRIPTION

      input_schema do
        field :customer_account_id, 'Customer Account ID', :string,
              hint: 'The Xurrent account ID of the customer that installed the App. Defaults to the current customer.',
              visibility: 'optional'

        field :app_reference, 'App Reference', :string,
              hint: 'The reference of the App installed by the customer. Defaults to the current App.',
              visibility: 'optional'
      end

      output_schema do
        field :oauth_application_nodeID, 'OAuth Application ID', :string,
              hint: 'The node ID of the related OAuth Application in Xurrent.'

        field :client_id, 'Client ID', :string,
              hint: 'The OAuth client ID.'

        field :client_secret, 'Client Secret', :secret_string,
              hint: 'The OAuth client secret.'
      end

      run do
        customer_account_id = action.input[:customer_account_id] || trigger_output[:customer_account_id]
        app_reference = action.input[:app_reference] || trigger_output[:app_reference]
        [{ output: helpers.customer_authorization_code_token(customer_account_id, app_reference) }]
      end
    end

    action '01947437-fec0-70e5-8adf-879234ae7892' do
      name 'Retrieve App Config'
      avatar '/assets/icons/sliders2.svg'
      description <<~END_OF_DESCRIPTION
        ## Retrieve App Config (2)
        Outputs secrets and configuration values provided by the customer in Xurrent. The fields depend on the UI extension for the App offering.

        All fields that need to be retrieved must be added to the `Configuration schema`. Secret values in the UI extension should be defined using the `secret_string`-type.

        Runbooks starting with the `Installation Changed` or `Automation Webhook` triggers can use this action without any further configuration to retrieve the configuration details.

        When using this action in another context the following 2 fields must be provided:
         - `customer_account_id`: The account ID of the customer’s Xurrent account.
         - `app_reference`: The reference of the app offering.
      END_OF_DESCRIPTION

      input_schema do
        field :config_schema, 'Configuration schema', [:schema_field], required: true

        field :customer_account_id, 'Customer Account ID', :string,
              hint: 'The Xurrent account ID of the customer that installed the App. Defaults to the current customer.',
              visibility: 'optional'

        field :app_reference, 'App Reference', :string,
              hint: 'The reference of the App installed by the customer. Defaults to the current App.',
              visibility: 'optional'

        after_update do |_fields|
          regenerate_schema(output_schema.first) if action.input[:config_schema].present?
        end
      end

      output_schema do
        field :config, 'Config', :nested, fields: action.input[:config_schema]

        field :disabled, 'Disabled', :boolean,
              hint: 'Whether or not the App is disabled.'

        field :enabled_by_customer, 'Enabled by customer', :boolean,
              hint: 'Whether or not the App is enabled by the customer.'

        field :suspended, 'Suspended', :boolean,
              hint: 'Whether or not the App is suspended.'

        field :suspension_comment, 'Suspension Comment', :string,
              hint: 'Reason for the App’s suspension.'
      end

      run do
        config = {}

        helpers.retrieve_secrets(config)
        app_instance_data = helpers.retrieve_app_instance_config(config)

        [{ output: { config: config }.merge(app_instance_data) }]
      end

      helper :config_fields do |secret_flag|
        action.input[:config_schema].select do |config_field|
          is_secret = config_field.type.to_s == 'secret_string'
          (secret_flag && is_secret) || (!secret_flag && !is_secret)
        end
      end

      helper :retrieve_secrets do |config|
        secret_fields = helpers.config_fields(true)
        next unless secret_fields.any?

        secrets = helpers.read_customer_secrets

        secret_fields.select { |secret_field| secret_field.required && !secrets.key?(secret_field.id) }
                     .map(&:id)
                     .tap do |missing_fields|
          # secret-changed-webhook not processed yet, backoff for a while
          backoff("Required secrets not available yet: #{missing_fields.join(', ')}") if missing_fields.any?
        end

        secret_fields.each do |secret_field|
          secret_value = secrets[secret_field.id]
          config[secret_field.id] = new_secret_string(secret_value) if secret_value.present?
        end
      end

      helper :retrieve_app_instance_config do |config|
        fields = helpers.config_fields(false)
        app_instance_data = helpers.query_app_instance_custom_fields

        status_fields = {
          disabled: app_instance_data[:disabled],
          enabled_by_customer: app_instance_data[:enabled_by_customer],
          suspended: app_instance_data[:suspended],
          suspension_comment: app_instance_data[:suspension_comment],
        }

        next status_fields if fields.empty?

        custom_fields = (app_instance_data[:custom_fields] || []).index_by { |cf| cf['id'] }

        fields.select { |field| field.required && !custom_fields[field.id.to_s] }
              .map { |field| field.id.to_s }
              .tap do |missing_fields|
          # instance-create/update webhook not processed yet, backoff for a while
          backoff("Required fields not available yet: #{missing_fields.join(', ')}") if missing_fields.any?
        end

        fields.each do |field|
          config[field.id] = custom_fields.dig(field.id.to_s, 'value')
        end

        status_fields
      end

      helper :query_app_instance_custom_fields do
        customer_account_id = action.input[:customer_account_id] || trigger_output[:customer_account_id]
        app_reference = action.input[:app_reference] || trigger_output[:app_reference]
        variables = {
          appReference: app_reference,
          customerAccountId: customer_account_id,
        }
        ctx = 'query App Instance custom fields'
        response = helpers.provider_graphql(<<~END_OF_GRAPHQL, variables: variables, context: ctx)
          query($appReference: String!, $customerAccountId: String!) {
            appInstances(first: 1, filter: {
              appOfferingReference: { values: [$appReference] },
              customerAccount: { values: [$customerAccountId] }
            }) {
              nodes {
                customFields { id value }
                disabled
                enabledByCustomer
                suspended
                suspensionComment
              }
            }
          }
        END_OF_GRAPHQL
        nodes = response.dig('appInstances', 'nodes') || []
        node = nodes.first || {}
        {
          custom_fields: node['customFields'] || [],
          disabled: node['disabled'],
          enabled_by_customer: node['enabledByCustomer'],
          suspended: node['suspended'],
          suspension_comment: node['suspensionComment'],
        }
      end
    end

    action '0197a1a0-118f-7374-b2d9-9ef2ecbead4c' do
      name 'Update App Config'
      avatar '/assets/icons/sliders2.svg'
      description <<~END_OF_DESCRIPTION
        ## Update App Config (4)
        Update the configuration values visible to the customer in Xurrent. The available fields depend on the UI extension related to the App offering.

        Next to the custom fields it is also possible to update the disabled status of the App instance or to suspend the integration with a specific comment.

        Runbooks starting with the `Installation Changed` or `Automation Webhook` triggers can use this action without any further configuration to update the configuration details.

        When using this action in another context the following 2 fields must be provided:
         - `customer_account_id`: The account ID of the customer’s Xurrent account.
         - `app_reference`: The reference of the app offering.
      END_OF_DESCRIPTION

      input_schema do
        field :custom_fields, 'Custom fields', :nested, array: true do
          field :id, 'ID', :string, required: true
          field :value, 'Value', :string
        end

        field :disabled, 'Disabled', :boolean, visibility: 'optional'

        field :suspension, 'Suspension', :nested, visibility: 'optional' do
          field :suspended, 'Suspended', :boolean, required: true
          field :comment, 'Suspension Comment', :string, required: true
        end

        field :customer_account_id, 'Customer Account ID', :string,
              hint: 'The Xurrent account ID of the customer that installed the App. Defaults to the current customer.',
              visibility: 'optional'

        field :app_reference, 'App Reference', :string,
              hint: 'The reference of the App installed by the customer. Defaults to the current App.',
              visibility: 'optional'
      end

      output_schema do
        field :app_instance_id, 'App Instance ID', :string
      end

      run do
        app_instance_id = helpers.query_app_instance_id

        variables = helpers.app_instance_update_variables
        helpers.update_app_instance_config(app_instance_id, variables)

        [{ output: { app_instance_id: app_instance_id } }]
      end

      helper :app_instance_update_variables do
        variables = {
          customFields: action.input[:custom_fields] || [],
        }

        variables['disabled'] = action.input[:disabled] if action.input.key?(:disabled)

        suspension = action.input[:suspension]
        if suspension.present?
          variables['suspended'] = suspension[:suspended]
          variables['suspensionComment'] = suspension[:comment]
        end

        variables
      end

      helper :query_app_instance_id do
        customer_account_id = action.input[:customer_account_id] || trigger_output[:customer_account_id]
        app_reference = action.input[:app_reference] || trigger_output[:app_reference]
        variables = {
          appReference: app_reference,
          customerAccountId: customer_account_id,
        }
        response = helpers.provider_graphql(<<~END_OF_GRAPHQL, variables: variables, context: 'query App Instance')
          query($appReference: String!, $customerAccountId: String!) {
            appInstances(first: 1, filter: {
              appOfferingReference: { values: [$appReference] },
              customerAccount: { values: [$customerAccountId] }
            }) {
              nodes {
                id
              }
            }
          }
        END_OF_GRAPHQL
        node = response.dig('appInstances', 'nodes').first || {}
        app_instance_id = node['id']
        if app_instance_id.blank?
          fail_job!('App instance %<app_reference>s not found for customer %<customer_account_id>s',
                    { app_reference: app_reference, customer_account_id: customer_account_id })
        end
        app_instance_id
      end

      helper :update_app_instance_config do |app_instance_id, variables|
        next false unless app_instance_id
        input = { input: variables.merge(id: app_instance_id) }
        helpers.provider_graphql(<<~END_OF_GRAPHQL, variables: input, context: 'update App Instance configuration')
          mutation($input: AppInstanceUpdateInput!) {
            appInstanceUpdate(
              input: $input
            ) {
              appInstance { id }
              errors {
                path
                message
              }
            }
          }
        END_OF_GRAPHQL
      end
    end

    action '6dd92b76-9519-4f8f-b076-ceae9c429050' do
      name 'Async URLs'
      description 'Poll multiple URLs and return data when available. ' \
                  'This action will check each URL and return the first one ' \
                  'that has data available. Subsequent iterations will poll remaining URLs until ' \
                  'all URLs have been processed.'
      avatar '/assets/icons/x-logo-graphql.svg'
      nested true

      input_schema do
        field :urls,
              'URLs',
              :string,
              array: true,
              hint: 'Array of URLs to poll for data. Each URL will be checked in sequence.',
              default: [],
              required: false
        field :backoff_time,
              'Backoff Time',
              :integer,
              hint: 'Time after which the job will be rescheduled',
              default: 1.minute
        field :max_iterations,
              'Max Iterations',
              :integer,
              hint: 'Maximum number of times the job can be rescheduled',
              default: 1000
      end

      output_schema 'result' do
        name 'URL Result'
        field :url,
              'URL',
              :string,
              required: true
        field :body,
              'Response Body',
              :hash,
              required: true,
              hint: 'Parsed JSON response from the URL'
      end

      iteration_state_schema do
        field :index_to_skip,
              'Index to skip',
              :integer,
              array: true,
              hint: 'Array of indices for URLs that have already been processed'
        field :iteration_count,
              'Iteration Count',
              :integer,
              hint: 'Number of times this action has been executed without finding'
      end

      run do
        urls = input[:urls]

        iteration_state = self.iteration_state_value || {}
        iteration_count = iteration_state[:iteration_count] || 0
        index_to_skip = iteration_state[:index_to_skip] || []

        max_iterations = input[:max_iterations]
        if iteration_count >= max_iterations
          fail_job!("Maximum iterations (#{max_iterations}) reached without finding data")
        end

        iteration_count += 1
        self.iteration_state_value = { iteration_count: iteration_count, index_to_skip: index_to_skip } if urls.present?

        return_value = nil
        urls.each_with_index do |url, index|
          next if index_to_skip.include?(index)

          response = http_get(url)
          backoff_if_needed(response, api_name: 'Xurrent')
          fail_job!("HTTP Error #{response.status}: '#{response.body}' for URL: '#{url}'") unless response.status == 200

          next unless response.body.present?

          begin
            body = JSON.parse(response.body)
          rescue JSON::ParserError => e
            fail_job!("JSON Parser Error for URL '#{url}': #{e.message}. Response body: '#{response.body}'")
          end

          next unless body.present?

          index_to_skip << index

          return_value = [{
            schema_reference: 'result',
            output: { url: url, body: body },
          }]

          break
        end

        if return_value.present?
          self.iteration_state_value = if index_to_skip.size == urls.size
                                         nil
                                       else
                                         {
                                           iteration_count: iteration_count - 1,
                                           index_to_skip: index_to_skip,
                                         }
                                       end
        elsif urls.present?
          backoff('Data not available yet', retry_after: input[:backoff_time])
        end

        return_value
      end
    end

    ##################################################################################
    # Top level helpers to query the Xurrent provider account using GraphQL

    helper :update_app_offering do |app_offering_id, new_values, context: 'update App Offering'|
      variables = {
        input: {
          id: app_offering_id,
        }.merge(new_values),
      }

      helpers.provider_graphql(<<~END_OF_GRAPHQL, variables: variables, context: context)
        mutation($input: AppOfferingUpdateInput!) {
          appOfferingUpdate(input: $input) {
            appOffering { id }
            errors {
              path
              message
            }
          }
        }
      END_OF_GRAPHQL
    end

    helper :provider_graphql do |query, variables: nil, fail_not_found: true, context: nil|
      graphql_error = ->(detail) { context ? "Unable to #{context}: #{detail}" : detail }

      request_body = { query: query.gsub(/\s+/, ' ').strip }
      request_body[:variables] = variables if variables.present?
      response = http_post(helpers.graphql_uri, request_body.to_json, { 'content-type' => 'application/json' })
      backoff_if_needed(response, api_name: 'Xurrent')

      next false if !fail_not_found && response.status == 404

      if response.status != 200
        fail_job!(graphql_error.call("HTTP error from Xurrent GraphQL API: #{response.status} '#{response.body}'"))
      end

      body = JSON.parse(response.body)
      if body['errors'].present?
        next false if !fail_not_found && body['errors'].all? { |e| e['message'] == 'Not Found' }

        fail_job!(graphql_error.call(body['errors'].map { |e| e['message'] }.join('; ')))
      end

      data = body['data']
      fail_job!(graphql_error.call('No data from Xurrent GraphQL API')) if data.blank?

      if data.size == 1
        nested = data.first.last
        fail_job!(graphql_error.call(nested['errors'].map { |e| e['message'] }.join('; '))) if nested['errors'].present?
      end

      data
    end

    helper :xurrent_domain do
      env = outbound_connection.config[:environment] || {}
      stage = env[:stage].presence || environment[:xurrent_ipaas_stage]
      region = env[:region].presence || environment[:xurrent_ipaas_region]
      stage_domain = case stage
                     when 'Demo' then 'xurrent-demo.com'
                     when 'QA' then 'xurrent.qa'
                     else 'xurrent.com'
                     end
      if stage != 'Demo' && region.present?
        "#{region}.#{stage_domain}"
      else
        stage_domain
      end
    end

    ENDPOINT_DEFAULTS = {
      oauth: { config_key: :oauth2_endpoint, system_var: :xurrent_ipaas_oauth_endpoint,
               subdomain: 'oauth', suffix: '/token', }.freeze,
      graphql: { config_key: :graphql_endpoint, system_var: :xurrent_ipaas_graphql_endpoint,
                 subdomain: 'graphql', suffix: '', }.freeze,
      rest: { config_key: :rest_endpoint, system_var: :xurrent_ipaas_rest_endpoint,
              subdomain: 'api', suffix: '', }.freeze,
    }.freeze

    helper :endpoint_for do |kind|
      spec = ENDPOINT_DEFAULTS.fetch(kind)
      env = outbound_connection.config[:environment] || {}
      configured = env[spec[:config_key]].presence
      next configured if configured

      derived = "https://#{spec[:subdomain]}.#{helpers.xurrent_domain}#{spec[:suffix]}"
      env[:stage].present? ? derived : (environment[spec[:system_var]] || derived)
    end

    helper :oauth_endpoint do
      helpers.endpoint_for(:oauth)
    end

    helper :graphql_uri do
      URI.parse(helpers.endpoint_for(:graphql))
    end

    helper :rest_uri do
      URI.parse(helpers.endpoint_for(:rest))
    end

    helper :system_account_id do
      environment[:xurrent_ipaas_account_id]
    end

    ##################################################################################
    # Top level helpers for inbound webhook processing

    helper :extract_webhook_body do |request, policy_config|
      fail_job!('Webhook policy not configured') if policy_config.nil?

      parsed_body = begin
        JSON.parse(request.body.read)
      rescue JSON::ParserError
        fail_job!('Unable to parse incoming request')
      end

      jwt = parsed_body['jwt'].presence || fail_job!('Request does not contain jwt property')
      decoded_token = begin
        decode_jwt!(jwt, algorithm: policy_config[:algorithm], pem: policy_config[:public_key_pem],
                         issuer: policy_config[:issuer], audience: policy_config[:audience])
      rescue IPaaS::Error => e
        fail_job!("Unable to validate request: #{e}")
      end

      decoded_token[:payload]['data'].with_indifferent_access
    end

    helper :webhook_verification? do |payload|
      payload&.dig('event') == 'webhook.verify'
    end

    helper :handle_webhook_verification do |payload|
      if payload.dig('payload', 'callback').present?
        webhook_description = "#{payload['name']} (#{payload['webhook_nodeID']})"
        log("Verifying webhook #{webhook_description}")
        response = http_get(payload['payload']['callback'], skip_authentication: true)
        if response.status == 200
          discard_trigger_event!("Webhook verification handled automatically: #{webhook_description}")
        else
          fail_job!("Unable to verify webhook #{webhook_description}.\n#{response.status}: #{response.body}")
        end
      end
    end

    helper :webhook_response_with_verification do |context, response|
      error = context[:error]
      if error.present? && error.is_a?(IPaaS::Job::DiscardTriggerEvent)
        response[:status] = 200
        response[:body] = error.message
      end

      response
    end

    helper :issuer do |customer_account_id|
      "https://#{customer_account_id}.#{helpers.xurrent_domain}"
    end

    helper :finish_trigger_output do |config, request, webhook_body, base_output|
      webhook_output = helpers.extract_received_webhook_details(request.headers, webhook_body)
      base_output.merge(webhook: webhook_output)
                 .tap do |trigger_output|
        if config[:discard_filter].present?
          discard = ruby_eval(config[:discard_filter], trigger_output)&.dig(:discard)
          discard_trigger_event!('No job created based on discard filter') if discard == true
        end
      end
    end

    helper :extract_received_webhook_details do |headers, webhook_body|
      delivery = headers['x-xurrent-delivery']
      delivery_origin = headers['x-xurrent-delivery-origin']

      {
        event: webhook_body[:event],
        delivery: delivery,
        delivery_origin: delivery_origin,
        person: {
          id: webhook_body[:person_id],
          nodeID: webhook_body[:person_nodeID],
          name: webhook_body[:person_name],
        },
      }.tap do |hash|
        hash.delete(:delivery_origin) if delivery_origin.blank?
      end
    end

    helper :store_job_context_identifier do |customer_account_id, app_reference|
      next unless customer_account_id.present?

      id = if app_reference.present?
             "#{app_reference}@#{customer_account_id}"
           else
             customer_account_id
           end
      self.job_context_identifier = id
    end

    ##################################################################################
    # Top level helpers for managing provider data

    helper :enable_or_create_provider_webhook_policy do
      helpers.toggle_webhook_policy(helpers.provider_webhook_policy&.[](:id), true) ||
        helpers.create_provider_webhook_policy
    end

    helper :toggle_webhook_policy do |webhook_policy_id, flag|
      next false unless webhook_policy_id

      ctx = "#{flag ? 'enable' : 'disable'} Webhook Policy"
      vars = { id: webhook_policy_id }
      helpers.provider_graphql(<<~END_OF_GRAPHQL, variables: vars, fail_not_found: false, context: ctx)
        mutation($id: ID!) {
          webhookPolicyUpdate(
            input: {
              id: $id,
              disabled: #{flag ? 'false' : 'true'}
            }
          ) {
            webhookPolicy { id }
            errors {
              path
              message
            }
          }
        }
      END_OF_GRAPHQL
    end

    helper :create_provider_webhook_policy do
      response = helpers.provider_graphql(<<~END_OF_GRAPHQL, context: 'create Webhook Policy')
        mutation {
          webhookPolicyCreate(
            input: {
              jwtAlg: "es256"
            }
          ) {
            errors {
              path
              message
            }
            webhookPolicy {
              id
              jwtAlg
              jwtAudience
              publicKeyPem
              account { url }
            }
          }
        }
      END_OF_GRAPHQL
      policy = response.dig('webhookPolicyCreate', 'webhookPolicy')
      helpers.write_webhook_policy('provider_webhook_policy',
                                   policy['id'],
                                   policy['jwtAlg'],
                                   policy['publicKeyPem'],
                                   policy.dig('account', 'url'),
                                   policy['jwtAudience'])
    end

    helper :provider_webhook_policy do
      helpers.read_webhook_policy('provider_webhook_policy')
    end

    # rubocop:disable Metrics/ParameterLists
    helper :write_webhook_policy do |key, id, algorithm, public_key_pem, issuer, audience|
      policy = {
        id: id,
        algorithm: algorithm.upcase,
        public_key_pem: public_key_pem,
        issuer: issuer,
        audience: audience,
      }
      outbound_connection.store.write(key, policy.to_json)
    end
    # rubocop:enable Metrics/ParameterLists

    helper :parse_json_hash do |json|
      JSON.parse(json).with_indifferent_access if json
    end

    helper :read_webhook_policy do |key|
      helpers.parse_json_hash(outbound_connection.store.read(key))
    end

    helper :toggle_webhook do |webhook_id, flag, event, references|
      variables = {
        id: webhook_id,
        event: event,
        references: references,
      }
      ctx = "#{flag ? 'enable' : 'disable'} Webhook"
      helpers.provider_graphql(<<~END_OF_GRAPHQL, variables: variables, fail_not_found: false, context: ctx)
        mutation($id: ID!, $event: WebhookEvent!, $references: [String!]) {
          webhookUpdate(
            input: {
              id: $id,
              disabled: #{flag ? 'false' : 'true'},
              event: $event,
              appOfferingReferences: $references
            }
          ) {
            webhook { id }
            errors {
              path
              message
            }
          }
        }
      END_OF_GRAPHQL
    end

    helper :create_provider_webhook do |event:, app_reference:, endpoint:, name: event, runbook_uuid: nil|
      app_references = if app_reference.blank?
                         []
                       else
                         Array(app_reference)
                       end
      webhook_name = "iPaaS - #{name}"
      webhook_name << " [#{app_references.join(', ')}]" if app_references.present?
      webhook_name << " - #{runbook_uuid}" if runbook_uuid.present?

      variables = {
        event: event,
        uri: endpoint,
        name: webhook_name,
        policyId: helpers.provider_webhook_policy[:id],
        references: app_references,
        description: "DO NOT DELETE!\n\nUsed by iPaaS.",
      }
      ctx = "create Webhook '#{webhook_name}'"
      response = helpers.provider_graphql(<<~END_OF_GRAPHQL, variables: variables, context: ctx)
        mutation($event: WebhookEvent!, $uri: String!, $name: String!, $description: String!, $policyId: ID!, $references: [String!]) {
          webhookCreate(
            input: {
              event: $event,
              uri: $uri,
              name: $name,
              description: $description,
              webhookPolicyId: $policyId,
              appOfferingReferences: $references
            }
          ) {
            errors {
              path
              message
            }
            webhook {
              id
            }
          }
        }
      END_OF_GRAPHQL
      response&.dig('webhookCreate', 'webhook', 'id')
    end

    ##################################################################################
    # Top level helpers for managing customer data

    helper :customer_webhook_policy do |customer_account_id, app_reference|
      helpers.read_webhook_policy(helpers.customer_webhook_policy_key(customer_account_id, app_reference))
    end

    helper :customer_webhook_policy_key do |customer_account_id, app_reference|
      "customer_webhook_policy/#{customer_account_id}/#{app_reference}"
    end

    helper :write_oauth_token do |key, id, client_id, client_secret|
      oath_token = {
        oauth_application_nodeID: id,
        client_id: client_id,
        client_secret: make_secret_string(client_secret),
      }
      outbound_connection.store.write(key, oath_token.to_json)
    end

    helper :read_oauth_token do |key|
      token = helpers.parse_json_hash(outbound_connection.store.read(key))
      token['client_secret'] = new_secret_string(token['client_secret']) if token
      token
    end

    helper :customer_client_credentials_token do |customer_account_id, app_reference|
      helpers.read_oauth_token(helpers.customer_client_credentials_token_key(customer_account_id, app_reference))
    end

    helper :customer_client_credentials_token_key do |customer_account_id, app_reference|
      "customer_client_credentials_token/#{customer_account_id}/#{app_reference}"
    end

    helper :customer_authorization_code_token do |customer_account_id, app_reference|
      helpers.read_oauth_token(helpers.customer_authorization_code_token_key(customer_account_id, app_reference))
    end

    helper :customer_authorization_code_token_key do |customer_account_id, app_reference|
      "customer_authorization_code_token/#{customer_account_id}/#{app_reference}"
    end

    helper :customer_secrets_key do |customer_account_id, app_reference|
      "customer_secrets/#{customer_account_id}/#{app_reference}"
    end

    helper :read_customer_secrets do |customer_account_id, app_reference|
      customer_account_id ||= action&.input&.[](:customer_account_id) || trigger_output[:customer_account_id]
      app_reference ||= action&.input&.[](:app_reference) || trigger_output[:app_reference]
      secrets_json = outbound_connection.store.read(helpers.customer_secrets_key(customer_account_id, app_reference))
      helpers.parse_json_hash(secrets_json) || {}
    end

    ##################################################################################
    # Blueprint helpers for managing app offerings

    helper :extract_app_offering do
      app_offering = helpers.find_app_offering
      fail_job!("Unable to find App Offering with reference '#{trigger.config[:app_reference]}'.") unless app_offering

      helpers.include_avatar(app_offering)
      helpers.extract_inline_images(app_offering)
      helpers.extract_ui_extension(app_offering)
      helpers.extract_automation_rules(app_offering)

      app_offering.delete('id')
      app_offering['newScopes'] = app_offering.delete('scopes') if app_offering['scopes'].present?
      app_offering['newScopes']&.each { |new_scope| new_scope.delete('id') }
      app_offering['source'] = 'Xurrent App Connector'
      app_offering['sourceID'] = trigger.runbook.uuid
      app_offering['webhookUriTemplate'] = 'https://test.com' if app_offering['webhookUriTemplate'].present?
      helpers.write_blueprint_json('app_offering', app_offering)
    end

    helper :extract_inline_images do |app_offering|
      all_attachments = []
      all_attachments += app_offering.dig('featuresAttachments', 'nodes') || []
      all_attachments += app_offering.dig('descriptionAttachments', 'nodes') || []

      inline_images = all_attachments.each_with_object({}) do |attachment, hash|
        next unless attachment['key'] && attachment['expiringUrl']

        file_name, image = helpers.download_avatar(attachment['expiringUrl'])
        hash[attachment['key']] = {
          file_name: file_name,
          data: Base64.encode64(image),
          inline: attachment['inline'],
        }
      end

      app_offering['inline_images'] = inline_images
      app_offering.delete('featuresAttachments')
      app_offering.delete('descriptionAttachments')
    end

    helper :find_app_offering do |id_only: false|
      variables = {
        reference: trigger.config[:app_reference],
        published: false,
      }
      fields = id_only ? 'id' : APP_OFFERING_FIELDS
      ctx = "find App Offering with reference '#{trigger.config[:app_reference]}'"
      response = helpers.provider_graphql(<<~END_OF_GRAPHQL, variables: variables, context: ctx)
        query($reference: String, $published: Boolean) {
          appOfferings(first: 1, filter: { published: $published, reference: { values: [$reference] } } ) {
            nodes {
              #{fields}
            }
          }
        }
      END_OF_GRAPHQL
      response&.dig('appOfferings', 'nodes')&.first
    end

    helper :apply_app_offering do
      app_offering_input = helpers.read_blueprint_json('app_offering')
      next unless app_offering_input

      app_offering = helpers.find_app_offering
      helpers.remove_default_webhook_template(app_offering_input, app_offering)
      helpers.upload_inline_images(app_offering_input)
      helpers.app_offering_input_picture_uri(app_offering_input)
      helpers.app_offering_input_service_instance(app_offering_input)
      helpers.app_offering_input_scopes(app_offering, app_offering_input)
      app_offering_input.merge!(helpers.apply_ui_extension(app_offering))

      if app_offering
        helpers.update_app_offering(app_offering['id'], app_offering_input)
        app_offering_input['id'] = app_offering['id']
      else
        app_offering = helpers.insert_app_offering(app_offering_input)
      end

      helpers.apply_automation_rules(app_offering)
      app_offering
    end

    helper :fetch_upload_details do
      details = helpers.provider_graphql(<<~GRAPHQL, context: 'fetch attachment upload details')
        query {
          attachmentStorage {
            sizeLimit
            allowedExtensions
            uploadUri
            provider
            providerParameters
          }
        }
      GRAPHQL

      upload_uri = details.dig('attachmentStorage', 'uploadUri')
      upload_params = details.dig('attachmentStorage', 'providerParameters') || {}
      [upload_uri, upload_params.transform_values(&:to_s)]
    end

    helper :upload_image do |image|
      file_name = image['file_name']
      data = Base64.decode64(image['data'])
      content_type = helpers.determine_content_type(file_name)

      upload_uri, upload_params_base = helpers.fetch_upload_details
      upload_params = upload_params_base.merge(
        'Content-Type' => content_type,
        'file' => IPaaS::Job::Outbound::HTTP.create_binary_part(file_name, content_type, data)
      )

      response = multipart_post(upload_uri, upload_params, { 'Authorization' => '' })

      fail_job!("Rate limit hit on image upload. '#{response.body}'") if response.status == 429
      fail_job!("Xurrent server not available. '#{response.body}'") if response.status == 503

      new_key = begin
        JSON.parse(response.body)['key']
      rescue JSON::ParserError
        response.body[%r{<Key>(.*?)</Key>}m, 1]
      end

      unless [200, 201].include?(response.status) && new_key.present?
        fail_job!("Unable to upload image: #{response.status} '#{response.body}'")
      end

      { key: new_key, inline: image['inline'] }
    end

    helper :process_markdown_attachments do |content, image_keys|
      attachments = []

      updated_content = content.gsub(INLINE_MEDIA_REGEX) do |match|
        name, path, attributes = Regexp.last_match.captures
        next match unless path.start_with?('attachments/') && image_keys.key?(path)

        new_path = image_keys[path]
        next match unless new_path && new_path[:key]

        attachments << new_path
        markdown = "![#{name}](#{new_path[:key]})"
        markdown += "{:#{attributes}}" if attributes.present?
        markdown
      end

      [updated_content, attachments]
    end

    helper :upload_inline_images do |app_offering_input|
      inline_images = app_offering_input.delete('inline_images') || {}
      image_keys = inline_images.transform_values do |image|
        helpers.upload_image(image)
      end

      %w[description features].each do |field|
        content = app_offering_input[field]
        next unless content

        updated_content, attachments = helpers.process_markdown_attachments(content, image_keys)
        app_offering_input[field] = updated_content

        app_offering_input["#{field}Attachments"] = attachments
      end
    end

    helper :app_offering_input_picture_uri do |app_offering_input|
      avatar_params = helpers.delete_avatar_params(app_offering_input)
      app_offering_input['pictureUri'] = helpers.avatar_to_picture_uri(avatar_params)
    end

    helper :app_offering_input_service_instance do |app_offering_input|
      service_instance = app_offering_input.delete('serviceInstance')
      app_offering_input['serviceInstanceId'] = helpers.app_offering_si_id(service_instance['name'])
    end

    helper :app_offering_input_scopes do |app_offering, app_offering_input|
      current_scopes = app_offering&.[]('scopes')
      next unless current_scopes

      new_scopes = app_offering_input['newScopes'] || []
      max_length = [current_scopes.length, new_scopes.length].max
      # reuse existing scope IDs, and delete excess scope IDs
      current_scopes.fill(nil, current_scopes.length...max_length).zip(new_scopes) do |current, new_scope|
        if new_scope
          new_scope['id'] = current&.dig('id')
        else
          app_offering_input['scopesToDelete'] ||= []
          app_offering_input['scopesToDelete'] << current['id']
        end
      end
    end

    helper :app_offering_si_id do |service_instance_name|
      variables = {
        name: service_instance_name,
      }
      ctx = "find Service Instance '#{service_instance_name}'"
      response = helpers.provider_graphql(<<~END_OF_GRAPHQL, variables: variables, context: ctx)
        query($name: String!) {
          serviceInstances(first: 1, filter: {
            name: { values: [$name] },
          }) {
            nodes {
              id
            }
          }
        }
      END_OF_GRAPHQL
      nodes = response.dig('serviceInstances', 'nodes') || []
      fail_job!("Unable to find Service Instance with name '#{service_instance_name}'.") if nodes.empty?
      nodes.first&.[]('id')
    end

    helper :insert_app_offering do |app_offering_input|
      variables = {
        input: app_offering_input,
      }
      name = app_offering_input['name']
      ctx = "create App Offering#{" '#{name}'" if name}"
      response = helpers.provider_graphql(<<~END_OF_GRAPHQL, variables: variables, context: ctx)
        mutation($input: AppOfferingCreateInput!) {
          appOfferingCreate(input: $input) {
            errors {
              path
              message
            }
            appOffering {
              #{APP_OFFERING_FIELDS}
            }
          }
        }
      END_OF_GRAPHQL
      response.dig('appOfferingCreate', 'appOffering')
    end

    helper :write_blueprint_json do |basename, content|
      blueprint_store.write("#{basename}.json", JSON.pretty_generate(content, indent: '  '))
    end

    helper :read_blueprint_json do |basename|
      content = blueprint_store.read("#{basename}.json")
      content.present? ? JSON.parse(content) : nil
    end

    ##################################################################################
    # Blueprint helpers for managing app offering - Webhook Template Uri

    helper :remove_default_webhook_template do |app_offering_input, app_offering|
      # do not overwrite existing webhook template with default from blueprint
      next unless app_offering&.dig('webhookUriTemplate').present?

      app_offering_input.delete('webhookUriTemplate') if app_offering_input['webhookUriTemplate'] == 'https://test.com'
    end

    ##################################################################################
    # Blueprint helpers for managing app offering - App Offering Avatar

    helper :include_avatar do |app_offering|
      picture_uri = app_offering.delete('pictureUri')
      next if picture_uri.blank?

      avatar_file_name, image = helpers.download_avatar(picture_uri)
      app_offering[:avatar_file_name] = avatar_file_name
      app_offering[:avatar] = Base64.encode64(image)
      app_offering
    end

    helper :download_avatar do |avatar_uri|
      uri = URI.parse(avatar_uri)
      file_name = uri.path.split('/').last
      response = http_get(avatar_uri, skip_authentication: true) do |request|
        request.headers.delete('X-Xurrent-Account')
      end

      # TODO: fail_enable! instead of fail_job! or something similar?
      fail_job!("Rate limit hit. '#{response.body}'") if response.status == 429
      fail_job!("Avatar server not available. '#{response.body}'") if response.status == 503

      next false if response.status == 404

      fail_job!("Unable to download avatar: #{response.status} '#{response.body}'") if response.status != 200

      [file_name, response.body]
    end

    helper :delete_avatar_params do |app_offering_input|
      avatar = app_offering_input.delete('avatar')
      file_name = app_offering_input.delete('avatar_file_name')
      next [] if avatar.blank? || file_name.blank?

      [file_name, avatar]
    end

    helper :avatar_to_picture_uri do |avatar_params|
      next if avatar_params.blank?

      file_name, avatar = avatar_params
      content_type = helpers.determine_content_type(file_name)
      "data:#{content_type};base64,#{avatar.delete("\n")}"
    end

    helper :determine_content_type do |file_name|
      extension = file_name.split('.').last.downcase
      if extension == 'jpg'
        'image/jpeg'
      elsif extension == 'svg'
        'image/svg+xml'
      else
        "image/#{extension}"
      end
    end

    ##################################################################################
    # Blueprint helpers for managing app offering - UI extension

    helper :extract_ui_extension do |app_offering|
      ui_extension_version = app_offering.delete('uiExtensionVersion')
      next if ui_extension_version.blank?

      ui_extension = ui_extension_version['uiExtension']
      ui_extension.delete('id')
      keys = %w[css html javascript formDefinition]
      ui_extension.merge!(ui_extension_version.slice(*keys))
      ui_extension.delete('formDefinition') if ui_extension['formDefinition'].blank?
      ui_extension['activate'] = true
      ui_extension['source'] = 'Xurrent App Connector'
      ui_extension['sourceID'] = trigger.runbook.uuid
      helpers.write_blueprint_json('app_offering_ui_extension', ui_extension)
    end

    helper :apply_ui_extension do |app_offering|
      ui_extension_input = helpers.read_blueprint_json('app_offering_ui_extension')
      next {} unless ui_extension_input

      ui_extension_id = app_offering&.dig('uiExtensionVersion', 'uiExtension', 'id')
      ui_extension_id ||= helpers.find_ui_extension_id_by_source(ui_extension_input)
      if ui_extension_id
        ui_extension_input['id'] = ui_extension_id
        ui_extension_input.delete('category')
        helpers.upsert_ui_extension(ui_extension_input, 'UiExtensionUpdateInput', 'uiExtensionUpdate')
      else
        helpers.upsert_ui_extension(ui_extension_input, 'UiExtensionCreateInput', 'uiExtensionCreate')
      end
    end

    helper :find_ui_extension_id_by_source do |ui_extension_input|
      variables = {
        source: ui_extension_input['source'],
        sourceID: ui_extension_input['sourceID'],
      }
      response = helpers.provider_graphql(<<~END_OF_GRAPHQL, variables: variables, context: 'find UI Extension')
        query($source: String!, $sourceID: String!) {
          uiExtensions(first: 1, filter: { source: { values: [$source] }, sourceID: { values: [$sourceID] } }) {
            nodes {
              id
            }
          }
        }
      END_OF_GRAPHQL
      nodes = response.dig('uiExtensions', 'nodes') || []
      nodes.pick('id')
    end

    helper :upsert_ui_extension do |ui_extension_input, input_type, operation|
      variables = {
        input: ui_extension_input,
      }
      verb = operation.include?('Create') ? 'create' : 'update'
      name = ui_extension_input['name']
      ctx = "#{verb} UI Extension#{" '#{name}'" if name}"
      response = helpers.provider_graphql(<<~END_OF_GRAPHQL, variables: variables, context: ctx)
        mutation($input: #{input_type}!) {
          #{operation}(input: $input) {
            errors {
              path
              message
            }
            uiExtension {
              id
              activeVersion { id }
            }
          }
        }
      END_OF_GRAPHQL
      ui_extension = response.dig(operation, 'uiExtension')
      {
        uiExtensionId: ui_extension['id'],
        uiExtensionVersionId: ui_extension.dig('activeVersion', 'id'),
      }.with_indifferent_access
    end

    ##################################################################################
    # Blueprint helpers for managing app offering - Automation Rules

    helper :extract_automation_rules do |app_offering|
      next if app_offering['automationRules'].blank?

      automation_rules = app_offering.dig('automationRules', 'nodes')
      app_offering.delete('automationRules')
      automation_rules.each { |automation_rule| automation_rule.delete('id') }
      helpers.write_blueprint_json('app_offering_automation_rules', automation_rules)
    end

    helper :apply_automation_rules do |app_offering|
      new_rule_inputs = helpers.read_blueprint_json('app_offering_automation_rules')
      next unless new_rule_inputs

      existing_rules = app_offering.dig('automationRules', 'nodes')

      grouped = helpers.group_offering_automation_rules(existing_rules, new_rule_inputs)
      grouped.flat_map do |_, (existing_group_rules, new_group_rule_inputs)|
        helpers.sync_offering_automation_rule_group(
          existing_group_rules,
          new_group_rule_inputs,
          app_offering['id']
        )
      end
    end

    helper :sync_offering_automation_rule_group do |existing_rules, new_rule_inputs, app_offering_id|
      existing_rules.each_with_index do |existing_rule, index|
        rule_id = existing_rule['id']
        if new_rule_inputs[index]
          helpers.upsert_offering_automation_rule(rule_id, new_rule_inputs[index])
        else
          helpers.delete_offering_automation_rule(rule_id)
        end
      end

      (existing_rules.size...new_rule_inputs.size).each do |index|
        new_rule_inputs[index]['appOfferingId'] = app_offering_id
        helpers.create_offering_automation_rule(new_rule_inputs[index])
      end
    end

    helper :upsert_offering_automation_rule do |rule_id, automation_rule_input|
      if rule_id.nil?
        helpers.create_offering_automation_rule(automation_rule_input)
      else
        update_input = automation_rule_input.merge('id' => rule_id).except('appOfferingId')
        helpers.update_offering_automation_rule(update_input)
      end
    end

    helper :create_offering_automation_rule do |automation_rule_input|
      helpers.automation_rule_mutation(
        automation_rule_input,
        'AppOfferingAutomationRuleCreateInput',
        'appOfferingAutomationRuleCreate'
      )
    end

    helper :update_offering_automation_rule do |automation_rule_input|
      helpers.automation_rule_mutation(
        automation_rule_input,
        'AppOfferingAutomationRuleUpdateInput',
        'appOfferingAutomationRuleUpdate'
      )
    end

    helper :delete_offering_automation_rule do |automation_rule_input_id|
      helpers.automation_rule_mutation(
        { id: automation_rule_input_id },
        'AppOfferingAutomationRuleDeleteMutationInput',
        'appOfferingAutomationRuleDelete'
      )
    end

    helper :automation_rule_mutation do |mutation_input, input_type, operation|
      variables = {
        input: mutation_input,
      }
      verb = if operation.include?('Create')
               'create'
             elsif operation.include?('Update')
               'update'
             else
               'delete'
             end
      name = mutation_input['name'] || mutation_input[:name]
      ctx = "#{verb} Automation Rule#{" '#{name}'" if name}"
      helpers.provider_graphql(<<~END_OF_GRAPHQL, variables: variables, context: ctx)
        mutation($input: #{input_type}!) {
          #{operation}(input: $input) {
            errors {
              path
              message
            }
          }
        }
      END_OF_GRAPHQL
    end

    helper :group_offering_automation_rules do |existing_rules, new_rule_inputs|
      groups = {}
      current = existing_rules || []

      current.each do |rule|
        generic = rule['generic'] # request, problem, ci or task
        groups[generic] ||= [[], []]
        groups[generic][0] << rule
        groups[generic][1] << nil
      end

      new_rules = new_rule_inputs || []
      new_rules.each do |new_rule|
        generic = new_rule['generic']
        groups[generic] ||= [[], []]
        current_rules = groups[generic][0]
        index = current_rules.find_index { |r| r['name'].downcase == new_rule['name'].downcase }

        if index
          groups[generic][1][index] = new_rule
        else
          groups[generic][1] << new_rule
        end
      end

      groups
    end
  end
end
