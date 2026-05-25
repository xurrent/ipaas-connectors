module GraphqlErrorHandlingSpecs
  def self.included(base)
    base.class_eval do
      it 'triggers backoff on 429 response with correct reschedule_after and retry-after in message' do
        stub_request(:post, graphql_endpoint)
          .with { |req| !req.body.include?('__schema') }
          .to_return(status: 429, body: 'Rate limited', headers: { 'Retry-After' => '30' })

        expect { run_action(action_input) }.to raise_error(IPaaS::Job::RescheduleJob, /rate limit/i) do |error|
          expect(error.message).to include('retry after: 30')
          expect(error.reschedule_after).to be_within(1.seconds).of(Time.current + 30.seconds)
        end
      end

      it 'triggers backoff on 503 response with correct reschedule_after and retry-after in message' do
        stub_request(:post, graphql_endpoint)
          .with { |req| !req.body.include?('__schema') }
          .to_return(status: 503, body: 'Service unavailable', headers: { 'Retry-After' => '60' })

        expect { run_action(action_input) }.to raise_error(IPaaS::Job::RescheduleJob, /not available/i) do |error|
          expect(error.message).to include('retry after: 60')
          expect(error.reschedule_after).to be_within(1.seconds).of(Time.current + 60.seconds)
        end
      end

      it 'fails on GraphQL errors in response' do
        stub_request(:post, graphql_endpoint)
          .with { |req| !req.body.include?('__schema') }
          .to_return(
            status: 200,
            body: { errors: [{ 'message' => 'Not authorized' }] }.to_json,
            headers: graphql_response_headers,
          )

        expect { run_action(action_input) }.to raise_error(IPaaS::Job::FailJob, /Not authorized/)
      end
    end
  end
end
