require 'spec_helper'

describe IPaaS::Job::Outbound::XurrentRateLimits do
  class XurrentRateLimitsTestContext
    include IPaaS::Job::Context
  end

  let(:context) { XurrentRateLimitsTestContext.new }
  let(:response) { double('Response', headers: headers) }

  describe 'xurrent_rate_limit_from_headers' do
    context 'when all rate-limit headers are present' do
      let(:headers) do
        {
          'x-ratelimit-limit' => '7200',
          'x-ratelimit-remaining' => '7188',
          'x-ratelimit-reset' => '1714492800',
        }
      end

      it 'returns a hash with limit, remaining, reset populated from the headers' do
        expect(context.xurrent_rate_limit_from_headers(response))
          .to eq(limit: '7200', remaining: '7188', reset: '1714492800')
      end
    end

    context 'when rate-limit headers are absent' do
      let(:headers) { {} }

      it 'returns a hash with nil values' do
        expect(context.xurrent_rate_limit_from_headers(response))
          .to eq(limit: nil, remaining: nil, reset: nil)
      end
    end

    context 'when only some rate-limit headers are present' do
      let(:headers) { { 'x-ratelimit-remaining' => '42' } }

      it 'returns a hash with the present value and nil for missing headers' do
        expect(context.xurrent_rate_limit_from_headers(response))
          .to eq(limit: nil, remaining: '42', reset: nil)
      end
    end
  end

  describe 'xurrent_cost_limit_from_headers' do
    context 'when all cost-limit headers are present' do
      let(:headers) do
        {
          'x-costlimit-limit' => '5000',
          'x-costlimit-cost' => '12',
          'x-costlimit-remaining' => '4988',
          'x-costlimit-reset' => '1714492800',
        }
      end

      it 'returns a hash with limit, cost, remaining, reset populated from the headers' do
        expect(context.xurrent_cost_limit_from_headers(response))
          .to eq(limit: '5000', cost: '12', remaining: '4988', reset: '1714492800')
      end
    end

    context 'when cost-limit headers are absent' do
      let(:headers) { {} }

      it 'returns a hash with nil values' do
        expect(context.xurrent_cost_limit_from_headers(response))
          .to eq(limit: nil, cost: nil, remaining: nil, reset: nil)
      end
    end

    context 'when rate-limit headers are present but cost-limit headers are not' do
      let(:headers) do
        {
          'x-ratelimit-limit' => '7200',
          'x-ratelimit-remaining' => '7188',
        }
      end

      it 'returns a cost-limit hash with all nil values, ignoring the rate-limit headers' do
        expect(context.xurrent_cost_limit_from_headers(response))
          .to eq(limit: nil, cost: nil, remaining: nil, reset: nil)
      end
    end
  end
end
