class AmazonSqsConnector < IPaaS::Connector::Definition
  connector '49885952-c9e3-4841-9e06-43bcf879902a' do
    name 'Amazon SQS Connector'
    avatar '/assets/icons/amazon-sqs.svg'
    description <<~END_OF_DESCRIPTION
      This connector enables integration with Amazon Simple Queue Service (SQS), AWS's fully managed message
      queuing service. Send messages to SQS queues for decoupled, scalable application architectures.

      # Prerequisites

      To use this connector, you need:
      * An AWS account with SQS access
      * An IAM role with SQS permissions
      * Our AWS Account ID (see 'AWS Account ID' in the 'Setup Information' section below)
      * External ID: Generated automatically during connection setup

      # Authentication Setups

      This connector uses AWS IAM Role ARN authentication with an external ID for enhanced security.

      ## Step 1: Create IAM Policy

      In your AWS account, create a new IAM policy with the following permissions:

      ```json
      {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": [
              "sqs:SendMessage",
              "sqs:GetQueueUrl",
              "sqs:GetQueueAttributes"
            ],
            "Resource": "arn:aws:sqs:*:*:*"
          }
        ]
      }
      ```

      For better security, replace `"Resource": "arn:aws:sqs:*:*:*"` with the specific queue ARN(s).

      ## Step 2: Create IAM Role

      1. In the AWS IAM console, create a new role
      2. Select "Another AWS account" as the trusted entity
      3. Enter the **AWS Account ID** shown in the 'Setup Information' section below as AWS Account ID.
      4. Check "Require external ID" and enter the **External ID** shown in the 'Setup Information' section below
      5. Attach the policy created in Step 1
      6. Complete role creation and copy the **Role ARN**

      ## Step 3: Configure Connection

      1. Paste the **Role ARN** from your AWS role
      2. Select the **AWS Region** where your SQS queue is located

      # Available Actions

      ## Send Message to Queue

      Sends a message to a specified SQS queue. Messages are durably stored and can be processed asynchronously
      by consumers polling the queue.

      **Features**:
      * Support for message delays (0-900 seconds)
      * Message attributes for metadata
      * Support for both standard and FIFO queues
      * Automatic message deduplication (FIFO queues)

      # Rate Limiting and Error Handling

      SQS has the following limits:
      * Standard queues: Nearly unlimited throughput
      * FIFO queues: 300 messages/second (batched) or 3000 messages/second (unbatched)
      * Maximum message size: 256 KB

      The connector includes built-in handling for AWS throttling and service availability:
      * Automatic backoff and retry for throttling errors (HTTP 429, RequestThrottled)
      * Automatic backoff and retry for service unavailable errors (HTTP 503, ServiceUnavailable)
      * Exponential backoff strategy with configurable retry intervals
      * Respects AWS throttling recommendations for optimal retry timing

      # Common Use Cases

      * Trigger background processing workflows
      * Decouple microservices and distributed systems
      * Buffer high-volume requests during traffic spikes
      * Implement event-driven architectures
      * Queue tasks for batch processing
      * Integrate with AWS Lambda for serverless processing
    END_OF_DESCRIPTION

    outbound_connection do
      setup_info do
        external_id = store.read('external_id')
        if external_id.blank?
          external_id = SecureRandom.uuid
          store.write('external_id', external_id)
        end

        { 'Setup Information (Copy to AWS)': {
          'External ID': {
            hint: 'Auto-generated unique ID. Use this in your IAM role trust policy to ' \
                  'prevent the "confused deputy" security issue.',
            value: external_id,
          },
          'AWS Account ID': {
            hint: 'The Xurrent iPaaS AWS Account ID. This will be used in your IAM role trust relationship.',
            value: aws_account_id,
          },
        } }
      end

      config_schema do
        field :aws_credentials, 'AWS Credentials', :nested,
              required: true do
          field :role_arn, 'IAM Role ARN', :string,
                required: true,
                hint: 'After creating the IAM role in your AWS account, paste the Role ARN here. ' \
                      'Example: arn:aws:iam::123456789012:role/YourRoleName',
                pattern: %r{\Aarn:aws:iam::\d{12}:role/[\w+=,.@-]+\z}

          field :region, 'AWS Region', :string,
                required: true,
                hint: 'The AWS region where your SQS queue is located',
                enumeration: %w[
                  us-east-1 us-east-2 us-west-1 us-west-2
                  us-gov-east-1 us-gov-west-1
                  ca-central-1 ca-west-1
                  sa-east-1 mx-central-1
                  eu-west-1 eu-west-2 eu-west-3 eu-central-1 eu-central-2 eu-north-1 eu-south-1 eu-south-2 il-central-1
                  me-south-1 me-central-1
                  af-south-1
                  ap-east-1 ap-east-2 ap-south-1 ap-south-2 ap-northeast-1 ap-northeast-2 ap-northeast-3
                  ap-southeast-1 ap-southeast-2 ap-southeast-3 ap-southeast-4 ap-southeast-5 ap-southeast-6
                  ap-southeast-7 cn-north-1 cn-northwest-1
                ],
                default: 'us-east-1'
        end

        field :advanced, 'Advanced Settings', :nested,
              visibility: 'optional' do
          field :session_name, 'Session Name', :string,
                default: 'XurrentIPaaSSession',
                hint: 'Name for the AWS session (appears in CloudTrail logs)'
        end
      end

      authenticate do |_request|
        # skipped since authentication requires the payload, which is not yet available when this is called
        # authentication is handled in helpers.sqs_request
      end
    end

    action 'ad0dc183-7de4-4252-97b9-a07247ab894b' do
      name 'Send Message to Queue'
      avatar '/assets/icons/amazon-sqs.svg'
      description <<~END_OF_DESCRIPTION
        Sends a message to an Amazon SQS queue. The message will be durably stored and available
        for processing by consumers polling the queue.

        **Input Parameters**:
        * **Queue URL** (required): The full SQS queue URL
        * **Message Body** (required): The message content (max 256 KB)
        * **Delay Seconds** (optional): Delay message delivery (0-900 seconds)
        * **Message Attributes** (optional): Key-value metadata for the message

        **Output**:
        * **Message ID**: Unique identifier assigned by SQS
        * **MD5 of Message Body**: MD5 hash for verification
        * **MD5 of Message Attributes**: MD5 hash of attributes (if provided)
        * **Sequence Number**: For FIFO queues only

        **Example Use Cases**:
        * Send task to background worker queue
        * Trigger Lambda function via SQS
        * Buffer requests during high traffic
        * Implement async processing pipelines

        **Rate Limits**:
        * Standard queues: Nearly unlimited
        * FIFO queues: 300 msg/s (batched) or 3000 msg/s (unbatched)

        **Error Handling**:
        * Invalid queue URL: Job fails with error message
        * Message too large (>256 KB): Job fails
        * Insufficient permissions: Job fails with access denied error
        * Throttling (429/RequestThrottled): Automatic backoff and retry
        * Service unavailable (503): Automatic backoff and retry
        * Network issues: Job retries automatically
      END_OF_DESCRIPTION

      input_schema do
        field :queue_url, 'Queue URL', :string,
              required: true,
              hint: 'Full SQS queue URL (e.g., https://sqs.us-east-1.amazonaws.com/123456789012/MyQueue)',
              pattern: %r{\Ahttps://sqs\.[a-z0-9-]+\.amazonaws\.com/\d+/[a-zA-Z0-9_.-]+\z}

        field :message_body, 'Message Body', :string,
              required: true,
              hint: 'The message content to send (max 256 KB)',
              max_length: 262_144 # 256 KB

        field :delay_seconds, 'Delay Seconds', :integer,
              visibility: 'optional',
              hint: 'Delay delivery of this message (0-900 seconds, default: 0)',
              min: 0,
              max: 900,
              default: 0

        message_attributes_validator = ->(attr) do
          return true if attr.nil? || attr.empty?
          attr = attr.with_indifferent_access

          value = attr['value']

          case attr['data_type']
          when 'Number'
            begin
              Float(value)
              true
            rescue ArgumentError, TypeError
              raise ArgumentError, 'Value must be a valid number (integer or float)'
            end
          when 'Binary'
            unless value.is_a?(String) &&
                   value.match?(%r{\A[A-Za-z0-9+/]*={0,2}\z}) &&
                   !value.empty?
              raise ArgumentError, 'Value must be valid Base64-encoded data'
            end
            true
          else
            true
          end
        end
        field :message_attributes, 'Message Attributes', :nested,
              visibility: 'optional',
              array: true,
              hint: 'Optional metadata to attach to the message',
              validator: message_attributes_validator do
          field :name, 'Name', :string, required: true
          field :value, 'Value', :string, required: true
          field :data_type, 'Data Type', :string,
                enumeration: %w[String Number Binary],
                default: 'String'
        end

        field :message_group_id, 'Message Group ID', :string,
              visibility: 'optional',
              hint: 'Required for FIFO queues. Messages with same group ID are processed in order.'

        field :message_deduplication_id, 'Message Deduplication ID', :string,
              visibility: 'optional',
              hint: 'Optional for FIFO queues. Token used for deduplication of messages.'
      end

      output_schema do
        field :message_id, 'Message ID', :string, required: true
        field :md5_of_message_body, 'MD5 of Message Body', :string, required: true
        field :md5_of_message_attributes, 'MD5 of Message Attributes', :string
        field :sequence_number, 'Sequence Number', :string,
              hint: 'Only present for FIFO queues'
      end

      run do
        queue_url = input[:queue_url]

        sqs_params = {
          'Action' => 'SendMessage',
          'Version' => '2012-11-05',
          'MessageBody' => input[:message_body],
        }

        if input[:delay_seconds].present? && input[:delay_seconds] > 0
          sqs_params['DelaySeconds'] = input[:delay_seconds].to_s
        end

        if input[:message_attributes].present?
          attribute_names = input[:message_attributes].filter_map { |attr| attr[:name] }
          duplicates = attribute_names.group_by(&:itself).select { |_k, v| v.length > 1 }.keys

          fail_job!("Duplicate message attribute names found: #{duplicates.join(', ')}.") if duplicates.any?

          input[:message_attributes].each_with_index do |attr, idx|
            prefix = "MessageAttribute.#{idx + 1}"
            sqs_params["#{prefix}.Name"] = attr[:name]
            data_type = attr[:data_type] || 'String'
            sqs_params["#{prefix}.Value.DataType"] = data_type

            value_key = data_type == 'Binary' ? 'BinaryValue' : 'StringValue'
            sqs_params["#{prefix}.Value.#{value_key}"] = attr[:value]
          end
        end

        sqs_params['MessageGroupId'] = input[:message_group_id] if input[:message_group_id].present?

        if input[:message_deduplication_id].present?
          sqs_params['MessageDeduplicationId'] = input[:message_deduplication_id]
        end

        response = helpers.sqs_request(queue_url, sqs_params)

        doc = helpers.parse_sqs_xml(response.body)

        result_element = doc.at_xpath('//SendMessageResult')

        fail_job!("Invalid SQS response structure: #{response.body}") unless result_element

        output = {
          message_id: helpers.extract_xml_text(result_element, 'MessageId', required: true),
          md5_of_message_body: helpers.extract_xml_text(result_element, 'MD5OfMessageBody', required: true),
          md5_of_message_attributes: helpers.extract_xml_text(result_element, 'MD5OfMessageAttributes'),
          sequence_number: helpers.extract_xml_text(result_element, 'SequenceNumber'),
        }

        [{ output: output }]
      end
    end

    helper :get_aws_credentials do
      external_id = outbound_connection.store.read('external_id')
      fail_job!('External ID not found. Please re-provision the connection.') unless external_id.present?

      creds_config = outbound_connection.config[:aws_credentials]
      advanced_config = outbound_connection.config[:advanced] || {}
      outbound_connection.aws_credentials_for_role(
        creds_config[:role_arn],
        external_id,
        creds_config[:region],
        advanced_config[:session_name],
      )
    end

    helper :sqs_request do |queue_url, params|
      credentials = helpers.get_aws_credentials
      region = outbound_connection.config[:aws_credentials][:region]

      payload = URI.encode_www_form(params)
      content_type = 'application/x-www-form-urlencoded'

      signed_headers = build_aws_signed_headers(
        method: 'POST',
        url: queue_url,
        payload: payload,
        credentials: credentials,
        region: region,
        service: 'sqs',
        content_type: content_type,
      )

      headers = signed_headers.merge({
        'Content-Type' => content_type,
      })

      begin
        call_aws('SQS') do
          http_post(queue_url, payload, headers, skip_authentication: true)
        end
      rescue IPaaS::Error => e
        fail_job!(e.message)
      rescue StandardError => e
        fail_job!("SQS request error: #{e.message}")
      end
    end

    helper :parse_sqs_xml do |xml_body|
      parse_xml_response(xml_body)
    rescue StandardError => e
      fail_job!("Failed to parse SQS XML response: #{e.message}")
    end

    helper :extract_xml_text do |parent_element, tag_name, required: false|
      element = parent_element.at_xpath(tag_name)
      text = element&.text

      fail_job!("Missing required field '#{tag_name}' in SQS response") if required && text.blank?

      text.presence
    end
  end
end
