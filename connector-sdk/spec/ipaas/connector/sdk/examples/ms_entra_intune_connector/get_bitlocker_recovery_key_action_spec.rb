require 'spec_helper'

describe 'Microsoft Intune Get BitLocker Recovery Key Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-271f-778f-9e2c-7623d07b7046' }
  let(:keys_url) { "#{graph}/informationProtection/bitlocker/recoveryKeys" }
  let(:key_id) { 'b465e4e8-e4e8-b465-e8e4-65b4e8e465b4' }
  let(:newest_os_key) { '6a30ed7b-247b-4d26-86b5-2f405e55ea42' }
  let(:recovery_key) { '123456-231453-873456-213546-654678-765689-123456-324565' }
  let(:key_select) { { '$select' => 'id,createdDateTime,volumeType,deviceId,key' } }
  let(:device_filter) { { '$filter' => "deviceId eq '#{entra_device_id}'" } }

  def key_answer(id, volume_type: '1', key: recovery_key)
    { value: { id: id, createdDateTime: '2020-06-15T13:45:30Z', volumeType: volume_type, deviceId: entra_device_id,
               key: key, } }
  end

  def stub_key(id, status: 200, body: key_answer(id).to_json)
    stub_request(:get, "#{keys_url}/#{id}")
      .with(query: key_select, headers: { 'User-Agent' => 'Xurrent iPaaS' })
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_device_keys(keys, next_link: nil)
    stub_request(:get, keys_url)
      .with(query: device_filter, headers: { 'User-Agent' => 'Xurrent iPaaS' })
      .to_return(status: 200, body: { value: keys, '@odata.nextLink' => next_link }.compact.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def os_key(id, created)
    { id: id, createdDateTime: created, volumeType: '1', deviceId: entra_device_id }
  end

  describe 'input_schema' do
    it 'takes an optional recovery key id and an optional Entra device id' do
      expect(action.input_schema.field(:recovery_key_id).required).to be_falsey
      expect(action.input_schema.field(:azure_ad_device_id).required).to be_falsey
    end
  end

  describe 'output_schema' do
    it 'returns the recovery key as a secret string' do
      schema = action.output_schema.first
      expect(schema.field(:recovery_key_id).required).to be_truthy
      expect(schema.field(:recovery_key).type).to eq(:secret_string)
    end
  end

  describe 'run' do
    it 'reads the key by its id with the User-Agent header and returns the key as a secret' do
      stub_key(key_id)
      output = run_action({ recovery_key_id: key_id })
      expect(output.except('recovery_key')).to eq(
        'recovery_key_id' => key_id, 'azure_ad_device_id' => entra_device_id,
        'volume_type' => 'operatingSystemVolume', 'created_date_time' => '2020-06-15T13:45:30Z'
      )
      expect(output['recovery_key']).to be_a(IPaaS::Encryption::SecretString)
      expect(action.decrypt_secret_string(output['recovery_key'])).to eq(recovery_key)
    end

    it 'returns the name of a volume type that Graph sends as a number' do
      stub_key(key_id, body: key_answer(key_id, volume_type: 2).to_json)
      expect(run_action({ recovery_key_id: key_id })['volume_type']).to eq('fixedDataVolume')
    end

    it 'passes a volume type it does not know through as a string' do
      stub_key(key_id, body: key_answer(key_id, volume_type: 'futureVolume').to_json)
      expect(run_action({ recovery_key_id: key_id })['volume_type']).to eq('futureVolume')
    end

    it 'finds the newest operating system drive key of the device and reads that key' do
      stub_device_keys([
        os_key(key_id, '2024-01-01T00:00:00Z'),
        os_key(newest_os_key, '2025-03-01T00:00:00Z').merge(volumeType: 'operatingSystemVolume'),
        { id: '0f3a1b2c-3d4e-4f50-8a6b-7c8d9e0f1a2b', createdDateTime: '2026-01-01T00:00:00Z', volumeType: '2',
          deviceId: entra_device_id, },
      ])
      stub_key(newest_os_key)
      output = run_action({ azure_ad_device_id: entra_device_id })
      expect(output['recovery_key_id']).to eq(newest_os_key)
      expect(action.decrypt_secret_string(output['recovery_key'])).to eq(recovery_key)
    end

    it 'reads the newest operating system drive key when Graph lists it before an older one' do
      stub_device_keys([os_key(newest_os_key, '2025-03-01T00:00:00Z'), os_key(key_id, '2024-01-01T00:00:00Z')])
      stub_key(newest_os_key)
      expect(run_action({ azure_ad_device_id: entra_device_id })['recovery_key_id']).to eq(newest_os_key)
    end

    it 'follows the next page link and reads the newest operating system drive key from the second page' do
      second_page = "#{keys_url}?$filter=deviceId%20eq%20%27#{entra_device_id}%27&$skiptoken=page2"
      stub_device_keys([os_key(key_id, '2024-01-01T00:00:00Z')], next_link: second_page)
      stub_request(:get, second_page)
        .to_return(status: 200, body: { value: [os_key(newest_os_key, '2025-03-01T00:00:00Z')] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      stub_key(newest_os_key)
      expect(run_action({ azure_ad_device_id: entra_device_id })['recovery_key_id']).to eq(newest_os_key)
    end

    it 'skips a listed key that is not an object and reads the operating system drive key beside it' do
      stub_device_keys([nil, os_key(key_id, '2024-01-01T00:00:00Z')])
      stub_key(key_id)
      expect(run_action({ azure_ad_device_id: entra_device_id })['recovery_key_id']).to eq(key_id)
    end

    it 'fails, and sends nothing to the other host, when the next page link is on another host' do
      elsewhere = 'https://graph.example.com/v1.0/informationProtection/bitlocker/recoveryKeys?$skiptoken=page2'
      stub_device_keys([os_key(key_id, '2024-01-01T00:00:00Z')], next_link: elsewhere)
      stub_request(:get, /graph\.example\.com/).to_return(status: 200, body: { value: [] }.to_json)
      expect { run_action({ azure_ad_device_id: entra_device_id }) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph answered with a next page link that is not on ' \
                                             "https://graph.microsoft.com/v1.0: '#{elsewhere}'")
      expect(a_request(:get, /graph\.example\.com/)).not_to have_been_made
    end

    it 'fails when the keys of the device fill more pages than it reads' do
      page_limit = MsEntraIntuneConnector::BITLOCKER_KEY_PAGE_LIMIT
      stub_request(:get, /recoveryKeys\?/)
        .to_return(status: 200, body: { value: [], '@odata.nextLink' => "#{keys_url}?$skiptoken=more" }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect { run_action({ azure_ad_device_id: entra_device_id }) }
        .to raise_error(IPaaS::Job::FailJob, "Microsoft Graph returned more than #{page_limit} pages of BitLocker " \
                                             "recovery keys for Entra device #{entra_device_id}. Give the recovery " \
                                             'key ID instead.')
      expect(a_request(:get, /recoveryKeys\?/)).to have_been_made.times(page_limit)
    end

    it 'fails saying the id may be the Intune device id when the device has no operating system drive key' do
      stub_device_keys([{ id: key_id, createdDateTime: '2024-01-01T00:00:00Z', volumeType: '2' }])
      expect { run_action({ azure_ad_device_id: entra_device_id }) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Entra ID holds no BitLocker recovery key for the operating ' \
                                             "system drive of Entra device #{entra_device_id}. The ID may be the " \
                                             'Intune device ID instead of the Entra device ID.')
    end

    it 'fails when Graph returns the recovery key without the key' do
      stub_key(key_id, body: key_answer(key_id, key: nil).to_json)
      expect { run_action({ recovery_key_id: key_id }) }
        .to raise_error(IPaaS::Job::FailJob, "Microsoft Graph returned no key for BitLocker recovery key ID #{key_id}.")
    end

    it 'fails without the key in the message when Graph answers with something that is not JSON' do
      stub_key(key_id, body: key_answer(key_id).to_json.chop)
      expect { run_action({ recovery_key_id: key_id }) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned a response that is not JSON.') do |error|
          expect(error.message).not_to include(recovery_key)
        end
    end

    it 'fails with no request when the recovery key id is not a GUID' do
      expect { run_action({ recovery_key_id: '../deviceManagement' }) }
        .to raise_error(IPaaS::Job::FailJob, "Recovery key ID '../deviceManagement' is not a valid id (a GUID).")
      expect(a_request(:get, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails with no request when neither id is given' do
      expect { run_action({ recovery_key_id: ' ', azure_ad_device_id: nil }) }
        .to raise_error(IPaaS::Job::FailJob, 'Give exactly one of Recovery key ID and Entra device ID.')
      expect(a_request(:get, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails with no request when both ids are given' do
      expect { run_action({ recovery_key_id: key_id, azure_ad_device_id: entra_device_id }) }
        .to raise_error(IPaaS::Job::FailJob, 'Give exactly one of Recovery key ID and Entra device ID.')
      expect(a_request(:get, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails with no request when the Entra device id would change the filter' do
      expect { run_action({ azure_ad_device_id: "x' or deviceId ne 'x" }) }
        .to raise_error(IPaaS::Job::FailJob, "Entra device ID 'x' or deviceId ne 'x' is not a valid id (a GUID).")
      expect(a_request(:get, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails with no request when the Entra device id is all zeros' do
      expect { run_action({ azure_ad_device_id: '00000000-0000-0000-0000-000000000000' }) }
        .to raise_error(IPaaS::Job::FailJob, "Entra device ID '00000000-0000-0000-0000-000000000000' means that " \
                                             'the device has no Microsoft Entra ID record.')
      expect(a_request(:get, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails naming BitlockerKey.Read.All on 403' do
      stub_key(key_id, status: 403, body: access_denied)
      expect { run_action({ recovery_key_id: key_id }) }
        .to raise_error(IPaaS::Job::FailJob, access_denied_failure('BitlockerKey.Read.All'))
    end
  end
end
