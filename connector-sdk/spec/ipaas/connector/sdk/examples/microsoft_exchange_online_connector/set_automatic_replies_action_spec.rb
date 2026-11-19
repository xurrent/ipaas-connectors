require 'spec_helper'

describe 'Microsoft Exchange Online Set automatic replies Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-0291-76fa-936f-5446fad43616' }
  let(:settings_url) { "#{graph_base_url}/users/leaver@contoso.com/mailboxSettings" }

  def input(overrides = {})
    { user: 'leaver@contoso.com', status: 'Enabled', internal_message: 'I have left.',
      external_message: 'Please write to support@contoso.com.', external_audience: nil,
      scheduled_start: nil, scheduled_end: nil, }.merge(overrides)
  end

  def stub_settings(status: 200, body: { automaticRepliesSetting: {} }.to_json, headers: {})
    stub_request(:patch, settings_url).to_return(status: status, body: body, headers: headers)
  end

  def patched(setting)
    a_request(:patch, settings_url).with(body: { automaticRepliesSetting: setting }.to_json,
                                         headers: { 'Authorization' => 'Bearer graph-token',
                                                    'Content-Type' => 'application/json', })
  end

  it 'turns replies on with both messages for all external senders, using a Graph token' do
    stub_settings
    output = run_action(input)
    expect(patched(status: 'alwaysEnabled', internalReplyMessage: 'I have left.',
                   externalReplyMessage: 'Please write to support@contoso.com.', externalAudience: 'all'))
      .to have_been_made
    expect(output).to eq('user' => 'leaver@contoso.com', 'status' => 'Enabled', 'external_audience' => 'All',
                         'scheduled_start' => nil, 'scheduled_end' => nil)
  end

  it 'limits the external audience when the step asks' do
    stub_settings
    run_action(input(external_audience: 'Contacts only'))
    expect(a_request(:patch, settings_url)
      .with(body: hash_including('automaticRepliesSetting' => hash_including('externalAudience' => 'contactsOnly'))))
      .to have_been_made
  end

  it 'schedules replies between Start and End, in UTC' do
    stub_settings
    output = run_action(input(status: 'Scheduled', scheduled_start: '2026-12-01T09:00:00+01:00',
                              scheduled_end: '2026-12-15T17:00:00+01:00'))
    expect(a_request(:patch, settings_url).with(body: hash_including('automaticRepliesSetting' => hash_including(
      'status' => 'scheduled',
      'scheduledStartDateTime' => { 'dateTime' => '2026-12-01T08:00:00', 'timeZone' => 'UTC' },
      'scheduledEndDateTime' => { 'dateTime' => '2026-12-15T16:00:00', 'timeZone' => 'UTC' },
    )))).to have_been_made
    expect(output['scheduled_start']).to be_present
    expect(output['scheduled_end']).to be_present
  end

  it 'refuses a schedule without an End' do
    expect { run_action(input(status: 'Scheduled', scheduled_start: '2026-12-01T09:00:00Z')) }
      .to raise_error(IPaaS::Job::FailJob, 'Scheduled replies need both Start and End.')
  end

  it 'refuses a schedule that ends before it starts' do
    expect do
      run_action(input(status: 'Scheduled', scheduled_start: '2026-12-15T09:00:00Z',
                       scheduled_end: '2026-12-01T09:00:00Z'))
    end.to raise_error(IPaaS::Job::FailJob, 'End must be after Start.')
  end

  it 'turns replies off without touching the messages' do
    stub_settings
    output = run_action(input(status: 'Disabled'))
    expect(patched(status: 'disabled')).to have_been_made
    expect(output).to include('status' => 'Disabled')
    expect(output['scheduled_start']).to be_nil
  end

  it 'names the permission when Graph refuses' do
    stub_settings(status: 403, body: { error: { code: 'ErrorAccessDenied', message: 'Access is denied.' } }.to_json)
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob, 'Microsoft Graph returned HTTP 403 ErrorAccessDenied for mailbox ' \
                                           "'leaver@contoso.com': Access is denied. Check that the app holds " \
                                           'MailboxSettings.ReadWrite.')
  end

  it 'quotes the raw body of a failure that carries no Graph error' do
    stub_settings(status: 400, body: 'Bad Request')
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob,
                      "Microsoft Graph returned HTTP 400  for mailbox 'leaver@contoso.com': Bad Request")
  end

  it 'says there was no body when Graph sent none' do
    stub_settings(status: 500, body: '')
    expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /: no response body\z/)
  end

  it 'pauses the step when Graph throttles' do
    stub_settings(status: 429, body: '', headers: { 'Retry-After' => '12' })
    expect_reschedule_after(12) { run_action(input) }
  end
end
