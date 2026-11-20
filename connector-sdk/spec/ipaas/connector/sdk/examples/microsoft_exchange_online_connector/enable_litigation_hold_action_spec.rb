require 'spec_helper'

describe 'Microsoft Exchange Online Enable litigation hold Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-029b-71e5-95cc-bb9dabb2aafa' }

  def input(overrides = {})
    { mailbox: 'leaver@contoso.com', duration_days: nil, owner: nil, comment: nil }.merge(overrides)
  end

  it 'places an unlimited hold by default and reports the change' do
    stub_cmdlet('Get-Mailbox', output: [{ LitigationHoldEnabled: false, LitigationHoldDuration: 'Unlimited' }])
    stub_cmdlet('Set-Mailbox', output: [])
    output = run_action(input)
    expect(runner_request('Set-Mailbox', { Identity: 'leaver@contoso.com', LitigationHoldEnabled: true,
                                           LitigationHoldDuration: 'Unlimited', })).to have_been_made
    expect(output).to eq('mailbox' => 'leaver@contoso.com', 'duration' => 'Unlimited', 'changed' => true)
  end

  it 'places a hold for a number of days with its owner and comment' do
    stub_cmdlet('Get-Mailbox', output: [{ LitigationHoldEnabled: false }])
    stub_cmdlet('Set-Mailbox', output: [])
    output = run_action(input(duration_days: 365, owner: 'Legal', comment: 'Case 2026-114'))
    expect(runner_request('Set-Mailbox', { Identity: 'leaver@contoso.com', LitigationHoldEnabled: true,
                                           LitigationHoldDuration: 365, LitigationHoldOwner: 'Legal',
                                           RetentionComment: 'Case 2026-114', })).to have_been_made
    expect(output['duration']).to eq('365')
  end

  it 'changes nothing when the same hold is already in place' do
    stub_cmdlet('Get-Mailbox', output: [{ LitigationHoldEnabled: true, LitigationHoldDuration: '365.00:00:00' }])
    expect(run_action(input(duration_days: 365))['changed']).to be(false)
    expect(runner_request('Set-Mailbox')).not_to have_been_made
  end

  it 'treats an existing unlimited hold as the same as an unlimited request' do
    stub_cmdlet('Get-Mailbox', output: [{ LitigationHoldEnabled: true, LitigationHoldDuration: 'unlimited' }])
    expect(run_action(input)['changed']).to be(false)
  end

  it 'changes a hold with another duration' do
    stub_cmdlet('Get-Mailbox', output: [{ LitigationHoldEnabled: true, LitigationHoldDuration: 'Unlimited' }])
    stub_cmdlet('Set-Mailbox', output: [])
    expect(run_action(input(duration_days: 30))['changed']).to be(true)
  end

  it 'fails with the Exchange reason when the mailbox lacks the licence for a hold' do
    stub_cmdlet('Get-Mailbox', output: [{ LitigationHoldEnabled: false }])
    stub_cmdlet_error('Set-Mailbox', error_id: 'RecipientTaskException',
                                     message: 'The mailbox needs an Exchange Online Plan 2 license.')
    expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /needs an Exchange Online Plan 2 license/)
  end
end
