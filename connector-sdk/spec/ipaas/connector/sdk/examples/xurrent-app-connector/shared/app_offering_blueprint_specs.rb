module AppOfferingBlueprintSpecs
  SECOND_SCOPE_ID = 842

  def self.included(base)
    base.class_eval do
      describe 'blueprint' do
        before(:each) do
          stub_xurrent_oauth2_token(outbound_connection_config)
        end

        let(:endpoint) do
          outbound_connection_config[:environment][:graphql_endpoint]
        end

        let(:trigger_config) do
          {
            event: 'app_instance.create',
            app_reference: 'yoda',
          }
        end

        let(:find_app_offering_query) do
          <<~END_OF_GRAPHQL
              query($reference: String, $published: Boolean) {
                appOfferings(first: 1, filter: { published: $published, reference: { values: [$reference] } } ) {
                  nodes {
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
                }
              }
            }
          END_OF_GRAPHQL
        end

        let(:yoda_app_offering) do
          {
            id: 'app-offering-id',
            name: 'Yoda Translate',
            reference: 'yoda',
            cardDescription: 'Ask Yoda to translate all your notes.',
            description: 'A long description of Yoda',
            descriptionAttachments: { nodes: [] },
            pictureUri: 'https://cdn.pixabay.com/photo/2015/12/13/12/58/yoda-1091030_1280.jpg',
            features: 'Feature description',
            featuresAttachments: { nodes: [] },
            compliance: 'Compliance description',
            serviceInstance: { name: 'Conference Rooms Houston' },
            webhookUriTemplate: 'https://company.org/webhook',
            configurationUriTemplate: 'https://company.org/configuration',
            oauthAuthorizationEndpoints: 'https://company.org/oauth',
            policyJwtAlg: 'rs512',
            policyJwtAudience: 'audience',
            policyJwtClaimExpiresIn: 3600,
            requiresEnabledOauthPerson: false,
            openidConnectDiscovery: false,
            scopes: [
              {
                id: 841,
                actions: ['request:Read', 'affected-sla:Read'],
                effect: 'allow',
                grantType: 'client_credentials',
              },
            ],
            uiExtensionVersion: {
              id: 'ui-extension-version-id',
              css: nil,
              html: 'Very simple UI extension',
              javascript: nil,
              formDefinition: nil,
              uiExtension: {
                id: 'ui-extension-id',
                category: 'app_offering',
                description: nil,
                name: 'xurrent_apps_statuscast',
                title: 'StatusCast Configuration',
              },
            },
            automationRules: {
              nodes: [
                {
                  actions: [
                    {
                      name: 'action1',
                      value: "add note 'Automated completion note'",
                    },
                  ],
                  id: 'automation-rule-id',
                  condition: 'is_completed',
                  description: nil,
                  expressions: [
                    {
                      name: 'is_completed',
                      value: 'status = completed',
                    },
                  ],
                  generic: 'request',
                  name: 'Automated note on completion',
                  trigger: 'on status update',
                },
              ],
            },
          }.with_indifferent_access
        end

        let(:yoda_app_offering_blueprint) do
          blueprint = yoda_app_offering.deep_dup
          blueprint.delete(:id)
          blueprint.delete(:automationRules)
          blueprint[:source] = 'Xurrent App Connector'
          blueprint[:sourceID] = trigger.runbook.uuid
          blueprint[:newScopes] = blueprint.delete(:scopes)
          blueprint[:newScopes].each { |new_scope| new_scope.delete('id') }
          blueprint.delete(:uiExtensionVersion)
          blueprint.delete(:pictureUri)
          blueprint[:avatar_file_name] = 'yoda-1091030_1280.jpg'
          blueprint[:avatar] = Base64.encode64(File.binread(avatar_image_fixture_location))
          blueprint[:webhookUriTemplate] = 'https://test.com'
          blueprint.to_json
        end

        let(:yoda_ui_extension_blueprint) do
          {
            category: 'app_offering',
            description: nil,
            name: 'xurrent_apps_statuscast',
            title: 'StatusCast Configuration',
            css: nil,
            html: 'Very simple UI extension',
            javascript: nil,
            activate: true,
            source: 'Xurrent App Connector',
            sourceID: trigger.runbook.uuid,
          }.to_json
        end

        let(:yoda_automation_rules_blueprint) do
          [
            {
              actions:
                [
                  { name: 'action1', value: "add note 'Automated completion note'" },
                ],
              condition: 'is_completed',
              description: nil,
              expressions:
              [
                { name: 'is_completed', value: 'status = completed' },
              ],
              generic: 'request',
              name: 'Automated note on completion',
              trigger: 'on status update',
            },
          ].to_json
        end

        def avatar_to_picture_uri(input)
          base64_content = input.delete(:avatar)
          _ = input.delete(:avatar_file_name)
          "data:image/jpeg;base64,#{base64_content.delete("\n")}"
        end

        let(:yoda_app_offering_upsert_input) do
          input = JSON.parse(yoda_app_offering_blueprint).with_indifferent_access
          input.delete(:serviceInstance)
          input[:serviceInstanceId] = 513
          input[:uiExtensionId] = 'ui-extension-id'
          input[:uiExtensionVersionId] = 'ui-extension-version-id'
          input[:pictureUri] = avatar_to_picture_uri(input)
          input[:webhookUriTemplate] = "#{trigger.endpoint}?customer_account_id={account}"
          input
        end

        let(:yoda_app_offering_insert_output) do
          output = yoda_app_offering
          output.delete(:pictureUri)
          output[:automationRules][:nodes] = []
          output.delete(:webhookUriTemplate)
          output
        end

        let(:find_app_offering_response) do
          {
            appOfferings: {
              nodes: [
                yoda_app_offering,
              ],
            },
          }.with_indifferent_access
        end

        let(:find_app_offering_without_automation_rules_response) do
          {
            appOfferings: {
              nodes: [
                yoda_app_offering.except('automationRules'),
              ],
            },
          }.with_indifferent_access
        end

        let(:find_app_offering_stub) do
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(find_app_offering_query,
                                             variables: { reference: 'yoda', published: false },),
                  headers: { 'content-type' => 'application/json' })
            .to_return(body: { data: find_app_offering_response }.to_json)
        end

        let(:avatar_image_fixture_location) do
          File.new('spec/ipaas/connector/sdk/examples/xurrent-app-connector/shared/my-yoda.jpg')
        end

        let(:download_avatar_stub) do
          stub_request(:get, 'https://cdn.pixabay.com/photo/2015/12/13/12/58/yoda-1091030_1280.jpg')
            .with do |request|
            expect(request.headers.key?('Authorization')).to be_falsey
            expect(request.headers.key?('X-Xurrent-Account')).to be_falsey
          end.to_return(body: File.new(avatar_image_fixture_location), status: 200)
        end

        let(:find_app_offering_with_two_scopes_stub) do
          response = find_app_offering_response
          response[:appOfferings][:nodes].first[:scopes] << {
            id: SECOND_SCOPE_ID,
            actions: ['request:Update'],
            effect: 'allow',
            grantType: 'client_credentials',
          }

          stub_request(:post, endpoint)
            .with(body: graphql_request_body(find_app_offering_query,
                                             variables: { reference: 'yoda', published: false },))
            .to_return(body: { data: response }.to_json)
        end

        let(:find_app_offering_with_two_automation_rules_stub) do
          response = find_app_offering_response
          automation_rules = response[:appOfferings][:nodes].first[:automationRules][:nodes]
          automation_rules << {
            actions: [
              {
                name: 'action1',
                value: "set source 'My source'",
              },
            ],
            id: 'automation-rule-id-2',
            condition: 'true',
            description: nil,
            expressions: [
              {
                name: 'is_truthy',
                value: 'true',
              },
            ],
            generic: 'request',
            name: 'Second rule',
            trigger: 'on impact update',
          }

          stub_request(:post, endpoint)
            .with(body: graphql_request_body(find_app_offering_query,
                                             variables: { reference: 'yoda', published: false },))
            .to_return(body: { data: response }.to_json)
        end

        let(:find_no_app_offering_response) do
          {
            appOfferings: {
              nodes: [],
            },
          }.with_indifferent_access
        end

        let(:find_no_app_offering_stub) do
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(find_app_offering_query,
                                             variables: { reference: 'yoda', published: false },))
            .to_return(
              { body: { data: find_no_app_offering_response }.to_json },
              { body: { data: find_app_offering_without_automation_rules_response }.to_json },
              { body: { data: find_app_offering_without_automation_rules_response }.to_json }
            )
        end

        let(:find_app_offering_id_query) do
          <<~END_OF_GRAPHQL
            query($reference: String!) {
              appOfferings(first: 1, filter: { reference: { values: [$reference] } }) {
                nodes {
                  id
                }
              }
            }
          END_OF_GRAPHQL
        end

        let(:find_app_offering_id_stub) do
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(find_app_offering_id_query,
                                             variables: { reference: 'yoda' },))
            .to_return(body: { data: find_app_offering_response }.to_json)
        end

        let(:find_ui_extension_response) do
          {
            uiExtensions: {
              nodes: [
                { id: 'ui-extension-id' },
              ],
            },
          }.with_indifferent_access
        end

        let(:find_no_ui_extension_response) do
          {
            uiExtensions: {
              nodes: [],
            },
          }.with_indifferent_access
        end

        let(:find_ui_extension_by_source) do
          <<~END_OF_GRAPHQL
            query($source: String!, $sourceID: String!) {
              uiExtensions(first: 1, filter: { source: { values: [$source] }, sourceID: { values: [$sourceID] } }) {
                nodes {
                  id
                }
              }
            }
          END_OF_GRAPHQL
        end

        let(:find_no_ui_extension_by_source_stub) do
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(find_ui_extension_by_source,
                                             variables: { source: 'Xurrent App Connector',
                                                          sourceID: trigger.runbook.uuid, },))
            .to_return(body: { data: find_no_ui_extension_response }.to_json)
        end

        let(:find_ui_extension_by_source_stub) do
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(find_ui_extension_by_source,
                                             variables: { source: 'Xurrent App Connector',
                                                          sourceID: trigger.runbook.uuid, },))
            .to_return(body: { data: find_ui_extension_response }.to_json)
        end

        let(:find_service_instances_query) do
          <<~END_OF_GRAPHQL
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
        end

        let(:find_service_instances_response) do
          {
            serviceInstances: {
              nodes: [
                {
                  id: 513,
                }.with_indifferent_access,
              ],
            },
          }.with_indifferent_access
        end

        let(:find_service_instances_stub) do
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(find_service_instances_query,
                                             variables: { name: 'Conference Rooms Houston' },))
            .to_return(body: { data: find_service_instances_response }.to_json)
        end

        def upsert_app_offering_query(input_type, operation)
          <<~END_OF_GRAPHQL
            mutation($input: #{input_type}!) {
              #{operation}(input: $input) {
                appOffering {
                  id
                }
                errors {
                  path
                  message
                }
              }
            }
          END_OF_GRAPHQL
        end

        let(:create_app_offering_query) do
          <<~END_OF_GRAPHQL
            mutation($input: AppOfferingCreateInput!) {
              appOfferingCreate(input: $input) {
                errors { path message }
                appOffering {
                  id name reference cardDescription description
                  descriptionAttachments(first: 100) { nodes { key inline expiringUrl } }
                  pictureUri features
                  featuresAttachments(first: 100) { nodes { key inline expiringUrl } }
                  compliance serviceInstance { name }
                  webhookUriTemplate configurationUriTemplate oauthAuthorizationEndpoints
                  policyJwtAlg policyJwtAudience policyJwtClaimExpiresIn requiresEnabledOauthPerson openidConnectDiscovery
                  scopes { id actions effect grantType }
                  uiExtensionVersion {
                    id css html javascript formDefinition
                    uiExtension { id category description name title }
                  }
                  automationRules(first: 100) {
                    nodes {
                      actions { name value }
                      id condition description
                      expressions { name value }
                      generic name trigger
                    }
                   }
                  }
                }
              }
          END_OF_GRAPHQL
        end

        let(:update_app_offering_query) do
          upsert_app_offering_query('AppOfferingUpdateInput', 'appOfferingUpdate')
        end

        def upsert_app_offering_response(operation, additional_field_content = {})
          {
            operation => {
              appOffering: {
                id: 'app-offering-id',
              }.merge(additional_field_content),
            },
          }.with_indifferent_access
        end

        def create_app_offering_response(additional_field_content = {})
          upsert_app_offering_response('appOfferingCreate', additional_field_content)
        end

        let(:update_app_offering_response) do
          upsert_app_offering_response('appOfferingUpdate')
        end

        let(:create_app_offering_stub) do
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(create_app_offering_query,
                                             variables: { input: yoda_app_offering_upsert_input },))
            .to_return(body: { data: create_app_offering_response(yoda_app_offering_insert_output) }.to_json)
        end

        def update_app_offering_stub(input = yoda_app_offering_upsert_input)
          to_send = { id: 'app-offering-id' }.merge(input).with_indifferent_access
          to_send[:newScopes][0][:id] = 841

          stub_request(:post, endpoint)
            .with(body: graphql_request_body(update_app_offering_query,
                                             variables: { input: to_send },))
            .to_return(body: { data: update_app_offering_response }.to_json)
        end

        def reorder_keys_to_end(hash, *keys)
          values = hash.slice(*keys)      # Get the key-value pairs to move
          hash.except(*keys).merge(values) # Remove the keys and merge them back at the end
        end

        let(:update_app_offering_with_deleted_scope_stub) do
          input = yoda_app_offering_upsert_input.except(:webhookUriTemplate)
          input[:newScopes][0][:id] = 841
          input[:scopesToDelete] = [SECOND_SCOPE_ID]
          input = reorder_keys_to_end(input, :uiExtensionId, :uiExtensionVersionId)
          to_send = { id: 'app-offering-id' }.merge(input)
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(update_app_offering_query,
                                             variables: { input: to_send },))
            .to_return(body: { data: update_app_offering_response }.to_json)
        end

        def yoda_ui_extension_upsert_input(operation)
          input = JSON.parse(yoda_ui_extension_blueprint).with_indifferent_access
          if operation == :update
            input.delete(:category)
            input[:id] = 'ui-extension-id'
          end
          input
        end

        def upsert_ui_extension_query(input_type, operation)
          <<~END_OF_GRAPHQL
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
        end

        let(:create_ui_extension_query) do
          upsert_ui_extension_query('UiExtensionCreateInput', 'uiExtensionCreate')
        end

        let(:update_ui_extension_query) do
          upsert_ui_extension_query('UiExtensionUpdateInput', 'uiExtensionUpdate')
        end

        def upsert_ui_extension_response(operation)
          {
            operation => {
              uiExtension: {
                id: 'ui-extension-id',
                activeVersion: { id: 'ui-extension-version-id' },
              },
            },
          }.with_indifferent_access
        end

        let(:create_ui_extension_response) do
          upsert_ui_extension_response('uiExtensionCreate')
        end

        let(:update_ui_extension_response) do
          upsert_ui_extension_response('uiExtensionUpdate')
        end

        let(:create_ui_extension_stub) do
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(create_ui_extension_query,
                                             variables: { input: yoda_ui_extension_upsert_input(:create) },))
            .to_return(body: { data: create_ui_extension_response }.to_json)
        end

        let(:update_ui_extension_stub) do
          yoda_ui_extension_upsert_input(:update)
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(update_ui_extension_query,
                                             variables: { input: yoda_ui_extension_upsert_input(:update) },))
            .to_return(body: { data: update_ui_extension_response }.to_json)
        end

        let(:yoda_automation_rule_upsert_input) do
          input = JSON.parse(yoda_automation_rules_blueprint).first.with_indifferent_access
          input
        end

        def upsert_automation_rule_query(input_type, operation)
          <<~END_OF_GRAPHQL
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

        let(:create_automation_rule_query) do
          upsert_automation_rule_query('AppOfferingAutomationRuleCreateInput', 'appOfferingAutomationRuleCreate')
        end

        let(:update_automation_rule_query) do
          upsert_automation_rule_query('AppOfferingAutomationRuleUpdateInput', 'appOfferingAutomationRuleUpdate')
        end

        def upsert_automation_rule_response(operation)
          {
            operation => {}, # empty response
          }
        end

        let(:create_automation_rule_response) do
          upsert_automation_rule_response('uiExtensionCreate')
        end

        let(:update_automation_rule_response) do
          upsert_automation_rule_response('uiExtensionUpdate')
        end

        let(:create_automation_rule_stub) do
          yoda_automation_rule_upsert_input[:appOfferingId] = 'app-offering-id'
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(create_automation_rule_query,
                                             variables: { input: yoda_automation_rule_upsert_input },))
            .to_return(body: { data: create_automation_rule_response }.to_json)
        end

        let(:update_automation_rule_stub) do
          yoda_automation_rule_upsert_input[:id] = 'automation-rule-id'
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(update_automation_rule_query,
                                             variables: { input: yoda_automation_rule_upsert_input },))
            .to_return(body: { data: update_automation_rule_response }.to_json)
        end

        let(:update_app_offering_webhook_uri_query) do
          <<~END_OF_GRAPHQL
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

        let(:update_app_offering_webhook_uri_response) do
          {
            appOfferingUpdate: {
              appOffering: {
                id: 'app-offering-id',
              },
            },
          }.with_indifferent_access
        end

        let(:update_app_offering_configuration_uri_stub) do
          variables = {
            input: {
              id: 'app-offering-id',
              configurationUriTemplate: trigger.config[:configuration_uri_template],
            },
          }
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(update_app_offering_webhook_uri_query, variables: variables))
            .to_return(body: { data: update_app_offering_webhook_uri_response }.to_json)
        end

        let(:update_app_offering_webhook_uri_stub) do
          variables = {
            input: {
              id: 'app-offering-id',
              webhookUriTemplate: "#{trigger.endpoint}?customer_account_id={account}",
            },
          }
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(update_app_offering_webhook_uri_query, variables: variables))
            .to_return(body: { data: update_app_offering_webhook_uri_response }.to_json)
        end

        def delete_automation_rule_query
          <<~END_OF_GRAPHQL
            mutation($input: AppOfferingAutomationRuleDeleteMutationInput!) {
              appOfferingAutomationRuleDelete(input: $input) {
                errors {
                  path
                  message
                }
              }
            }
          END_OF_GRAPHQL
        end

        def delete_automation_rule_response
          {
            'uiExtensionDelete' => {}, # empty response
          }
        end

        let(:delete_automation_rule_stub) do
          delete_automation_rule_input = { id: 'automation-rule-id-2' }
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(delete_automation_rule_query,
                                             variables: { input: delete_automation_rule_input },))
            .to_return(body: { data: delete_automation_rule_response }.to_json)
        end

        let(:attachment_storage_query) do
          <<~END_OF_GRAPHQL
            query {
              attachmentStorage {
                sizeLimit
                allowedExtensions
                uploadUri
                provider
                providerParameters
              }
            }
          END_OF_GRAPHQL
        end

        let(:attachment_storage_response) do
          {
            attachmentStorage: {
              sizeLimit: 10_485_760,
              allowedExtensions: %w[jpg png gif],
              uploadUri: 'https://upload.example.com/upload',
              provider: 's3',
              providerParameters: {
                'key' => 'test-key',
                'policy' => 'test-policy',
              },
            },
          }.with_indifferent_access
        end

        let(:attachment_storage_stub) do
          stub_request(:post, endpoint)
            .with(body: graphql_request_body(attachment_storage_query))
            .to_return(body: { data: attachment_storage_response }.to_json)
        end

        context 'extract' do
          before(:each) do
            allow(trigger.helpers).to receive(:extract_inline_images).and_return(nil)
            allow(trigger.helpers).to receive(:upload_inline_images).and_return(nil)
          end

          it 'should extract the app offering json' do
            download_avatar_stub
            find_app_offering_stub

            trigger.extract_blueprint

            expect(find_app_offering_stub).to have_been_requested.once

            stored_app_offering = JSON.parse(trigger.blueprint_store.read('app_offering.json'))
            expect(stored_app_offering.to_a).to contain_exactly(*JSON.parse(yoda_app_offering_blueprint).to_a)

            stored_ui_extension = JSON.parse(trigger.blueprint_store.read('app_offering_ui_extension.json'))
            expect(stored_ui_extension).to eq(JSON.parse(yoda_ui_extension_blueprint))

            stored_automation_rules = JSON.parse(trigger.blueprint_store.read('app_offering_automation_rules.json'))
            expect(stored_automation_rules).to eq(JSON.parse(yoda_automation_rules_blueprint))
          end

          it 'should extract the app offering json when app offering has no scopes' do
            app_offering_without_scopes = yoda_app_offering.deep_dup
            app_offering_without_scopes.delete(:scopes)

            stub_request(:post, endpoint)
              .with(body: graphql_request_body(find_app_offering_query,
                                               variables: { reference: 'yoda', published: false },))
              .to_return(body: { data: { appOfferings: { nodes: [app_offering_without_scopes] } } }.to_json)

            stub_request(:get, 'https://cdn.pixabay.com/photo/2015/12/13/12/58/yoda-1091030_1280.jpg')
              .to_return(body: 'fake_avatar_data', status: 200)

            expect { trigger.extract_blueprint }.not_to raise_error

            stored_app_offering = JSON.parse(trigger.blueprint_store.read('app_offering.json'))
            expect(stored_app_offering).not_to have_key('newScopes')
          end

          it 'should extract inline images from app offering attachments' do
            test_app_offering = yoda_app_offering.deep_dup
            test_app_offering[:featuresAttachments] = {
              nodes: [
                {
                  key: 'attachments/test_image.jpg',
                  inline: true,
                  expiringUrl: 'https://example.com/test_image.jpg',
                },
              ],
            }
            test_app_offering[:descriptionAttachments] = {
              nodes: [
                {
                  key: 'attachments/desc_image.png',
                  inline: false,
                  expiringUrl: 'https://example.com/desc_image.png',
                },
              ],
            }

            stub_request(:post, endpoint)
              .with(body: graphql_request_body(find_app_offering_query,
                                               variables: { reference: 'yoda', published: false },))
              .to_return(body: { data: { appOfferings: { nodes: [test_app_offering] } } }.to_json)

            stub_request(:get, 'https://cdn.pixabay.com/photo/2015/12/13/12/58/yoda-1091030_1280.jpg')
              .to_return(body: 'fake_avatar_data', status: 200)

            stub_request(:get, 'https://example.com/test_image.jpg')
              .to_return(body: 'fake_image_data_1', status: 200)
            stub_request(:get, 'https://example.com/desc_image.png')
              .to_return(body: 'fake_image_data_2', status: 200)

            allow(trigger.helpers).to receive(:extract_inline_images).and_call_original

            trigger.extract_blueprint

            expect(trigger.helpers).to have_received(:extract_inline_images).with(an_instance_of(Hash))
          end
        end

        context 'apply' do
          before(:each) do
            trigger.blueprint_store.write('app_offering.json', yoda_app_offering_blueprint)
            trigger.blueprint_store.write('app_offering_ui_extension.json', yoda_ui_extension_blueprint)
            trigger.blueprint_store.write('app_offering_automation_rules.json', yoda_automation_rules_blueprint)

            allow(trigger.helpers).to receive(:extract_inline_images).and_return(nil)
            allow(trigger.helpers).to receive(:upload_inline_images).and_return(nil)
          end

          it 'should handle a service instance not found' do
            find_no_app_offering_stub

            find_si_response =
              {
                serviceInstances: {
                  nodes: [],
                },
              }.with_indifferent_access
            stub_request(:post, endpoint)
              .with(body: graphql_request_body(find_service_instances_query,
                                               variables: { name: 'Conference Rooms Houston' },))
              .to_return(body: { data: find_si_response }.to_json)

            expect { trigger.provision }
              .to raise_error(IPaaS::Job::FailJob,
                              "Unable to find Service Instance with name 'Conference Rooms Houston'.")
          end

          it 'should apply and create a new app offering' do
            find_no_app_offering_stub
            find_no_ui_extension_by_source_stub
            find_service_instances_stub
            create_app_offering_stub
            create_ui_extension_stub
            create_automation_rule_stub
            find_app_offering_id_stub
            update_app_offering_webhook_uri_stub # only used in Automation Webhook Trigger

            trigger.provision

            expect(find_no_app_offering_stub).to have_been_requested.once
            expect(find_no_ui_extension_by_source_stub).to have_been_requested.once
            expect(find_service_instances_stub).to have_been_requested.once
            expect(create_app_offering_stub).to have_been_requested.once
            expect(create_ui_extension_stub).to have_been_requested.once
            expect(create_automation_rule_stub).to have_been_requested.once
          end

          it 'should update existing UI extension even when app offering does not reference the UI extension' do
            find_no_app_offering_stub
            find_ui_extension_by_source_stub
            find_service_instances_stub
            create_app_offering_stub
            update_ui_extension_stub
            create_automation_rule_stub
            find_app_offering_id_stub
            update_app_offering_webhook_uri_stub # only used in Automation Webhook Trigger

            trigger.provision

            expect(find_no_app_offering_stub).to have_been_requested.once
            expect(find_ui_extension_by_source_stub).to have_been_requested.once
            expect(find_service_instances_stub).to have_been_requested.once
            expect(create_app_offering_stub).to have_been_requested.once
            expect(update_ui_extension_stub).to have_been_requested.once
            expect(create_automation_rule_stub).to have_been_requested.once
          end

          it 'should apply and update an existing app offering' do
            find_app_offering_stub
            find_service_instances_stub
            update_mutation_stub = update_app_offering_stub(yoda_app_offering_upsert_input.except(:webhookUriTemplate))
            update_ui_extension_stub
            update_automation_rule_stub
            find_app_offering_id_stub
            update_app_offering_webhook_uri_stub # only used in Automation Webhook Trigger

            trigger.provision

            expect(find_app_offering_stub).to have_been_requested.once
            expect(find_service_instances_stub).to have_been_requested.once
            expect(update_mutation_stub).to have_been_requested.once
            expect(update_ui_extension_stub).to have_been_requested.once
            expect(update_automation_rule_stub).to have_been_requested.once
          end

          it 'should apply and update configuration uri template of app offering' do
            next unless trigger.trigger_template.name == 'Installation Changed'

            trigger.config[:configuration_uri_template] = 'https://wdc.status.page/configureXurrent'

            find_app_offering_stub
            find_service_instances_stub
            update_app_offering_stub(yoda_app_offering_upsert_input.except(:webhookUriTemplate))
            update_ui_extension_stub
            update_automation_rule_stub
            find_app_offering_id_stub
            update_app_offering_configuration_uri_stub

            trigger.provision

            expect(update_app_offering_configuration_uri_stub).to have_been_requested.once
          end

          it 'should not change configuration uri template of app offering if no value is configured' do
            next unless trigger.trigger_template.name == 'Installation Changed'

            trigger.config[:configuration_uri_template] = ''

            find_app_offering_stub
            find_service_instances_stub
            update_app_offering_stub(yoda_app_offering_upsert_input.except(:webhookUriTemplate))
            update_ui_extension_stub
            update_automation_rule_stub
            find_app_offering_id_stub

            trigger.provision

            expect(update_app_offering_configuration_uri_stub).not_to have_been_requested
          end

          it 'should remove excessive scopes' do
            find_app_offering_with_two_scopes_stub
            find_service_instances_stub
            update_app_offering_with_deleted_scope_stub
            update_ui_extension_stub
            update_automation_rule_stub
            find_app_offering_id_stub
            update_app_offering_webhook_uri_stub # only used in Automation Webhook Trigger

            trigger.provision

            expect(update_app_offering_with_deleted_scope_stub).to have_been_requested.once
          end

          it 'should remove excessive automation rules' do
            find_app_offering_with_two_automation_rules_stub
            find_service_instances_stub
            update_app_offering_stub(yoda_app_offering_upsert_input.except(:webhookUriTemplate))
            update_ui_extension_stub
            update_automation_rule_stub
            delete_automation_rule_stub
            find_app_offering_id_stub
            update_app_offering_webhook_uri_stub # only used in Automation Webhook Trigger

            trigger.provision

            expect(delete_automation_rule_stub).to have_been_requested.once
          end

          it 'should upload inline images when applying app offering' do
            test_app_offering_input = yoda_app_offering.deep_dup
            test_app_offering_input[:inline_images] = {
              'attachments/test_image.jpg' => {
                'file_name' => 'test_image.jpg',
                'data' => Base64.encode64('fake_image_data_1'),
                'inline' => true,
              },
              'attachments/desc_image.png' => {
                'file_name' => 'desc_image.png',
                'data' => Base64.encode64('fake_image_data_2'),
                'inline' => false,
              },
            }
            test_app_offering_input[:description] = 'Test description with ![image](attachments/test_image.jpg)'
            test_app_offering_input[:features] = 'Test features with ![feature](attachments/desc_image.png)'

            trigger.blueprint_store.write('app_offering.json', test_app_offering_input.to_json)
            trigger.blueprint_store.write('app_offering_ui_extension.json', yoda_ui_extension_blueprint)
            trigger.blueprint_store.write('app_offering_automation_rules.json', yoda_automation_rules_blueprint)

            attachment_storage_stub

            stub_request(:post, 'https://upload.example.com/upload')
              .to_return(body: '<Key>new_image_key_1</Key>', status: 200)

            stub_request(:post, 'https://upload.example.com/upload')
              .to_return(body: '<Key>new_image_key_2</Key>', status: 200)

            create_response = { data: create_app_offering_response(yoda_app_offering_insert_output) }.to_json
            create_req_regex = /mutation.*AppOfferingCreateInput.*descriptionAttachments.*featuresAttachments/m
            create_app_offering_stub = stub_request(:post, endpoint)
                                       .with(body: create_req_regex)
                                       .to_return(body: create_response)

            stub_request(:post, endpoint)
              .with(body: /mutation.*AppOfferingUpdateInput/)
              .to_return(body: { data: { appOfferingUpdate: {
                appOffering: { id: 'app-offering-id', reference: 'yoda' }, errors: [],
              } } }.to_json)

            allow(trigger.helpers).to receive(:upload_inline_images).and_call_original

            find_no_app_offering_stub
            find_no_ui_extension_by_source_stub
            find_service_instances_stub
            create_ui_extension_stub
            create_automation_rule_stub
            update_app_offering_webhook_uri_stub # only used in Automation Webhook Trigger

            trigger.provision
            expect(find_no_app_offering_stub).to have_been_requested.once
            expect(create_app_offering_stub).to have_been_requested

            expect(trigger.helpers).to have_received(:upload_inline_images).with(an_instance_of(Hash))
          end
        end

        context 'GraphQL error context' do
          # Locks in the dynamic `context:` strings built by the App Offering, UI Extension, and
          # Automation Rule helpers so that any future regression in the interpolation
          # (operation verb, conditional name suffix, reference passthrough) is caught.

          before(:each) do
            trigger.blueprint_store.write('app_offering.json', yoda_app_offering_blueprint)
            trigger.blueprint_store.write('app_offering_ui_extension.json', yoda_ui_extension_blueprint)
            trigger.blueprint_store.write('app_offering_automation_rules.json', yoda_automation_rules_blueprint)
            allow(trigger.helpers).to receive(:extract_inline_images).and_return(nil)
            allow(trigger.helpers).to receive(:upload_inline_images).and_return(nil)
          end

          # B6 — find App Offering interpolates the configured app_reference
          it 'interpolates the app_reference into the find-App-Offering context' do
            stub_request(:post, endpoint)
              .with(body: graphql_request_body(find_app_offering_query,
                                               variables: { reference: 'yoda', published: false }))
              .to_return(body: { errors: [{ message: 'permission denied' }] }.to_json)

            expect { trigger.provision }.to raise_error(
              IPaaS::Job::FailJob,
              "Unable to find App Offering with reference 'yoda': permission denied"
            )
          end

          # B4 — insert_app_offering quotes the input name when present
          it 'interpolates the App Offering name into the create-App-Offering context' do
            find_no_app_offering_stub
            find_no_ui_extension_by_source_stub
            find_service_instances_stub
            create_ui_extension_stub
            stub_request(:post, endpoint)
              .with(body: graphql_request_body(create_app_offering_query,
                                               variables: { input: yoda_app_offering_upsert_input }))
              .to_return(body: { data: { appOfferingCreate: {
                errors: [{ path: 'appOffering.reference', message: 'reference taken' }],
              } } }.to_json)

            expect { trigger.provision }.to raise_error(
              IPaaS::Job::FailJob,
              "Unable to create App Offering 'Yoda Translate': reference taken"
            )
          end

          # B5 — insert_app_offering omits the quoted name when input has no name
          it 'omits the name suffix from the create-App-Offering context when input has no name' do
            blueprint_without_name = JSON.parse(yoda_app_offering_blueprint)
            blueprint_without_name.delete('name')
            trigger.blueprint_store.write('app_offering.json', blueprint_without_name.to_json)
            expected_input = yoda_app_offering_upsert_input.except(:name)

            find_no_app_offering_stub
            find_no_ui_extension_by_source_stub
            find_service_instances_stub
            create_ui_extension_stub
            stub_request(:post, endpoint)
              .with(body: graphql_request_body(create_app_offering_query,
                                               variables: { input: expected_input }))
              .to_return(body: { data: { appOfferingCreate: {
                errors: [{ path: 'appOffering.reference', message: 'reference taken' }],
              } } }.to_json)

            expect { trigger.provision }.to raise_error(
              IPaaS::Job::FailJob,
              'Unable to create App Offering: reference taken'
            )
          end

          # B7 — upsert_ui_extension Create branch quotes the UI Extension name
          it 'interpolates the UI Extension name into the create-UI-Extension context' do
            find_no_app_offering_stub
            find_no_ui_extension_by_source_stub
            find_service_instances_stub
            stub_request(:post, endpoint)
              .with(body: graphql_request_body(create_ui_extension_query,
                                               variables: { input: yoda_ui_extension_upsert_input(:create) }))
              .to_return(body: { data: { uiExtensionCreate: {
                errors: [{ path: 'uiExtension.html', message: 'invalid html' }],
              } } }.to_json)

            expect { trigger.provision }.to raise_error(
              IPaaS::Job::FailJob,
              "Unable to create UI Extension 'xurrent_apps_statuscast': invalid html"
            )
          end

          # B8 — upsert_ui_extension Update branch omits the name suffix when no name
          it 'omits the name suffix from the update-UI-Extension context when input has no name' do
            blueprint_without_name = JSON.parse(yoda_ui_extension_blueprint)
            blueprint_without_name.delete('name')
            trigger.blueprint_store.write('app_offering_ui_extension.json', blueprint_without_name.to_json)

            # find_app_offering returning yoda_app_offering yields a non-nil ui_extension_id, so the
            # UPDATE branch of apply_ui_extension is taken (find_ui_extension_id_by_source is NOT called).
            find_app_offering_stub
            find_service_instances_stub
            expected_input = yoda_ui_extension_upsert_input(:update).except(:name)
            stub_request(:post, endpoint)
              .with(body: graphql_request_body(update_ui_extension_query,
                                               variables: { input: expected_input }))
              .to_return(body: { data: { uiExtensionUpdate: {
                errors: [{ path: 'uiExtension.html', message: 'invalid html' }],
              } } }.to_json)

            expect { trigger.provision }.to raise_error(
              IPaaS::Job::FailJob,
              'Unable to update UI Extension: invalid html'
            )
          end

          # B9 — automation_rule_mutation Create branch quotes the rule name
          it 'interpolates the rule name into the create-Automation-Rule context' do
            find_no_app_offering_stub
            find_no_ui_extension_by_source_stub
            find_service_instances_stub
            create_app_offering_stub
            create_ui_extension_stub
            create_automation_rule_input = yoda_automation_rule_upsert_input
            create_automation_rule_input[:appOfferingId] = 'app-offering-id'
            stub_request(:post, endpoint)
              .with(body: graphql_request_body(create_automation_rule_query,
                                               variables: { input: create_automation_rule_input }))
              .to_return(body: { data: { appOfferingAutomationRuleCreate: {
                errors: [{ path: 'automationRule.condition', message: 'invalid condition' }],
              } } }.to_json)

            expect { trigger.provision }.to raise_error(
              IPaaS::Job::FailJob,
              "Unable to create Automation Rule 'Automated note on completion': invalid condition"
            )
          end

          # B10 — automation_rule_mutation Update branch quotes the rule name
          it 'interpolates the rule name into the update-Automation-Rule context' do
            find_app_offering_stub
            find_service_instances_stub
            update_ui_extension_stub
            update_app_offering_stub(yoda_app_offering_upsert_input.except(:webhookUriTemplate))
            find_app_offering_id_stub
            update_app_offering_webhook_uri_stub # only used in Automation Webhook Trigger
            update_automation_rule_input = yoda_automation_rule_upsert_input
            update_automation_rule_input[:id] = 'automation-rule-id'
            stub_request(:post, endpoint)
              .with(body: graphql_request_body(update_automation_rule_query,
                                               variables: { input: update_automation_rule_input }))
              .to_return(body: { data: { appOfferingAutomationRuleUpdate: {
                errors: [{ path: 'automationRule.condition', message: 'invalid condition' }],
              } } }.to_json)

            expect { trigger.provision }.to raise_error(
              IPaaS::Job::FailJob,
              "Unable to update Automation Rule 'Automated note on completion': invalid condition"
            )
          end

          # B11 — automation_rule_mutation Delete branch (input has no name) omits the suffix
          it 'omits the name suffix from the delete-Automation-Rule context (input has no name)' do
            find_app_offering_with_two_automation_rules_stub
            find_service_instances_stub
            update_ui_extension_stub
            update_app_offering_stub(yoda_app_offering_upsert_input.except(:webhookUriTemplate))
            update_automation_rule_stub
            find_app_offering_id_stub
            update_app_offering_webhook_uri_stub # only used in Automation Webhook Trigger
            stub_request(:post, endpoint)
              .with(body: graphql_request_body(delete_automation_rule_query,
                                               variables: { input: { id: 'automation-rule-id-2' } }))
              .to_return(body: { data: { appOfferingAutomationRuleDelete: {
                errors: [{ path: 'automationRule', message: 'in use' }],
              } } }.to_json)

            expect { trigger.provision }.to raise_error(
              IPaaS::Job::FailJob,
              'Unable to delete Automation Rule: in use'
            )
          end

          # B13 — update_app_offering relies on its default context kwarg when caller omits it
          it 'falls back to the default update-App-Offering context when the caller passes no kwarg' do
            find_app_offering_stub
            find_service_instances_stub
            update_ui_extension_stub
            input = yoda_app_offering_upsert_input.except(:webhookUriTemplate)
            to_send = { id: 'app-offering-id' }.merge(input).with_indifferent_access
            to_send[:newScopes][0][:id] = 841
            stub_request(:post, endpoint)
              .with(body: graphql_request_body(update_app_offering_query,
                                               variables: { input: to_send }))
              .to_return(body: { data: { appOfferingUpdate: {
                errors: [{ path: 'appOffering', message: 'locked' }],
              } } }.to_json)

            expect { trigger.provision }.to raise_error(
              IPaaS::Job::FailJob,
              'Unable to update App Offering: locked'
            )
          end

          # B14 — update_app_offering with the explicit configuration_uri_template override context
          it 'uses the explicit set-Configuration-URI-Template context when provided by the caller' do
            next unless trigger.trigger_template.name == 'Installation Changed'

            trigger.config[:configuration_uri_template] = 'https://wdc.status.page/configureXurrent'

            find_app_offering_stub
            find_service_instances_stub
            update_app_offering_stub(yoda_app_offering_upsert_input.except(:webhookUriTemplate))
            update_ui_extension_stub
            update_automation_rule_stub
            find_app_offering_id_stub
            variables = {
              input: {
                id: 'app-offering-id',
                configurationUriTemplate: trigger.config[:configuration_uri_template],
              },
            }
            stub_request(:post, endpoint)
              .with(body: graphql_request_body(update_app_offering_webhook_uri_query, variables: variables))
              .to_return(body: { data: { appOfferingUpdate: {
                errors: [{ path: 'appOffering.configurationUriTemplate', message: 'invalid uri' }],
              } } }.to_json)

            expect { trigger.provision }.to raise_error(
              IPaaS::Job::FailJob,
              'Unable to set Configuration URI Template on App Offering: invalid uri'
            )
          end
        end
      end
    end
  end
end
