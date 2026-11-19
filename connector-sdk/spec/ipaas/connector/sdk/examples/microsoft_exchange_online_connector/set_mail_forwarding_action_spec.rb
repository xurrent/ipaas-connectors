require 'spec_helper'

describe 'Microsoft Exchange Online Set mail forwarding Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-028f-7dd1-8674-5b535937d270' }

  def input(overrides = {})
    { mailbox: 'leaver@contoso.com', target: 'manager@contoso.com', keep_copy: nil }.merge(overrides)
  end

  before { stub_cmdlet('Get-AcceptedDomain', output: [{ DomainName: 'Contoso.com' }, { DomainName: 'fabrikam.com' }]) }

  it 'forwards to an internal address, keeps a copy by default and reports the change' do
    stub_cmdlet('Get-Mailbox', output: [{ ForwardingSmtpAddress: nil, DeliverToMailboxAndForward: false }])
    stub_cmdlet('Set-Mailbox', output: [])
    output = run_action(input)
    expect(runner_request('Set-Mailbox', { Identity: 'leaver@contoso.com',
                                           ForwardingSmtpAddress: 'smtp:manager@contoso.com',
                                           DeliverToMailboxAndForward: true, })).to have_been_made
    expect(output).to eq('mailbox' => 'leaver@contoso.com', 'target' => 'manager@contoso.com',
                         'keep_copy' => true, 'changed' => true)
  end

  it 'forwards without a copy when the step turns Keep a copy off' do
    stub_cmdlet('Get-Mailbox', output: [{ ForwardingSmtpAddress: 'smtp:manager@contoso.com',
                                          DeliverToMailboxAndForward: true, }])
    stub_cmdlet('Set-Mailbox', output: [])
    expect(run_action(input(keep_copy: false))).to include('keep_copy' => false, 'changed' => true)
    expect(runner_request('Set-Mailbox', { Identity: 'leaver@contoso.com',
                                           ForwardingSmtpAddress: 'smtp:manager@contoso.com',
                                           DeliverToMailboxAndForward: false, })).to have_been_made
  end

  it 'changes nothing when the mailbox already forwards the same way' do
    stub_cmdlet('Get-Mailbox', output: [{ ForwardingSmtpAddress: 'smtp:Manager@Contoso.com',
                                          DeliverToMailboxAndForward: true, }])
    expect(run_action(input)['changed']).to be(false)
    expect(runner_request('Set-Mailbox')).not_to have_been_made
  end

  it 'refuses an address outside the accepted domains and names them' do
    expect { run_action(input(target: 'someone@gmail.com')) }
      .to raise_error(IPaaS::Job::FailJob,
                      "Address 'someone@gmail.com' is outside the organization: gmail.com is not one of its " \
                      'accepted domains (contoso.com, fabrikam.com).')
    expect(runner_request('Get-Mailbox')).not_to have_been_made
  end
end
