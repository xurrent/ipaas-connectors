require 'spec_helper'

describe IPaaS::Job::BasicAuth do
  class BasicAuthTestContext
    include IPaaS::Job::Context
  end

  let(:context) { BasicAuthTestContext.new }
  let(:request) { double('Request', headers: headers) }
  let(:headers) { { 'Authorization' => "Basic #{Base64.strict_encode64('user:pass')}" } }

  describe 'basic_auth_credentials' do
    it 'returns user_name and password from Basic Auth header' do
      result = context.basic_auth_credentials(request.headers)
      expect(result).to eq(%w[user pass])
    end

    it 'preserves colons in password' do
      allow(request).to receive(:headers)
        .and_return({ 'Authorization' => "Basic #{Base64.strict_encode64('user:pa:ss')}" })
      result = context.basic_auth_credentials(request.headers)
      expect(result).to eq(%w[user pa:ss])
    end

    it 'rejects blank credentials' do
      allow(request).to receive(:headers).and_return({ 'Authorization' => 'Basic ' })
      result = context.basic_auth_credentials(request.headers)
      expect(result).to eq([nil, nil])
    end

    it 'rejects base64 with trailing newlines' do
      allow(request).to receive(:headers)
        .and_return({ 'Authorization' => "Basic #{Base64.encode64('user:pass')}" })
      result = context.basic_auth_credentials(request.headers)
      expect(result).to eq([nil, nil])
    end

    context 'with strict: false' do
      it 'tolerates base64 with trailing newlines' do
        allow(request).to receive(:headers)
          .and_return({ 'Authorization' => "Basic #{Base64.encode64('user:pass')}" })
        result = context.basic_auth_credentials(request.headers, strict: false)
        expect(result).to eq(%w[user pass])
      end

      it 'preserves colons in password' do
        allow(request).to receive(:headers)
          .and_return({ 'Authorization' => "Basic #{Base64.encode64('user:pa:ss')}" })
        result = context.basic_auth_credentials(request.headers, strict: false)
        expect(result).to eq(%w[user pa:ss])
      end
    end

    it 'raises FailJob when Authorization header is missing' do
      allow(request).to receive(:headers).and_return({})
      expect { context.basic_auth_credentials(request.headers) }
        .to raise_error(IPaaS::Job::FailJob, 'Missing basic authentication header.')
    end

    it 'raises FailJob when Authorization header is not Basic' do
      allow(request).to receive(:headers).and_return({ 'Authorization' => 'Bearer token' })
      expect { context.basic_auth_credentials(request.headers) }
        .to raise_error(IPaaS::Job::FailJob, 'Missing basic authentication header.')
    end
  end
end
