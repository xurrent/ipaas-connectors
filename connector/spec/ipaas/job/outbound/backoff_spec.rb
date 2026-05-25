require 'spec_helper'

describe IPaaS::Job::Outbound::Backoff do
  class BackoffTestContext
    include IPaaS::Job::Context
  end

  let(:context) { BackoffTestContext.new }
  let(:response) { double('Response', status: status, headers: headers, body: 'response body') }
  let(:headers) { {} }

  describe 'backoff_if_needed' do
    context 'when response status is 200' do
      let(:status) { 200 }

      it 'does not raise' do
        expect { context.backoff_if_needed(response, api_name: 'Test') }.not_to raise_error
      end
    end

    context 'when response status is 429' do
      let(:status) { 429 }

      it 'raises RescheduleJob with default retry_after when no header present' do
        Timecop.freeze do
          expect_any_instance_of(Logger).to receive(:info)
          expect { context.backoff_if_needed(response, api_name: 'Test') }
            .to raise_error(IPaaS::Job::RescheduleJob, "Test API rate limit hit. 'response body'") do |e|
            expect(e.reschedule_after).to eq(60.seconds.from_now)
          end
        end
      end

      context 'with numeric Retry-After header' do
        let(:headers) { { 'Retry-After' => '120' } }

        it 'raises RescheduleJob with parsed retry_after seconds' do
          Timecop.freeze do
            expect_any_instance_of(Logger).to receive(:info)
            expect { context.backoff_if_needed(response, api_name: 'Test') }
              .to raise_error(IPaaS::Job::RescheduleJob,
                              "Test API rate limit hit (retry after: 120). 'response body'") do |e|
              expect(e.reschedule_after).to eq(120.seconds.from_now)
            end
          end
        end
      end

      context 'with RFC date Retry-After header in the future' do
        let(:future_time) { 90.seconds.from_now }
        let(:headers) { { 'Retry-After' => future_time.httpdate } }

        it 'raises RescheduleJob with parsed time delta' do
          Timecop.freeze do
            expect_any_instance_of(Logger).to receive(:info)
            expect { context.backoff_if_needed(response, api_name: 'Test') }
              .to raise_error(IPaaS::Job::RescheduleJob) do |e|
              expect(e.reschedule_after).to be_within(2.seconds).of(future_time)
            end
          end
        end
      end

      context 'with RFC date Retry-After header in the past' do
        let(:headers) { { 'Retry-After' => 10.seconds.ago.httpdate } }

        it 'falls back to default retry_after' do
          Timecop.freeze do
            expect_any_instance_of(Logger).to receive(:info)
            expect { context.backoff_if_needed(response, api_name: 'Test') }
              .to raise_error(IPaaS::Job::RescheduleJob) do |e|
              expect(e.reschedule_after).to eq(60.seconds.from_now)
            end
          end
        end
      end

      context 'with invalid Retry-After header' do
        let(:headers) { { 'Retry-After' => 'not-a-date' } }

        it 'falls back to default retry_after' do
          Timecop.freeze do
            expect_any_instance_of(Logger).to receive(:info)
            expect { context.backoff_if_needed(response, api_name: 'Test') }
              .to raise_error(IPaaS::Job::RescheduleJob) do |e|
              expect(e.reschedule_after).to eq(60.seconds.from_now)
            end
          end
        end
      end
    end

    context 'when response status is 503' do
      let(:status) { 503 }

      it 'raises RescheduleJob with not available message' do
        Timecop.freeze do
          expect_any_instance_of(Logger).to receive(:info)
          expect { context.backoff_if_needed(response, api_name: 'Test') }
            .to raise_error(IPaaS::Job::RescheduleJob, "Test API not available. 'response body'") do |e|
            expect(e.reschedule_after).to eq(60.seconds.from_now)
          end
        end
      end
    end

    context 'with custom header_name' do
      let(:status) { 429 }
      let(:headers) { { 'X-RateLimit-Reset' => '30' } }

      it 'reads from the specified header' do
        Timecop.freeze do
          expect_any_instance_of(Logger).to receive(:info)
          expect { context.backoff_if_needed(response, api_name: 'Test', header_name: 'X-RateLimit-Reset') }
            .to raise_error(IPaaS::Job::RescheduleJob) do |e|
            expect(e.reschedule_after).to eq(30.seconds.from_now)
          end
        end
      end
    end

    context 'with custom server_error_statuses' do
      let(:status) { 500 }

      it 'triggers backoff for statuses in the custom list' do
        Timecop.freeze do
          expect_any_instance_of(Logger).to receive(:info)
          expect { context.backoff_if_needed(response, api_name: 'Test', server_error_statuses: [500, 502, 503]) }
            .to raise_error(IPaaS::Job::RescheduleJob, "Test API not available. 'response body'") do |e|
            expect(e.reschedule_after).to eq(60.seconds.from_now)
          end
        end
      end
    end

    context 'with custom default_retry_after' do
      let(:status) { 429 }

      it 'uses the provided default' do
        Timecop.freeze do
          expect_any_instance_of(Logger).to receive(:info)
          expect { context.backoff_if_needed(response, api_name: 'Test', default_retry_after: 30) }
            .to raise_error(IPaaS::Job::RescheduleJob) do |e|
            expect(e.reschedule_after).to eq(30.seconds.from_now)
          end
        end
      end
    end
  end
end
