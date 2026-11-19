require 'spec_helper'

describe 'Microsoft Exchange Online Add email alias Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-0299-7db0-9ea4-2dc1de74b7ef' }

  def input(overrides = {})
    { mailbox: 'jane@contoso.com', alias: 'jane.smith@contoso.com' }.merge(overrides)
  end

  let(:mailbox) do
    { EmailAddresses: ['SMTP:jane@contoso.com', 'smtp:jane@contoso.onmicrosoft.com', 'X500:/o=x'], IsDirSynced: false }
  end

  def stub_address_free
    stub_cmdlet_error('Get-Recipient', status: 404, category: 'not_found',
                                       error_id: 'ManagementObjectNotFoundException')
  end

  before { stub_cmdlet('Get-AcceptedDomain', output: [{ DomainName: 'contoso.com' }]) }

  it 'adds the alias as a secondary address and reports the change' do
    stub_cmdlet('Get-Mailbox', output: [mailbox])
    stub_address_free
    stub_cmdlet('Set-Mailbox', output: [])
    output = run_action(input)
    expected = { Identity: 'jane@contoso.com', EmailAddresses: { add: ['smtp:jane.smith@contoso.com'] } }
    expect(runner_request('Set-Mailbox', expected)).to have_been_made
    expect(output).to eq('mailbox' => 'jane@contoso.com', 'alias' => 'jane.smith@contoso.com', 'changed' => true)
  end

  it 'changes nothing when the mailbox already carries the alias, in any case' do
    stub_cmdlet('Get-Mailbox',
                output: [mailbox.merge(EmailAddresses: ['SMTP:jane@contoso.com', 'smtp:Jane.Smith@Contoso.com'])])
    expect(run_action(input)['changed']).to be(false)
    expect(runner_request('Set-Mailbox')).not_to have_been_made
  end

  it 'refuses an alias another recipient already uses' do
    stub_cmdlet('Get-Mailbox', output: [mailbox])
    stub_cmdlet('Get-Recipient', output: [{ Name: 'Jane Smith', RecipientTypeDetails: 'UserMailbox' }])
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob,
                      "Address 'jane.smith@contoso.com' already belongs to UserMailbox 'Jane Smith'.")
  end

  it 'refuses an alias outside the accepted domains' do
    stub_cmdlet('Get-Mailbox', output: [mailbox])
    expect do
      run_action(input(alias: 'jane@gmail.com'))
    end.to raise_error(IPaaS::Job::FailJob, /outside the organization/)
  end

  it 'refuses a mailbox synchronized from on-premises and names proxyAddresses' do
    stub_cmdlet('Get-Mailbox', output: [mailbox.merge(IsDirSynced: 'True')])
    expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /Set proxyAddresses on the on-premises account/)
  end
end
