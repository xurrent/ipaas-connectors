require 'spec_helper'

describe 'Microsoft Exchange Online Grant Send As Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-027e-7153-9f6d-ecb2c8a560cd' }

  def input(overrides = {})
    { mailbox: 'support@contoso.com', user: 'jane@contoso.com' }.merge(overrides)
  end

  let(:lookup) { { Identity: 'support@contoso.com', Trustee: 'jane@contoso.com', AccessRights: 'SendAs' } }
  let(:change) do
    { Identity: 'support@contoso.com', Trustee: 'jane@contoso.com', AccessRights: ['SendAs'], Confirm: false }
  end
  let(:send_as_entry) { { AccessRights: ['SendAs'], AccessControlType: 'Allow', IsInherited: false } }

  it 'grants Send As when the user lacks it and reports the change' do
    stub_cmdlet('Get-RecipientPermission', output: [])
    stub_cmdlet('Add-RecipientPermission', output: [send_as_entry])
    output = run_action(input)
    expect(runner_request('Get-RecipientPermission', lookup)).to have_been_made
    expect(runner_request('Add-RecipientPermission', change)).to have_been_made
    expect(output).to eq('mailbox' => 'support@contoso.com', 'user' => 'jane@contoso.com', 'changed' => true)
  end

  it 'changes nothing when the user already holds Send As' do
    stub_cmdlet('Get-RecipientPermission', output: [send_as_entry])
    expect(run_action(input)['changed']).to be(false)
    expect(runner_request('Add-RecipientPermission')).not_to have_been_made
  end

  it 'grants when the only Send As entry is a deny' do
    stub_cmdlet('Get-RecipientPermission', output: [send_as_entry.merge(AccessControlType: 'Deny')])
    stub_cmdlet('Add-RecipientPermission', output: [])
    expect(run_action(input)['changed']).to be(true)
  end

  it 'grants when the only Send As entry is inherited' do
    stub_cmdlet('Get-RecipientPermission', output: [send_as_entry.merge(IsInherited: true)])
    stub_cmdlet('Add-RecipientPermission', output: [])
    expect(run_action(input)['changed']).to be(true)
  end
end
