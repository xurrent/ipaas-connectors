require 'spec_helper'

describe 'Microsoft Exchange Online Grant shared mailbox Full Access Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-0279-7d47-9565-a937427dd458' }

  def input(overrides = {})
    { mailbox: 'support@contoso.com', user: 'jane@contoso.com', auto_mapping: nil }.merge(overrides)
  end

  let(:lookup) { { Identity: 'support@contoso.com', User: 'jane@contoso.com' } }

  def grant(auto_mapping)
    { Identity: 'support@contoso.com', User: 'jane@contoso.com', AccessRights: ['FullAccess'],
      InheritanceType: 'All', AutoMapping: auto_mapping, }
  end

  describe 'when the user has no Full Access yet' do
    before do
      stub_cmdlet('Get-MailboxPermission', output: [])
      stub_cmdlet('Add-MailboxPermission', output: [{ AccessRights: ['FullAccess'] }])
    end

    it 'grants Full Access with auto-mapping and reports the change' do
      output = run_action(input)
      expect(runner_request('Get-MailboxPermission', lookup)).to have_been_made
      expect(runner_request('Add-MailboxPermission', grant(true))).to have_been_made
      expect(output).to eq('mailbox' => 'support@contoso.com', 'user' => 'jane@contoso.com',
                           'auto_mapping' => true, 'changed' => true)
    end

    it 'grants without auto-mapping when the step turns it off' do
      output = run_action(input(auto_mapping: false))
      expect(runner_request('Add-MailboxPermission', grant(false))).to have_been_made
      expect(output['auto_mapping']).to be(false)
    end

    it 'sends the organization, cloud and Exchange token to the runner with the runner key' do
      run_action(input)
      expect(a_request(:post, runner_url).with(
               headers: { 'Authorization' => 'Bearer runner-key', 'Content-Type' => 'application/json' },
               body: hash_including('organization' => 'contoso.onmicrosoft.com',
                                    'exchange_environment' => 'O365Default',
                                    'access_token' => 'exchange-token'),
             )).to have_been_made.twice
    end

    it 'strips the spaces around the mailbox and the user' do
      run_action(input(mailbox: '  support@contoso.com ', user: ' jane@contoso.com  '))
      expect(runner_request('Add-MailboxPermission', grant(true))).to have_been_made
    end
  end

  describe 'when the user already has Full Access' do
    it 'changes nothing and reports no change' do
      stub_cmdlet('Get-MailboxPermission',
                  output: [{ AccessRights: ['FullAccess'], Deny: false, IsInherited: false, User: 'CONTOSO\\jane' }])
      output = run_action(input)
      expect(runner_request('Add-MailboxPermission')).not_to have_been_made
      expect(output['changed']).to be(false)
    end

    it 'reads access rights that Exchange wrote as one comma-separated string' do
      stub_cmdlet('Get-MailboxPermission',
                  output: [{ AccessRights: 'ReadPermission, FullAccess', Deny: 'False', IsInherited: 'False' }])
      expect(run_action(input)['changed']).to be(false)
    end
  end

  describe 'permissions that do not count as Full Access' do
    before { stub_cmdlet('Add-MailboxPermission', output: []) }

    it 'grants when the only Full Access entry is a deny' do
      stub_cmdlet('Get-MailboxPermission', output: [{ AccessRights: ['FullAccess'], Deny: true, IsInherited: false }])
      expect(run_action(input)['changed']).to be(true)
    end

    it 'grants when the only Full Access entry is inherited' do
      stub_cmdlet('Get-MailboxPermission', output: [{ AccessRights: ['FullAccess'], Deny: false, IsInherited: true }])
      expect(run_action(input)['changed']).to be(true)
    end

    it 'grants when the user holds other rights only' do
      stub_cmdlet('Get-MailboxPermission', output: [{ AccessRights: ['ReadPermission'] }])
      expect(run_action(input)['changed']).to be(true)
    end
  end

  describe 'input checks' do
    it 'refuses a user that holds a routing character' do
      expect { run_action(input(user: 'contoso\\jane')) }
        .to raise_error(IPaaS::Job::FailJob, /User 'contoso\\jane' holds a slash/)
    end
  end
end
