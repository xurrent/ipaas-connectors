require 'spec_helper'

describe IPaaS::Job::PsaAuth do
  class PsaAuthTestContext
    include IPaaS::Job::Context
  end

  let(:context) { PsaAuthTestContext.new }
  let(:store) { double('Store') }
  let(:outbound_connection) { double('OutboundConnection', store: store) }
  let(:inbound_config) { {} }
  let(:inbound_connection) { double('InboundConnection', config: inbound_config) }
  let(:request) { double('Request', headers: headers) }
  let(:headers) { { 'Authorization' => "Basic #{Base64.strict_encode64('user:pass')}" } }

  before do
    allow(context).to receive(:outbound_connection).and_return(outbound_connection)
    allow(context).to receive(:inbound_connection).and_return(inbound_connection)
  end

  describe 'psa_extract_basic_auth' do
    it 'returns user_name and password from Basic Auth header' do
      result = context.psa_extract_basic_auth(request)
      expect(result).to eq(%w[user pass])
    end

    it 'preserves colons in password' do
      allow(request).to receive(:headers)
        .and_return({ 'Authorization' => "Basic #{Base64.strict_encode64('user:pa:ss')}" })
      result = context.psa_extract_basic_auth(request)
      expect(result).to eq(%w[user pa:ss])
    end

    context 'with strict: true (default)' do
      it 'rejects base64 with trailing newlines' do
        allow(request).to receive(:headers)
          .and_return({ 'Authorization' => "Basic #{Base64.encode64('user:pass')}" })
        expect { context.psa_extract_basic_auth(request) }
          .to raise_error(IPaaS::Job::FailJob, 'Invalid basic authentication header.')
      end
    end

    context 'with strict: false' do
      it 'tolerates base64 with trailing newlines' do
        allow(request).to receive(:headers)
          .and_return({ 'Authorization' => "Basic #{Base64.encode64('user:pass')}" })
        result = context.psa_extract_basic_auth(request, strict: false)
        expect(result).to eq(%w[user pass])
      end

      it 'preserves colons in password' do
        allow(request).to receive(:headers)
          .and_return({ 'Authorization' => "Basic #{Base64.encode64('user:pa:ss')}" })
        result = context.psa_extract_basic_auth(request, strict: false)
        expect(result).to eq(%w[user pa:ss])
      end
    end

    it 'raises FailJob when Authorization header is missing' do
      allow(request).to receive(:headers).and_return({})
      expect { context.psa_extract_basic_auth(request) }
        .to raise_error(IPaaS::Job::FailJob, 'Missing basic authentication header.')
    end

    it 'raises FailJob when Authorization header is not Basic' do
      allow(request).to receive(:headers).and_return({ 'Authorization' => 'Bearer token' })
      expect { context.psa_extract_basic_auth(request) }
        .to raise_error(IPaaS::Job::FailJob, 'Missing basic authentication header.')
    end

    it 'raises FailJob when credentials are blank' do
      allow(request).to receive(:headers).and_return({ 'Authorization' => 'Basic ' })
      expect { context.psa_extract_basic_auth(request) }
        .to raise_error(IPaaS::Job::FailJob, 'Invalid basic authentication header.')
    end
  end

  describe 'psa_validate_secret' do
    context 'with fixed credentials in inbound config' do
      let(:inbound_config) { { user_name: 'user', password: 'encrypted_pass' } }

      it 'validates when credentials match' do
        allow(context).to receive(:decrypt_secret_string).with('encrypted_pass').and_return('pass')
        expect { context.psa_validate_secret(request) }.not_to raise_error
      end

      it 'raises FailJob when user_name does not match' do
        allow(request).to receive(:headers)
          .and_return({ 'Authorization' => "Basic #{Base64.strict_encode64('wrong:pass')}" })
        expect { context.psa_validate_secret(request) }
          .to raise_error(IPaaS::Job::FailJob, 'Invalid basic authentication header.')
      end

      it 'raises FailJob when password does not match' do
        allow(context).to receive(:decrypt_secret_string).with('encrypted_pass').and_return('other')
        expect { context.psa_validate_secret(request) }
          .to raise_error(IPaaS::Job::FailJob, 'Invalid basic authentication header.')
      end
    end

    context 'with dynamic credentials from store' do
      let(:inbound_config) { {} }

      it 'validates when stored secret matches' do
        allow(store).to receive(:read).with('secret#user').and_return('encrypted_pass')
        allow(context).to receive(:decrypt_secret_string).with('encrypted_pass').and_return('pass')
        expect { context.psa_validate_secret(request) }.not_to raise_error
      end

      it 'raises FailJob when no stored secret exists' do
        allow(store).to receive(:read).with('secret#user').and_return(nil)
        expect { context.psa_validate_secret(request) }
          .to raise_error(IPaaS::Job::FailJob, 'Invalid basic authentication header.')
      end
    end
  end

  describe 'psa_generate_secret_for' do
    it 'creates a secret and stores it' do
      allow(context).to receive(:make_secret_string).and_return('encrypted_uuid')
      expect(store).to receive(:write).with('secret#user', 'encrypted_uuid')
      result = context.psa_generate_secret_for('user')
      expect(result).to eq('encrypted_uuid')
    end
  end

  describe 'psa_secret_for' do
    it 'reads the stored secret' do
      expect(store).to receive(:read).with('secret#user').and_return('encrypted_pass')
      expect(context.psa_secret_for('user')).to eq('encrypted_pass')
    end
  end

  describe 'psa_delete_secret_for' do
    it 'deletes the stored secret' do
      expect(store).to receive(:delete).with('secret#user')
      context.psa_delete_secret_for('user')
    end
  end
end
