require 'spec_helper'

describe 'Microsoft Exchange Online Grant calendar delegate access Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-0296-72c4-a69e-0d7cfcaed557' }
  let(:calendar) { 'ceo@contoso.com:\\Kalender' }

  def input(overrides = {})
    { mailbox: 'ceo@contoso.com', user: 'jane@contoso.com', access_rights: 'Reviewer',
      sharing_permission: nil, }.merge(overrides)
  end

  def stub_no_entry
    error_id = '[FailureCategory=Cmdlet-UserNotFoundInPermissionEntryException]'
    stub_cmdlet_error('Get-MailboxFolderPermission', status: 404, category: 'not_found', error_id: error_id)
  end

  before do
    stub_cmdlet('Get-MailboxFolderStatistics', output: [{ Name: 'Kalender', FolderType: 'Calendar' },
                                                        { Name: 'Geburtstage', FolderType: 'Birthdays' },])
  end

  it 'finds the calendar by type, whatever its name, and adds the user' do
    stub_no_entry
    stub_cmdlet('Add-MailboxFolderPermission', output: [])
    output = run_action(input)
    expect(runner_request('Get-MailboxFolderStatistics', { Identity: 'ceo@contoso.com', FolderScope: 'Calendar' }))
      .to have_been_made
    expect(runner_request('Add-MailboxFolderPermission',
                          { Identity: calendar, User: 'jane@contoso.com',
                            AccessRights: ['Reviewer'], })).to have_been_made
    expect(output).to eq('mailbox' => 'ceo@contoso.com', 'user' => 'jane@contoso.com', 'calendar' => calendar,
                         'access_rights' => 'Reviewer', 'sharing_permission' => 'None', 'changed' => true)
  end

  it 'makes the user a delegate who sees private items when asked' do
    stub_no_entry
    stub_cmdlet('Add-MailboxFolderPermission', output: [])
    run_action(input(access_rights: 'Editor', sharing_permission: 'Delegate and private items'))
    expect(runner_request('Add-MailboxFolderPermission',
                          { Identity: calendar, User: 'jane@contoso.com', AccessRights: ['Editor'],
                            SharingPermissionFlags: 'Delegate,CanViewPrivateItems', })).to have_been_made
  end

  it 'changes the rights of a user who already has other rights' do
    stub_cmdlet('Get-MailboxFolderPermission', output: [{ AccessRights: ['AvailabilityOnly'] }])
    stub_cmdlet('Set-MailboxFolderPermission', output: [])
    expect(run_action(input)['changed']).to be(true)
    expect(runner_request('Set-MailboxFolderPermission',
                          { Identity: calendar, User: 'jane@contoso.com',
                            AccessRights: ['Reviewer'], })).to have_been_made
    expect(runner_request('Add-MailboxFolderPermission')).not_to have_been_made
  end

  it 'changes nothing when the user already has exactly these rights' do
    stub_cmdlet('Get-MailboxFolderPermission', output: [{ AccessRights: ['Reviewer'], SharingPermissionFlags: 'None' }])
    expect(run_action(input)['changed']).to be(false)
    expect(runner_request('Set-MailboxFolderPermission')).not_to have_been_made
  end

  it 'compares delegate flags whatever order Exchange lists them in' do
    stub_cmdlet('Get-MailboxFolderPermission',
                output: [{ AccessRights: ['Editor'], SharingPermissionFlags: 'CanViewPrivateItems, Delegate' }])
    expect(run_action(input(access_rights: 'Editor', sharing_permission: 'Delegate and private items'))['changed'])
      .to be(false)
  end

  it 'refuses a delegate sharing permission without the Editor right' do
    expect { run_action(input(sharing_permission: 'Delegate')) }
      .to raise_error(IPaaS::Job::FailJob, 'Sharing permission Delegate needs the Editor access right, not Reviewer.')
  end

  it 'fails when the mailbox has no calendar folder' do
    stub_cmdlet('Get-MailboxFolderStatistics', output: [{ Name: 'Inbox', FolderType: 'Inbox' }])
    expect do
      run_action(input)
    end.to raise_error(IPaaS::Job::FailJob, "Mailbox 'ceo@contoso.com' has no calendar folder.")
  end

  it 'fails when Exchange cannot read the folder permissions' do
    stub_cmdlet_error('Get-MailboxFolderPermission', status: 500, category: 'internal', error_id: 'Boom',
                                                     message: 'Server error.')
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob, 'Get-MailboxFolderPermission failed with HTTP 500 (internal): Server error.')
  end
end
