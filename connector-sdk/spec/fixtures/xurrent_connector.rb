class XurrentConnector < IPaaS::Connector::Definition
  GqlSchema = IPaaS::Job::GraphQL::Schema
  GqlQuery = IPaaS::Job::GraphQL::QueryBuilder
  GqlFields = IPaaS::Job::GraphQL::FieldBuilder
  GqlResult = IPaaS::Job::GraphQL::Result
  Humanize = IPaaS::Job::Humanize
  CompactHash = IPaaS::Job::CompactHash

  MAX_WEBHOOK_BODY_BYTES = 256 * 1024

  INTROSPECTION_FAILURE_TTL = 10.minutes # configuration errors cached for 10 minutes
  INTROSPECTION_TRANSIENT_FAILURE_TTL = 30.seconds # transient errors cached for 30 seconds
  INTROSPECTION_FAILURE_MESSAGE_LIMIT = 200 # cap on the length of the error message

  connector '01930641-94f0-7d88-941f-cd0f542b75b9' do
    name 'Xurrent Connector'
    avatar '/assets/icons/x-logo-graphql.svg'
    description <<~DESC
      Connector for integrating with Xurrent using the GraphQL API with dynamic schema introspection.

      # Outbound Connection
      The query, mutation, and upload attachment actions all require an outbound connection. It supports two authentication methods: **OAuth2 Client Credentials** and **Personal Access Token**.

      # Xurrent Webhook Trigger
      The `Xurrent Webhook` trigger receives and processes webhook events from Xurrent. JWT verification uses OIDC auto-discovery by default; configure overrides on the inbound connection or per trigger. Define additional payload fields to parse webhook data into typed values.

      # Xurrent Query Action (1)
      Dynamically queries Xurrent records. Select a query object (e.g. `people`, `requests`, `configurationItems`); schema introspection generates the input arguments and output fields from the Xurrent GraphQL schema.

      ## How it works
      1. Select a **query object** (e.g. `people`, `requests`, `configurationItems`). Once you configure the outbound connection, the connector loads the available objects from the Xurrent GraphQL schema.
      2. Schema introspection generates the input fields (filters, views) and output fields from the selected query object.
      3. Use **Include nested fields** to select which related objects to include in the query result (e.g. include `team` fields when querying people).
      4. Set **Max results** to cap the total number of records and **Page size** (1-100) to control records per page.

      This action is **nested**: it iterates over all matching records and runs the successor action once per record. Connect downstream actions to the output schema to process each record.

      ## Refreshing the schema cache
      The connector caches the GraphQL schema in the connection store after the first introspection. Check **Refresh schema** to clear the cache and re-fetch (e.g. after Xurrent schema changes).

      # Xurrent Mutation Action (2)
      Executes a Xurrent GraphQL mutation. Select a mutation (e.g. `requestCreate`, `personUpdate`, `noteCreate`); schema introspection generates the input and output schemas.

      ## How it works
      1. Select a **mutation** (e.g. `requestCreate`, `personUpdate`, `noteCreate`). Once you configure the outbound connection, the connector loads the available mutations from the Xurrent GraphQL schema.
      2. Schema introspection generates the input and output fields from the selected mutation.
      3. Provide the mutation input either by mapping individual fields or as a **JSON object**.

      ## Attaching files
      To attach files to a record (e.g. a note), first use the **Upload Attachment** action to upload the file. Then use the returned `storage_key` as the `key` value in the mutation's attachment input.

      ## Refreshing the schema cache
      The connector caches the GraphQL schema in the connection store after the first introspection. Check **Refresh schema** to clear the cache and re-fetch (e.g. after Xurrent schema changes).

      # Upload Attachment Action (3)
      Uploads a file via the `attachmentStorage` GraphQL query and returns a storage key. Pass the key to any mutation that accepts `AttachmentInput` (e.g. attach a file to a note via `noteCreate`).

      ## How it works
      1. The action queries the `attachmentStorage` endpoint for upload credentials and a pre-signed upload URI.
      2. The connector uploads the file directly to the storage provider (`s3` or `local`) via multipart POST per RFC 2388.
      3. The returned **storage key** identifies the uploaded file.

      ## Using the storage key
      Use the `storage_key` output as the `key` value in any mutation that accepts `AttachmentInput`. For example, when creating a note with an attachment via `noteCreate`, map the `storage_key` to the attachment's `key` field.

      ## Content type detection
      If you don't provide a content type, the connector derives it from the file name extension.
    DESC

    # ──────────────────────────────────────────────
    # Inbound Connection (webhook JWT verification)
    # ──────────────────────────────────────────────

    inbound_connection do
      config_schema do
        pem_validator = ->(value) do
          pem = value[:public_key_pem]
          algorithm = value[:algorithm]
          next true if pem.blank? && algorithm.blank?
          next false if pem.blank? || algorithm.blank?
          IPaaS::Job::JWT.pem_valid?(algorithm, pem)
        end

        field :policy, 'Webhook Policy', :nested,
              hint: 'Configure JWT verification for inbound webhooks. ' \
                    'This policy applies to all runbooks unless overridden per trigger.',
              validator: pem_validator,
              visibility: 'optional' do
          field :account_url, 'Issuer', :string,
                hint: 'Optional. If set, the JWT issuer must equal this value exactly. ' \
                      'When blank, the issuer is required to match the current Xurrent ' \
                      'account URL (scheme, host, and path prefix).',
                visibility: 'optional'
          field :algorithm, 'Algorithm', :string,
                hint: 'Optional. When blank, the algorithm is taken from the JWT header ' \
                      'and must be one of RS256, RS384, RS512, ES256, ES384, ES512.',
                enumeration: %w[RS256 RS384 RS512 ES256 ES384 ES512],
                visibility: 'optional'
          field :public_key_pem, 'Public key PEM', :string,
                hint: 'Optional. When blank, the signing key is discovered via OIDC from ' \
                      'the JWT issuer and stored per key id on the inbound connection.',
                visibility: 'optional'
          field :audience, 'Audience', :string,
                hint: 'Optional JWT audience claim. Must match the audience configured ' \
                      'in the Xurrent Webhook Policy, if set.'
        end
      end
      validate do |_request|
        true
      end
    end

    # ──────────────────────────────────────────────
    # Outbound Connection (API authentication)
    # ──────────────────────────────────────────────

    outbound_connection do
      config_schema do
        field :credentials, 'Credentials', :nested,
              hint: <<~HINT.strip,
                Authenticate with the Xurrent GraphQL API using either OAuth2 Client Credentials
                or a Personal Access Token. When a Personal Access Token is provided it takes
                precedence and the Client ID and Client secret are not required.

                # OAuth2 Client Credentials
                Use for server-to-server integration without user interaction.

                ## Steps to create an OAuth2 Application
                1. Login to Xurrent as a user with the Account Administrator role.
                2. Navigate to Settings > OAuth Applications.
                3. Click 'New OAuth Application' and select **Client credentials grant**.
                4. Configure the required scopes based on the data you need to access
                   (e.g. Person — Read, Request — Read/Create/Update).
                5. Save the application, then copy the **Client ID** and **Client secret** below.

                # Personal Access Token
                Use for quick setup or personal integrations.

                ## Steps to create a Personal Access Token
                1. Login to Xurrent as the user whose permissions the integration should use.
                2. Navigate to your Profile > Personal Access Tokens.
                3. Click 'Generate New Token'.
                4. Give the token a descriptive name (e.g. 'iPaaS Integration').
                5. Copy the generated token and paste it as the **Personal Access Token** below.

                Note: The token inherits the permissions of the user who created it.
              HINT
              required: true do
          field :account_id, 'Account ID', :string,
                hint: 'The Xurrent account identifier. Found in the URL when logged in ' \
                      '(e.g. https://\<account_id\>.xurrent.com). Leave blank to use the current iPaaS account.',
                visibility: 'optional'
          field :client_id, 'Client ID', :string,
                hint: 'The Client ID from the OAuth Application in Xurrent.',
                required: true
          field :client_secret, 'Client secret', :secret_string,
                hint: 'The Client secret from the OAuth Application in Xurrent.',
                required: true
          field :personal_access_token, 'Personal Access Token', :secret_string,
                hint: 'When set, authenticates with a Personal Access Token instead of OAuth2 client credentials.',
                visibility: 'optional'
        end

        env_validator = ->(value) do
          return true if value.blank?
          return true if value[:graphql_endpoint].present? && value[:oauth2_endpoint].present?

          value[:stage].present?
        end
        field :environment, 'Environment', :nested,
              hint: 'Select the Xurrent environment to connect to. ' \
                    'Use custom endpoints only when connecting to a non-standard environment. ' \
                    'Leave blank to use the current iPaaS environment.',
              visibility: 'optional',
              validator: env_validator do
          field :stage, 'Stage', :string,
                hint: 'The Xurrent environment stage.',
                enumeration: %w[Demo QA Prod]
          field :region, 'Region', :string,
                hint: 'The data center region of the Xurrent account.',
                enumeration: %w[au ch uk us]
          field :oauth2_endpoint, 'OAuth2 Endpoint', :uri,
                hint: 'Custom OAuth2 token endpoint. Only needed for non-standard environments.',
                visibility: 'optional'
          field :graphql_endpoint, 'GraphQL Endpoint', :uri,
                hint: 'Custom GraphQL API endpoint. Only needed for non-standard environments.',
                visibility: 'optional'
        end

        # Make OAuth2 client credentials optional when a Personal Access Token is provided,
        # since PAT takes precedence in the authenticate block.
        after_update do |fields, new_values|
          credentials_field = fields.detect { |f| f.id == :credentials }
          pat_provided = new_values.dig(:credentials, :personal_access_token).present?
          credentials_field.fields.detect { |f| f.id == :client_id }.required = !pat_provided
          credentials_field.fields.detect { |f| f.id == :client_secret }.required = !pat_provided
          fields
        end
      end

      authenticate do |request|
        credentials_config = config[:credentials] || {}
        account_id = credentials_config[:account_id].presence || helpers.system_account_id
        request.headers['X-Xurrent-Account'] = account_id

        if credentials_config[:personal_access_token].present?
          token = decrypt_secret_string(credentials_config[:personal_access_token])
          request.headers['Authorization'] = "Bearer #{token}"
        else
          body = oauth2_client_credentials_body(credentials_config[:client_id],
                                                decrypt_secret_string(credentials_config[:client_secret]))
          request.headers['Authorization'] = oauth2_authorization_header(helpers.oauth_endpoint,
                                                                         body,
                                                                         account_id: account_id)
        end
      end
    end

    # ──────────────────────────────────────────────
    # Trigger: Webhook Event
    # ──────────────────────────────────────────────

    trigger '01930641-dd8e-7e8c-8550-e8cdbe31eddb' do
      name 'Xurrent Webhook'
      avatar '/assets/icons/x-logo-webhook.svg'
      description <<~DESC.strip
        Receive and process Xurrent webhook events with JWT verification.

        # How it works
        1. Configure a webhook in Xurrent (Settings > Webhooks) to point at the endpoint of this runbook.
        2. Optionally configure a Webhook Policy in Xurrent to sign deliveries with JWT. By default the trigger discovers the signing key via OIDC from the JWT issuer; configure Webhook Policy fields below only to override.
        3. On each event, the trigger validates the JWT issuer against the current Xurrent account, validates timestamps, resolves the signing key (configured PEM, then OIDC well-known + JWKS), and verifies the signature.

        # JWT verification overrides
        - Inbound connection Webhook Policy: shared across all runbooks.
        - Trigger Webhook Policy: overrides the inbound connection policy for this runbook.

        # Custom payload fields
        Define Additional payload fields to parse webhook data into typed values.
      DESC

      config_schema do
        pem_validator = ->(value) do
          pem = value[:public_key_pem]
          algorithm = value[:algorithm]
          next true if pem.blank? && algorithm.blank?
          next false if pem.blank? || algorithm.blank?
          IPaaS::Job::JWT.pem_valid?(algorithm, pem)
        end

        field :policy, 'Webhook Policy', :nested,
              hint: 'Configure JWT verification for this trigger. Overrides the inbound connection policy if set.',
              validator: pem_validator,
              visibility: 'optional' do
          field :account_url, 'Issuer', :string,
                hint: 'Optional. If set, the JWT issuer must equal this value exactly. ' \
                      'When blank, the issuer is required to match the current Xurrent ' \
                      'account URL (scheme, host, and path prefix).',
                visibility: 'optional'
          field :algorithm, 'Algorithm', :string,
                hint: 'Optional. When blank, the algorithm is taken from the JWT header ' \
                      'and must be one of RS256, RS384, RS512, ES256, ES384, ES512.',
                enumeration: %w[RS256 RS384 RS512 ES256 ES384 ES512],
                visibility: 'optional'
          field :public_key_pem, 'Public key PEM', :string,
                hint: 'Optional. When blank, the signing key is discovered via OIDC from ' \
                      'the JWT issuer and stored per key id on the inbound connection.',
                visibility: 'optional'
          field :audience, 'Audience', :string,
                hint: 'Optional JWT audience claim. Must match the audience ' \
                      'configured in the Xurrent Webhook Policy, if set.'
        end

        field :payload_schema,
              'Additional payload fields',
              [:schema_field],
              hint: 'Define additional fields to parse from the webhook payload into typed values.'

        after_update do
          regenerate_schema(output_schema)
        end
      end

      output_schema do
        field :webhook_id, 'Webhook ID', :integer,
              hint: 'The ID of the webhook that delivered this event.'
        field :webhook_nodeID, 'Webhook nodeID', :string,
              hint: 'The node ID of the webhook that delivered this event.'
        field :account_id, 'Account ID', :string,
              hint: 'The Xurrent account ID from which the webhook was sent.'
        field :account, 'Account URL', :string,
              hint: 'The URL of the Xurrent account from which the webhook was sent.'
        field :custom_url, 'Custom URL', :string,
              hint: 'The custom collection element URL, if applicable.'
        field :name, 'Webhook name', :string,
              hint: 'The name of the webhook in Xurrent.'
        field :event, 'Event', :string,
              required: true,
              hint: 'The type of event that triggered the webhook ' \
                    '(e.g. request.completed, task.updated).'
        field :object_id, 'Object ID', :integer,
              hint: 'The ID of the object that triggered the event.'
        field :object_nodeID, 'Object nodeID', :string,
              hint: 'The node ID of the object that triggered the event.'
        field :person_id, 'Person ID', :integer,
              hint: 'The ID of the person who performed the action.'
        field :person_nodeID, 'Person nodeID', :string,
              hint: 'The node ID of the person who performed the action.'
        field :person_name, 'Person name', :string,
              hint: 'The name of the person who performed the action.'
        field :instance_name, 'Instance name', :string,
              hint: 'The name of the Xurrent instance.'

        field :payload, 'Payload', :nested do
          field :audit_line_id, 'Audit line ID', :integer
          field :audit_line_nodeID, 'Audit Line nodeID', :string
          field :note_id, 'Note ID', :integer
          field :note_nodeID, 'Note nodeID', :string
          field :source, 'Source', :string
          field :sourceID, 'Source ID', :string
          field :status, 'Status', :string
          field :previous_status, 'Previous status', :string
          field :team, 'Team', :nested do
            field :id, 'ID', :integer
            field :nodeID, 'NodeID', :string
            field :name, 'Name', :string
            field :sourceID, 'Source ID', :string
            field :disabled, 'Disabled', :boolean
            field :account, 'Account', :nested do
              field :id, 'ID', :string
              field :name, 'Name', :string
            end
          end
          field :member, 'Member', :nested do
            field :id, 'ID', :integer
            field :nodeID, 'NodeID', :string
            field :name, 'Name', :string
            field :sourceID, 'Source ID', :string
            field :disabled, 'Disabled', :boolean
            field :account, 'Account', :nested do
              field :id, 'ID', :string
              field :name, 'Name', :string
            end
          end
        end
        field(:payload).fields += trigger.config[:payload_schema] || []

        field :raw_payload, 'Raw payload', :hash,
              visibility: 'optional'
        field :delivery, 'Webhook delivery ID', :string,
              required: true, visibility: 'optional'
        field :delivery_origin, 'Original webhook delivery ID', :string,
              visibility: 'optional'
      end

      helper :extract_webhook_body do |request|
        parsed_body = helpers.read_webhook_body!(request)
        policy_config = helpers.resolve_webhook_policy_config
        jwt = parsed_body['jwt']
        next parsed_body if jwt.blank? && policy_config.blank?
        fail_job!('Webhook request does not contain jwt property') if jwt.blank?
        helpers.verify_webhook_jwt!(jwt, policy_config)
      end

      helper :read_webhook_body! do |request|
        raw = request.body.read
        if raw.bytesize > XurrentConnector::MAX_WEBHOOK_BODY_BYTES
          log("Webhook body too large: #{raw.bytesize} > #{XurrentConnector::MAX_WEBHOOK_BODY_BYTES}")
          fail_job!('Webhook body too large')
        end
        JSON.parse(raw)
      rescue JSON::ParserError
        fail_job!('Unable to parse incoming webhook request')
      end

      helper :resolve_webhook_policy_config do
        config[:policy].presence || inbound_connection.config[:policy].presence || {}
      end

      helper :verify_webhook_jwt! do |jwt, policy_config|
        if jwt.bytesize > IPaaS::Job::JWT::MAX_TOKEN_BYTES
          log("Webhook JWT too large: #{jwt.bytesize} > #{IPaaS::Job::JWT::MAX_TOKEN_BYTES}")
          fail_job!('Webhook JWT is too large')
        end

        expected_prefix = helpers.expected_issuer_prefix_for(policy_config)
        if policy_config[:account_url].blank? && expected_prefix.blank?
          log('Xurrent webhook misconfigured: no policy account_url and no system Xurrent account')
          fail_job!('Webhook configuration error')
        end

        decoded = begin
          decode_jwt!(
            jwt,
            algorithm: policy_config[:algorithm],
            algorithm_allowlist: IPaaS::Job::JWT::SUPPORTED_ALGORITHMS,
            pem: policy_config[:public_key_pem],
            key_resolver: helpers.oidc_key_resolver,
            issuer: policy_config[:account_url],
            issuer_prefix: policy_config[:account_url].blank? ? expected_prefix : nil,
            audience: policy_config[:audience],
          )
        rescue IPaaS::Error => e
          log("Webhook JWT verification failed: #{e}")
          fail_job!('Webhook JWT verification failed')
        end
        decoded[:payload]['data']
      end

      helper :oidc_key_resolver do
        ->(header, payload) { helpers.resolve_oidc_pem(header, payload['iss']) }
      end

      helper :resolve_oidc_pem do |header, iss|
        kid = header['kid']
        raise IPaaS::Error, 'JWT has no kid header and no public key configured' if kid.blank?

        normalised_iss = helpers.normalise_iss_for_cache(iss)
        cache_key = "oidc_jwks/#{Digest::SHA256.hexdigest(normalised_iss)}/#{kid}"
        cached = inbound_connection.store.read(cache_key)
        next cached if cached.present?

        pem = helpers.fetch_oidc_pem(iss, kid, header['alg'])
        inbound_connection.store.write(cache_key, pem)
        pem
      end

      helper :normalise_iss_for_cache do |iss|
        uri = URI.parse(iss.to_s)
        port_part = uri.port == uri.default_port ? '' : ":#{uri.port}"
        "#{uri.scheme}://#{uri.host&.downcase}#{port_part}#{uri.path.chomp('/')}"
      rescue URI::InvalidURIError
        iss.to_s
      end

      helper :fetch_oidc_pem do |iss, kid, jwt_alg|
        iss_uri = helpers.validate_oidc_url!(iss)
        jwks_uri = helpers.discover_jwks_uri!(iss_uri)
        jwks_body = helpers.fetch_oidc_json!(jwks_uri.to_s, 'JWKS fetch failed')
        candidate = helpers.select_jwk!(jwks_body['keys'] || [], kid, jwt_alg)
        IPaaS::Job::JWT.jwk_to_pem(candidate)
      end

      helper :fetch_oidc_json! do |url, error_label|
        response = http_get(url, nil, nil,
                            skip_authentication: true, **IPaaS::Job::JWT::OIDC_HTTP_OPTS)
        IPaaS::Job::JWT.assert_no_oidc_redirect!(response, url)
        raise IPaaS::Error, "#{error_label}: #{response.status}" unless response.status == 200
        helpers.assert_oidc_response_size!(response)
        JSON.parse(response.body)
      rescue JSON::ParserError
        raise IPaaS::Error, "#{error_label}: response could not be parsed"
      end

      helper :discover_jwks_uri! do |iss_uri|
        config_url = "#{iss_uri.to_s.chomp('/')}/.well-known/openid-configuration"
        config_body = helpers.fetch_oidc_json!(config_url, 'OIDC discovery failed')
        jwks_uri_str = config_body['jwks_uri']
        raise IPaaS::Error, 'OIDC discovery document missing jwks_uri' if jwks_uri_str.blank?
        jwks_uri = helpers.validate_oidc_url!(jwks_uri_str)
        unless jwks_uri.host == iss_uri.host
          raise IPaaS::Error, "JWKS URI host mismatch: #{jwks_uri.host} != #{iss_uri.host}"
        end
        jwks_uri
      end

      helper :select_jwk! do |keys, kid, jwt_alg|
        candidate = keys.detect do |k|
          k['kid'] == kid &&
            IPaaS::Job::JWT::ASYMMETRIC_JWK_KTYS.include?(k['kty']) &&
            k['use'] == 'sig' &&
            (k['alg'].nil? || k['alg'] == jwt_alg)
        end
        raise IPaaS::Error, "Key '#{kid}' not found in JWKS" if candidate.nil?
        candidate
      end

      helper :assert_oidc_response_size! do |response|
        cap = IPaaS::Job::JWT::MAX_OIDC_RESPONSE_BYTES
        declared = response.headers['content-length']&.to_i
        raise IPaaS::Error, 'OIDC response too large' if declared && declared > cap
        raise IPaaS::Error, 'OIDC response too large' if response.body.bytesize > cap
      end

      helper :validate_oidc_url! do |url|
        uri = begin
          URI.parse(url.to_s)
        rescue URI::InvalidURIError
          raise IPaaS::Error, "Invalid OIDC URL: #{url}"
        end
        raise IPaaS::Error, "OIDC URL must use https: #{url}" unless uri.scheme == 'https'
        raise IPaaS::Error, "OIDC URL must not contain userinfo: #{url}" if uri.userinfo.present?
        raise IPaaS::Error, "OIDC URL missing host: #{url}" if uri.host.blank?
        uri
      end

      helper :expected_issuer_prefix_for do |policy_config|
        next nil if policy_config[:account_url].present?
        helpers.expected_issuer_prefix
      end

      helper :expected_issuer_prefix do
        account_id = outbound_connection&.config&.dig(:credentials, :account_id) ||
                     helpers.system_account_id
        domain = helpers.safe_xurrent_domain
        next nil if account_id.blank? || domain.blank?
        "https://#{account_id}.#{domain}"
      end

      helper :safe_xurrent_domain do
        next helpers.system_xurrent_domain if outbound_connection.nil?
        helpers.xurrent_domain
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
            discard_trigger_event!("Webhook verification handled: #{webhook_description}")
          else
            fail_job!("Unable to verify webhook #{webhook_description}.\n#{response.status}: #{response.body}")
          end
        end
      end

      helper :process_top_level_fields do |webhook, result|
        top_level = webhook.except('payload')
        unexpected_fields = {}
        top_level.each do |key, value|
          next if output_schema.field(key)

          unexpected_fields[key] = value
          top_level.delete(key)
        end
        if unexpected_fields.present?
          msg = unexpected_fields.map { |k, v| "'#{k}' => '#{v}'" }.join(', ')
          log("Ignored unexpected fields in webhook: #{msg}")
        end
        result.merge(top_level)
      end

      helper :process_payload do |webhook, result|
        helpers.process_top_level_fields(webhook, result).tap do |trigger_output|
          extra_fields = false
          payload_schema = output_schema.field(:payload)
          payload = {}
          webhook['payload']&.each do |key, value|
            if payload_schema.field(key.to_sym)
              payload[key] = value
            else
              extra_fields = true
            end
          end
          trigger_output['raw_payload'] = webhook['payload'] if extra_fields
          trigger_output['payload'] = payload
        end
      end

      parse do |request|
        fail_job!('Request has no body') if request.body.blank?

        result = { delivery: request.headers['x-xurrent-delivery'] }
        if request.headers['x-xurrent-delivery-origin'].present?
          result[:delivery_origin] = request.headers['x-xurrent-delivery-origin']
        end

        webhook = helpers.extract_webhook_body(request)
        helpers.handle_webhook_verification(webhook) if helpers.webhook_verification?(webhook)
        helpers.process_payload(webhook, result)
      end

      respond_with do |context, response|
        error = context[:error]
        if error.present? && error.is_a?(IPaaS::Job::DiscardTriggerEvent)
          response[:status] = 200
          response[:body] = error.message
        end
        response
      end
    end

    # ──────────────────────────────────────────────
    # Action: Dynamic GraphQL Query
    # ──────────────────────────────────────────────

    action '019ce240-76c9-75d1-beac-8c07b2325e76' do
      name 'Xurrent Query'
      description <<~DESC
        Query Xurrent records using the GraphQL API with dynamically generated input and output fields.

        # How it works
        1. Select a **query object** (e.g. `people`, `requests`, `configurationItems`). Once you configure the outbound connection, the connector loads the available objects from the Xurrent GraphQL schema.
        2. Schema introspection generates the input fields (filters, views) and output fields from the selected query object.
        3. Use **Include nested fields** to select which related objects to include in the query result (e.g. include `team` fields when querying people).
        4. Set **Max results** to cap the total number of records and **Page size** (1-100) to control records per page.

        This action is **nested**: it iterates over all matching records and runs the successor action once per record. Connect downstream actions to the output schema to process each record.

        # Refreshing the schema cache
        The connector caches the GraphQL schema in the connection store after the first introspection. Check **Refresh schema** to clear the cache and re-fetch (e.g. after Xurrent schema changes).
      DESC
      avatar '/assets/icons/x-logo-graphql.svg'
      nested true

      # Builds every query input field. Defined before input_schema (which runs
      # eagerly at connector load) so the helper is registered when first called.
      # schema_data lives only in this helper's frame, so the input_schema block's
      # after_update closure never captures it — capturing it would pin the multi-MB
      # parsed gql_schema on the cached Schema per solution version (GUI OOM).
      helper :build_query_input_fields do |schema|
        object_name = action.input&.[](:object)
        schema_data = cache_read('gql_schema')
        query_options = schema_data.present? ? GqlSchema.gql_list_root_fields(schema_data, 'query') : []

        if query_options.any?
          schema.field :object, 'Query object', :string,
                       enumeration: query_options,
                       required: true
        else
          schema.field :object, 'Query object', :string,
                       hint: 'The GraphQL query field name (e.g. people, requests, configurationItems).',
                       notice: 'Outbound Connection is not configured correctly.',
                       notice_type: 'error',
                       notice_action: 'edit_connection',
                       pattern: /\A[A-Za-z][A-Za-z0-9]*\z/,
                       required: true
        end

        # Define include_fields early so its value is resolved in the first pass,
        # making it available in action.input when after_update regenerates the output schema.
        schema.field :include_fields, 'Include nested fields', :nested

        if schema_data.present? && object_name.present?
          helpers.add_input_fields_from_schema_data(schema, schema_data, object_name)
        end

        schema.field :page_size, 'Page size', :integer,
                     min: 1, max: 100,
                     visibility: 'optional',
                     default: 100,
                     hint: 'Number of records to retrieve per page (1-100). Defaults to 100.'
        schema.field :max_results, 'Max results', :integer,
                     min: 1,
                     visibility: 'optional',
                     hint: 'Maximum total number of records to retrieve. Leave empty to retrieve all records.'
        schema.field :refresh_schema, 'Refresh schema', :boolean,
                     hint: 'Check to clear the cached GraphQL schema and re-fetch it from Xurrent. ' \
                           'Useful after schema changes in the Xurrent environment.',
                     visibility: 'optional',
                     default: false
      end

      input_schema do
        # Built in a helper so schema_data stays out of this block's binding and is
        # never captured by the after_update closure below (stored on the cached Schema).
        helpers.build_query_input_fields(self)
        after_update do |_fields|
          helpers.refresh_dynamic_schemas(self, :object, 'query_result')
        end
      end

      output_schema 'query_result' do
        object_name = action.input&.[](:object)

        if object_name.present?
          schema_data = cache_read('gql_schema')
          helpers.add_query_fields_from_schema_data(self, schema_data, object_name) if schema_data.present?
        end

        field :ratelimit, 'Rate limit', :nested,
              visibility: 'optional' do
          field :limit, 'Limit', :integer
          field :remaining, 'Remaining', :integer
          field :reset, 'Reset', :integer
        end
        field :costlimit, 'Cost limit', :nested,
              visibility: 'optional' do
          field :limit, 'Limit', :integer
          field :cost, 'Cost', :integer
          field :remaining, 'Remaining', :integer
          field :reset, 'Reset', :integer
        end
        field :request_id, 'Request ID', :string,
              visibility: 'optional'
      end

      iteration_state_schema do
        field :end_cursor, 'End cursor', :string, required: true
        field :fetched_count, 'Fetched count', :integer
      end

      run do
        schema_data = helpers.ensure_schema_cached
        object_name = input[:object]
        node_type_name = GqlSchema.gql_resolve_connection_node_type(schema_data, 'query', object_name)
        is_connection = node_type_name.present?

        gql_output = if is_connection
                       helpers.run_connection_query(schema_data, object_name, node_type_name)
                     else
                       helpers.run_simple_query(schema_data, object_name)
                     end

        data = gql_output[:data]
        result = gql_output.except(:data)

        if is_connection
          helpers.process_connection_result(data, object_name, result)
        else
          object_data = data[object_name]
          fail_job!("No data returned for '#{object_name}'") if object_data.blank?
          # Flatten nested connection { nodes => [...] } layers to the arrays
          # declared by the generated schema (connection-shaped results route
          # to process_connection_result, so the flattened value is still a hash here).
          result.merge!(GqlResult.gql_flatten_nodes(object_data)) if object_data.is_a?(Hash)
        end

        [{ output: result, schema_reference: 'query_result' }]
      end

      helper :add_input_fields_from_schema_data do |schema, schema_data, object_name|
        root_field = GqlSchema.gql_find_root_field(schema_data, 'query', object_name)
        gql_args = root_field&.[]('args') || []

        # View field — populated from ENUM arg
        view_arg = helpers.find_gql_arg(gql_args, 'view')
        if view_arg.present?
          view_type_info = GqlSchema.gql_unwrap_type(view_arg['type'])
          if view_type_info[:kind] == 'ENUM'
            enum_type = GqlSchema.gql_find_type(schema_data, view_type_info[:name])
            view_values = enum_type&.[]('enumValues')&.map do |e|
              { id: e['name'], label: Humanize.humanize_field_name(e['name']) }
            end || []
            schema.field :view, 'View', :string, enumeration: view_values
          else
            schema.field :view, 'View', :string
          end
        end

        # Filter field — typed sub-fields from INPUT_OBJECT arg, all optional
        filter_arg = helpers.find_gql_arg(gql_args, 'filter')
        if filter_arg.present?
          filter_type_info = GqlSchema.gql_unwrap_type(filter_arg['type'])
          if filter_type_info[:kind] == 'INPUT_OBJECT'
            schema.field :filter, 'Filter', :nested

            GqlFields.gql_add_dynamic_input_fields(
              schema.field(:filter), schema_data, filter_type_info[:name], 0,
              sort: true,
              visibility: ->(name, _, _) { 'optional' unless name == 'query' },
            )
          end
        end

        # Order field — field ENUM + direction ENUM from INPUT_OBJECT arg
        order_arg = helpers.find_gql_arg(gql_args, 'order')
        if order_arg.present?
          order_type_info = GqlSchema.gql_unwrap_type(order_arg['type'])
          if order_type_info[:kind] == 'INPUT_OBJECT'
            schema.field :order, 'Order', :nested, array: true

            GqlFields.gql_build_order_subfields(schema.field(:order), schema_data, order_type_info[:name])
          end
        end

        # Include fields — update with proper enumeration and sub-sections
        node_type_name = GqlSchema.gql_resolve_connection_node_type(schema_data, 'query', object_name)
        target_type = node_type_name || GqlSchema.gql_resolve_return_type_name(schema_data, 'query', object_name)
        if target_type.present?
          GqlFields.gql_update_include_fields_input(schema, schema_data, target_type, action.input, 0)
        end
      end

      helper :add_query_fields_from_schema_data do |schema, schema_data, object_name|
        node_type_name = GqlSchema.gql_resolve_connection_node_type(schema_data, 'query', object_name)
        if node_type_name.present?
          schema.field :total_count, 'Total count', :integer
          schema.field :has_next_page, 'Has next page', :boolean
          schema.field :nodes, 'Records', :nested, array: true
          GqlFields.gql_add_dynamic_fields(schema.field(:nodes), schema_data, node_type_name, 0,
                                           include_data: action.input)
        else
          # Non-connection return type (single object query)
          return_type_name = GqlSchema.gql_resolve_return_type_name(schema_data, 'query', object_name)
          if return_type_name.present?
            GqlFields.gql_add_dynamic_fields(schema, schema_data, return_type_name, 0, include_data: action.input)
          end
        end
      end

      helper :effective_page_size do
        page_size = input[:page_size]
        max_results = input[:max_results]
        if max_results.present?
          fetched_count = iteration_state_value(:fetched_count).to_i
          remaining = max_results - fetched_count
          page_size = [page_size, remaining].min
        end
        page_size
      end

      helper :run_connection_query do |schema_data, object_name, node_type_name|
        root_field = GqlSchema.gql_find_root_field(schema_data, 'query', object_name)
        gql_args = root_field&.[]('args') || []
        field_selection = GqlQuery.gql_build_field_selection(schema_data, node_type_name, 0, include_data: input)

        var_defs = []
        query_params = ["first: #{helpers.effective_page_size}"]
        variables = {}

        cursor = iteration_state_value(:end_cursor)
        query_params << %(after: "#{cursor}") if cursor.present?

        if input[:view].present?
          view_arg = helpers.find_gql_arg(gql_args, 'view')
          if view_arg
            var_defs << "$view: #{GqlQuery.gql_type_ref_string(view_arg['type'])}"
            query_params << 'view: $view'
            variables['view'] = input[:view]
          end
        end

        filter_hash = CompactHash.compact_hash(input[:filter])
        if filter_hash.present?
          filter_arg = helpers.find_gql_arg(gql_args, 'filter')
          if filter_arg
            var_defs << "$filter: #{GqlQuery.gql_type_ref_string(filter_arg['type'])}"
            query_params << 'filter: $filter'
            variables['filter'] = filter_hash
          end
        end

        if input[:order].present?
          order_arg = helpers.find_gql_arg(gql_args, 'order')
          if order_arg
            var_defs << "$order: #{GqlQuery.gql_type_ref_string(order_arg['type'])}"
            query_params << 'order: $order'
            variables['order'] = input[:order].map do |o|
              { 'field' => o[:field], 'direction' => o[:direction] }
            end
          end
        end

        var_clause = var_defs.any? ? "(#{var_defs.join(', ')})" : ''
        query = <<~GRAPHQL
          query#{var_clause} { #{object_name}(#{query_params.join(', ')}) {
              pageInfo { hasNextPage endCursor }
              totalCount
              nodes { #{field_selection} }
            } }
        GRAPHQL

        helpers.graphql_call(query, variables.presence)
      end

      helper :run_simple_query do |schema_data, object_name|
        return_type_name = GqlSchema.gql_resolve_return_type_name(schema_data, 'query', object_name)
        field_selection = GqlQuery.gql_build_field_selection(schema_data, return_type_name, 0, include_data: input)
        query = "{ #{object_name} { #{field_selection} } }"
        helpers.graphql_call(query)
      end

      helper :process_connection_result do |data, object_name, result|
        max_results = input[:max_results]
        fetched_count = iteration_state_value(:fetched_count).to_i

        query_result = data[object_name]
        fail_job!("No data returned for '#{object_name}'") if query_result.blank?

        nodes = query_result['nodes'] || []
        new_fetched_count = fetched_count + nodes.length

        next_state = helpers.extract_next_iteration_state_value(query_result)
        if next_state && (!max_results || new_fetched_count < max_results)
          next_state[:fetched_count] = new_fetched_count if max_results
          self.iteration_state_value = next_state
        else
          self.iteration_state_value = nil
        end

        result[:total_count] = query_result['totalCount']
        result[:has_next_page] = iteration_state_value.present?
        # Flatten nested connection { nodes => [...] } layers inside the records
        # to the arrays declared by the generated schema; the top-level nodes
        # layer was already unwrapped above.
        result[:nodes] = GqlResult.gql_flatten_nodes(nodes)
      end

      helper :extract_next_iteration_state_value do |query_result|
        end_cursor = query_result.dig('pageInfo', 'endCursor')
        { end_cursor: end_cursor } if end_cursor.present? && query_result.dig('pageInfo', 'hasNextPage')&.to_s == 'true'
      end

      helper :find_gql_arg do |args, name|
        args.detect { |a| a['name'] == name }
      end
    end

    # ──────────────────────────────────────────────
    # Action: Dynamic GraphQL Mutation
    # ──────────────────────────────────────────────

    action '019ce240-76c9-7847-9dfa-a48d104515b3' do
      name 'Xurrent Mutation'
      description <<~DESC
        Execute a Xurrent GraphQL mutation with dynamically generated input and output fields.

        # How it works
        1. Select a **mutation** (e.g. `requestCreate`, `personUpdate`, `noteCreate`). Once you configure the outbound connection, the connector loads the available mutations from the Xurrent GraphQL schema.
        2. Schema introspection generates the input and output fields from the selected mutation.
        3. Provide the mutation input either by mapping individual fields or as a **JSON object**.

        # Attaching files
        To attach files to a record (e.g. a note), first use the **Upload Attachment** action to upload the file. Then use the returned `storage_key` as the `key` value in the mutation's attachment input.

        # Refreshing the schema cache
        The connector caches the GraphQL schema in the connection store after the first introspection. Check **Refresh schema** to clear the cache and re-fetch (e.g. after Xurrent schema changes).
      DESC
      avatar '/assets/icons/x-logo-graphql.svg'

      # Defined before input_schema (which runs eagerly at connector load) so the
      # helper is registered when first called. schema_data stays local to this
      # helper and is never captured by the after_update closure (which lives on
      # the cached Schema) — see build_query_input_fields above.
      helper :build_mutation_input_fields do |schema|
        mutation_name = action.input&.[](:mutation)
        schema_data = cache_read('gql_schema')
        mutation_options = schema_data.present? ? GqlSchema.gql_list_root_fields(schema_data, 'mutation') : []

        if mutation_options.any?
          schema.field :mutation, 'Mutation', :string,
                       enumeration: mutation_options,
                       required: true
        else
          schema.field :mutation, 'Mutation', :string,
                       hint: 'The GraphQL mutation name (e.g. requestCreate, personUpdate, noteCreate).',
                       notice: 'Outbound Connection is not configured correctly.',
                       notice_type: 'error',
                       notice_action: 'edit_connection',
                       pattern: /\A[A-Za-z][A-Za-z0-9]*\z/,
                       required: true
        end

        # Define include_fields early so its value is resolved in the first pass
        schema.field :include_fields, 'Include nested fields', :nested

        if schema_data.present? && mutation_name.present?
          helpers.add_mutation_input_fields(schema, schema_data, mutation_name)
        else
          schema.field :input, 'Input', :hash,
                       hint: 'The mutation input variables as a JSON object.',
                       required: true
        end

        schema.field :refresh_schema, 'Refresh schema', :boolean,
                     hint: 'Check to clear the cached GraphQL schema and re-fetch it from Xurrent. ' \
                           'Useful after schema changes in the Xurrent environment.',
                     visibility: 'optional',
                     default: false
      end

      input_schema do
        # See build_query_input_fields above: building in a helper keeps schema_data
        # out of the after_update closure's binding (which lives on the cached Schema).
        helpers.build_mutation_input_fields(self)
        after_update do |_fields|
          helpers.refresh_dynamic_schemas(self, :mutation, 'mutation_result')
        end
      end

      output_schema 'mutation_result' do
        mutation_name = action.input&.[](:mutation)

        if mutation_name.present?
          schema_data = cache_read('gql_schema')
          helpers.add_mutation_output_fields(self, schema_data, mutation_name) if schema_data.present?
        end

        field :ratelimit, 'Rate limit', :nested,
              visibility: 'optional' do
          field :limit, 'Limit', :integer
          field :remaining, 'Remaining', :integer
          field :reset, 'Reset', :integer
        end
        field :costlimit, 'Cost limit', :nested,
              visibility: 'optional' do
          field :limit, 'Limit', :integer
          field :cost, 'Cost', :integer
          field :remaining, 'Remaining', :integer
          field :reset, 'Reset', :integer
        end
        field :request_id, 'Request ID', :string,
              visibility: 'optional'
      end

      run do
        mutation_name = input[:mutation]
        gql_output = helpers.run_mutation_query(mutation_name)
        mutation_data = gql_output.delete(:data)[mutation_name]
        fail_job!("No data returned for mutation '#{mutation_name}'") if mutation_data.blank?

        # Check for mutation-level errors
        if mutation_data['errors'].is_a?(Array) && mutation_data['errors'].any?
          messages = mutation_data['errors'].filter_map { |e| e['message'] }
          fail_job!("Mutation error: #{messages.join('; ')}") if messages.any?
        end

        # Flatten nested connection { nodes => [...] } layers to the arrays
        # declared by the generated schema (mutation payloads are object
        # types, so the flattened value stays a hash).
        result = gql_output.merge!(GqlResult.gql_flatten_nodes(mutation_data))
        [{ output: result, schema_reference: 'mutation_result' }]
      end

      helper :add_mutation_input_fields do |schema, schema_data, mutation_name|
        input_type_name = GqlSchema.gql_mutation_input_type_name(schema_data, mutation_name)
        input_type = GqlSchema.gql_find_type(schema_data, input_type_name)
        if input_type.present? && input_type['inputFields'].present?
          schema.field :input, 'Input', :nested, required: true
          GqlFields.gql_add_dynamic_input_fields(
            schema.field(:input), schema_data, input_type_name, 0,
            visibility: ->(name, is_required, depth) {
              next if depth > 0 || is_required
              'optional' unless %w[subject name source sourceID note].include?(name)
            },
          )
        else
          schema.field :input, 'Input', :hash,
                       hint: 'The mutation input variables as a JSON object.', required: true
        end

        return_type_name = GqlSchema.gql_resolve_return_type_name(schema_data, 'mutation', mutation_name)
        if return_type_name.present?
          GqlFields.gql_update_include_fields_input(schema, schema_data, return_type_name, action.input, 0)
        end
      end

      helper :add_mutation_output_fields do |schema, schema_data, mutation_name|
        return_type_name = GqlSchema.gql_resolve_return_type_name(schema_data, 'mutation', mutation_name)
        next if return_type_name.blank?

        include_data = helpers.mutation_include_data(schema_data, return_type_name)
        GqlFields.gql_add_dynamic_fields(schema, schema_data, return_type_name, 0,
                                         include_data: include_data)

        # Ensure errors field is always present for mutations
        unless schema.field(:errors)
          schema.field :errors, 'Errors', :nested, array: true, visibility: 'optional' do
            schema.field :message, 'Message', :string
            schema.field :path, 'Path', :string, array: true
          end
        end
      end

      helper :run_mutation_query do |mutation_name|
        schema_data = helpers.ensure_schema_cached
        return_type_name = GqlSchema.gql_resolve_return_type_name(schema_data, 'mutation', mutation_name)
        input_type_name = GqlSchema.gql_mutation_input_type_name(schema_data, mutation_name)

        include_data = helpers.mutation_include_data(schema_data, return_type_name)
        field_selection = GqlQuery.gql_build_field_selection(
          schema_data, return_type_name, 0,
          include_data: include_data
        )

        mutation = "mutation($input: #{input_type_name}!) { #{mutation_name}(input: $input) { #{field_selection} } }"
        helpers.graphql_call(mutation, { input: input[:input] })
      end

      # Merges the user's include_fields with the mutation's top-level nested
      # payload fields, ensuring they are always included in output and query.
      helper :mutation_include_data do |schema_data, return_type_name|
        payload_fields = GqlSchema.gql_collect_fields(schema_data, return_type_name)
        top_level = payload_fields.filter_map do |f|
          type_info = GqlSchema.gql_unwrap_type(f['type'])
          f['name'] if GqlSchema.gql_to_ipaas_type(type_info) == :nested
        end

        user_includes = input[:include_fields]
        user_includes = {} unless user_includes.is_a?(Hash)
        merged = user_includes.to_hash
        top_level.each { |name| merged[name.to_sym] = true unless merged.key?(name.to_sym) }

        input.to_hash.merge(include_fields: merged)
      end
    end

    # ──────────────────────────────────────────────
    # Action: Upload Attachment
    # ──────────────────────────────────────────────

    action '019ce240-76c9-7f7c-9ed7-2a07c3133f2e' do
      name 'Upload Attachment'
      description <<~DESC
        Upload a file to Xurrent storage and return a storage key for use in subsequent mutations.

        # How it works
        1. The action queries the `attachmentStorage` endpoint for upload credentials and a pre-signed upload URI.
        2. The connector uploads the file directly to the storage provider (`s3` or `local`) via multipart POST per RFC 2388.
        3. The returned **storage key** identifies the uploaded file.

        # Using the storage key
        Use the `storage_key` output as the `key` value in any mutation that accepts `AttachmentInput`. For example, when creating a note with an attachment via `noteCreate`, map the `storage_key` to the attachment's `key` field.

        # Content type detection
        If you don't provide a content type, the connector derives it from the file name extension.
      DESC
      avatar '/assets/icons/x-logo-graphql.svg'

      input_schema do
        field :file_name, 'File name', :string,
              hint: 'Name of the file including extension (e.g. report.pdf).',
              required: true
        field :file_content, 'File content', :binary,
              hint: 'The binary content of the file to upload.',
              required: true
        field :content_type, 'Content type', :string,
              hint: 'MIME type of the file (e.g. application/pdf). If omitted, derived from file name.',
              visibility: 'optional'
      end

      output_schema do
        field :storage_key, 'Storage key', :string,
              hint: 'The storage key of the uploaded file. Use this in mutations to attach the file.',
              required: true
        field :size, 'File size', :integer
        field :ratelimit, 'Rate limit', :nested,
              visibility: 'optional' do
          field :limit, 'Limit', :integer
          field :remaining, 'Remaining', :integer
          field :reset, 'Reset', :integer
        end
        field :request_id, 'Request ID', :string,
              visibility: 'optional'
      end

      run do
        content_type = input[:content_type].presence || IPaaS::Job::ContentType.detect_content_type(input[:file_name])

        gql_output, upload_uri, provider, provider_params = helpers.fetch_attachment_storage

        # Build the multipart form
        # All values must be strings for the multipart_post framework method.
        form_data = { 'Content-Type' => content_type }.tap do |data|
          provider_params.each { |key, value| data[key.to_s] = value.to_s }
          data['file'] = IPaaS::Job::Outbound::HTTP.create_binary_part(
            input[:file_name], content_type, input[:file_content]
          )
        end

        response = multipart_post(upload_uri, form_data, skip_authentication: true)
        unless [200, 201, 204].include?(response.status)
          fail_job!("Upload failed (#{provider}): #{response.status} #{response.body}")
        end

        storage_key = helpers.extract_storage_key(provider, response)

        [{ output: {
          storage_key: storage_key,
          size: input[:file_content].size,
          ratelimit: gql_output[:ratelimit],
          request_id: gql_output[:request_id],
        } }]
      end

      helper :fetch_attachment_storage do
        cached = cache_read('attachment_storage')
        next cached if cached.present?

        storage_query = <<~GRAPHQL
          query {
            attachmentStorage {
              uploadUri
              provider
              providerParameters
              sizeLimit
              allowedExtensions
            }
          }
        GRAPHQL

        gql_output = helpers.graphql_call(storage_query)
        storage = gql_output[:data]['attachmentStorage']
        fail_job!('No attachment storage info returned') if storage.blank?

        upload_uri = storage['uploadUri']
        provider = storage['provider']
        provider_params = storage['providerParameters'] || {}
        fail_job!('No upload URI returned') if upload_uri.blank?

        result = [gql_output, upload_uri, provider, provider_params]
        cache_write('attachment_storage', result, 60)
        result
      end

      helper :extract_storage_key do |provider, response|
        key = if provider == 's3'
                # S3 returns XML with a <Key> element
                response.body.match(%r{<Key>(.+?)</Key>})&.[](1)
              else
                # Local provider returns JSON with a 'key' property
                begin
                  JSON.parse(response.body)['key']
                rescue StandardError
                  nil
                end
              end
        fail_job!('Could not extract storage key from upload response') if key.blank?
        key
      end
    end

    # ──────────────────────────────────────────────
    # Connector-level Helpers: Schema Introspection
    # ──────────────────────────────────────────────

    # Shared after_update logic for query and mutation actions:
    # clears the schema cache if requested, fetches the schema, and regenerates schemas.
    helper :refresh_dynamic_schemas do |context, selection_field, output_schema_ref|
      if action.input&.[](:refresh_schema)
        cache_clear('gql_schema')
        cache_clear('_schema_present')
        cache_clear(helpers.introspection_failure_cache_key)
      end
      begin
        helpers.ensure_schema_cached
      rescue StandardError => e
        log("Schema introspection failed: #{e.message}")
      end
      context.regenerate_schema(context.output_schema(output_schema_ref)) if action.input&.[](selection_field).present?
      context.regenerate_schema(context.input_schema)
    end

    # Returns the cached schema data, fetching it if needed.
    # `_schema_present` is a lightweight boolean flag that avoids deserializing
    # the full schema JSON on every call. When set, we skip the JSON parse check
    # and return the cached schema directly.
    helper :ensure_schema_cached do
      next cache_read('gql_schema') if cache_read('_schema_present') == true

      cached = cache_read('gql_schema')
      if cached.present?
        cache_write('_schema_present', true, 3600)
        next cached
      end

      # failures are cached to limit the number of API calls
      cached_failure = cache_read(helpers.introspection_failure_cache_key)
      fail_job!(cached_failure) if cached_failure.present?

      schema_data = helpers.fetch_introspection_schema
      fail_job!('No schema data from introspection') if schema_data.blank?

      cache_write('gql_schema', schema_data, 3600)
      cache_write('_schema_present', true, 3600)
      schema_data
    end

    # Performs the introspection HTTP call and, on failure, records a negative
    # cache entry.
    helper :fetch_introspection_schema do
      response = begin
        helpers.graphql_call_impl(IPaaS::Job::GraphQL::Schema::INTROSPECTION_QUERY)
      rescue IPaaS::Job::RescheduleJob
        # A backoff (429/503) is a transient signal raised upstream, not cached.
        raise
      rescue IPaaS::Job::Outbound::CustomerCredentialsError => e
        # OAuth credential rejection (401/403/known-400) raises before any GraphQL
        # response. Deterministic config failure; message is credential-free.
        helpers.record_introspection_failure(e.message, INTROSPECTION_FAILURE_TTL)
      rescue IPaaS::Error => e
        # Other auth errors (e.g. a 5xx from the OAuth token endpoint) are transient.
        helpers.record_introspection_failure(e.message, INTROSPECTION_TRANSIENT_FAILURE_TTL)
      end

      if response.status != 200
        # PAT connections make no token call, so a bad credential surfaces as a non-200 response.
        deterministic = response.status >= 400 && response.status < 500
        ttl = deterministic ? INTROSPECTION_FAILURE_TTL : INTROSPECTION_TRANSIENT_FAILURE_TTL
        helpers.record_introspection_failure("HTTP error from Xurrent GraphQL API: #{response.status} " \
                                             "'#{response.body}'", ttl)
      end
      helpers.extract_data_from_graphql_response(response)['__schema']
    end

    # Writes the bounded failure message to the negative cache keyed by the auth
    # tuple and fails the job with it. The message is capped because it is
    # re-logged on every cache hit for the TTL; the message never contains credentials.
    helper :record_introspection_failure do |message, ttl|
      bounded = message.to_s[0, INTROSPECTION_FAILURE_MESSAGE_LIMIT]
      cache_write(helpers.introspection_failure_cache_key, bounded, ttl)
      fail_job!(bounded)
    end

    # Builds a stable, secret-safe negative-cache key from the elements that
    # determine whether introspection is authorized.
    helper :introspection_failure_cache_key do
      credentials = outbound_connection.config[:credentials] || {}
      client_secret = credentials[:client_secret].present? ? decrypt_secret_string(credentials[:client_secret]) : ''
      personal_access_token =
        credentials[:personal_access_token].present? ? decrypt_secret_string(credentials[:personal_access_token]) : ''
      account_id = credentials[:account_id].presence || helpers.system_account_id
      tuple = [
        helpers.graphql_endpoint, # for actual introspection
        helpers.oauth_endpoint, # to get client-credential token
        account_id,
        credentials[:client_id],
        client_secret,
        personal_access_token,
      ].join("\n")
      "introspection_failure_#{Digest::SHA256.hexdigest(tuple)}"
    end

    # ──────────────────────────────────────────────
    # Connector-level Helpers: Schema Field Caching
    # ──────────────────────────────────────────────

    helper :collect_field_descriptors do |fields|
      fields.map do |f|
        desc = { 'id' => f.id.to_s, 'label' => f.label, 'type' => f.type.to_s }
        desc['array'] = true if f.array
        desc['required'] = true if f.required
        desc['hint'] = f.hint if f.hint.present?
        desc['visibility'] = f.visibility if f.visibility && f.visibility != 'visible'
        if f.enumeration.present?
          desc['enumeration'] = f.enumeration.map { |e| { 'id' => e[:id].to_s, 'label' => e[:label].to_s } }
        end
        sub_fields = f.fields
        desc['fields'] = helpers.collect_field_descriptors(sub_fields) if sub_fields.is_a?(Array) && sub_fields.any?
        desc
      end
    end

    helper :restore_fields_from_descriptors do |target, descriptors|
      descriptors.each do |desc|
        opts = {}
        opts[:array] = desc['array'] if desc['array']
        opts[:required] = desc['required'] if desc['required']
        opts[:hint] = desc['hint'] if desc['hint']
        opts[:visibility] = desc['visibility'] if desc['visibility']
        if desc['enumeration'].present?
          opts[:enumeration] = desc['enumeration'].map { |e| { id: e['id'], label: e['label'] } }
        end
        target.field desc['id'].to_sym, desc['label'], desc['type'].to_sym, **opts
        if desc['fields'].present?
          parent_field = target.field(desc['id'].to_sym)
          helpers.restore_fields_from_descriptors(parent_field, desc['fields'])
        end
      end
    end

    # ──────────────────────────────────────────────
    # Connector-level Helpers: GraphQL Execution
    # ──────────────────────────────────────────────

    helper :graphql_call do |query, variables = nil, operation_name = nil|
      request_body = { query: query.gsub(/\s+/, ' ').strip }
      request_body[:variables] = helpers.decrypt_secret_strings_in_variables(variables) if variables.present?
      request_body[:operationName] = operation_name if operation_name.present?

      response = helpers.graphql_call_impl(request_body.to_json)

      {}.tap do |output|
        output[:data] = helpers.extract_data_from_graphql_response(response)
        output[:request_id] = response.headers['x-request-id']
        output[:ratelimit] = xurrent_rate_limit_from_headers(response)
        output[:costlimit] = xurrent_cost_limit_from_headers(response)
      end
    end

    helper :graphql_call_impl do |request_body|
      response = http_post(helpers.graphql_endpoint, request_body, { 'content-type' => 'application/json' })
      backoff_if_needed(response, api_name: 'Xurrent')

      response
    end

    helper :decrypt_secret_strings_in_variables do |value|
      case value
      when Hash
        value.to_hash.transform_values { |v| helpers.decrypt_secret_strings_in_variables(v) }
      when Array
        value.map { |v| helpers.decrypt_secret_strings_in_variables(v) }
      when IPaaS::Encryption::SecretString
        decrypt_secret_string(value)
      else
        value
      end
    end

    helper :extract_data_from_graphql_response do |response|
      fail_job!("HTTP error from Xurrent GraphQL API: #{response.status} '#{response.body}'") if response.status != 200

      body = JSON.parse(response.body)
      fail_job!("Errors from Xurrent GraphQL API: #{body['errors'].to_json}") if body['errors'].present?

      data = body['data']
      fail_job!('No data from Xurrent GraphQL API') if data.blank?
      data
    end

    # ──────────────────────────────────────────────
    # Connector-level Helpers: Connection Endpoints
    # ──────────────────────────────────────────────

    ENDPOINT_DEFAULTS = {
      oauth: { config_key: :oauth2_endpoint, system_var: :xurrent_ipaas_oauth_endpoint,
               subdomain: 'oauth', suffix: '/token', }.freeze,
      graphql: { config_key: :graphql_endpoint, system_var: :xurrent_ipaas_graphql_endpoint,
                 subdomain: 'graphql', suffix: '', }.freeze,
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

    helper :graphql_endpoint do
      helpers.endpoint_for(:graphql)
    end

    helper :xurrent_domain do
      env = outbound_connection.config[:environment] || {}
      stage_domain = case env[:stage]
                     when 'Demo' then 'xurrent-demo.com'
                     when 'QA' then 'xurrent.qa'
                     else 'xurrent.com'
                     end
      if env[:stage] != 'Demo' && env[:region]
        "#{env[:region]}.#{stage_domain}"
      else
        stage_domain
      end
    end

    helper :system_xurrent_domain do
      environment[:xurrent_ipaas_domain]
    end

    helper :system_account_id do
      environment[:xurrent_ipaas_account_id]
    end
  end
end
