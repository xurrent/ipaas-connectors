require 'spec_helper'

describe 'Amazon SQS Send Message Action', :action do
  let(:connector_id) { '49885952-c9e3-4841-9e06-43bcf879902a' }
  let(:action_template_id) { 'ad0dc183-7de4-4252-97b9-a07247ab894b' }

  let(:outbound_connection_config) do
    {
      aws_credentials: {
        role_arn: 'arn:aws:iam::123456789012:role/TestRole',
        region: 'us-east-1',
      },
    }
  end

  describe 'input_schema' do
    it 'defines queue_url field' do
      action.input_schema.field(:queue_url).tap do |field|
        expect(field.label).to eq('Queue URL')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
        expect(field.pattern).to eq(%r{\Ahttps://sqs\.[a-z0-9-]+\.amazonaws\.com/\d+/[a-zA-Z0-9_.-]+\z})
      end
    end

    it 'defines message_body field' do
      action.input_schema.field(:message_body).tap do |field|
        expect(field.label).to eq('Message Body')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
        expect(field.max_length).to eq(262_144)
      end
    end

    it 'defines delay_seconds field' do
      action.input_schema.field(:delay_seconds).tap do |field|
        expect(field.label).to eq('Delay Seconds')
        expect(field.type).to eq(:integer)
        expect(field.required).to be_falsey
        expect(field.min).to eq(0)
        expect(field.max).to eq(900)
        expect(field.default).to eq(0)
      end
    end

    it 'defines message_group_id field' do
      action.input_schema.field(:message_group_id).tap do |field|
        expect(field.label).to eq('Message Group ID')
        expect(field.type).to eq(:string)
        expect(field.required).to be_falsey
      end
    end

    it 'defines message_deduplication_id field' do
      action.input_schema.field(:message_deduplication_id).tap do |field|
        expect(field.label).to eq('Message Deduplication ID')
        expect(field.type).to eq(:string)
        expect(field.required).to be_falsey
      end
    end

    describe 'message_attributes nested field' do
      let(:field) { action.input_schema.field(:message_attributes) }

      it 'is defined as nested array' do
        expect(field.label).to eq('Message Attributes')
        expect(field.type).to eq(:nested)
        expect(field.array).to eq(true)
        expect(field.required).to be_falsey
      end

      it 'has name subfield' do
        field.field(:name).tap do |f|
          expect(f.label).to eq('Name')
          expect(f.type).to eq(:string)
          expect(f.required).to be_truthy
        end
      end

      it 'has value subfield' do
        field.field(:value).tap do |f|
          expect(f.label).to eq('Value')
          expect(f.type).to eq(:string)
          expect(f.required).to be_truthy
        end
      end

      it 'has data_type subfield with enumeration' do
        field.field(:data_type).tap do |f|
          expect(f.label).to eq('Data Type')
          expect(f.type).to eq(:string)
          expect(f.enumeration.map { |e| e[:id] }).to contain_exactly('String', 'Number', 'Binary')
          expect(f.default).to eq('String')
        end
      end
    end
  end

  describe 'output_schema' do
    let(:output_schema) { action.output_schema.first }

    it 'has standard output schema' do
      expect(action.output_schema.map(&:reference)).to contain_exactly('output')
    end

    it 'defines message_id field' do
      output_schema.field(:message_id).tap do |field|
        expect(field.label).to eq('Message ID')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end
    end

    it 'defines md5_of_message_body field' do
      output_schema.field(:md5_of_message_body).tap do |field|
        expect(field.label).to eq('MD5 of Message Body')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end
    end

    it 'defines md5_of_message_attributes field' do
      output_schema.field(:md5_of_message_attributes).tap do |field|
        expect(field.label).to eq('MD5 of Message Attributes')
        expect(field.type).to eq(:string)
        expect(field.required).to be_falsey
      end
    end

    it 'defines sequence_number field' do
      output_schema.field(:sequence_number).tap do |field|
        expect(field.label).to eq('Sequence Number')
        expect(field.type).to eq(:string)
        expect(field.required).to be_falsey
      end
    end
  end

  describe 'run' do
    def run_action(input = nil, schema_reference: nil)
      remove_instance_variable(:@action) if defined?(@action)
      super
    end

    def setup_sts_credentials
      ENV['AWS_ACCESS_KEY_ID'] = 'AKIAIOSFODNN7EXAMPLE'
      ENV['AWS_SECRET_ACCESS_KEY'] = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
    end

    def sts_assume_role_params
      {
        'Action' => 'AssumeRole',
        'RoleArn' => 'arn:aws:iam::123456789012:role/TestRole',
        'RoleSessionName' => 'XurrentIPaaSSession',
        'ExternalId' => 'test-external-id-12345',
        'Version' => '2011-06-15',
        'DurationSeconds' => '3600',
      }
    end

    def stub_sts_assume_role
      setup_sts_credentials
      sts_url = 'https://sts.us-east-1.amazonaws.com/'
      query_string = URI.encode_www_form(sts_assume_role_params)

      @stubbed_sts_expiration ||= Time.now + 1.hour
      stub_request(:get, "#{sts_url}?#{query_string}")
        .with(headers: { 'Authorization' => /AWS4-HMAC-SHA256/ })
        .to_return(status: 200, body: sts_response_xml)
    end

    def sts_response_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <AssumeRoleResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
          <AssumeRoleResult>
            <Credentials>
              <AccessKeyId>ASIAIOSFODNN7EXAMPLE</AccessKeyId>
              <SecretAccessKey>wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY</SecretAccessKey>
              <SessionToken>FQoDYXdzEMb//////////example</SessionToken>
              <Expiration>#{@stubbed_sts_expiration.utc.iso8601}</Expiration>
            </Credentials>
          </AssumeRoleResult>
        </AssumeRoleResponse>
      XML
    end

    def build_sqs_response_body(message_id, md5_body, md5_attrs, sequence)
      xml = "    <MessageId>#{message_id}</MessageId>\n"
      xml += "    <MD5OfMessageBody>#{md5_body}</MD5OfMessageBody>\n"
      xml += "    <MD5OfMessageAttributes>#{md5_attrs}</MD5OfMessageAttributes>\n" if md5_attrs
      xml += "    <SequenceNumber>#{sequence}</SequenceNumber>\n" if sequence
      xml
    end

    def sqs_success_response_xml(message_id: 'msg-12345', md5_body: '5d41402abc4b2a76b9719d911017c592',
                                 md5_attrs: nil, sequence: nil)
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <SendMessageResponse xmlns="http://queue.amazonaws.com/doc/2012-11-05/">
          <SendMessageResult>
        #{build_sqs_response_body(message_id, md5_body, md5_attrs, sequence)}  </SendMessageResult>
        </SendMessageResponse>
      XML
    end

    def sqs_error_response_xml(code, message)
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <ErrorResponse>
          <Error>
            <Code>#{code}</Code>
            <Message>#{message}</Message>
          </Error>
        </ErrorResponse>
      XML
    end

    before(:each) do
      action.outbound_connection.provision
      allow(action.outbound_connection.store).to receive(:read).and_call_original
      allow(action.outbound_connection.store).to receive(:read).with('external_id')
                                                               .and_return('test-external-id-12345')

      @sts_stub = stub_sts_assume_role
    end

    it 'sends basic message successfully' do
      Timecop.freeze(@stubbed_sts_expiration - 11.minutes)
      expected_expiry = (11.minutes - IPaaS::Job::Outbound::AwsSigV4::AWS_CACHE_BUFFER_SECONDS.seconds).to_i

      expect(outbound_connection).to receive(:cache_read) do |key|
        @sts_cache_key = key
        nil
      end
      expect(outbound_connection).to receive(:cache_write) do |key, credentials, expiry|
        expect(key).to eq(@sts_cache_key)
        expect(expiry).to eq(expected_expiry)
        expect(credentials)
          .to include(access_key_id: 'ASIAIOSFODNN7EXAMPLE',
                      secret_access_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
                      session_token: 'FQoDYXdzEMb//////////example',)
      end

      queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

      sqs_stub = stub_request(:post, queue_url)
                 .with do |request|
        body = URI.decode_www_form(request.body).to_h
        body['Action'] == 'SendMessage' &&
          body['MessageBody'] == 'Test message' &&
          body['Version'] == '2012-11-05'
      end
                   .to_return(status: 200, body: sqs_success_response_xml)

      output = run_action({
        queue_url: queue_url,
        message_body: 'Test message',
      })

      expect(output[:message_id]).to eq('msg-12345')
      expect(output[:md5_of_message_body]).to eq('5d41402abc4b2a76b9719d911017c592')
      expect(output[:md5_of_message_attributes]).to be_nil
      expect(output[:sequence_number]).to be_nil
      expect(sqs_stub).to have_been_requested.once
      expect(@sts_stub).to have_been_requested.once
    end

    it 'sends message with delay' do
      queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

      sqs_stub = stub_request(:post, queue_url)
                 .with do |request|
        body = URI.decode_www_form(request.body).to_h
        body['Action'] == 'SendMessage' &&
          body['MessageBody'] == 'Delayed message' &&
          body['DelaySeconds'] == '60'
      end
                   .to_return(status: 200, body: sqs_success_response_xml)

      output = run_action({
        queue_url: queue_url,
        message_body: 'Delayed message',
        delay_seconds: 60,
      })

      expect(output[:message_id]).to eq('msg-12345')
      expect(sqs_stub).to have_been_requested.once
    end

    it 'sends message without delay when delay is zero' do
      queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

      sqs_stub = stub_request(:post, queue_url)
                 .with do |request|
        body = URI.decode_www_form(request.body).to_h
        body['Action'] == 'SendMessage' &&
          body['MessageBody'] == 'No delay' &&
          !body.key?('DelaySeconds')
      end
                   .to_return(status: 200, body: sqs_success_response_xml)

      output = run_action({
        queue_url: queue_url,
        message_body: 'No delay',
        delay_seconds: 0,
      })

      expect(output[:message_id]).to eq('msg-12345')
      expect(sqs_stub).to have_been_requested.once
    end

    it 'sends message with single attribute' do
      queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

      sqs_stub = stub_request(:post, queue_url)
                 .with do |request|
        body = URI.decode_www_form(request.body).to_h
        body['Action'] == 'SendMessage' &&
          body['MessageBody'] == 'Message with attributes' &&
          body['MessageAttribute.1.Name'] == 'Author' &&
          body['MessageAttribute.1.Value.StringValue'] == 'John' &&
          body['MessageAttribute.1.Value.DataType'] == 'String'
      end
                   .to_return(status: 200, body: sqs_success_response_xml(md5_attrs: 'abc123'))

      output = run_action({
        queue_url: queue_url,
        message_body: 'Message with attributes',
        message_attributes: [
          { name: 'Author', value: 'John', data_type: 'String' },
        ],
      })

      expect(output[:message_id]).to eq('msg-12345')
      expect(output[:md5_of_message_attributes]).to eq('abc123')
      expect(sqs_stub).to have_been_requested.once
    end

    it 'sends message with multiple attributes' do
      queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

      sqs_stub = stub_request(:post, queue_url)
                 .with do |request|
        body = URI.decode_www_form(request.body).to_h
        body['MessageAttribute.1.Name'] == 'Author' &&
          body['MessageAttribute.1.Value.StringValue'] == 'Alice' &&
          body['MessageAttribute.2.Name'] == 'Priority' &&
          body['MessageAttribute.2.Value.StringValue'] == 'High' &&
          body['MessageAttribute.2.Value.DataType'] == 'String'
      end
                   .to_return(status: 200, body: sqs_success_response_xml)

      output = run_action({
        queue_url: queue_url,
        message_body: 'Multi-attr message',
        message_attributes: [
          { name: 'Author', value: 'Alice', data_type: 'String' },
          { name: 'Priority', value: 'High', data_type: 'String' },
        ],
      })

      expect(output[:message_id]).to eq('msg-12345')
      expect(sqs_stub).to have_been_requested.once
    end

    it 'sends message with Number data type attribute' do
      queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

      sqs_stub = stub_request(:post, queue_url)
                 .with do |request|
        body = URI.decode_www_form(request.body).to_h
        body['MessageAttribute.1.Name'] == 'Count' &&
          body['MessageAttribute.1.Value.StringValue'] == '42' &&
          body['MessageAttribute.1.Value.DataType'] == 'Number'
      end
                   .to_return(status: 200, body: sqs_success_response_xml)

      output = run_action({
        queue_url: queue_url,
        message_body: 'Number attribute',
        message_attributes: [
          { name: 'Count', value: '42', data_type: 'Number' },
        ],
      })

      expect(output[:message_id]).to eq('msg-12345')
      expect(sqs_stub).to have_been_requested.once
    end

    it 'sends message with Binary data type attribute' do
      queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'
      binary_value = Base64.strict_encode64('binary data')

      sqs_stub = stub_request(:post, queue_url)
                 .with do |request|
        body = URI.decode_www_form(request.body).to_h
        body['MessageAttribute.1.Name'] == 'Data' &&
          body['MessageAttribute.1.Value.BinaryValue'] == binary_value &&
          body['MessageAttribute.1.Value.DataType'] == 'Binary'
      end
                   .to_return(status: 200, body: sqs_success_response_xml)

      output = run_action({
        queue_url: queue_url,
        message_body: 'Binary attribute',
        message_attributes: [
          { name: 'Data', value: binary_value, data_type: 'Binary' },
        ],
      })

      expect(output[:message_id]).to eq('msg-12345')
      expect(sqs_stub).to have_been_requested.once
    end

    it 'sends message with float Number data type attribute' do
      queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

      sqs_stub = stub_request(:post, queue_url)
                 .with do |request|
        body = URI.decode_www_form(request.body).to_h
        body['MessageAttribute.1.Name'] == 'Price' &&
          body['MessageAttribute.1.Value.StringValue'] == '3.14' &&
          body['MessageAttribute.1.Value.DataType'] == 'Number'
      end
                   .to_return(status: 200, body: sqs_success_response_xml)

      output = run_action({
        queue_url: queue_url,
        message_body: 'Float number attribute',
        message_attributes: [
          { name: 'Price', value: '3.14', data_type: 'Number' },
        ],
      })

      expect(output[:message_id]).to eq('msg-12345')
      expect(sqs_stub).to have_been_requested.once
    end

    it 'sends message with negative Number data type attribute' do
      queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

      sqs_stub = stub_request(:post, queue_url)
                 .with do |request|
        body = URI.decode_www_form(request.body).to_h
        body['MessageAttribute.1.Name'] == 'Temperature' &&
          body['MessageAttribute.1.Value.StringValue'] == '-10.5' &&
          body['MessageAttribute.1.Value.DataType'] == 'Number'
      end
                   .to_return(status: 200, body: sqs_success_response_xml)

      output = run_action({
        queue_url: queue_url,
        message_body: 'Negative number attribute',
        message_attributes: [
          { name: 'Temperature', value: '-10.5', data_type: 'Number' },
        ],
      })

      expect(output[:message_id]).to eq('msg-12345')
      expect(sqs_stub).to have_been_requested.once
    end

    it 'sends message with mixed data types' do
      queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'
      binary_value = Base64.strict_encode64('test')

      sqs_stub = stub_request(:post, queue_url)
                 .with do |request|
        body = URI.decode_www_form(request.body).to_h
        body['MessageAttribute.1.Name'] == 'Text' &&
          body['MessageAttribute.1.Value.StringValue'] == 'Hello' &&
          body['MessageAttribute.1.Value.DataType'] == 'String' &&
          body['MessageAttribute.2.Name'] == 'Count' &&
          body['MessageAttribute.2.Value.StringValue'] == '42' &&
          body['MessageAttribute.2.Value.DataType'] == 'Number' &&
          body['MessageAttribute.3.Name'] == 'Data' &&
          body['MessageAttribute.3.Value.BinaryValue'] == binary_value &&
          body['MessageAttribute.3.Value.DataType'] == 'Binary'
      end
                   .to_return(status: 200, body: sqs_success_response_xml)

      output = run_action({
        queue_url: queue_url,
        message_body: 'Mixed attributes',
        message_attributes: [
          { name: 'Text', value: 'Hello', data_type: 'String' },
          { name: 'Count', value: '42', data_type: 'Number' },
          { name: 'Data', value: binary_value, data_type: 'Binary' },
        ],
      })

      expect(output[:message_id]).to eq('msg-12345')
      expect(sqs_stub).to have_been_requested.once
    end

    describe 'message_attributes_validator' do
      it 'validates Number data type with valid integer' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        stub_request(:post, queue_url)
          .to_return(status: 200, body: sqs_success_response_xml)

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test',
            message_attributes: [
              { name: 'Count', value: '42', data_type: 'Number' },
            ],
          })
        end.not_to raise_error
      end

      it 'validates Number data type with valid float' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        stub_request(:post, queue_url)
          .to_return(status: 200, body: sqs_success_response_xml)

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test',
            message_attributes: [
              { name: 'Price', value: '3.14', data_type: 'Number' },
            ],
          })
        end.not_to raise_error
      end

      it 'validates Number data type with invalid value' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test',
            message_attributes: [
              { name: 'Count', value: 'not a number', data_type: 'Number' },
            ],
          })
        end.to raise_error(IPaaS::Error, /Value must be a valid number/)
      end

      it 'validates Binary data type with valid base64' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'
        binary_value = Base64.strict_encode64('test data')

        stub_request(:post, queue_url)
          .to_return(status: 200, body: sqs_success_response_xml)

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test',
            message_attributes: [
              { name: 'Data', value: binary_value, data_type: 'Binary' },
            ],
          })
        end.not_to raise_error
      end

      it 'validates Binary data type with invalid base64' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test',
            message_attributes: [
              { name: 'Data', value: 'not valid base64!@#', data_type: 'Binary' },
            ],
          })
        end.to raise_error(IPaaS::Error, /Value must be valid Base64-encoded data/)
      end

      it 'validates Binary data type with invalid base64 format' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test',
            message_attributes: [
              { name: 'Data', value: 'invalid==base64==', data_type: 'Binary' },
            ],
          })
        end.to raise_error(IPaaS::Error, /Value must be valid Base64-encoded data/)
      end

      it 'validates String data type accepts any string' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        stub_request(:post, queue_url)
          .to_return(status: 200, body: sqs_success_response_xml)

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test',
            message_attributes: [
              { name: 'Text', value: 'any string value', data_type: 'String' },
            ],
          })
        end.not_to raise_error
      end
    end

    describe 'duplicate message attribute names' do
      it 'fails when duplicate attribute names are provided' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test',
            message_attributes: [
              { name: 'Author', value: 'John', data_type: 'String' },
              { name: 'Author', value: 'Jane', data_type: 'String' },
            ],
          })
        end.to raise_error(IPaaS::Job::FailJob, /Duplicate message attribute names found: Author/)
      end

      it 'fails with multiple duplicate attribute names' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test',
            message_attributes: [
              { name: 'Author', value: 'John', data_type: 'String' },
              { name: 'Priority', value: 'High', data_type: 'String' },
              { name: 'Author', value: 'Jane', data_type: 'String' },
              { name: 'Priority', value: 'Low', data_type: 'String' },
            ],
          })
        end.to raise_error(IPaaS::Job::FailJob, /Duplicate message attribute names found: Author, Priority/)
      end

      it 'succeeds when all attribute names are unique' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        stub_request(:post, queue_url)
          .to_return(status: 200, body: sqs_success_response_xml)

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test',
            message_attributes: [
              { name: 'Author', value: 'John', data_type: 'String' },
              { name: 'Priority', value: 'High', data_type: 'String' },
              { name: 'Category', value: 'News', data_type: 'String' },
            ],
          })
        end.not_to raise_error
      end
    end

    it 'sends message to FIFO queue with message group ID' do
      queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

      sqs_stub = stub_request(:post, queue_url)
                 .with do |request|
        body = URI.decode_www_form(request.body).to_h
        body['MessageBody'] == 'FIFO message' &&
          body['MessageGroupId'] == 'group-123'
      end
                   .to_return(status: 200, body: sqs_success_response_xml(sequence: '12345'))

      output = run_action({
        queue_url: queue_url,
        message_body: 'FIFO message',
        message_group_id: 'group-123',
      })

      expect(output[:message_id]).to eq('msg-12345')
      expect(output[:sequence_number]).to eq('12345')
      expect(sqs_stub).to have_been_requested.once
    end

    it 'sends message with deduplication ID' do
      queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

      sqs_stub = stub_request(:post, queue_url)
                 .with do |request|
        body = URI.decode_www_form(request.body).to_h
        body['MessageBody'] == 'Dedup message' &&
          body['MessageDeduplicationId'] == 'dedup-456'
      end
                   .to_return(status: 200, body: sqs_success_response_xml)

      output = run_action({
        queue_url: queue_url,
        message_body: 'Dedup message',
        message_deduplication_id: 'dedup-456',
      })

      expect(output[:message_id]).to eq('msg-12345')
      expect(sqs_stub).to have_been_requested.once
    end

    it 'sends message with all FIFO parameters' do
      queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

      sqs_stub = stub_request(:post, queue_url)
                 .with do |request|
        body = URI.decode_www_form(request.body).to_h
        body['MessageBody'] == 'Full FIFO message' &&
          body['MessageGroupId'] == 'group-789' &&
          body['MessageDeduplicationId'] == 'dedup-789'
      end
                   .to_return(status: 200, body: sqs_success_response_xml(sequence: '67890'))

      output = run_action({
        queue_url: queue_url,
        message_body: 'Full FIFO message',
        message_group_id: 'group-789',
        message_deduplication_id: 'dedup-789',
      })

      expect(output[:message_id]).to eq('msg-12345')
      expect(output[:sequence_number]).to eq('67890')
      expect(sqs_stub).to have_been_requested.once
    end

    describe 'error handling' do
      it 'handles SQS AccessDenied error' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        stub_request(:post, queue_url)
          .to_return(status: 403, body: sqs_error_response_xml('AccessDenied', 'Access to the resource is denied'))

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test message',
          })
        end.to raise_error(IPaaS::Job::FailJob, /AccessDenied: Access to the resource is denied/)
      end

      it 'handles SQS InvalidParameterValue error' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        stub_request(:post, queue_url)
          .to_return(status: 400,
                     body: sqs_error_response_xml('InvalidParameterValue', 'Invalid message body'))

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test message',
          })
        end.to raise_error(IPaaS::Job::FailJob, /InvalidParameterValue: Invalid message body/)
      end

      it 'handles SQS QueueDoesNotExist error' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/NonExistentQueue'

        stub_request(:post, queue_url)
          .to_return(status: 400, body: sqs_error_response_xml('AWS.SimpleQueueService.NonExistentQueue',
                                                               'The specified queue does not exist'))

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test message',
          })
        end.to raise_error(IPaaS::Job::FailJob, /NonExistentQueue/)
      end

      it 'handles network errors' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        stub_request(:post, queue_url)
          .to_raise(StandardError.new('Network timeout'))

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test message',
          })
        end.to raise_error(IPaaS::Job::FailJob, /Network timeout/)
      end

      it 'handles STS AssumeRole error' do
        sts_url = 'https://sts.us-east-1.amazonaws.com/'
        stub_request(:get, /#{Regexp.escape(sts_url)}/)
          .to_return(status: 403, body: <<~XML)
            <?xml version="1.0" encoding="UTF-8"?>
            <ErrorResponse>
              <Error>
                <Message>User is not authorized to perform: sts:AssumeRole</Message>
              </Error>
            </ErrorResponse>
          XML

        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test message',
          })
        end.to raise_error(IPaaS::Error,
                           'AWS STS call failed (HTTP 403): User is not authorized to perform: sts:AssumeRole')
      end

      it 'handles invalid SQS response structure' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        stub_request(:post, queue_url)
          .to_return(status: 200, body: '<InvalidResponse></InvalidResponse>')

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test message',
          })
        end.to raise_error(IPaaS::Job::FailJob, /Invalid SQS response structure/)
      end

      it 'handles missing required field in response' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        invalid_xml = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <SendMessageResponse xmlns="http://queue.amazonaws.com/doc/2012-11-05/">
            <SendMessageResult>
            </SendMessageResult>
          </SendMessageResponse>
        XML

        stub_request(:post, queue_url)
          .to_return(status: 200, body: invalid_xml)

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test message',
          })
        end.to raise_error(IPaaS::Job::FailJob, /Missing required field/)
      end

      it 'handles XML parsing error' do
        queue_url = 'https://sqs.us-east-1.amazonaws.com/123456789012/TestQueue'

        stub_request(:post, queue_url)
          .to_return(status: 200, body: '<<invalid xml>>')

        expect do
          run_action({
            queue_url: queue_url,
            message_body: 'Test message',
          })
        end.to raise_error(IPaaS::Job::FailJob, /Failed to parse SQS XML response/)
      end
    end
  end
end
