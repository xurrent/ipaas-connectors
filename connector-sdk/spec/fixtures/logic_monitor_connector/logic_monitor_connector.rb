class LogicMonitorConnector < IPaaS::Connector::Definition
  connector '0199a9a6-ac42-7ad1-a22e-26a05ff5d538' do
    name 'Logic Monitor Connector'
    avatar '/assets/icons/logic-monitor.svg'
    description 'Logic Monitor Connector'
    description <<~END_OF_DESCRIPTION
      This connector allows for integrations between Logic Monitor and a PSA (Professional Services Automation) tool like Xurrent.

      # PSA - Generate Ticket

      The PSA endpoint listening for Logic Monitor webhooks to generate a ticket.

      This trigger listens to Custom PSA Integration messages from Logic Monitor. To configure the integration in Logic Monitor go to Settings → Integrations → Add → Custom HTTP integration.. Then choose the following:
      * Choose your PSA Solution: Custom PSA
      * API Credentials
        - Password: Set any value and ignore (required, but not used)
      * API Ticket generation:
        - Ticketing Endpoint URL: The trigger endpoint, e.g. `https://trigger.ipaas.xurrent.com/inbound/1/d4b8ddd0-b8ba/01922296-df4a`
        - User Name: Any user name that matches the user name in the inbound connection configuration.
        - Password: Any password that matches the password in the inbound connection configuration.

      # Register LM user

      If the Logic Monitor connector will be used for multiple Logic Monitor customers this action is required to generate a password for each customer.

      Once this action completes, the customer needs to be informed on how to configure their Custom PSD Integration in Logic Monitor. All information required during that setup is provided in the action output.

      If the Logic Monitor connector will be used for multiple customers the "(Un)Registers LM user" actions are required to generate passwords for each customer. The setup works as follows:
      * In the inbound connection configuration leave the "User Name" and "Password" fields empty.
      * Create a runbook that is triggered for each new customer and use the "Register LM user" action to generate a password for the customer.
        - The user name that is provided in the configuration should contain a unique ID for the customer.
        - Also provide the runbook that is using the "PSA - Generate Ticket" trigger.
      * Each customer needs to be informed on how to configure their Custom PSD Integration in Logic Monitor. All information required for that setup is provided in the "Register LM user" action output.
      * When the "PSA - Generate Ticket" runbook is triggered, the password is automatically validated and the User Name identifying the customer is available in the trigger output.
      * Do not forget to create another runbook that is triggered on customer removal that uses the "Unregister LM user" action to remove the access for that customer.

      # Unregister LM user

      If the Logic Monitor connector will be used for multiple Logic Monitor customers this action is required to remove the generated password for a given customer when they no longer require the integration.

      Once this action completes subsequent calls to the "PSA - Generate Ticket" trigger for this customer will fail.

      # Fetch devices from Logic Monitor CMDB

      Retrieves a comprehensive list of devices from Logic Monitor CMDB (Configuration Management Database), including detailed device information for device management and asset tracking.

      **Input**:
      - Last sync datetime (optional) - for incremental synchronization (filters devices updated after this time)
      - Page size (1-1000, default: 100) - Number of devices to return per page

      **Output**:
      - Complete list of all devices with comprehensive information including:
        - Device identification (ID, name, display name)
        - System properties (array of {name, value} objects from Logic Monitor)
      - All results automatically retrieved across all pages (pagination handled internally)
      - Pagination continues until a page with fewer items than the page size is returned (or no items at all)

      **Use Case**: Device inventory management, CMDB synchronization, asset tracking, integration with IT service management systems, device discovery and mapping

      **Example Input**:
      ```json
      {
        "last_sync": "2024-01-01T00:00:00Z",
        "page_size": 100
      }
      ```

      **Example Output**:
      ```json
      {
        "total": 606,
        "has_next_page": true,
        "devices": [
          {
            "device_id": 1,
            "name": "LMAWSACCOUNT-17",
            "display_name": "DevOps Account",
            "system_properties": [{"name":"system.device.provider","value":"AWS"},{"name":"system.hostname","value":"LMAWSACCOUNT-17"}]
          }
        ]
      }
      ```

      **Authentication**: Requires a permanent bearer token configured in the outbound connection.
      **Rate Limit**: 700 requests per minute (automatic backoff on 429 errors).
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

    outbound_connection do
      bearer_authenticator
    end

    trigger '0199a9a6-d3c8-7d78-870c-069a8db0f19b' do
      name 'PSA - Generate Ticket'
      avatar '/assets/icons/logic-monitor.svg'
      description 'The PSA endpoint listening for Logic Monitor webhooks to generate a ticket.'
      outbound_traffic true

      config_schema do
        field :ticket_url_template,
              'Ticket URL template',
              :string,
              hint: <<~END_OF_HINT,
                LogicMonitor can optionally receive a value for any field in the trigger response.
                So we use the field ticket_url, which is used to link a LogicMonitor alert to a corresponding request in Xurrent.
                To enable this linkage, you can define a ticket_url_template that specifies how the LogicMonitor alert ID should be embedded in a URL pointing back to the related request.
                The text {lm_alert_id} must be present in the template to indicate where the LogicMonitor Alert ID will be inserted.
                The text {lm_user_name} can optionally be included and will be substituted with the LogicMonitor user name.

                When connecting with Xurrent the following may work well:
                `https://{lm_user_name}.<xurrent-domain>/requests/show_by_source?source=logicmonitor&sourceID={lm_alert_id}`

                Substitute the text `<xurrent-domain>` with the domain of your Xurrent account, for example `xurrent.com`.
              END_OF_HINT
              pattern: /\A(.*\{lm_alert_id}.*)\z/,
              required: true

        field :data_schema,
              'Data schema',
              [:schema_field],
              required: false

        after_update do
          regenerate_schema(output_schema)
        end
      end

      output_schema do
        field :user_name, 'User Name', :string, required: true
        field :alert_id, 'Alert ID', :string, required: true
        field :alert_message, 'Alert Message', :string, required: true
        field :alert_level, 'Alert Level', :string, required: true
        field :alert_status, 'Alert Status', :string, required: true
        field :alert_type, 'Alert Status', :string, required: true

        field :data, 'Data', :nested, fields: trigger.config[:data_schema] if trigger.config[:data_schema].present?
      end

      parse do |request|
        psa_validate_secret(request, strict: false)

        data = helpers.read_logic_monitor_trigger_body(request)
        data[:user_name] = psa_extract_basic_auth(request, strict: false).first
        self.job_context_identifier = data[:user_name]

        data_schema = trigger.config[:data_schema]
        if data_schema.present? && data[:data].is_a?(Hash)
          data_field_ids = data_schema.map(&:id)
          data[:data] = data[:data].slice(*data_field_ids)
        end

        data
      end

      respond_with do |context, response|
        alert_id = helpers.read_logic_monitor_trigger_body(context[:request])[:alert_id]
        user_name = psa_extract_basic_auth(context[:request], strict: false).first
        ticket_url = trigger.config[:ticket_url_template]
                            .gsub('{lm_alert_id}') { alert_id.to_s }
                            .gsub('{lm_user_name}') { user_name.to_s }

        response[:headers]['content-type'] = 'application/json; charset=utf-8'
        response[:body] = {
          'ticket_url' => ticket_url.to_s,
        }.to_json
        response
      end

      helper :read_logic_monitor_trigger_body do |request|
        body_content = request.body&.read
        result = body_content.present? ? JSON.parse(body_content) : body_content
        fail_job!('Expected a JSON hash from Logic Monitor.') unless result.is_a?(Hash)
        result.with_indifferent_access
      end
    end

    action '0199a9a7-1270-7861-9a65-832e8c806c2e' do
      name 'Register LM user'
      avatar '/assets/icons/logic-monitor.svg'
      description <<~END_OF_DESCRIPTION
        If the Logic Monitor connector will be used for multiple Logic Monitor customers this action is required to generate a password for each customer.

        Once this action completes, the customer needs to be informed on how to configure their Custom PSD Integration in Logic Monitor. All information required during that setup is provided in the action output.
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
        field :ticketing_endpoint_url, 'Ticketing Endpoint URL', :string
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
          data[:ticketing_endpoint_url] = "#{uri.scheme}://#{uri.host}#{uri.request_uri}"
        end
        [{ output: data }]
      end
    end

    action '0199a9a7-3ca2-7ab0-9bd2-8fca8ad3f7da' do
      name 'Unregister LM user'
      avatar '/assets/icons/logic-monitor.svg'
      description <<~END_OF_DESCRIPTION
        If the Logic Monitor connector will be used for multiple Logic Monitor customers this action is required to remove the generated password for a given customer when they no longer require the integration.

        Once this action completes subsequent calls to the "PSA - Generate Ticket" trigger for this customer will fail.
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

    action '0199a9a7-cdb4-7c91-a382-79e30c4d572f' do
      name 'Fetch devices from Logic Monitor CMDB'
      avatar '/assets/icons/logic-monitor.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Retrieves a comprehensive list of devices from Logic Monitor CMDB (Configuration Management Database), including detailed device information for device management and asset tracking.

        **Input**:
        - Last sync datetime (optional) - for incremental synchronization (filters devices updated after this time)
        - Page size (1-1000, default: 100) - Number of devices to return per page

        **Output**:
        - Complete list of all devices with comprehensive information including:
          - Device identification (ID, name, display name)
          - System properties (array of {name, value} objects from Logic Monitor)
        - All results automatically retrieved across all pages (pagination handled internally)
        - Pagination continues until a page with fewer items than the page size is returned (or no items at all)

        **Use Case**: Device inventory management, CMDB synchronization, asset tracking, integration with IT service management systems, device discovery and mapping

        **Example Input**:
        ```json
        {
          "last_sync": "2024-01-01T00:00:00Z",
          "page_size": 100
        }
        ```

        **Example Output**:
        ```json
        {
          "total": 606,
          "has_next_page": true,
          "devices": [
            {
              "device_id": 1,
              "name": "LMAWSACCOUNT-17",
              "display_name": "DevOps Account",
              "system_properties": [{"name":"system.device.provider","value":"AWS"},{"name":"system.hostname","value":"LMAWSACCOUNT-17"}]
            }
          ]
        }
        ```

        **Authentication**: Requires a permanent bearer token configured in the outbound connection.
        **Rate Limit**: 700 requests per minute (automatic backoff on 429 errors).
      END_OF_DESCRIPTION

      input_schema do
        field :account, 'Account', :string,
              required: true,
              hint: 'Your Logic Monitor account name (e.g., "xurrent" for https://xurrent.logicmonitor.com)'
        field :last_sync, 'Last sync', :date_time
        field :page_size, 'Page size', :integer,
              min: 1, max: 1000,
              visibility: 'optional',
              default: 100,
              hint: 'Number of devices to return per page (max 1000, default: 100)'
      end

      output_schema 'page' do
        field :total, 'Total', :integer,
              hint: 'Total number of devices matching the criteria'
        field :has_next_page, 'Has next page', :boolean, required: true

        field :devices, 'Devices', :nested,
              array: true do
          field :device_id, 'Device ID', :integer, required: true
          field :name, 'Name', :string
          field :display_name, 'Display name', :string
          field :system_properties, 'System properties', :nested,
                hint: 'JSON object containing system properties array (array of {name, value} objects)',
                array: true do
            field :name, 'Name', :string
            field :value, 'Value', :string
          end
        end
      end

      iteration_state_schema do
        field :offset, 'Offset', :integer, required: true
      end

      run do
        offset = iteration_state_value(:offset) || 0
        page_size = input[:page_size]&.to_i || 100

        device_url = "#{helpers.logic_monitor_api_endpoint}/device/devices"

        query_params = {
          fields: 'id,name,displayName,systemProperties',
          size: page_size.to_s,
          offset: offset.to_s,
        }

        if input[:last_sync].present?
          last_sync_timestamp = input[:last_sync].to_i
          query_params[:filter] = "updatedOn>#{last_sync_timestamp}"
        end

        response = http_get(device_url, query_params)
        backoff_if_needed(response, api_name: 'LogicMonitor')
        result = helpers.parse_logic_monitor_response(response)

        items = result.dig(:data, :items)
        fail_job!('Expected items to be an array from Logic Monitor') unless items.is_a?(Array)

        total = result.dig(:data, :total)
        fail_job!('Expected total to be an integer from Logic Monitor') unless total.is_a?(Integer)

        devices = items.map do |device|
          {
            device_id: device[:id],
            name: device[:name],
            display_name: device[:displayName],
            system_properties: device[:systemProperties] || [],
          }
        end

        next_offset = items.empty? || (items.size < page_size) ? nil : offset + page_size
        self.iteration_state_value = next_offset ? { offset: next_offset } : nil

        page = {}
        page[:total] = total
        page[:has_next_page] = self.iteration_state_value.present?
        page[:devices] = devices.presence || []

        [{ output: page, schema_reference: 'page' }]
      end
    end

    helper :logic_monitor_api_endpoint do
      account = action.input[:account]
      fail_job!('Logic Monitor account name is required.') if account.blank?
      "https://#{account}.logicmonitor.com/santaba/rest"
    end

    helper :parse_logic_monitor_response do |response|
      if [401, 403].include?(response.status)
        fail_job!("Authentication error from Logic Monitor API: #{response.status} '#{response.body}'")
      end

      fail_job!("HTTP error from Logic Monitor API: #{response.status} '#{response.body}'") if response.status != 200

      body = parse_json_response(
        response.body,
        error_message: "Logic Monitor API response was not JSON: '#{response.body}'"
      )

      if body['status'] && body['status'] != 200
        error_msg = body['errmsg'] || body['error'] || body['message'] || 'Unknown error'
        fail_job!("Error from Logic Monitor API: #{error_msg}")
      end

      body.with_indifferent_access
    end
  end
end
