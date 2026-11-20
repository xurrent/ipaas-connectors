require 'spec_helper'

describe 'Microsoft Exchange Online Grant Send on Behalf Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-0283-7a28-a20d-7151e9003538' }

  def input(overrides = {})
    { mailbox: 'ceo@contoso.com', user: 'jane@contoso.com' }.merge(overrides)
  end

  let(:jane) do
    { Name: 'Jane Doe', Identity: 'Jane Doe', Alias: 'jane', DisplayName: 'Jane Doe',
      PrimarySmtpAddress: 'jane@contoso.com', ExternalDirectoryObjectId: '7f2b0c3e-1111-4c1a-9d3b-2f0a9e1c5b7d', }
  end

  before { stub_cmdlet('Get-Recipient', output: [jane]) }

  it 'adds the user to the Send on Behalf list and keeps the delegates already on it' do
    stub_cmdlet('Get-Mailbox', output: [{ GrantSendOnBehalfTo: ['Blake Lee'] }])
    stub_cmdlet('Set-Mailbox', output: [])
    output = run_action(input)
    expect(runner_request('Set-Mailbox', { Identity: 'ceo@contoso.com',
                                           GrantSendOnBehalfTo: { add: ['jane@contoso.com'] }, })).to have_been_made
    expect(output).to eq('mailbox' => 'ceo@contoso.com', 'user' => 'jane@contoso.com', 'changed' => true)
  end

  it 'adds the user when the mailbox has no delegates at all' do
    stub_cmdlet('Get-Mailbox', output: [{ GrantSendOnBehalfTo: nil }])
    stub_cmdlet('Set-Mailbox', output: [])
    expect(run_action(input)['changed']).to be(true)
  end

  it 'changes nothing when Exchange lists the user by name' do
    stub_cmdlet('Get-Mailbox', output: [{ GrantSendOnBehalfTo: ['jane doe'] }])
    expect(run_action(input)['changed']).to be(false)
    expect(runner_request('Set-Mailbox')).not_to have_been_made
  end

  it 'changes nothing when Exchange lists the user by object id, as one value rather than a list' do
    stub_cmdlet('Get-Mailbox', output: [{ GrantSendOnBehalfTo: '7f2b0c3e-1111-4c1a-9d3b-2f0a9e1c5b7d' }])
    expect(run_action(input)['changed']).to be(false)
  end

  it 'fails when the mailbox does not exist' do
    stub_cmdlet('Get-Mailbox', output: [])
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob, "Mailbox 'ceo@contoso.com' was not found in Exchange Online.")
  end

  it 'fails when the user does not exist' do
    stub_cmdlet('Get-Mailbox', output: [{ GrantSendOnBehalfTo: [] }])
    stub_cmdlet('Get-Recipient', output: [])
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob, "User 'jane@contoso.com' was not found in Exchange Online.")
  end
end
