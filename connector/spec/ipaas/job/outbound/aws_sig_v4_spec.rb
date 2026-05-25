require 'spec_helper'

describe IPaaS::Job::Outbound::AwsSigV4 do
  let(:connector) do
    IPaaS::Connector::Connector.new('aws-test-connector') do
      outbound_connection do
        config_schema do
          field :role_arn, 'Role ARN', :string, required: true
          field :external_id, 'External ID', :string, required: true
          field :region, 'Region', :string, required: true
        end
      end
    end
  end

  let(:connection) do
    IPaaS::Connector::Connection.parse(
      {
        uuid: 'connection_uuid',
        direction: 'outbound',
        name: 'test aws connection',
        connector: {
          uuid: connector.uuid,
        },
        config_mapping: [
          { field_id: 'role_arn', fixed: 'arn:aws:iam::123456789012:role/TestRole' },
          { field_id: 'external_id', fixed: 'test-external-id' },
          { field_id: 'region', fixed: 'us-east-1' },
        ],
      },
    )
  end

  before(:each) do
    ENV['AWS_ACCOUNT_ID'] = '123456789012'
    ENV['AWS_ACCESS_KEY_ID'] = 'AKIAIOSFODNN7EXAMPLE'
    ENV['AWS_SECRET_ACCESS_KEY'] = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
  end

  after(:each) do
    ENV.delete('AWS_ACCOUNT_ID')
    ENV.delete('AWS_ACCESS_KEY_ID')
    ENV.delete('AWS_SECRET_ACCESS_KEY')
    ENV.delete('AWS_SESSION_TOKEN')
  end

  describe '#aws_account_id' do
    it 'returns the AWS account ID from environment variable' do
      expect(connection.aws_account_id).to eq('123456789012')
    end

    it 'returns N/A when environment variable is not set' do
      ENV.delete('AWS_ACCOUNT_ID')
      expect(connection.aws_account_id).to eq('Not available')
    end
  end

  describe '#parse_xml_response' do
    it 'parses valid XML and removes namespaces' do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Response xmlns="http://example.com">
          <Result>
            <Value>test</Value>
          </Result>
        </Response>
      XML

      doc = connection.parse_xml_response(xml)
      expect(doc.at_xpath('//Result/Value').text).to eq('test')
    end

    it 'handles XML without namespaces' do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Response>
          <Status>success</Status>
        </Response>
      XML

      doc = connection.parse_xml_response(xml)
      expect(doc.at_xpath('//Status').text).to eq('success')
    end

    it 'configures XML parser with security options' do
      xml = '<Root><Child>value</Child></Root>'
      doc = connection.parse_xml_response(xml)
      expect(doc).to be_a(Nokogiri::XML::Document)
      expect(doc.at_xpath('//Child').text).to eq('value')
    end

    it 'prevents XXE attacks by not substituting external entities' do
      xxe_xml = <<~XML
        <?xml version="1.0"?>
        <!DOCTYPE root [
          <!ENTITY xxe SYSTEM "file:///etc/passwd">
        ]>
        <root>&xxe;</root>
      XML

      doc = connection.parse_xml_response(xxe_xml)
      root_text = doc.at_xpath('//root')&.text || ''
      expect(root_text).not_to include('/bin/bash')
      expect(root_text).not_to include('root:')
    end
  end

  describe '#build_aws_signed_headers' do
    let(:credentials) do
      {
        access_key_id: 'AKIAIOSFODNN7EXAMPLE',
        secret_access_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        session_token: 'test-session-token',
      }
    end

    it 'generates signed headers for AWS requests' do
      url = 'https://sqs.us-east-1.amazonaws.com/'
      payload = 'Action=SendMessage&MessageBody=test'

      headers = connection.build_aws_signed_headers(
        method: 'POST',
        url: url,
        payload: payload,
        credentials: credentials,
        region: 'us-east-1',
        service: 'sqs',
        content_type: 'application/x-www-form-urlencoded'
      )

      expect(headers['Authorization']).to start_with('AWS4-HMAC-SHA256')
      expect(headers['Authorization']).to include('Credential=AKIAIOSFODNN7EXAMPLE')
      expect(headers['Authorization']).to include('SignedHeaders=')
      expect(headers['Authorization']).to include('Signature=')
      expect(headers['x-amz-date']).to match(/\d{8}T\d{6}Z/)
      expect(headers['x-amz-security-token']).to eq('test-session-token')
    end

    it 'generates signed headers without session token' do
      credentials_without_token = credentials.dup
      credentials_without_token.delete(:session_token)

      url = 'https://sts.us-east-1.amazonaws.com/'

      headers = connection.build_aws_signed_headers(
        method: 'GET',
        url: url,
        payload: '',
        credentials: credentials_without_token,
        region: 'us-east-1',
        service: 'sts'
      )

      expect(headers['Authorization']).to start_with('AWS4-HMAC-SHA256')
      expect(headers['x-amz-security-token']).to be_nil
    end

    it 'includes content-type in signature when provided' do
      url = 'https://sqs.us-east-1.amazonaws.com/'
      payload = 'test'

      headers = connection.build_aws_signed_headers(
        method: 'POST',
        url: url,
        payload: payload,
        credentials: credentials,
        region: 'us-east-1',
        service: 'sqs',
        content_type: 'application/json'
      )

      expect(headers['Authorization']).to include('content-type')
    end
  end

  describe '#aws_credentials_for_role' do
    let(:sts_response_xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <AssumeRoleResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
          <AssumeRoleResult>
            <Credentials>
              <AccessKeyId>ASIAIOSFODNN7EXAMPLE</AccessKeyId>
              <SecretAccessKey>wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY</SecretAccessKey>
              <SessionToken>FQoDYXdzEMb//////////example</SessionToken>
              <Expiration>#{(Time.now + 1.hour).utc.iso8601}</Expiration>
            </Credentials>
          </AssumeRoleResult>
        </AssumeRoleResponse>
      XML
    end

    before(:each) do
      stub_request(:get, %r{https://sts\.us-east-1\.amazonaws\.com/})
        .to_return(status: 200, body: sts_response_xml)
    end

    it 'assumes role and returns temporary credentials' do
      credentials = connection.aws_credentials_for_role(
        'arn:aws:iam::123456789012:role/TestRole',
        'test-external-id',
        'us-east-1',
        'TestSession'
      )

      expect(credentials[:access_key_id]).to eq('ASIAIOSFODNN7EXAMPLE')
      expect(credentials[:secret_access_key]).to eq('wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY')
      expect(credentials[:session_token]).to eq('FQoDYXdzEMb//////////example')
      expect(credentials[:expiration]).to be_present
    end

    it 'caches credentials to avoid repeated STS calls' do
      connection.aws_credentials_for_role(
        'arn:aws:iam::123456789012:role/TestRole',
        'test-external-id',
        'us-east-1'
      )

      connection.aws_credentials_for_role(
        'arn:aws:iam::123456789012:role/TestRole',
        'test-external-id',
        'us-east-1'
      )

      expect(WebMock).to have_requested(:get, /sts\.us-east-1\.amazonaws\.com/).once
    end

    it 'uses different cache keys for different roles' do
      connection.aws_credentials_for_role(
        'arn:aws:iam::123456789012:role/Role1',
        'external-id-1',
        'us-east-1'
      )

      connection.aws_credentials_for_role(
        'arn:aws:iam::123456789012:role/Role2',
        'external-id-2',
        'us-east-1'
      )

      expect(WebMock).to have_requested(:get, /sts\.us-east-1\.amazonaws\.com/).twice
    end

    it 'raises error when STS returns error response' do
      stub_request(:get, %r{https://sts\.us-east-1\.amazonaws\.com/})
        .to_return(status: 403, body: <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <ErrorResponse>
            <Error>
              <Message>User is not authorized to perform: sts:AssumeRole</Message>
            </Error>
          </ErrorResponse>
        XML

      expect do
        connection.aws_credentials_for_role(
          'arn:aws:iam::123456789012:role/TestRole',
          'test-external-id',
          'us-east-1'
        )
      end.to raise_error(IPaaS::Error,
                         'AWS STS call failed (HTTP 403): User is not authorized to perform: sts:AssumeRole')
    end

    it 'raises error when credentials are incomplete' do
      incomplete_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <AssumeRoleResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
          <AssumeRoleResult>
            <Credentials>
              <AccessKeyId>ASIAIOSFODNN7EXAMPLE</AccessKeyId>
            </Credentials>
          </AssumeRoleResult>
        </AssumeRoleResponse>
      XML

      stub_request(:get, %r{https://sts\.us-east-1\.amazonaws\.com/})
        .to_return(status: 200, body: incomplete_xml)

      expect do
        connection.aws_credentials_for_role(
          'arn:aws:iam::123456789012:role/TestRole',
          'test-external-id',
          'us-east-1'
        )
      end.to raise_error(IPaaS::Error, /Incomplete credentials/)
    end

    it 'uses default session name when not provided' do
      request_stub = stub_request(:get, %r{https://sts\.us-east-1\.amazonaws\.com/})
                     .with(query: hash_including('RoleSessionName' => 'XurrentIPaaSSession'))
                     .to_return(status: 200, body: sts_response_xml)

      connection.aws_credentials_for_role(
        'arn:aws:iam::123456789012:role/TestRole',
        'test-external-id',
        'us-east-1'
      )

      expect(request_stub).to have_been_requested
    end

    it 'uses custom session name when provided' do
      request_stub = stub_request(:get, %r{https://sts\.us-east-1\.amazonaws\.com/})
                     .with(query: hash_including('RoleSessionName' => 'CustomSession'))
                     .to_return(status: 200, body: sts_response_xml)

      connection.aws_credentials_for_role(
        'arn:aws:iam::123456789012:role/TestRole',
        'test-external-id',
        'us-east-1',
        'CustomSession'
      )

      expect(request_stub).to have_been_requested
    end
  end

  describe 'integration with STS AssumeRole' do
    it 'builds correct STS request with all required parameters' do
      sts_response = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <AssumeRoleResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
          <AssumeRoleResult>
            <Credentials>
              <AccessKeyId>ASIATESTACCESSKEY</AccessKeyId>
              <SecretAccessKey>testSecretKey</SecretAccessKey>
              <SessionToken>testSessionToken</SessionToken>
              <Expiration>#{(Time.now + 1.hour).utc.iso8601}</Expiration>
            </Credentials>
          </AssumeRoleResult>
        </AssumeRoleResponse>
      XML

      request_stub = stub_request(:get, 'https://sts.us-east-1.amazonaws.com/')
                     .with(query: {
                       'Action' => 'AssumeRole',
                       'RoleArn' => 'arn:aws:iam::123456789012:role/TestRole',
                       'RoleSessionName' => 'TestSession',
                       'ExternalId' => 'external-123',
                       'Version' => '2011-06-15',
                       'DurationSeconds' => '3600',
                     })
                     .to_return(status: 200, body: sts_response)

      credentials = connection.aws_credentials_for_role(
        'arn:aws:iam::123456789012:role/TestRole',
        'external-123',
        'us-east-1',
        'TestSession'
      )

      expect(credentials[:access_key_id]).to eq('ASIATESTACCESSKEY')
      expect(request_stub).to have_been_requested
    end
  end

  describe 'signature calculation' do
    it 'generates consistent signatures for identical requests' do
      credentials = {
        access_key_id: 'AKIAIOSFODNN7EXAMPLE',
        secret_access_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      }

      allow(Time).to receive(:now).and_return(Time.utc(2023, 1, 1, 12, 0, 0))

      headers1 = connection.build_aws_signed_headers(method: 'GET', url: 'https://example.com/', payload: '',
                                                     credentials: credentials, region: 'us-east-1', service: 'service')
      headers2 = connection.build_aws_signed_headers(method: 'GET', url: 'https://example.com/', payload: '',
                                                     credentials: credentials, region: 'us-east-1', service: 'service')

      expect(headers1['Authorization']).to eq(headers2['Authorization'])
    end
  end

  describe 'cache security' do
    let(:sts_response_xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <AssumeRoleResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
          <AssumeRoleResult>
            <Credentials>
              <AccessKeyId>ASIAIOSFODNN7EXAMPLE</AccessKeyId>
              <SecretAccessKey>wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY</SecretAccessKey>
              <SessionToken>FQoDYXdzEMb//////////example</SessionToken>
              <Expiration>#{(Time.now + 1.hour).utc.iso8601}</Expiration>
            </Credentials>
          </AssumeRoleResult>
        </AssumeRoleResponse>
      XML
    end

    it 'uses SHA256 hashed cache keys to prevent enumeration' do
      stub_request(:get, %r{https://sts\.us-east-1\.amazonaws\.com/})
        .to_return(status: 200, body: sts_response_xml)
      stub_request(:get, %r{https://sts\.us-west-2\.amazonaws\.com/})
        .to_return(status: 200, body: sts_response_xml)

      cache_keys = []
      allow(connection).to receive(:cache_read).and_return(nil)
      allow(connection).to receive(:cache_write) { |key, _value, _time| cache_keys << key }

      connection.aws_credentials_for_role('arn:aws:iam::111:role/Role1', 'ext-id-1', 'us-east-1')
      connection.aws_credentials_for_role('arn:aws:iam::222:role/Role2', 'ext-id-2', 'us-west-2')

      expect(cache_keys.length).to eq(2)
      cache_key1 = cache_keys[0]
      cache_key2 = cache_keys[1]

      expect(cache_key1).to match(/^aws_credentials_[a-f0-9]{64}$/)
      expect(cache_key2).to match(/^aws_credentials_[a-f0-9]{64}$/)
      expect(cache_key1).not_to eq(cache_key2)
      expect(cache_key1).not_to include('Role1')
      expect(cache_key1).not_to include('ext-id-1')
    end

    it 'cache keys are deterministic for same inputs' do
      stub_request(:get, %r{https://sts\.us-east-1\.amazonaws\.com/})
        .to_return(status: 200, body: sts_response_xml)

      cache_keys = []
      allow(connection).to receive(:cache_read).and_return(nil)
      allow(connection).to receive(:cache_write) { |key, _value, _time| cache_keys << key }

      connection.aws_credentials_for_role('arn:aws:iam::123:role/Test', 'ext-123', 'us-east-1')
      connection.aws_credentials_for_role('arn:aws:iam::123:role/Test', 'ext-123', 'us-east-1')

      expect(cache_keys.length).to eq(2)
      expect(cache_keys[0]).to eq(cache_keys[1])
    end

    it 'respects cache expiration buffer for security' do
      fixed_time = Time.now
      allow(Time).to receive(:current).and_return(fixed_time)
      allow(Time).to receive(:iso8601).and_call_original

      expiration = (fixed_time + 10.minutes).utc.iso8601
      sts_response = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <AssumeRoleResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
          <AssumeRoleResult>
            <Credentials>
              <AccessKeyId>ASIAIOSFODNN7EXAMPLE</AccessKeyId>
              <SecretAccessKey>wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY</SecretAccessKey>
              <SessionToken>FQoDYXdzEMb//////////example</SessionToken>
              <Expiration>#{expiration}</Expiration>
            </Credentials>
          </AssumeRoleResult>
        </AssumeRoleResponse>
      XML

      stub_request(:get, %r{https://sts\.us-east-1\.amazonaws\.com/})
        .to_return(status: 200, body: sts_response)

      cache_time = nil
      allow(connection).to receive(:cache_read).and_return(nil)
      allow(connection).to receive(:cache_write) { |_key, _value, time| cache_time = time }

      connection.aws_credentials_for_role('arn:aws:iam::123:role/Test', 'ext-123', 'us-east-1')

      expected_cache = (10.minutes - 300).to_i
      expect(cache_time).to be_within(2).of(expected_cache)
    end

    it 'does not cache credentials that expire too soon' do
      fixed_time = Time.now
      allow(Time).to receive(:current).and_return(fixed_time)

      expiration = (fixed_time + 2.minutes).utc.iso8601
      sts_response = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <AssumeRoleResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
          <AssumeRoleResult>
            <Credentials>
              <AccessKeyId>ASIAIOSFODNN7EXAMPLE</AccessKeyId>
              <SecretAccessKey>wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY</SecretAccessKey>
              <SessionToken>FQoDYXdzEMb//////////example</SessionToken>
              <Expiration>#{expiration}</Expiration>
            </Credentials>
          </AssumeRoleResult>
        </AssumeRoleResponse>
      XML

      stub_request(:get, %r{https://sts\.us-east-1\.amazonaws\.com/})
        .to_return(status: 200, body: sts_response)

      allow(connection).to receive(:cache_read).and_return(nil)
      expect(connection).not_to receive(:cache_write)

      connection.aws_credentials_for_role('arn:aws:iam::123:role/Test', 'ext-123', 'us-east-1')
    end
  end
end
