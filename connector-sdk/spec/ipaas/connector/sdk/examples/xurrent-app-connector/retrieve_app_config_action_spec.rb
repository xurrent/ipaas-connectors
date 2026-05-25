require 'spec_helper'

describe 'App Config Action', :action do
  let(:action_template_id) { '01947437-fec0-70e5-8adf-879234ae7892' }

  let(:outbound_connection_config) do
    {
      credentials: {
        account_id: 'wdc',
        client_id: 'abc',
        client_secret: make_secret_string('def'),
      },
      environment: {
        stage: 'Demo',
        graphql_endpoint: 'https://graphql.example.com/graphql',
      },
    }
  end

  before(:each) do
    stub_xurrent_oauth2_token(outbound_connection_config)
  end

  let(:endpoint) do
    outbound_connection_config[:environment][:graphql_endpoint]
  end

  let(:find_app_config_query) do
    <<~END_OF_GRAPHQL
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
  end

  let(:find_app_config_response) do
    {
      appInstances: {
        nodes: [
          {
            customFields: [
              { id: 'phone_nr', value: '+99 555 222 421' },
              { id: 'bounces', value: 42 },
            ],
            disabled: false,
            enabledByCustomer: true,
            suspended: false,
            suspensionComment: nil,
          },
        ],
      },
    }.with_indifferent_access
  end

  let(:find_app_config_stub) do
    variables = {
      appReference: 'weu_it_phone',
      customerAccountId: 'wdc',
    }
    stub_request(:post, endpoint)
      .with(body: graphql_request_body(find_app_config_query, variables: variables),
            headers: { 'content-type' => 'application/json' })
      .to_return(body: { data: find_app_config_response }.to_json)
  end

  let(:customer_secrets) do
    {
      'credit_card_nr' => make_secret_string('1234.5678'),
    }
  end

  def store_customer_secrets(app_reference: 'weu_it_phone')
    customer_key = "customer_secrets/wdc/#{app_reference}"
    action.outbound_connection.store.write(customer_key, customer_secrets.to_json)
  end

  context 'using trigger output' do
    before(:each) do
      allow(runbook).to receive(:trigger_output).and_return(
        {
          customer_account_id: 'wdc',
          app_reference: 'weu_it_phone',
        }
      )
    end

    context 'regular configuration only' do
      let(:action_input) do
        {
          config_schema: [
            { id: 'phone_nr', label: 'Phone Nr', type: 'string' },
            { id: 'bounces', label: 'Bounces', type: 'integer' },
            { id: 'field3', label: 'Field 3', type: 'string' },
          ],
        }
      end

      before(:each) do
        find_app_config_stub
      end

      it 'should retrieve the normal app config' do
        output = run_action
        config = output[:config]
        expect(config[:phone_nr]).to eq('+99 555 222 421')
        expect(config[:bounces]).to eq(42)
      end

      it 'should retrieve app instance status fields' do
        output = run_action
        expect(output[:disabled]).to eq(false)
        expect(output[:enabled_by_customer]).to eq(true)
        expect(output[:suspended]).to eq(false)
        expect(output[:suspension_comment]).to be_nil
      end

      it 'should backoff when a required custom field is not present' do
        expect do
          run_action(
            {
              config_schema: [
                { id: 'field3', label: 'Field 3', type: 'string', required: true },
              ],
            }
          )
        end.to raise_error(IPaaS::Job::RescheduleJob, 'Required fields not available yet: field3')
      end
    end

    context 'app instance status fields with suspended app' do
      let(:action_input) do
        {
          config_schema: [
            { id: 'optional_field', label: 'Optional Field', type: 'string' },
          ],
        }
      end

      let(:suspended_app_response) do
        {
          appInstances: {
            nodes: [
              {
                customFields: [],
                disabled: true,
                enabledByCustomer: false,
                suspended: true,
                suspensionComment: 'App suspended',
              },
            ],
          },
        }.with_indifferent_access
      end

      before(:each) do
        variables = {
          appReference: 'weu_it_phone',
          customerAccountId: 'wdc',
        }
        stub_request(:post, endpoint)
          .with(body: graphql_request_body(find_app_config_query, variables: variables),
                headers: { 'content-type' => 'application/json' })
          .to_return(body: { data: suspended_app_response }.to_json)
      end

      it 'should retrieve app instance status fields even when custom fields are empty' do
        output = run_action
        expect(output[:config][:optional_field]).to be_nil
        expect(output[:disabled]).to eq(true)
        expect(output[:enabled_by_customer]).to eq(false)
        expect(output[:suspended]).to eq(true)
        expect(output[:suspension_comment]).to eq('App suspended')
      end
    end

    context 'secrets only' do
      let(:action_input) do
        {
          config_schema: [
            { id: 'credit_card_nr', label: 'Creditcard Nr', type: 'secret_string', required: true },
          ],
        }
      end

      before(:each) do
        find_app_config_stub
      end

      it 'should retrieve the secret app config' do
        store_customer_secrets
        output = run_action
        config = output[:config]
        expect(action.decrypt_secret_string(config[:credit_card_nr])).to eq('1234.5678')
      end

      it 'should backoff when a required secret is not present' do
        expect do
          run_action
        end.to raise_error(IPaaS::Job::RescheduleJob, 'Required secrets not available yet: credit_card_nr')
      end
    end

    context 'mixed configuration' do
      let(:action_input) do
        {
          config_schema: [
            { id: 'bounces', label: 'Bounces', type: 'integer' },
            { id: 'credit_card_nr', label: 'Creditcard Nr', type: 'secret_string' },
          ],
        }
      end

      before(:each) do
        find_app_config_stub
        store_customer_secrets
      end

      it 'should retrieve both the normal and secret app config' do
        output = run_action
        config = output[:config]
        expect(config[:bounces]).to eq(42)
        expect(action.decrypt_secret_string(config[:credit_card_nr])).to eq('1234.5678')
      end
    end
  end

  context 'using action input' do
    let(:action_input) do
      {
        customer_account_id: 'wdc',
        app_reference: 'xurrent_sync',
        config_schema: [
          { id: 'credit_card_nr', label: 'Creditcard Nr', type: 'secret_string' },
        ],
      }
    end

    before(:each) do
      store_customer_secrets(app_reference: 'xurrent_sync')
      variables = {
        appReference: 'xurrent_sync',
        customerAccountId: 'wdc',
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(find_app_config_query, variables: variables),
              headers: { 'content-type' => 'application/json' })
        .to_return(body: { data: find_app_config_response }.to_json)
    end

    it 'should use the action input to reference the correct secret app config' do
      output = run_action
      config = output[:config]
      expect(action.decrypt_secret_string(config[:credit_card_nr])).to eq('1234.5678')
    end
  end

  context 'using unknown app' do
    let(:action_input) do
      {
        customer_account_id: 'wdc',
        app_reference: 'foo_bar',
        config_schema: [
          { id: 'credit_card_nr', label: 'Creditcard Nr', type: 'secret_string' },
        ],
      }
    end

    let(:empty_app_response) do
      {
        appInstances: {
          nodes: [],
        },
      }.with_indifferent_access
    end

    before(:each) do
      store_customer_secrets
      variables = {
        appReference: 'foo_bar',
        customerAccountId: 'wdc',
      }
      stub_request(:post, endpoint)
        .with(body: graphql_request_body(find_app_config_query, variables: variables),
              headers: { 'content-type' => 'application/json' })
        .to_return(body: { data: empty_app_response }.to_json)
    end

    it 'should return empty values when app instance is not found' do
      output = run_action
      expect(output[:customer_account_id]).to be_nil
      expect(output[:app_reference]).to be_nil
      expect(output[:credit_card_nr]).to be_nil
      expect(output[:config]).to eq({})
      expect(output[:disabled]).to be_nil
      expect(output[:enabled_by_customer]).to be_nil
      expect(output[:suspended]).to be_nil
      expect(output[:suspension_comment]).to be_nil
    end
  end

  describe 'error handling' do
    before(:each) do
      allow(runbook).to receive(:trigger_output).and_return(
        {
          customer_account_id: 'wdc',
          app_reference: 'weu_it_phone',
        }
      )
    end

    let(:action_input) do
      {
        config_schema: [
          { id: 'phone_nr', label: 'Phone Nr', type: 'string' },
        ],
      }
    end

    let(:content_type_json) { { 'content-type' => 'application/json' } }

    describe 'temporary errors' do
      describe 'without retry-after' do
        it 'handles 429' do
          variables = {
            appReference: 'weu_it_phone',
            customerAccountId: 'wdc',
          }
          stub = stub_request(:post, endpoint)
                 .with(body: graphql_request_body(find_app_config_query, variables: variables),
                       headers: content_type_json)
                 .to_return(status: 429, body: 'Wait 10 seconds')

          Timecop.freeze do
            expect { run_action }
              .to raise_error(IPaaS::Job::RescheduleJob, "Xurrent API rate limit hit. 'Wait 10 seconds'") do |e|
              expect(e.reschedule_after).to eq(1.minute.from_now)
            end
            expect(stub).to have_been_requested.once
          end
        end

        it 'handles 503' do
          variables = {
            appReference: 'weu_it_phone',
            customerAccountId: 'wdc',
          }
          stub = stub_request(:post, endpoint)
                 .with(body: graphql_request_body(find_app_config_query, variables: variables),
                       headers: content_type_json)
                 .to_return(status: 503, body: 'Service Unavailable')

          Timecop.freeze do
            expect { run_action }
              .to raise_error(IPaaS::Job::RescheduleJob,
                              %(Xurrent API not available. 'Service Unavailable')) do |e|
              expect(e.reschedule_after).to eq(1.minute.from_now)
            end
            expect(stub).to have_been_requested.once
          end
        end
      end

      describe 'with retry-after' do
        it 'handles 429' do
          variables = {
            appReference: 'weu_it_phone',
            customerAccountId: 'wdc',
          }
          stub = stub_request(:post, endpoint)
                 .with(body: graphql_request_body(find_app_config_query, variables: variables),
                       headers: content_type_json)
                 .to_return(status: 429, body: 'Wait 2 seconds', headers: { 'retry-after' => 2 })

          Timecop.freeze do
            expect { run_action }
              .to raise_error(IPaaS::Job::RescheduleJob,
                              "Xurrent API rate limit hit (retry after: 2). 'Wait 2 seconds'") do |e|
              expect(e.reschedule_after).to eq(2.seconds.from_now)
            end
            expect(stub).to have_been_requested.once
          end
        end

        it 'handles 503' do
          variables = {
            appReference: 'weu_it_phone',
            customerAccountId: 'wdc',
          }
          stub = stub_request(:post, endpoint)
                 .with(body: graphql_request_body(find_app_config_query, variables: variables),
                       headers: content_type_json)
                 .to_return(status: 503,
                            body: 'Service Unavailable',
                            headers: { 'retry-after' => 'Wed, 21 Oct 2015 07:28:00 GMT' })

          Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 +01:00')) do
            expect { run_action }
              .to raise_error(IPaaS::Job::RescheduleJob,
                              'Xurrent API not available (retry after: Wed, 21 Oct 2015 07:28:00 GMT). ' \
                              "'Service Unavailable'") do |e|
              expect(e.reschedule_after).to eq(8.minutes.from_now)
            end
            expect(stub).to have_been_requested.once
          end
        end
      end
    end
  end
end
