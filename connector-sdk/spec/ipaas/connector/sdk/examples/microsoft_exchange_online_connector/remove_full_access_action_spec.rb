require 'spec_helper'

describe 'Microsoft Exchange Online Remove shared mailbox Full Access Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-027b-7ef9-8990-ccb8b03904eb' }

  def input(overrides = {})
    { mailbox: 'support@contoso.com', user: 'jane@contoso.com' }.merge(overrides)
  end

  it 'removes an explicit Full Access permission and reports the change' do
    stub_cmdlet('Get-MailboxPermission', output: [{ AccessRights: ['FullAccess'], Deny: false, IsInherited: false }])
    stub_cmdlet('Remove-MailboxPermission', output: [])
    output = run_action(input)
    expect(runner_request('Remove-MailboxPermission',
                          { Identity: 'support@contoso.com', User: 'jane@contoso.com', AccessRights: ['FullAccess'],
                            InheritanceType: 'All', Confirm: false, })).to have_been_made
    expect(output).to eq('mailbox' => 'support@contoso.com', 'user' => 'jane@contoso.com', 'changed' => true)
  end

  it 'changes nothing when the user holds no Full Access' do
    stub_cmdlet('Get-MailboxPermission', output: [])
    expect(run_action(input)['changed']).to be(false)
    expect(runner_request('Remove-MailboxPermission')).not_to have_been_made
  end

  it 'leaves an inherited Full Access alone, because removing it here would not take' do
    stub_cmdlet('Get-MailboxPermission', output: [{ AccessRights: ['FullAccess'], Deny: false, IsInherited: true }])
    expect(run_action(input)['changed']).to be(false)
    expect(runner_request('Remove-MailboxPermission')).not_to have_been_made
  end

  it 'fails with the Exchange error when the mailbox does not exist' do
    stub_cmdlet_error('Get-MailboxPermission', status: 404, category: 'not_found',
                                               error_id: 'ManagementObjectNotFoundException',
                                               message: "The object 'support@contoso.com' couldn't be found.")
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob, 'Get-MailboxPermission failed with HTTP 404 (not_found): The object ' \
                                           "'support@contoso.com' couldn't be found.")
  end
end
