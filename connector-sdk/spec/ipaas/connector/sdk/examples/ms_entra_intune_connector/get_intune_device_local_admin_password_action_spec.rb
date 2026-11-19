require 'spec_helper'

describe 'Microsoft Intune Get Device Local Admin Password Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-26ac-7c69-a57d-2e5b8d376d3a' }
  let(:credentials_url) { "#{graph}/directory/deviceLocalCredentials/#{entra_device_id}" }
  let(:credential_select) { { '$select' => 'id,deviceName,lastBackupDateTime,refreshDateTime,credentials' } }
  let(:credential_info) do
    {
      '@odata.type' => '#microsoft.graph.deviceLocalCredentialInfo',
      'id' => entra_device_id,
      'deviceName' => 'LAPS_TEST',
      'lastBackupDateTime' => '2023-04-21T13:45:30Z',
      'refreshDateTime' => '2023-05-20T13:45:30Z',
      'credentials' => [
        { 'accountName' => 'ContosoLocalAdminAccount', 'accountSid' => 'S-1-5-21-2318549658-1965',
          'backupDateTime' => '2023-03-22T13:45:30Z', 'passwordBase64' => 'KgBEADkAawBsAGsAZgAjADQA', },
        { 'accountName' => 'ContosoLocalAdminAccount', 'accountSid' => 'S-1-5-21-2318549658-1965',
          'backupDateTime' => '2023-04-21T13:45:30Z', 'passwordBase64' => 'UQBRAEAAZAA4AGYAOABnAFkA', },
        { 'accountName' => 'Administrator', 'accountSid' => 'S-1-5-21-2318549658-500',
          'backupDateTime' => '2023-02-23T13:45:30Z', 'passwordBase64' => 'TABwAGQAOQAqACgAKQAzADQA', },
      ],
    }
  end

  def stub_credentials(status: 200, body: { value: credential_info }.to_json)
    stub_request(:get, credentials_url)
      .with(query: credential_select, headers: { 'User-Agent' => 'Xurrent iPaaS' })
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def with_password(encoded)
    credential_info.merge('credentials' => [credential_info['credentials'].second.merge('passwordBase64' => encoded)])
  end

  describe 'input_schema' do
    it 'requires the Entra device id' do
      expect(action.input_schema.field(:azure_ad_device_id).type).to eq(:string)
      expect(action.input_schema.field(:azure_ad_device_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the password as a secret string' do
      schema = action.output_schema.first
      expect(schema.field(:azure_ad_device_id).required).to be_truthy
      expect(schema.field(:password).type).to eq(:secret_string)
    end
  end

  describe 'run' do
    it 'reads the credentials with the User-Agent header and returns the newest password decoded as a secret' do
      stub_credentials
      output = run_action({ azure_ad_device_id: entra_device_id })
      expect(output.except('password')).to eq(
        'azure_ad_device_id' => entra_device_id, 'device_name' => 'LAPS_TEST',
        'account_name' => 'ContosoLocalAdminAccount', 'account_sid' => 'S-1-5-21-2318549658-1965',
        'backup_date_time' => '2023-04-21T13:45:30Z', 'last_backup_date_time' => '2023-04-21T13:45:30Z',
        'refresh_date_time' => '2023-05-20T13:45:30Z'
      )
      expect(output['password']).to be_a(IPaaS::Encryption::SecretString)
      expect(action.decrypt_secret_string(output['password'])).to eq('QQ@d8f8gY')
    end

    it 'reads a credential that Graph returns at the top level' do
      stub_credentials(body: credential_info.to_json)
      output = run_action({ azure_ad_device_id: entra_device_id })
      expect(action.decrypt_secret_string(output['password'])).to eq('QQ@d8f8gY')
    end

    it 'decodes a password that is Base64 of UTF-8 text' do
      stub_credentials(body: with_password(Base64.strict_encode64('Pässwört-42')).to_json)
      output = run_action({ azure_ad_device_id: entra_device_id })
      expect(action.decrypt_secret_string(output['password'])).to eq('Pässwört-42')
    end

    it 'decodes a password that is Base64 of UTF-16LE text with characters outside ASCII' do
      stub_credentials(body: with_password(Base64.strict_encode64('Łódź-Pässwört-42'.encode('UTF-16LE'))).to_json)
      output = run_action({ azure_ad_device_id: entra_device_id })
      expect(action.decrypt_secret_string(output['password'])).to eq('Łódź-Pässwört-42')
    end

    it 'fails when the UTF-16LE password has a character outside the Basic Multilingual Plane' do
      stub_credentials(body: with_password(Base64.strict_encode64('Key-🔑-42'.encode('UTF-16LE'))).to_json)
      expect { run_action({ azure_ad_device_id: entra_device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'The local administrator password has characters that this action cannot decode.')
    end

    it 'fails when the UTF-16LE password has an odd number of bytes' do
      stub_credentials(body: with_password(Base64.strict_encode64("A\u0000B")).to_json)
      expect { run_action({ azure_ad_device_id: entra_device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'The local administrator password has characters that this action cannot decode.')
    end

    it 'fails when Graph returns a password that is not Base64' do
      stub_credentials(body: with_password('not base64!').to_json)
      expect { run_action({ azure_ad_device_id: entra_device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned a local administrator password that is not Base64.')
    end

    it 'fails when Graph returns no credentials for the device' do
      stub_credentials(body: credential_info.except('credentials').to_json)
      expect { run_action({ azure_ad_device_id: entra_device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Microsoft Graph returned no local administrator password for Entra device #{entra_device_id}.")
    end

    it 'fails when the newest credential has no password' do
      stub_credentials(body: with_password(nil).to_json)
      expect { run_action({ azure_ad_device_id: entra_device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Microsoft Graph returned no local administrator password for Entra device #{entra_device_id}.")
    end

    it 'fails without the password in the message when Graph answers with something that is not JSON' do
      encoded_password = credential_info['credentials'].second['passwordBase64']
      stub_credentials(body: credential_info.to_json.chop)
      expect { run_action({ azure_ad_device_id: entra_device_id }) }
        .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned a response that is not JSON.') do |error|
          expect(error.message).not_to include(encoded_password)
        end
    end

    it 'fails asking for the Entra device id on 404' do
      stub_credentials(status: 404, body: graph_error('ResourceNotFound', 'Device not found.'))
      expect { run_action({ azure_ad_device_id: entra_device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 404 ResourceNotFound: Device not found. Check that the ID is ' \
                        'the Entra device ID: the azureADDeviceId of the managed device, which Managed devices from ' \
                        'Intune returns as azure_ad_device_id.')
    end

    it 'fails naming DeviceLocalCredential.Read.All on 403' do
      stub_credentials(status: 403, body: access_denied)
      expect { run_action({ azure_ad_device_id: entra_device_id }) }
        .to raise_error(IPaaS::Job::FailJob, access_denied_failure('DeviceLocalCredential.Read.All'))
    end

    it 'fails with no request when the Entra device id is a device name' do
      expect { run_action({ azure_ad_device_id: 'LAPS_TEST' }) }
        .to raise_error(IPaaS::Job::FailJob, "Entra device ID 'LAPS_TEST' is not a valid id (a GUID).")
      expect(a_request(:get, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails with no request when the Entra device id is all zeros' do
      expect { run_action({ azure_ad_device_id: '00000000-0000-0000-0000-000000000000' }) }
        .to raise_error(IPaaS::Job::FailJob, "Entra device ID '00000000-0000-0000-0000-000000000000' means that " \
                                             'the device has no Microsoft Entra ID record.')
      expect(a_request(:get, /graph\.microsoft\.com/)).not_to have_been_made
    end
  end
end
