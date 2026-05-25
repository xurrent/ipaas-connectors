require 'spec_helper'

describe 'Upload Attachment Action', :action do
  include XurrentIntrospectionHelper

  let(:action_template_id) { '019ce240-76c9-7f7c-9ed7-2a07c3133f2e' }
  let(:outbound_connection_config) { xurrent_outbound_connection_config }
  let(:graphql_endpoint) { xurrent_graphql_endpoint }

  describe 'input_schema' do
    it 'defines file_name as a required string' do
      field = action.input_schema.field(:file_name)
      expect(field.type).to eq(:string)
      expect(field.required).to be_truthy
    end

    it 'defines file_content as a required binary' do
      field = action.input_schema.field(:file_content)
      expect(field.type).to eq(:binary)
      expect(field.required).to be_truthy
    end

    it 'defines content_type as an optional string' do
      field = action.input_schema.field(:content_type)
      expect(field.type).to eq(:string)
      expect(field.visibility).to eq('optional')
    end
  end

  describe 'output_schema' do
    it 'defines storage_key as a required string' do
      field = action.output_schemas.first.field(:storage_key)
      expect(field.type).to eq(:string)
      expect(field.required).to be_truthy
    end

    it 'defines size as an integer' do
      field = action.output_schemas.first.field(:size)
      expect(field.type).to eq(:integer)
    end

    it 'includes ratelimit and request_id metadata fields' do
      field_ids = action.output_schemas.first.fields.map(&:id)
      expect(field_ids).to include(:ratelimit, :request_id)
    end
  end

  describe 'run' do
    let(:storage_response) do
      {
        'attachmentStorage' => {
          'uploadUri' => 'https://s3.example.com/upload',
          'provider' => 's3',
          'providerParameters' => { 'key' => 'uploads/${filename}', 'success_action_status' => 201 },
          'sizeLimit' => 10_485_760,
          'allowedExtensions' => %w[pdf png jpg],
        },
      }
    end

    let(:action_input) do
      { file_name: 'report.pdf', file_content: 'binary-content-here' }
    end

    def stub_storage_query(response_data = storage_response)
      stub_graphql_query(/attachmentStorage/, response_data)
    end

    def stub_upload(uri: 'https://s3.example.com/upload', status: 201, body: '<Key>uploads/report.pdf</Key>')
      stub_request(:post, uri).to_return(status: status, body: body)
    end

    context 'successful S3 upload' do
      before(:each) do
        stub_storage_query
        stub_upload
      end

      it 'returns the storage key, file size, and ratelimit metadata' do
        output = run_action(action_input)

        expect(output[:storage_key]).to eq('uploads/report.pdf')
        expect(output[:size]).to eq(action_input[:file_content].size)
        expect(output[:ratelimit][:limit]).to eq('3600')
        expect(output[:request_id]).to eq('req-test-123')
      end
    end

    context 'successful local provider upload' do
      before(:each) do
        local_storage = storage_response.deep_dup
        local_storage['attachmentStorage']['provider'] = 'local'
        local_storage['attachmentStorage']['uploadUri'] = 'https://local.example.com/upload'
        local_storage['attachmentStorage']['providerParameters'] = {}
        stub_storage_query(local_storage)
        stub_upload(uri: 'https://local.example.com/upload', status: 200,
                    body: { 'key' => 'local/report.pdf' }.to_json)
      end

      it 'extracts the storage key from JSON response' do
        output = run_action(action_input)
        expect(output[:storage_key]).to eq('local/report.pdf')
      end
    end

    context 'content type detection' do
      before(:each) do
        stub_storage_query
      end

      it 'detects content type from file name when not specified' do
        upload_stub = stub_request(:post, 'https://s3.example.com/upload')
                      .with { |req| req.body.include?('image/png') }
                      .to_return(status: 201, body: '<Key>uploads/report.pdf</Key>')

        run_action({ file_name: 'photo.png', file_content: 'png-data' })
        expect(upload_stub).to have_been_requested
      end

      it 'uses explicit content type when provided' do
        upload_stub = stub_request(:post, 'https://s3.example.com/upload')
                      .with { |req| req.body.include?('application/pdf') }
                      .to_return(status: 201, body: '<Key>uploads/report.pdf</Key>')

        run_action(action_input.merge(content_type: 'application/pdf'))
        expect(upload_stub).to have_been_requested
      end
    end

    context 'provider parameters' do
      it 'converts non-string provider parameters to strings' do
        stub_storage_query
        body = nil
        upload_stub = stub_request(:post, 'https://s3.example.com/upload')
                      .with { |req| body = req.body }
                      .to_return(status: 201, body: '<Key>uploads/report.pdf</Key>')

        run_action(action_input)
        expect(upload_stub).to have_been_requested
        expect(body.is_a?(String)).to be_truthy
        expect(body).to include('name="key"', 'name="success_action_status"')
      end
    end

    context 'attachment storage caching' do
      before(:each) do
        stub_storage_query
        stub_upload
        run_action(action_input)
      end

      it 'caches attachment storage data after first call' do
        expect(action.cache_read('attachment_storage')).to be_present
      end

      it 'reuses cached storage data without a second GraphQL call' do
        WebMock.reset!
        stub_upload

        run_action(action_input)

        expect(WebMock).not_to have_requested(:post, graphql_endpoint)
          .with { |req| req.body.include?('attachmentStorage') }
      end
    end

    context 'error handling' do
      it 'fails when no attachment storage info is returned' do
        stub_graphql_query(/attachmentStorage/, { 'attachmentStorage' => nil })

        expect { run_action(action_input) }.to raise_error(
          IPaaS::Job::FailJob, /No attachment storage info/
        )
      end

      it 'fails when no upload URI is returned' do
        no_uri = storage_response.deep_dup
        no_uri['attachmentStorage']['uploadUri'] = nil
        stub_storage_query(no_uri)

        expect { run_action(action_input) }.to raise_error(
          IPaaS::Job::FailJob, /No upload URI/
        )
      end

      it 'fails when upload returns a non-success status' do
        stub_storage_query
        stub_upload(status: 403, body: 'Access Denied')

        expect { run_action(action_input) }.to raise_error(
          IPaaS::Job::FailJob, /Upload failed.*403/
        )
      end

      it 'fails when storage key cannot be extracted from response' do
        stub_storage_query
        stub_upload(body: '<Response>no key here</Response>')

        expect { run_action(action_input) }.to raise_error(
          IPaaS::Job::FailJob, /Could not extract storage key/
        )
      end
    end
  end
end
