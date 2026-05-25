RSpec.shared_examples 'xurrent_imr rate limiting' do
  # Including specs must define:
  #   let(:rate_limit_url)         - URL to stub
  #   let(:rate_limit_http_method) - :get, :post, or :patch
  #   let(:rate_limit_input)       - input hash for run_action (can be nil)

  context 'when rate limited with Retry-After' do
    before do
      stub_request(rate_limit_http_method, rate_limit_url)
        .to_return(status: 429, headers: { 'Retry-After' => '45' })
    end

    it 'raises RescheduleJob with correct reschedule_after' do
      Timecop.freeze do
        expect { run_action(rate_limit_input) }
          .to raise_error(IPaaS::Job::RescheduleJob) { |error|
            expect(error.reschedule_after).to eq(45.seconds.from_now)
          }
      end
    end
  end

  context 'when rate limited without Retry-After' do
    before do
      stub_request(rate_limit_http_method, rate_limit_url)
        .to_return(status: 429)
    end

    it 'raises RescheduleJob with default reschedule_after' do
      Timecop.freeze do
        expect { run_action(rate_limit_input) }
          .to raise_error(IPaaS::Job::RescheduleJob) { |error|
            expect(error.reschedule_after).to eq(60.seconds.from_now)
          }
      end
    end
  end
end
