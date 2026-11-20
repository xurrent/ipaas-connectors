require 'spec_helper'

describe 'Microsoft Exchange Online Create shared mailbox Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-028a-71f2-95e8-12d120e87bed' }

  def input(overrides = {})
    { name: 'Support', display_name: nil, address: 'support@contoso.com', alias: nil,
      owners: ['jane@contoso.com'], }.merge(overrides)
  end

  def stub_address_free
    stub_cmdlet_error('Get-Recipient', status: 404, category: 'not_found',
                                       error_id: '[FailureCategory=Cmdlet-ManagementObjectNotFoundException]')
  end

  def grant_for(owner)
    { Identity: 'support@contoso.com', User: owner, AccessRights: ['FullAccess'], InheritanceType: 'All',
      AutoMapping: true, }
  end

  describe 'when the address is free' do
    before do
      stub_address_free
      stub_cmdlet('New-Mailbox', output: [{ Name: 'Support' }])
      stub_cmdlet('Get-MailboxPermission', output: [])
      stub_cmdlet('Add-MailboxPermission', output: [])
    end

    it 'creates the shared mailbox, grants each owner Full Access and reports both' do
      output = run_action(input(owners: ['jane@contoso.com', 'blake@contoso.com']))
      expect(runner_request('New-Mailbox', { Shared: true, Name: 'Support', DisplayName: 'Support',
                                             PrimarySmtpAddress: 'support@contoso.com', })).to have_been_made
      expect(runner_request('Add-MailboxPermission', grant_for('jane@contoso.com'))).to have_been_made
      expect(runner_request('Add-MailboxPermission', grant_for('blake@contoso.com'))).to have_been_made
      expect(output).to eq('mailbox' => 'support@contoso.com', 'created' => true,
                           'owners_granted' => ['jane@contoso.com', 'blake@contoso.com'], 'changed' => true)
    end

    it 'sends the display name and alias the step gives' do
      run_action(input(display_name: 'Customer Support', alias: 'support'))
      expect(runner_request('New-Mailbox', { Shared: true, Name: 'Support', DisplayName: 'Customer Support',
                                             PrimarySmtpAddress: 'support@contoso.com', Alias: 'support', }))
        .to have_been_made
    end

    it 'creates the mailbox with no owners when the step names none' do
      output = run_action(input(owners: nil))
      expect(output['owners_granted']).to eq([])
      expect(output['changed']).to be(true)
    end

    it 'accepts an address written with an smtp prefix' do
      expect(run_action(input(address: 'SMTP:support@contoso.com'))['mailbox']).to eq('support@contoso.com')
    end
  end

  describe 'when a shared mailbox with the address already exists' do
    before { stub_cmdlet('Get-Recipient', output: [{ Name: 'Support', RecipientTypeDetails: 'SharedMailbox' }]) }

    it 'does not create it again and only grants the owners who lack access' do
      stub_cmdlet('Get-MailboxPermission', output: [])
      stub_cmdlet('Add-MailboxPermission', output: [])
      output = run_action(input)
      expect(runner_request('New-Mailbox')).not_to have_been_made
      expect(output).to include('created' => false, 'owners_granted' => ['jane@contoso.com'], 'changed' => true)
    end

    it 'reports no change when every owner already has access' do
      stub_cmdlet('Get-MailboxPermission', output: [{ AccessRights: ['FullAccess'], Deny: false, IsInherited: false }])
      expect(run_action(input)).to include('created' => false, 'owners_granted' => [], 'changed' => false)
    end
  end

  it 'refuses an address that belongs to another kind of recipient' do
    stub_cmdlet('Get-Recipient', output: [{ Name: 'Jane Doe', RecipientTypeDetails: 'UserMailbox' }])
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob, "Address 'support@contoso.com' already belongs to UserMailbox 'Jane Doe'. " \
                                           'Pick another address.')
    expect(runner_request('New-Mailbox')).not_to have_been_made
  end

  it 'fails when Exchange cannot say whether the address is in use' do
    stub_cmdlet_error('Get-Recipient', status: 500, category: 'internal', error_id: 'Boom', message: 'Server error.')
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob, 'Get-Recipient failed with HTTP 500 (internal): Server error.')
  end

  it 'refuses an address that is not an SMTP address' do
    expect { run_action(input(address: 'support')) }
      .to raise_error(IPaaS::Job::FailJob, "Address 'support' is not an SMTP address such as jane@contoso.com.")
  end

  it 'refuses an owner that is blank' do
    expect { run_action(input(owners: ['jane@contoso.com', ' '])) }
      .to raise_error(IPaaS::Job::FailJob, 'Owner is empty.')
  end
end
