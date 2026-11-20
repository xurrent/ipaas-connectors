require 'spec_helper'

describe 'Microsoft Exchange Online Remove Send As Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-0280-7471-9ac6-d5e0b9808eff' }

  def input(overrides = {})
    { mailbox: 'support@contoso.com', user: 'jane@contoso.com' }.merge(overrides)
  end

  let(:change) do
    { Identity: 'support@contoso.com', Trustee: 'jane@contoso.com', AccessRights: ['SendAs'], Confirm: false }
  end

  it 'removes Send As the user holds and reports the change' do
    stub_cmdlet('Get-RecipientPermission', output: [{ AccessRights: ['SendAs'], AccessControlType: 'Allow' }])
    stub_cmdlet('Remove-RecipientPermission', output: [])
    expect(run_action(input)).to eq('mailbox' => 'support@contoso.com', 'user' => 'jane@contoso.com', 'changed' => true)
    expect(runner_request('Remove-RecipientPermission', change)).to have_been_made
  end

  it 'changes nothing when the user holds no Send As' do
    stub_cmdlet('Get-RecipientPermission', output: [])
    expect(run_action(input)['changed']).to be(false)
    expect(runner_request('Remove-RecipientPermission')).not_to have_been_made
  end
end
