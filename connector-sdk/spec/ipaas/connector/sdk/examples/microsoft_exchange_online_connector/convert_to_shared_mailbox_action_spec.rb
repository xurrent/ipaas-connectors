require 'spec_helper'

describe 'Microsoft Exchange Online Convert mailbox to shared Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-028c-7e7f-bcbe-18649dceec02' }

  def input(overrides = {})
    { mailbox: 'leaver@contoso.com' }.merge(overrides)
  end

  let(:user_mailbox) do
    { RecipientTypeDetails: 'UserMailbox', LitigationHoldEnabled: false, InPlaceHolds: [], ArchiveStatus: 'None' }
  end

  def stub_size(text)
    stub_cmdlet('Get-MailboxStatistics', output: [{ TotalItemSize: text }])
  end

  it 'converts a user mailbox under 50 GB and reports its size' do
    stub_cmdlet('Get-Mailbox', output: [user_mailbox])
    stub_size('1.2 GB (1,288,490,188 bytes)')
    stub_cmdlet('Set-Mailbox', output: [])
    output = run_action(input)
    expect(runner_request('Set-Mailbox', { Identity: 'leaver@contoso.com', Type: 'Shared' })).to have_been_made
    expect(output).to eq('mailbox' => 'leaver@contoso.com', 'previous_type' => 'UserMailbox',
                         'total_item_size_bytes' => 1_288_490_188, 'changed' => true)
  end

  it 'changes nothing when the mailbox already is shared' do
    stub_cmdlet('Get-Mailbox', output: [{ RecipientTypeDetails: 'SharedMailbox' }])
    expect(run_action(input)).to eq('mailbox' => 'leaver@contoso.com', 'previous_type' => 'SharedMailbox',
                                    'changed' => false)
    expect(runner_request('Set-Mailbox')).not_to have_been_made
  end

  it 'refuses a mailbox that is not a user mailbox' do
    stub_cmdlet('Get-Mailbox', output: [{ RecipientTypeDetails: 'RoomMailbox' }])
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob,
                      "Mailbox 'leaver@contoso.com' is a RoomMailbox; only a UserMailbox is converted.")
  end

  it 'refuses a mailbox whose type Exchange does not report' do
    stub_cmdlet('Get-Mailbox', output: [{ Name: 'Leaver' }])
    expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /is a mailbox of unknown type/)
  end

  it 'refuses a mailbox on litigation hold' do
    stub_cmdlet('Get-Mailbox', output: [user_mailbox.merge(LitigationHoldEnabled: true)])
    expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /'leaver@contoso.com' is on hold/)
  end

  it 'refuses a mailbox on in-place hold' do
    stub_cmdlet('Get-Mailbox', output: [user_mailbox.merge(InPlaceHolds: ['UniH7d8a'])])
    expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /'leaver@contoso.com' is on hold/)
  end

  it 'refuses a mailbox with an active archive' do
    stub_cmdlet('Get-Mailbox', output: [user_mailbox.merge(ArchiveStatus: 'Active')])
    expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /has an active archive/)
  end

  it 'refuses a mailbox over 50 GB' do
    stub_cmdlet('Get-Mailbox', output: [user_mailbox])
    stub_size('51 GB (54,760,833,024 bytes)')
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob,
                      "Mailbox 'leaver@contoso.com' holds 54760833024 bytes, more than the 50 GB an unlicensed " \
                      'shared mailbox may hold. Keep it licensed.')
    expect(runner_request('Set-Mailbox')).not_to have_been_made
  end

  it 'converts a mailbox of exactly 50 GB' do
    stub_cmdlet('Get-Mailbox', output: [user_mailbox])
    stub_size('50 GB (53,687,091,200 bytes)')
    stub_cmdlet('Set-Mailbox', output: [])
    expect(run_action(input)['changed']).to be(true)
  end

  it 'refuses to convert when the size cannot be read, since the limit cannot be checked' do
    stub_cmdlet('Get-Mailbox', output: [user_mailbox])
    stub_size('Unlimited')
    expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /could not be read from 'Unlimited'/)
  end

  it 'fails when Exchange returns no statistics' do
    stub_cmdlet('Get-Mailbox', output: [user_mailbox])
    stub_cmdlet('Get-MailboxStatistics', output: [])
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob,
                      "Statistics of mailbox 'leaver@contoso.com' was not found in Exchange Online.")
  end
end
