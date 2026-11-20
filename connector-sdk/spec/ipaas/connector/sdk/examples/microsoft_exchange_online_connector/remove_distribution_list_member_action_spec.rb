require 'spec_helper'

describe 'Microsoft Exchange Online Remove member from distribution list Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-0288-7626-b93b-25a8f0608152' }

  def input(overrides = {})
    { list: 'sales@contoso.com', user: 'jane@contoso.com' }.merge(overrides)
  end

  it 'removes the user and reports the change' do
    stub_cmdlet('Remove-DistributionGroupMember', output: [])
    output = run_action(input)
    expect(runner_request('Remove-DistributionGroupMember',
                          { Identity: 'sales@contoso.com', Member: 'jane@contoso.com',
                            BypassSecurityGroupManagerCheck: true, Confirm: false, })).to have_been_made
    expect(output).to eq('list' => 'sales@contoso.com', 'user' => 'jane@contoso.com', 'changed' => true)
  end

  it 'reports no change when Exchange says the user is not a member' do
    stub_cmdlet_error('Remove-DistributionGroupMember',
                      error_id: '[FailureCategory=Cmdlet-MemberNotFoundException] 9C2D',
                      message: "The recipient isn't a member of the group.")
    expect(run_action(input)['changed']).to be(false)
  end

  it 'fails with the Exchange error on any other refusal' do
    stub_cmdlet_error('Remove-DistributionGroupMember', status: 403, category: 'forbidden', error_id: '',
                                                        message: 'Access denied.')
    expect do
      run_action(input)
    end.to raise_error(IPaaS::Job::FailJob, /Exchange Online refused Remove-DistributionGroupMember/)
  end
end
