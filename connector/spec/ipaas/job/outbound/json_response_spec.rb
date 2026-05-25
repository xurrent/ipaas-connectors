require 'spec_helper'

describe IPaaS::Job::Outbound::JsonResponse do
  class JsonResponseTestContext
    include IPaaS::Job::Context
  end

  let(:context) { JsonResponseTestContext.new }

  describe 'parse_json_response' do
    it 'returns parsed hash for valid JSON' do
      result = context.parse_json_response('{"key": "value"}')
      expect(result).to eq('key' => 'value')
    end

    it 'raises FailJob with default message for invalid JSON' do
      expect { context.parse_json_response('not json') }
        .to raise_error(IPaaS::Job::FailJob, "Response was not valid JSON: 'not json'")
    end

    it 'raises FailJob with custom message for invalid JSON' do
      expect { context.parse_json_response('not json', error_message: 'Custom error') }
        .to raise_error(IPaaS::Job::FailJob, 'Custom error')
    end
  end
end
