require 'spec_helper'

describe 'Microsoft Intune Sync Device Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-2061-789c-aa75-8f78357ad804' }
  let(:command_url) { "#{graph}/deviceManagement/managedDevices/#{device_id}/syncDevice" }

  def stub_command(status: 204, body: '')
    stub_request(:post, command_url)
      .with { |request| @sent_body = request.body }
      .to_return(status: status, body: body)
  end

  describe 'input_schema' do
    it 'defines a required Intune device id string' do
      field = action.input_schema.field(:device_id)
      expect(field.type).to eq(:string)
      expect(field.required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns the required Intune device id' do
      expect(action.output_schema.first.field(:device_id).required).to be_truthy
    end
  end

  describe 'run' do
    it 'posts syncDevice on v1.0 with no body and returns the device id' do
      stub_command
      expect(run_action({ device_id: device_id })).to eq('device_id' => device_id)
      expect(@sent_body.to_s).to eq('')
    end

    it 'fails with the Graph message and then the permission the action needs on 403' do
      stub_command(status: 403, body: access_denied)
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        access_denied_failure('DeviceManagementManagedDevices.PrivilegedOperations.All'))
    end

    it 'fails with only the Message Intune wraps in a JSON document inside the Graph error on 403' do
      intune_message = 'Application is not authorized to perform this operation. Application must have one of the ' \
                       'following scopes: DeviceManagementManagedDevices.PrivilegedOperations.All - Activity ID: ' \
                       '7b4a6659-2b2b-4476-a710-87f1363f2582'
      wrapped = { _version: 3, Message: intune_message, CustomApiErrorPhrase: '', RetryAfter: nil }.to_json
      stub_command(status: 403, body: graph_error('Forbidden', wrapped))
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Microsoft Graph returned HTTP 403 Forbidden: #{intune_message} Permission this action " \
                        'needs: DeviceManagementManagedDevices.PrivilegedOperations.All. Admin consent is required.')
    end

    it 'fails with the whole Graph message when the Message that Intune wraps in it is not text' do
      wrapped = { _version: 3, Message: 42 }.to_json
      stub_command(status: 400, body: graph_error('BadRequest', wrapped))
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob, "Microsoft Graph returned HTTP 400 BadRequest: #{wrapped}")
    end

    it 'fails asking for the Intune device id and with no permission hint on 404' do
      stub_command(status: 404, body: graph_error('ResourceNotFound', 'Device not found.'))
      expect { run_action({ device_id: device_id }) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 404 ResourceNotFound: Device not found. Check that the ID is ' \
                        'the Intune device ID: the id of the managed device, which Managed devices from Intune ' \
                        'returns as device_id.')
    end

    it 'reschedules for the time in Retry-After on 429' do
      stub_request(:post, command_url).to_return(status: 429, body: 'Wait 2 seconds', headers: { 'retry-after' => 2 })
      Timecop.freeze do
        expect { run_action({ device_id: device_id }) }
          .to raise_error(IPaaS::Job::RescheduleJob,
                          "Microsoft API rate limit hit (retry after: 2). 'Wait 2 seconds'") do |error|
          expect(error.reschedule_after).to eq(2.seconds.from_now)
        end
      end
      expect(a_request(:post, command_url)).to have_been_made.once
    end

    it 'fails with no request when the device id is a dot segment' do
      expect { run_action({ device_id: '..' }) }
        .to raise_error(IPaaS::Job::FailJob, "Intune device ID '..' is not a valid id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end
  end
end
