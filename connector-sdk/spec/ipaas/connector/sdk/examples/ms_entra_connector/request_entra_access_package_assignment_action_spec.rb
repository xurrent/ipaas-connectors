require 'spec_helper'

describe 'Microsoft Entra Request Access Package Assignment Action', :action, :ms_entra do
  let(:action_template_id) { '01a1c904-3b90-7f58-8517-9b2b8a4100e4' }
  let(:requests_url) { "#{graph}/identityGovernance/entitlementManagement/assignmentRequests" }
  let(:access_package_id) { 'a914b616-e04e-476b-aa37-91038f0b165b' }
  let(:policy_id) { '2264bf65-76ba-417b-a27d-54d291f0cbc8' }
  let(:request_id) { 'c0a2d3e1-6f2b-4a8e-9b4d-1e7f3a2c5d60' }

  def request_input(overrides = {})
    { user_id: user_id, access_package_id: access_package_id, assignment_policy_id: policy_id }.merge(overrides)
  end

  def stub_request_post(status: 201, body: { id: request_id, requestType: 'adminAdd', state: 'submitted',
                                             status: 'Accepted', }.to_json)
    stub_request(:post, requests_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'requires the user, the access package and the policy' do
      schema = action.input_schema
      expect(schema.field(:user_id).required).to be_truthy
      expect(schema.field(:access_package_id).required).to be_truthy
      expect(schema.field(:assignment_policy_id).required).to be_truthy
    end
  end

  describe 'output_schema' do
    it 'returns a required request id' do
      expect(action.output_schema.first.field(:request_id).required).to be_truthy
    end
  end

  describe 'run' do
    it 'posts an administrator add request for the user and maps the request on 201' do
      stub_request_post
      output = run_action(request_input)
      expect(@sent).to eq('requestType' => 'adminAdd', 'assignment' => {
        'targetId' => user_id, 'assignmentPolicyId' => policy_id,
        'accessPackageId' => access_package_id,
      })
      expect(output).to eq('request_id' => request_id, 'request_type' => 'adminAdd', 'state' => 'submitted',
                           'status' => 'Accepted')
    end

    it 'sends the justification when it is set' do
      stub_request_post
      run_action(request_input(justification: ' Approved in Xurrent '))
      expect(@sent['justification']).to eq('Approved in Xurrent')
    end

    it 'ignores the beta names requestState and requestStatus, leaving state and status nil' do
      stub_request_post(body: { id: request_id, requestType: 'adminAdd', requestState: 'Submitted',
                                requestStatus: 'Accepted', }.to_json)
      output = run_action(request_input)
      expect(output).to include('state' => nil, 'status' => nil)
    end

    it 'fails with the Graph message when Graph answers 200 where 201 is expected' do
      stub_request_post(status: 200)
      expect { run_action(request_input) }.to raise_error(IPaaS::Job::FailJob, /Microsoft Graph returned HTTP 200/)
    end

    it 'fails with no request when the access package id is not a GUID' do
      expect { run_action(request_input(access_package_id: 'Sales access')) }
        .to raise_error(IPaaS::Job::FailJob,
                        "Access package ID 'Sales access' is not a Microsoft Entra object id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it 'fails the job on 503 instead of retrying, because the request may already be accepted' do
      stub = stub_request_post(status: 503, body: graph_error('serviceNotAvailable', 'Service unavailable'))
      expect { run_action(request_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        'Microsoft Graph returned HTTP 503 serviceNotAvailable: Service unavailable')
      expect(stub).to have_been_requested.once
    end

    it 'names EntitlementManagement.ReadWrite.All on 403' do
      stub_request_post(status: 403, body: access_denied.to_json)
      expect { run_action(request_input) }
        .to raise_error(IPaaS::Job::FailJob,
                        include('Permission this action needs: EntitlementManagement.ReadWrite.All. ' \
                                'Admin consent is required.'))
    end
  end
end
