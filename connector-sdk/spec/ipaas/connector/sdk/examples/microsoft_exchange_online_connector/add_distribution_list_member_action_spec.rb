require 'spec_helper'

describe 'Microsoft Exchange Online Add member to distribution list Action', :action, :microsoft_exchange_online do
  let(:action_template_id) { '01a1f2c3-0285-7f9d-96c4-3b6ffa0cd5ad' }

  def input(overrides = {})
    { list: 'sales@contoso.com', user: 'jane@contoso.com', allow_closed_list: nil }.merge(overrides)
  end

  let(:add) { { Identity: 'sales@contoso.com', Member: 'jane@contoso.com', BypassSecurityGroupManagerCheck: true } }

  def stub_list(restriction)
    stub_cmdlet('Get-DistributionGroup', output: [{ Name: 'Sales', MemberJoinRestriction: restriction }])
  end

  it 'adds the user to an open list and reports the change' do
    stub_list('Open')
    stub_cmdlet('Add-DistributionGroupMember', output: [])
    output = run_action(input)
    expect(runner_request('Add-DistributionGroupMember', add)).to have_been_made
    expect(output).to eq('list' => 'sales@contoso.com', 'user' => 'jane@contoso.com',
                         'member_join_restriction' => 'Open', 'changed' => true)
  end

  it 'reports no change when Exchange says the user already is a member' do
    stub_list('Open')
    stub_cmdlet_error('Add-DistributionGroupMember',
                      error_id: '[Server=AM0PR01][FailureCategory=Cmdlet-MemberAlreadyExistsException] 5F6A',
                      message: 'The recipient is already a member of the group.')
    expect(run_action(input)['changed']).to be(false)
  end

  it 'fails with the Exchange error on any other refusal' do
    stub_list('Open')
    stub_cmdlet_error('Add-DistributionGroupMember', status: 404, category: 'not_found',
                                                     error_id: 'ManagementObjectNotFoundException',
                                                     message: "Couldn't find object 'jane@contoso.com'.")
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob, "Add-DistributionGroupMember failed with HTTP 404 (not_found): Couldn't " \
                                           "find object 'jane@contoso.com'.")
  end

  it 'refuses a Closed list, which is not self-service' do
    stub_list('Closed')
    expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, /'sales@contoso.com' is Closed to new members/)
    expect(runner_request('Add-DistributionGroupMember')).not_to have_been_made
  end

  it 'adds to a Closed list when the step allows it' do
    stub_list('Closed')
    stub_cmdlet('Add-DistributionGroupMember', output: [])
    expect(run_action(input(allow_closed_list: true))['changed']).to be(true)
  end

  it 'leaves the restriction empty when Exchange reports none' do
    stub_cmdlet('Get-DistributionGroup', output: [{ Name: 'Sales' }])
    stub_cmdlet('Add-DistributionGroupMember', output: [])
    expect(run_action(input)['member_join_restriction']).to be_nil
  end

  it 'fails when the list does not exist' do
    stub_cmdlet('Get-DistributionGroup', output: [])
    expect { run_action(input) }
      .to raise_error(IPaaS::Job::FailJob, "Distribution list 'sales@contoso.com' was not found in Exchange Online.")
  end
end
