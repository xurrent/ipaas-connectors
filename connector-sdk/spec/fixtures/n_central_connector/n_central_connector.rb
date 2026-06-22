class NCentralConnector < IPaaS::Connector::Definition
  connector '0196d840-17db-739d-8dad-a1993d743573' do
    name 'N-Central Connector'
    avatar '/assets/icons/nable-logo.svg'
    description 'N-Able N-Central Connector'
    description <<~END_OF_DESCRIPTION
      This connector allows for integrations between N-Central from N-Able and a PSA (Professional Services Automation) tool like Xurrent.

      # PSA - Generate Ticket

      This trigger listens to Custom PSA Integration messages from N-Central. To configure the integration in N-Central go to Administration → PSA Integrations → Configure PSA Integration. Then choose the following:
      * Choose your PSA Solution: Custom PSA
      * API Credentials
        - Password: Set any value and ignore (required, but not used)
      * API Ticket generation:
        - Base Endpoint URL: Protocol and host of the Xurrent iPaaS platform, e.g. (https://trigger.ipaas.xurrent.com)
        - Ticketing Endpoint: The trigger endpoint, e.g. `/inbound/1/d4b8ddd0-b8ba/01922296-df4a`
        - User Name: Any user name that matches the user name in the inbound connection configuration.
        - Password: Any password that matches the password in the inbound connection configuration.

      # (Un)Register PSA user

      If the N-Central connector will be used for multiple customers the "(Un)Registers PSA user" actions are required to generate passwords for each customer. The setup works as follows:
      * In the inbound connection configuration leave the "User Name" and "Password" fields empty.
      * Create a runbook that is triggered for each new customer and use the "Register PSA user" action to generate a password for the customer.
        - The user name that is provided in the configuration should contain a unique ID for the customer.
        - Also provide the runbook that is using the "PSA - Generate Ticket" trigger.
      * Each customer needs to be informed on how to configure their Custom PSD Integration in N-Central. All information required for that setup is provided in the "Register PSA user" action output.
      * When the "PSA - Generate Ticket" runbook is triggered, the password is automatically validated and the User Name identifying the customer is available in the trigger output.
      * Do not forget to create another runbook that is triggered on customer removal that uses the "Unregister PSA user" action to remove the access for that customer.

      # Actions

      ## Register PSA user

      If the N-Central connector will be used for multiple N-Central customers this action is required to generate a password for each customer.

      Once this action completes, the customer needs to be informed on how to configure their Custom PSD Integration in N-Central. All information required during that setup is provided in the action output.

      ## Unregister PSA user

      If the N-Central connector will be used for multiple N-Central customers this action is required to remove the generated password for a given customer when they no longer require the integration.

      Once this action completes subsequent calls to the "PSA - Generate Ticket" trigger for ths customer will fail.
    END_OF_DESCRIPTION

    inbound_connection do
      config_schema do
        field :user_name, 'User Name', :string
        field :password, 'Password', :secret_string
      end

      validate do |_request|
        # validation is done when parsing requests in the triggers as it requires access to the outbound connection
        true
      end
    end

    trigger '0196d843-259d-7308-96bb-f44082fffecc' do
      name 'PSA - Generate Ticket'
      avatar '/assets/icons/nable-logo.svg'
      description 'The PSA endpoint listening for N-Central webhooks to generate a ticket.'
      outbound_traffic true # required to store shared secrets between trigger and action

      config_schema do
        field :ticket_url_template,
              'Ticket URL template',
              :string,
              hint: <<~END_OF_HINT,
                N-Central requires the trigger response to define the `externalTicketId` and `ticketUrl`.
                But as the Xurrent iPaaS platform is asynchronous that information is not available at the time of the
                response generation. Therefore the `externalTicketId` will be set to `PSA-<n-central-ticket-id>` and
                the `ticketUrl` will be set to the value of the `ticket_url_template` field. Note that the text
                `{n_central_ticket_id}` must be present to indicate where the N-Central ticket ID should be inserted.

                The text `{n_central_user_name}` can optionally be present and will be substituted with the user name in N-Central.

                When connecting with Xurrent the following may work well:
                `https://{n_central_user_name}.<xurrent-domain>/requests/show_by_source?source=ncentral&sourceID={n_central_ticket_id}`

                Substitute the text `<xurrent-domain>` with the domain of your Xurrent account, for example `xurrent.com`.
              END_OF_HINT
              pattern: /\A(.*\{n_central_ticket_id}.*)\z/,
              required: true

        field :custom_tags_schema,
              'Custom tags schema',
              [:schema_field],
              required: false

        after_update do
          regenerate_schema(output_schema)
        end
      end

      output_schema do
        field :user_name, 'User Name', :string, required: true
        field :action,
              'Action',
              :string,
              required: true,
              enumeration: [
                { id: 'CREATE', label: 'CREATE' },
                { id: 'UPDATE', label: 'UPDATE' },
              ]
        field :title, 'Title', :string, required: true
        field :details, 'Details', :string, required: true
        field :ncentralTicketId, 'N-Central Ticket ID', :string, required: true

        if trigger.config[:custom_tags_schema].present?
          field :customTags, 'Custom Tags', :nested, fields: trigger.config[:custom_tags_schema]
        end
      end

      parse do |request|
        psa_validate_secret(request, strict: false)

        data = helpers.read_n_central_trigger_body(request)
        data.delete(:psaTicketNumber) # generated and therefore not useful
        data[:user_name] = psa_extract_basic_auth(request, strict: false).first
        self.job_context_identifier = data[:user_name]
        ticket_id = data[:ncentralTicketId]
        discard_trigger_event!("Test ticket: #{ticket_id}") if ticket_id.starts_with?('TEST_NC_TICKET_ID')

        custom_tags_schema = trigger.config[:custom_tags_schema]
        if custom_tags_schema.present? && data[:customTags].is_a?(Hash)
          custom_tag_field_ids = custom_tags_schema.map(&:id)
          data[:customTags] = data[:customTags].slice(*custom_tag_field_ids)
        end

        data
      end

      respond_with do |context, response|
        data = helpers.read_n_central_trigger_body(context[:request])
        ticket_id = data[:ncentralTicketId]
        user_name = psa_extract_basic_auth(context[:request], strict: false).first
        ticket_url = trigger.config[:ticket_url_template]
                            .gsub('{n_central_ticket_id}') { ticket_id.to_s }
                            .gsub('{n_central_user_name}') { user_name.to_s }

        response[:headers]['content-type'] = 'application/json; charset=utf-8'
        response[:body] = {
          'externalTicketId' => "PSA-#{ticket_id}",
          'ticketUrl' => ticket_url,
        }.to_json
        response
      end

      helper :read_n_central_trigger_body do |request|
        body_content = request.body&.read
        result = body_content.present? ? JSON.parse(body_content) : body_content
        fail_job!('Expected a JSON hash from N-Central.') unless result.is_a?(Hash)
        result.with_indifferent_access
      end
    end

    action '01970d2a-8760-7251-a9d6-6bfc884d39cd' do
      name 'Register PSA user'
      avatar '/assets/icons/nable-logo.svg'
      description <<~END_OF_DESCRIPTION
        If the N-Central connector will be used for multiple N-Central customers this action is required to generate a password for each customer.

        Once this action completes, the customer needs to be informed on how to configure their Custom PSD Integration in N-Central. All information required during that setup is provided in the action output.
      END_OF_DESCRIPTION

      input_schema do
        field :user_name,
              'User Name',
              :string,
              required: true,
              hint: 'The user name should contain a unique ID for the customer.'
        field :psa_generate_ticket_runbook,
              'PSA Generate Ticket Runbook',
              :runbook,
              hint: 'The runbook that is using the "PSA - Generate Ticket" trigger.'
      end

      output_schema do
        field :base_endpoint_url, 'Base Endpoint URL', :string
        field :ticketing_endpoint, 'Ticketing Endpoint', :string
        field :user_name, 'User Name', :string, required: true
        field :password, 'Password', :secret_string, required: true
      end

      run do
        user_name = action.input[:user_name]
        password = psa_generate_secret_for(user_name)
        data = { user_name: user_name, password: password }

        generate_ticket_runbook = action.input[:psa_generate_ticket_runbook]
        if generate_ticket_runbook.present?
          uri = URI.parse(generate_ticket_runbook.endpoint)
          data[:base_endpoint_url] = "#{uri.scheme}://#{uri.host}"
          data[:ticketing_endpoint] = uri.request_uri
        end
        [{ output: data }]
      end
    end

    action '019710fb-804f-7532-8f3f-b97c9cbc189a' do
      name 'Unregister PSA user'
      avatar '/assets/icons/nable-logo.svg'
      description <<~END_OF_DESCRIPTION
        If the N-Central connector will be used for multiple N-Central customers this action is required to remove the generated password for a given customer when they no longer require the integration.

        Once this action completes subsequent calls to the "PSA - Generate Ticket" trigger for ths customer will fail.
      END_OF_DESCRIPTION

      input_schema do
        field :user_name,
              'User Name',
              :string,
              required: true,
              hint: 'The user name should contain a unique ID for the customer.'
      end

      output_schema do
        field :user_name, 'User Name', :string, required: true
      end

      run do
        user_name = action.input[:user_name]
        psa_delete_secret_for(user_name)
        [{ output: { user_name: user_name } }]
      end
    end
  end
end
