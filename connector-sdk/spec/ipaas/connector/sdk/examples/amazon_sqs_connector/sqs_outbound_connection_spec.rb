require 'spec_helper'

describe 'Amazon SQS Connection', :outbound_connection do
  let(:connector_id) { '49885952-c9e3-4841-9e06-43bcf879902a' }

  let(:outbound_connection_config) do
    {
      setup_info: {
        aws_account_id: '123456789012',
        external_id: 'test-external-id-12345',
      },
      aws_credentials: {
        role_arn: 'arn:aws:iam::123456789012:role/TestRole',
        region: 'us-east-1',
      },
    }
  end

  describe 'validation' do
    it 'is valid with complete config' do
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'requires role_arn' do
      outbound_connection_config[:aws_credentials].delete(:role_arn)
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
    end

    it 'has default region value' do
      outbound_connection_config[:aws_credentials].delete(:region)
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'validates role_arn format' do
      outbound_connection_config[:aws_credentials][:role_arn] = 'invalid-arn'
      expect(outbound_connection).not_to be_valid, outbound_connection.full_error_messages
    end

    it 'accepts valid role_arn with special characters' do
      outbound_connection_config[:aws_credentials][:role_arn] = 'arn:aws:iam::123456789012:role/ValidRole+With=Chars'
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'rejects role_arn with invalid account ID' do
      outbound_connection_config[:aws_credentials][:role_arn] = 'arn:aws:iam::invalid:role/TestRole'
      expect(outbound_connection).not_to be_valid
    end

    it 'rejects role_arn without role name' do
      outbound_connection_config[:aws_credentials][:role_arn] = 'arn:aws:iam::123456789012:role/'
      expect(outbound_connection).not_to be_valid
    end

    it 'accepts all supported AWS regions' do
      regions = %w[
        us-east-1 us-east-2 us-west-1 us-west-2
        us-gov-east-1 us-gov-west-1
        ca-central-1 ca-west-1
        sa-east-1 mx-central-1
        eu-west-1 eu-west-2 eu-west-3 eu-central-1 eu-central-2 eu-north-1 eu-south-1 eu-south-2 il-central-1
        me-south-1 me-central-1
        af-south-1
        ap-east-1 ap-east-2 ap-south-1 ap-south-2 ap-northeast-1 ap-northeast-2 ap-northeast-3
        ap-southeast-1 ap-southeast-2 ap-southeast-3 ap-southeast-4 ap-southeast-5 ap-southeast-6 ap-southeast-7
        cn-north-1 cn-northwest-1
      ]

      regions.each do |region|
        outbound_connection_config[:aws_credentials][:region] = region
        expect(outbound_connection).to be_valid,
                                       "Failed for region #{region}: #{outbound_connection.full_error_messages}"
      end
    end

    it 'allows external_id to be auto-generated' do
      outbound_connection_config[:setup_info].delete(:external_id)
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'allows aws_account_id to be auto-populated' do
      outbound_connection_config[:setup_info].delete(:aws_account_id)
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'accepts optional advanced settings' do
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'accepts custom session name' do
      outbound_connection.config[:advanced] = { session_name: 'CustomSessionName' }
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end

    it 'accepts empty advanced settings' do
      outbound_connection.config[:advanced] = {}
      expect(outbound_connection).to be_valid, outbound_connection.full_error_messages
    end
  end

  describe 'setup info' do
    it 'generates external_id when not present in store' do
      outbound_connection.store.write('external_id', nil)
      outbound_connection.setup_info

      external_id = outbound_connection.store.read('external_id')
      expect(external_id).to be_present
      expect(external_id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'preserves existing external_id in store' do
      existing_id = 'existing-uuid-12345'
      outbound_connection.store.write('external_id', existing_id)
      outbound_connection.setup_info

      external_id = outbound_connection.store.read('external_id')
      expect(external_id).to eq(existing_id)
    end

    it 'populates setup_info in config_mapping' do
      existing_id = 'existing-uuid-12346'
      aws_id = '123'
      outbound_connection.store.write('external_id', existing_id)
      expect(outbound_connection.store).not_to receive(:write)
      expect(outbound_connection).to receive(:aws_account_id).and_return(aws_id)

      setup_info = outbound_connection.setup_info
      expect(setup_info.size).to eq(1)
      expect(setup_info).to be_a(Hash)
      values = setup_info.values.first
      expect(values.keys).to match_array([:'AWS Account ID', :'External ID'])
      expect(values.values.pluck(:value)).to match_array([aws_id, existing_id])
      expect(values.values.pluck(:hint).uniq.compact.size).to eq(2)
    end
  end

  describe 'authenticate' do
    it 'does not add authentication headers' do
      request = Faraday::Request.create(:post) do |req|
        req.headers = {}
      end

      outbound_connection.authenticate_request(request)

      expect(request.headers['Authorization']).to be_nil
    end

    it 'leaves headers unchanged' do
      request = Faraday::Request.create(:post) do |req|
        req.headers = { 'X-Custom-Header' => 'value' }
      end

      outbound_connection.authenticate_request(request)

      expect(request.headers.keys).to contain_exactly('X-Custom-Header')
    end
  end
end
