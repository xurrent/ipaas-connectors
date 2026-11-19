require 'spec_helper'

describe 'Microsoft Exchange Online Hide from address list Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-0294-7e3d-9944-974c8aad81e5' }

  def input(overrides = {})
    { mailbox: 'leaver@contoso.com', hidden: nil }.merge(overrides)
  end

  it 'hides a visible mailbox by default and reports the change' do
    stub_cmdlet('Get-Mailbox', output: [{ HiddenFromAddressListsEnabled: false, IsDirSynced: false }])
    stub_cmdlet('Set-Mailbox', output: [])
    output = run_action(input)
    expect(runner_request('Set-Mailbox', { Identity: 'leaver@contoso.com', HiddenFromAddressListsEnabled: true }))
      .to have_been_made
    expect(output).to eq('mailbox' => 'leaver@contoso.com', 'hidden' => true, 'changed' => true)
  end

  it 'shows a hidden mailbox again when Hidden is false' do
    stub_cmdlet('Get-Mailbox', output: [{ HiddenFromAddressListsEnabled: true }])
    stub_cmdlet('Set-Mailbox', output: [])
    expect(run_action(input(hidden: false))).to include('hidden' => false, 'changed' => true)
    expect(runner_request('Set-Mailbox', { Identity: 'leaver@contoso.com', HiddenFromAddressListsEnabled: false }))
      .to have_been_made
  end

  it 'changes nothing when the mailbox already is hidden' do
    stub_cmdlet('Get-Mailbox', output: [{ HiddenFromAddressListsEnabled: true }])
    expect(run_action(input)['changed']).to be(false)
    expect(runner_request('Set-Mailbox')).not_to have_been_made
  end

  it 'refuses a mailbox synchronized from on-premises and names the attribute to set there' do
    stub_cmdlet('Get-Mailbox', output: [{ HiddenFromAddressListsEnabled: false, IsDirSynced: true }])
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob, "Mailbox 'leaver@contoso.com' is synchronized from on-premises Active " \
                                           'Directory, which would undo this change. Set msExchHideFromAddressLists ' \
                                           'on the on-premises account instead.')
  end
end
