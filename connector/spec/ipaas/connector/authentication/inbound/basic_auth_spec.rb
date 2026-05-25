require 'spec_helper'

describe IPaaS::Connector::Authentication::Inbound::BasicAuth do
  let(:connector) do
    IPaaS::Connector::Connector.new('uuid') do
      inbound_connection do
        basic_auth_validator
      end
    end
  end

  it 'should register the key' do
    expect(IPaaS::Connector::Authentication::Inbound.keys).to include(:basic_auth)
  end

  describe 'schema' do
    let(:basic_auth_field) do
      connector.inbound_connection.config_schema.field(:basic_auth)
    end

    it 'should define the top-level basic auth field' do
      expect(basic_auth_field.label).to eq('Basic authentication')
      expect(basic_auth_field.hint).not_to be_nil
      expect(basic_auth_field.visibility).to eq('optional')
      expect(basic_auth_field.fields.size).to eq(2)
    end

    it 'should define the username field' do
      username_field = basic_auth_field.field(:username)
      expect(username_field.label).to eq('Username')
      expect(username_field.type).to eq(:string)
      expect(username_field.required).to be_truthy
    end

    it 'should define the password field' do
      password_field = basic_auth_field.field(:password)
      expect(password_field.label).to eq('Password')
      expect(password_field.type).to eq(:secret_string)
      expect(password_field.required).to be_truthy
    end
  end

  describe 'validate' do
    let(:connection) do
      IPaaS::Connector::Connection.parse(
        {
          uuid: 'connection-uuid',
          direction: 'inbound',
          name: 'test inbound connection',
          connector: {
            uuid: connector.uuid,
          },
          config_mapping: [
            { field_id: 'basic_auth', nested: [
              { field_id: 'username', fixed: 'john' },
              { field_id: 'password', fixed: make_secret_string('secret:xurrent').to_s },
            ], },
          ],
        },
      )
    end

    let(:request) do
      headers = { 'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64('john:secret:xurrent')}" }
      Rack::Request.new(Rack::MockRequest.env_for('https://ipaas.xurrent.com/example?foo=bar&baz=bie', headers))
    end

    it 'should accept a valid request' do
      connection.validate_request(request)
    end

    describe 'is strict' do
      let(:request) do
        headers = { 'HTTP_AUTHORIZATION' => "Basic #{Base64.encode64('john:secret:xurrent')}" }
        Rack::Request.new(Rack::MockRequest.env_for('https://ipaas.xurrent.com/example?foo=bar&baz=bie', headers))
      end

      it 'rejects base64 with trailing newlines' do
        expect(connection).to receive(:fail_job!).with('Invalid basic authentication header.') { raise 'Failed' }

        expect do
          connection.validate_request(request)
        end.to raise_error('Failed')
      end
    end

    it 'should fail the job when the basic auth header is missing' do
      request.headers['Authorization'] = nil
      expect(connection).to receive(:fail_job!).with('Missing basic authentication header.') { raise 'Failed' }
      expect do
        connection.validate_request(request)
      end.to raise_error('Failed')
    end

    it 'should fail the job when the basic auth header is invalid Base64' do
      request.headers['Authorization'] = 'Basic THISISNOTBASE64'
      expect(connection).to receive(:fail_job!).with('Invalid basic authentication header.') { raise 'Failed' }
      expect do
        connection.validate_request(request)
      end.to raise_error('Failed')
    end

    it 'should fail the job when the basic auth username is incorrect' do
      connection.config[:basic_auth][:username] = 'foo'
      expect(connection).to receive(:fail_job!).with('Invalid basic authentication header.') { raise 'Failed' }
      expect do
        connection.validate_request(request)
      end.to raise_error('Failed')
    end

    it 'should fail the job when the basic auth password is incorrect' do
      connection.config[:basic_auth][:password] = make_secret_string('foo')
      expect(connection).to receive(:fail_job!).with('Invalid basic authentication header.') { raise 'Failed' }
      expect do
        connection.validate_request(request)
      end.to raise_error('Failed')
    end

    it 'should not ignore the part of the password beyond colon' do
      connection.config[:basic_auth][:password] = make_secret_string('john:secret')
      expect(connection).to receive(:fail_job!).with('Invalid basic authentication header.') { raise 'Failed' }
      expect do
        connection.validate_request(request)
      end.to raise_error('Failed')
    end
  end
end
