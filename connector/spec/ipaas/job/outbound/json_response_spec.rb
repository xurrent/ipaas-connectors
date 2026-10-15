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

  describe 'parse_json_object_or_empty' do
    it 'returns the parsed object of a JSON object' do
      expect(context.parse_json_object_or_empty('{"error": {"code": "E1"}}')).to eq('error' => { 'code' => 'E1' })
    end

    it 'returns an empty hash for a body that is not JSON' do
      expect(context.parse_json_object_or_empty('<html>Bad gateway</html>')).to eq({})
    end

    it 'returns an empty hash for JSON that is not an object' do
      expect(context.parse_json_object_or_empty('[1, 2]')).to eq({})
    end

    it 'returns an empty hash for a missing body' do
      expect(context.parse_json_object_or_empty(nil)).to eq({})
    end
  end
end
