require 'spec_helper'

describe 'Xurrent GraphQL Action', :action do
  let(:connector_id) { '01962529-c8eb-7a89-a682-73d6f09541d6' }
  let(:action_template_id) { '019320e9-e159-7bbf-983d-a861da9de712' }

  describe 'input_schema' do
    it 'should define the query field' do
      field = action.input_schema.field(:query)
      expect(field.label).to eq('Query')
      expect(field.type).to eq(:string)
      expect(field.required).to be_truthy
      expect(field.visibility).to eq('visible')
    end

    it 'should define the variables field' do
      field = action.input_schema.field(:variables)
      expect(field.label).to eq('Variables')
      expect(field.type).to eq(:hash)
      expect(field.required).to be_falsey
      expect(field.visibility).to eq('visible')
    end

    it 'should define the operation name field' do
      field = action.input_schema.field(:operation_name)
      expect(field.label).to eq('Operation name')
      expect(field.type).to eq(:string)
      expect(field.required).to be_falsey
      expect(field.visibility).to eq('optional')
    end
  end

  describe 'output_schema' do
    it 'should only have output output schema' do
      expect(action.output_schema.map(&:reference)).to contain_exactly('output')
    end

    describe 'output schema' do
      let(:output_schema) { action.output_schema.first }

      it 'should define the request_id field' do
        output_schema.field(:request_id).tap do |field|
          expect(field.label).to eq('Request ID')
          expect(field.type).to eq(:string)
          expect(field.visibility).to eq('optional')
        end
      end

      it 'should define the ratelimit field' do
        ratelimit_field = output_schema.field(:ratelimit).tap do |field|
          expect(field.label).to eq('Rate limit')
          expect(field.type).to eq(:nested)
          expect(field.visibility).to eq('optional')
        end

        ratelimit_field.field(:limit).tap do |field|
          expect(field.label).to eq('Limit')
          expect(field.type).to eq(:integer)
        end

        ratelimit_field.field(:remaining).tap do |field|
          expect(field.label).to eq('Remaining')
          expect(field.type).to eq(:integer)
        end

        ratelimit_field.field(:reset).tap do |field|
          expect(field.label).to eq('Reset')
          expect(field.type).to eq(:integer)
        end
      end

      it 'should define the costlimit field' do
        costlimit_field = output_schema.field(:costlimit).tap do |field|
          expect(field.label).to eq('Cost limit')
          expect(field.type).to eq(:nested)
          expect(field.visibility).to eq('optional')
        end

        costlimit_field.field(:cost).tap do |field|
          expect(field.label).to eq('Cost')
          expect(field.type).to eq(:integer)
        end

        costlimit_field.field(:limit).tap do |field|
          expect(field.label).to eq('Limit')
          expect(field.type).to eq(:integer)
        end

        costlimit_field.field(:remaining).tap do |field|
          expect(field.label).to eq('Remaining')
          expect(field.type).to eq(:integer)
        end

        costlimit_field.field(:reset).tap do |field|
          expect(field.label).to eq('Reset')
          expect(field.type).to eq(:integer)
        end
      end
    end
  end

  describe 'run' do
    let(:endpoint) do
      outbound_connection_config[:environment][:graphql_endpoint]
    end

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

    let(:content_type_json) { { 'content-type' => 'application/json' } }

    before(:each) do
      stub_xurrent_oauth2_token(outbound_connection_config)
    end

    describe 'return query result as data' do
      it 'should send the given query only' do
        stub = stub_request(:post, endpoint)
               .with(body: { query: 'query { services { totalCount } }' }.to_json,
                     headers: content_type_json)
               .to_return(body: { data: { services: { totalCount: 10 } } }.to_json)

        output = run_action({ query: 'query { services { totalCount } }' })
        expect(output.dig(:data, :services, :totalCount)).to eq(10)
        expect(stub).to have_been_requested.once
      end

      it 'should send the given query and variables' do
        stub = stub_request(:post, endpoint)
               .with(body: { query: 'query { services { totalCount } }', variables: { a: 1 } }.to_json,
                     headers: content_type_json)
               .to_return(body: { data: { totalCount: 3 } }.to_json)

        output = run_action({ query: 'query { services { totalCount } }', variables: { a: 1 } })
        expect(output.dig(:data, :totalCount)).to eq(3)
        expect(stub).to have_been_requested.once
      end

      it 'should send the given query, variables and operation name' do
        stub = stub_request(:post, endpoint)
               .with(body: { query: 'query { services { totalCount } }',
                             variables: { a: 2 },
                             operationName: 'count_them', }.to_json,
                     headers: content_type_json)
               .to_return(body: { data: { services: { totalCount: 4 } } }.to_json)

        output = run_action({ query: 'query { services { totalCount } }',
                              variables: { a: 2 },
                              operation_name: 'count_them', })
        expect(output.dig(:data, :services, :totalCount)).to eq(4)
        expect(stub).to have_been_requested.once
      end
    end

    describe 'extracts headers' do
      before(:each) do
        stub_request(:post, endpoint)
          .with(body: { query: 'query' }.to_json)
          .to_return(body: { data: { totalCount: 1 } }.to_json, headers: xurrent_headers)
      end

      let(:xurrent_headers) do
        {
          'x-costlimit-limit' => 5000,
          'x-costlimit-cost' => 1,
          'x-costlimit-remaining' => 4999,
          'x-costlimit-reset' => 1_720_199_698,
          'x-ratelimit-limit' => 3600,
          'x-ratelimit-remaining' => 3599,
          'x-ratelimit-reset' => 1_720_199_697,
          'x-request-id' => 'Root36a4573f-8036-463a-bf43-48d75c62218f',
        }
      end

      it 'extracts x-request-id header' do
        output = run_action({ query: 'query' })
        expect(output[:request_id]).to eq('Root36a4573f-8036-463a-bf43-48d75c62218f')
      end

      it 'extracts x-costlimit headers' do
        output = run_action({ query: 'query' })
        expect(output[:costlimit]).to eq({
          'cost' => '1',
          'limit' => '5000',
          'remaining' => '4999',
          'reset' => '1720199698',
        })
      end

      it 'extracts x-ratelimit headers' do
        output = run_action({ query: 'query' })
        expect(output[:ratelimit]).to eq({
          'limit' => '3600',
          'remaining' => '3599',
          'reset' => '1720199697',
        })
      end
    end

    describe 'error handling' do
      describe 'temporary errors' do
        describe 'without retry-after' do
          it 'handles 429' do
            stub = stub_request(:post, endpoint)
                   .with(body: { query: 'query' }.to_json, headers: content_type_json)
                   .to_return(status: 429, body: 'Wait 10 seconds')

            Timecop.freeze do
              expect { run_action({ query: 'query' }) }
                .to raise_error(IPaaS::Job::RescheduleJob, "Xurrent rate limit hit. 'Wait 10 seconds'") do |e|
                expect(e.reschedule_after).to eq(1.minute.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles 503' do
            stub = stub_request(:post, endpoint)
                   .with(body: { query: 'query' }.to_json, headers: content_type_json)
                   .to_return(status: 503, body: 'Service Unavailable')

            Timecop.freeze do
              expect { run_action({ query: 'query' }) }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                %(Xurrent not available. 'Service Unavailable')) do |e|
                expect(e.reschedule_after).to eq(1.minute.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end
        end

        describe 'with retry-after' do
          it 'handles 429' do
            stub = stub_request(:post, endpoint)
                   .with(body: { query: 'query' }.to_json, headers: content_type_json)
                   .to_return(status: 429, body: 'Wait 2 seconds', headers: { 'retry-after' => 2 })

            Timecop.freeze do
              expect { run_action({ query: 'query' }) }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                "Xurrent rate limit hit (retry after: 2). 'Wait 2 seconds'") do |e|
                expect(e.reschedule_after).to eq(2.seconds.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles 503' do
            stub = stub_request(:post, endpoint)
                   .with(body: { query: 'query' }.to_json, headers: content_type_json)
                   .to_return(status: 503,
                              body: 'Service Unavailable',
                              headers: { 'retry-after' => 'Wed, 21 Oct 2015 07:28:00 GMT' })

            Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 +01:00')) do
              expect { run_action({ query: 'query' }) }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                'Xurrent not available (retry after: Wed, 21 Oct 2015 07:28:00 GMT). ' \
                                "'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(8.minutes.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles retry after header in the past in 503' do
            stub = stub_request(:post, endpoint)
                   .with(body: { query: 'query' }.to_json, headers: content_type_json)
                   .to_return(status: 503,
                              body: 'Service Unavailable',
                              headers: { 'retry-after' => 'Wed, 21 Oct 2015 07:19:00 GMT' })

            Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 +01:00')) do
              expect { run_action({ query: 'query' }) }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                'Xurrent not available (retry after: Wed, 21 Oct 2015 07:19:00 GMT). ' \
                                "'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(1.minutes.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles invalid retry after header in 503' do
            stub = stub_request(:post, endpoint)
                   .with(body: { query: 'query' }.to_json, headers: content_type_json)
                   .to_return(status: 503,
                              body: 'Service Unavailable',
                              headers: { 'retry-after' => '642 Bla 2015 07:28:00 GMT' })

            Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 CET')) do
              expect { run_action({ query: 'query' }) }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                'Xurrent not available (retry after: 642 Bla 2015 07:28:00 GMT). ' \
                                "'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(1.minutes.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end
        end
      end

      it 'handles 401' do
        stub = stub_request(:post, endpoint)
               .with(body: { query: 'query' }.to_json, headers: content_type_json)
               .to_return(status: 401, body: '{"message":"Unauthorized"}')

        expect do
          run_action({ query: 'query' })
        end.to raise_error(IPaaS::Job::FailJob,
                           %(HTTP error from Xurrent GraphQL API: 401 '{"message":"Unauthorized"}'))
        expect(stub).to have_been_requested.once
      end

      it 'handles 500' do
        stub = stub_request(:post, endpoint)
               .with(body: { query: 'query' }.to_json, headers: content_type_json)
               .to_return(status: 500, body: '{"message":"Internal Server Error"}')

        expect do
          run_action({ query: 'query' })
        end.to raise_error(IPaaS::Job::FailJob,
                           %(HTTP error from Xurrent GraphQL API: 500 '{"message":"Internal Server Error"}'))
        expect(stub).to have_been_requested.once
      end

      it 'handles complex errors in body' do
        stub = stub_request(:post, endpoint)
               .with(body: { query: 'query' }.to_json, headers: content_type_json)
               .to_return(body: { errors: [{ message: 'bla', path: 'abc' }] }.to_json)

        expect do
          run_action({ query: 'query' })
        end.to raise_error(IPaaS::Job::FailJob,
                           %(Errors from Xurrent GraphQL API: [{"message":"bla","path":"abc"}]))

        expect(stub).to have_been_requested.once
      end

      it 'handles missing scope error' do
        stub = stub_request(:post, endpoint)
               .with(body: { query: 'query' }.to_json, headers: content_type_json)
               .to_return(body: { errors: [{ message: 'Missing required scope(s): request:Read' }] }.to_json)

        expect do
          run_action({ query: 'query' })
        end.to raise_error(IPaaS::Job::FailJob,
                           %(Errors from Xurrent GraphQL API: [{"message":"Missing required scope(s): request:Read"}]))

        expect(stub).to have_been_requested.once
      end

      it 'ignores empty errors in body' do
        stub = stub_request(:post, endpoint)
               .with(body: { query: 'query' }.to_json, headers: content_type_json)
               .to_return(body: { errors: [], data: { foo: :bar } }.to_json)

        output = run_action({ query: 'query' })
        expect(output.dig(:data, :foo)).to eq('bar')

        expect(stub).to have_been_requested.once
      end

      it 'handles missing data' do
        stub = stub_request(:post, endpoint)
               .with(body: { query: 'query' }.to_json, headers: content_type_json)
               .to_return(body: {}.to_json)

        expect do
          run_action({ query: 'query' })
        end.to raise_error(IPaaS::Job::FailJob, %(No data from Xurrent GraphQL API))

        expect(stub).to have_been_requested.once
      end
    end

    describe 'decrypt_secret_strings_in_variables helper' do
      it 'decrypts SecretString values in variables when calling graphql' do
        secret_value = make_secret_string('secret123')
        variables = { key1: secret_value, key2: 'plain_value' }

        stub = stub_request(:post, endpoint)
               .with(body: { query: 'query { test }', variables: { key1: 'secret123', key2: 'plain_value' } }.to_json,
                     headers: content_type_json)
               .to_return(body: { data: { result: 'ok' } }.to_json)

        output = run_action({ query: 'query { test }', variables: variables })
        expect(output.dig(:data, :result)).to eq('ok')
        expect(stub).to have_been_requested.once
      end

      it 'decrypts SecretString values in arrays within variables' do
        secret1 = make_secret_string('secret1')
        secret2 = make_secret_string('secret2')
        variables = { items: [secret1, 'plain', secret2] }

        stub = stub_request(:post, endpoint)
               .with(body: { query: 'query { test }', variables: { items: %w[secret1 plain secret2] } }.to_json,
                     headers: content_type_json)
               .to_return(body: { data: { result: 'ok' } }.to_json)

        output = run_action({ query: 'query { test }', variables: variables })
        expect(output.dig(:data, :result)).to eq('ok')
        expect(stub).to have_been_requested.once
      end

      it 'decrypts SecretString values in nested hashes within variables' do
        secret_value = make_secret_string('nested_secret')
        variables = {
          level1: {
            level2: {
              secret: secret_value,
              plain: 'plain_value',
            },
          },
        }

        stub = stub_request(:post, endpoint)
               .with(body: { query: 'query { test }',
                             variables: { level1: { level2: { secret: 'nested_secret',
                                                              plain: 'plain_value', } } }, }.to_json,
                     headers: content_type_json)
               .to_return(body: { data: { result: 'ok' } }.to_json)

        output = run_action({ query: 'query { test }', variables: variables })
        expect(output.dig(:data, :result)).to eq('ok')
        expect(stub).to have_been_requested.once
      end

      it 'leaves non-SecretString values unchanged' do
        variables = {
          string: 'value',
          integer: 123,
          boolean: true,
          nil_value: nil,
          float: 45.67,
        }

        stub = stub_request(:post, endpoint)
               .with(body: { query: 'query { test }',
                             variables: variables, }.to_json,
                     headers: content_type_json)
               .to_return(body: { data: { result: 'ok' } }.to_json)

        output = run_action({ query: 'query { test }', variables: variables })
        expect(output.dig(:data, :result)).to eq('ok')
        expect(stub).to have_been_requested.once
      end
    end
  end

  describe 'system_graphql_endpoint fallback' do
    # PAT credentials skip the OAuth flow so we can isolate the GraphQL endpoint helper.
    let(:outbound_connection_config) do
      {
        credentials: {
          account_id: 'wdc',
          personal_access_token: make_secret_string('pat'),
        },
        # No environment block — drives the system_graphql_endpoint fallback.
      }
    end

    before(:each) do
      # graphql_uri reads `environment` (Job::Environment#environment → solution.environment)
      # via the action's runbook, so the system var has to live on runbook.solution.
      runbook.solution = double(environment: {
        xurrent_ipaas_graphql_endpoint: 'https://graphql.system.example/',
      })
    end

    it 'POSTs the GraphQL query to system_graphql_endpoint when no endpoint is configured' do
      stub = stub_request(:post, 'https://graphql.system.example/')
             .to_return(body: { data: { ok: true } }.to_json)

      run_action({ query: 'query { test }' })

      expect(stub).to have_been_requested.once
    end

    it 'prefers an explicit graphql_endpoint over the system value' do
      outbound_connection_config[:environment] = {
        oauth2_endpoint: 'https://oauth.explicit.example/token',
        graphql_endpoint: 'https://graphql.explicit.example/',
      }
      explicit_stub = stub_request(:post, 'https://graphql.explicit.example/')
                      .to_return(body: { data: { ok: true } }.to_json)
      system_stub = stub_request(:post, 'https://graphql.system.example/')

      run_action({ query: 'query { test }' })

      expect(explicit_stub).to have_been_requested.once
      expect(system_stub).not_to have_been_requested
    end
  end
end
