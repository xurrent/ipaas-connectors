module GraphqlConnectorErrorHandlingSpecs
  def self.included(base)
    base.class_eval do
      it 'triggers backoff on 429 response without retry-after' do
        stub_request(:post, graphql_endpoint)
          .with { |req| !req.body.include?('__schema') }
          .to_return(status: 429, body: 'Rate limited')

        Timecop.freeze do
          expect { run_action(action_input) }
            .to raise_error(IPaaS::Job::RescheduleJob, /rate limit/i) do |e|
            expect(e.reschedule_after).to eq(1.minute.from_now)
          end
        end
      end

      it 'triggers backoff on 429 response with retry-after' do
        stub_request(:post, graphql_endpoint)
          .with { |req| !req.body.include?('__schema') }
          .to_return(status: 429, body: 'Rate limited', headers: { 'Retry-After' => '5' })

        Timecop.freeze do
          expect { run_action(action_input) }
            .to raise_error(IPaaS::Job::RescheduleJob, /rate limit/i) do |e|
            expect(e.message).to include('retry after: 5')
            expect(e.reschedule_after).to eq(5.seconds.from_now)
          end
        end
      end

      it 'triggers backoff on 503 response' do
        stub_request(:post, graphql_endpoint)
          .with { |req| !req.body.include?('__schema') }
          .to_return(status: 503, body: 'Service Unavailable')

        Timecop.freeze do
          expect { run_action(action_input) }
            .to raise_error(IPaaS::Job::RescheduleJob, /not available/i) do |e|
            expect(e.reschedule_after).to eq(1.minute.from_now)
          end
        end
      end

      it 'fails on HTTP errors' do
        stub_request(:post, graphql_endpoint)
          .with { |req| !req.body.include?('__schema') }
          .to_return(status: 401, body: '{"message":"Unauthorized"}')

        expect { run_action(action_input) }
          .to raise_error(IPaaS::Job::FailJob, /HTTP error from GraphQL API: 401/)
      end

      it 'fails on GraphQL errors in body' do
        stub_request(:post, graphql_endpoint)
          .with { |req| !req.body.include?('__schema') }
          .to_return(body: { errors: [{ message: 'Field not found' }] }.to_json)

        expect { run_action(action_input) }
          .to raise_error(IPaaS::Job::FailJob, /Errors from GraphQL API:.*Field not found/)
      end

      it 'fails on missing data in response' do
        stub_request(:post, graphql_endpoint)
          .with { |req| !req.body.include?('__schema') }
          .to_return(body: {}.to_json)

        expect { run_action(action_input) }
          .to raise_error(IPaaS::Job::FailJob, 'No data from GraphQL API')
      end

      it 'ignores empty errors in body' do
        stub_request(:post, graphql_endpoint)
          .with { |req| !req.body.include?('__schema') }
          .to_return(
            body: { errors: [], data: graphql_success_data }.to_json,
            headers: graphql_response_headers,
          )

        output = run_action(action_input)
        expect(output).to be_present
      end
    end
  end
end
