require 'spec_helper'

describe 'Microsoft Entra Assign Or Remove User Licenses Action', :action, :ms_entra do
  let(:action_template_id) { '01a1a1c8-debd-7648-a5aa-39879582ac3f' }
  let(:assign_url) { "#{graph}/users/#{user_id}/assignLicense" }
  let(:add_sku) { 'c7df2760-2c81-4ef7-b578-5b5392b571df' }
  let(:other_add_sku) { '6fd2c87f-b296-42f0-b197-1e91e994b900' }
  let(:remove_sku) { 'f30db892-07e9-47e9-837c-80727f46fd3d' }
  let(:plan_id) { '113feb6c-3fe4-4440-bddc-54d774bf0318' }

  def stub_assign(status: 200, body: { id: user_id }.to_json)
    stub_request(:post, assign_url).to_return(status: status, body: body,
                                              headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'defines a required user id and three optional string arrays' do
      schema = action.input_schema
      expect(schema.field(:user_id).required).to be_truthy
      [:add_sku_ids, :disabled_plan_ids, :remove_sku_ids].each do |id|
        expect(schema.field(id).type).to eq(:string)
        expect(schema.field(id).array).to eq(true)
        expect(schema.field(id).required).to be_falsey
      end
    end
  end

  describe 'output_schema' do
    it 'defines a required user id and the added and removed sku arrays' do
      schema = action.output_schema.first
      expect(schema.field(:user_id).required).to be_truthy
      expect(schema.field(:added_sku_ids).array).to eq(true)
      expect(schema.field(:removed_sku_ids).array).to eq(true)
    end
  end

  describe 'run' do
    it 'posts the licenses to add and to remove' do
      stub_assign
      run_action({ user_id: user_id, add_sku_ids: [add_sku], remove_sku_ids: [remove_sku] })
      expect(a_request(:post, assign_url)
        .with(body: { addLicenses: [{ skuId: add_sku, disabledPlans: [] }], removeLicenses: [remove_sku] }))
        .to have_been_made.once
    end

    it 'turns the disabled plans off in every license it adds' do
      stub_assign
      run_action({ user_id: user_id, add_sku_ids: [add_sku, other_add_sku], disabled_plan_ids: [plan_id] })
      expect(a_request(:post, assign_url)
        .with(body: { addLicenses: [{ skuId: add_sku, disabledPlans: [plan_id] },
                                    { skuId: other_add_sku, disabledPlans: [plan_id] },],
                      removeLicenses: [], }))
        .to have_been_made.once
    end

    it 'reports the user id and the skus it sent' do
      stub_assign
      expect(run_action({ user_id: user_id, add_sku_ids: [add_sku], remove_sku_ids: [remove_sku] }))
        .to eq('user_id' => user_id, 'added_sku_ids' => [add_sku], 'removed_sku_ids' => [remove_sku])
    end

    it 'reports the user id it was given when Graph answers without one' do
      stub_assign(body: {}.to_json)
      expect(run_action({ user_id: user_id, add_sku_ids: [add_sku] })['user_id']).to eq(user_id)
    end

    it 'fails without a request when both lists are empty' do
      expect { run_action({ user_id: user_id, add_sku_ids: [], remove_sku_ids: [] }) }
        .to raise_error(IPaaS::Job::FailJob, 'Set at least one SKU ID to add or to remove.')
      expect(a_request(:post, assign_url)).not_to have_been_made
    end

    it 'fails without a request when a sku id is not a GUID' do
      expect { run_action({ user_id: user_id, add_sku_ids: ['ENTERPRISEPACK'] }) }
        .to raise_error(IPaaS::Job::FailJob,
                        "SKU ID to add 'ENTERPRISEPACK' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:post, assign_url)).not_to have_been_made
    end

    it 'fails naming LicenseAssignment.ReadWrite.All when Graph answers 403' do
      stub_assign(status: 403, body: access_denied.to_json)
      expect { run_action({ user_id: user_id, add_sku_ids: [add_sku] }) }
        .to raise_error(IPaaS::Job::FailJob,
                        /Permission this action needs: LicenseAssignment\.ReadWrite\.All\. Admin consent is required\./)
    end
  end
end
