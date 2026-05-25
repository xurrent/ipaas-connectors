require 'spec_helper'

describe 'App Config Action', :action do
  let(:action_template_id) { '0197a1a0-118f-7374-b2d9-9ef2ecbead4c' }

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

  let(:find_app_instance_id_query) do
    <<~END_OF_GRAPHQL
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
  end

  let(:find_app_instance_id_response) do
    {
      appInstances: {
        nodes: [
          { id: 'myAppInstanceNodeID' },
        ],
      },
    }.with_indifferent_access
  end

  let(:find_no_app_instance_id_response) do
    {
      appInstances: {
        nodes: [],
      },
    }.with_indifferent_access
  end

  def find_app_instance_id_stub(app_reference: 'weu_it_phone', response: find_app_instance_id_response)
    variables = {
      appReference: app_reference,
      customerAccountId: 'wdc',
    }
    stub_request(:post, endpoint)
      .with(body: graphql_request_body(find_app_instance_id_query, variables: variables))
      .to_return(body: { data: response }.to_json)
  end

  let(:update_app_instance_query) do
    <<~END_OF_GRAPHQL
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

  let(:update_app_instance_response) do
    {
      appInstanceUpdate: {
        appInstance: {
          id: 'myAppInstanceNodeID',
        },
      },
    }.with_indifferent_access
  end

  def update_app_instance_stub(variables)
    stub_request(:post, endpoint)
      .with(body: graphql_request_body(update_app_instance_query, variables: { input: variables }))
      .to_return(body: { data: update_app_instance_response }.to_json)
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

    context 'update app instance' do
      let(:action_input) do
        {
          custom_fields: [
            { id: 'foo', value: 'bar' },
            { id: 'zoo', value: 'zar' },
          ],
          disabled: true,
          suspension: {
            suspended: true,
            comment: 'Wait for it...',
          },
        }
      end

      before(:each) do
        find_app_instance_id_stub
      end

      it 'should update the app config' do
        update_app_instance_stub({
          customFields: action_input[:custom_fields],
          disabled: true,
          suspended: true,
          suspensionComment: 'Wait for it...',
          id: 'myAppInstanceNodeID',
        })
        output = run_action
        expect(output[:app_instance_id]).to eq('myAppInstanceNodeID')
      end
    end
  end

  context 'using action input' do
    let(:action_input) do
      {
        customer_account_id: 'wdc',
        app_reference: 'xurrent_sync',
        custom_fields: [
          { id: 'foo', value: 'bar' },
          { id: 'zoo', value: 'zar' },
        ],
        disabled: true,
        suspension: {
          suspended: true,
          comment: 'Wait for it...',
        },
      }
    end

    before(:each) do
      find_app_instance_id_stub(app_reference: 'xurrent_sync')
    end

    it 'should update the app config' do
      update_app_instance_stub({
        customFields: action_input[:custom_fields],
        disabled: true,
        suspended: true,
        suspensionComment: 'Wait for it...',
        id: 'myAppInstanceNodeID',
      })
      output = run_action
      expect(output[:app_instance_id]).to eq('myAppInstanceNodeID')
    end
  end

  context 'when app instance is missing' do
    let(:action_input) do
      {
        customer_account_id: 'wdc',
        app_reference: 'weu_it_phone',
        disabled: true,
      }
    end

    before(:each) do
      find_app_instance_id_stub(response: find_no_app_instance_id_response)
    end

    it 'should fail the job when the app instance is missing' do
      expect do
        run_action
      end.to raise_error(IPaaS::Job::FailJob, 'App instance weu_it_phone not found for customer wdc')
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
        custom_fields: [{ id: 'foo', value: 'bar' }],
      }
    end

    let(:content_type_json) { { 'content-type' => 'application/json' } }

    describe 'temporary errors' do
      describe 'without retry-after' do
        it 'handles 429 on find app instance' do
          variables = {
            appReference: 'weu_it_phone',
            customerAccountId: 'wdc',
          }
          stub = stub_request(:post, endpoint)
                 .with(body: graphql_request_body(find_app_instance_id_query, variables: variables),
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

        it 'handles 503 on find app instance' do
          variables = {
            appReference: 'weu_it_phone',
            customerAccountId: 'wdc',
          }
          stub = stub_request(:post, endpoint)
                 .with(body: graphql_request_body(find_app_instance_id_query, variables: variables),
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

        it 'handles 429 on update app instance' do
          find_app_instance_id_stub
          stub = stub_request(:post, endpoint)
                 .with(body: hash_including(graphql_request_body(update_app_instance_query)),
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

        it 'handles 503 on update app instance' do
          find_app_instance_id_stub
          stub = stub_request(:post, endpoint)
                 .with(body: hash_including(graphql_request_body(update_app_instance_query)),
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
        it 'handles 429 on find app instance' do
          variables = {
            appReference: 'weu_it_phone',
            customerAccountId: 'wdc',
          }
          stub = stub_request(:post, endpoint)
                 .with(body: graphql_request_body(find_app_instance_id_query, variables: variables),
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

        it 'handles 503 on find app instance' do
          variables = {
            appReference: 'weu_it_phone',
            customerAccountId: 'wdc',
          }
          stub = stub_request(:post, endpoint)
                 .with(body: graphql_request_body(find_app_instance_id_query, variables: variables),
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
