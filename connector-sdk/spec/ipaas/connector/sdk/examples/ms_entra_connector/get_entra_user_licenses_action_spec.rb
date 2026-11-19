require 'spec_helper'

describe 'Microsoft Entra Get User Licenses Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-7d34-8ad6-5318d41eb50c' }
  let(:user_url) { "#{graph}/users/#{user_id}" }
  let(:sku_id) { 'c7df2760-2c81-4ef7-b578-5b5392b571df' }
  let(:plan_id) { '113feb6c-3fe4-4440-bddc-54d774bf0318' }

  let(:graph_user) do
    {
      id: user_id,
      assignedLicenses: [{ skuId: sku_id, disabledPlans: [plan_id] }],
      licenseAssignmentStates: [
        { skuId: sku_id, state: 'Active', error: 'None', assignedByGroup: group_id, disabledPlans: [plan_id] },
      ],
    }
  end

  def stub_user(status: 200, body: graph_user.to_json)
    stub_request(:get, user_url).with(query: hash_including({}))
                                .to_return(status: status, body: body,
                                           headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'defines a required user id string' do
      expect(action.input_schema.field(:user_id).type).to eq(:string)
      expect(action.input_schema.field(:user_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'defines a required user id and two nested license arrays' do
      schema = action.output_schema.first
      expect(schema.field(:user_id).required).to be_truthy
      expect(schema.field(:assigned_licenses).array).to eq(true)
      expect(schema.field(:assigned_licenses).field(:sku_id).required).to be_truthy
      expect(schema.field(:license_assignment_states).array).to eq(true)
      expect(schema.field(:license_assignment_states).field(:assigned_by_group).type).to eq(:string)
    end
  end

  describe 'run' do
    it 'reads the license properties of the user' do
      stub_user
      run_action({ user_id: user_id })
      expect(a_request(:get, user_url)
        .with(query: { '$select' => 'id,assignedLicenses,licenseAssignmentStates' })).to have_been_made.once
    end

    it 'never calls the license details API' do
      stub_user
      run_action({ user_id: user_id })
      expect(a_request(:get, %r{/licenseDetails})).not_to have_been_made
    end

    it 'maps the assigned licenses and the license assignment states' do
      stub_user
      expect(run_action({ user_id: user_id })).to eq(
        'user_id' => user_id,
        'assigned_licenses' => [{ 'sku_id' => sku_id, 'disabled_plans' => [plan_id] }],
        'license_assignment_states' => [{ 'sku_id' => sku_id, 'state' => 'Active', 'error' => 'None',
                                          'assigned_by_group' => group_id, 'disabled_plans' => [plan_id], }]
      )
    end

    it 'fails naming User.Read.All when Graph answers 403' do
      stub_user(status: 403, body: access_denied.to_json)
      expect do
        run_action({ user_id: user_id })
      end.to raise_error(IPaaS::Job::FailJob,
                         /Permission this action needs: User\.Read\.All\. Admin consent is required\./)
    end
  end
end
