require 'spec_helper'

describe 'Microsoft Intune Deny Or Revoke EPM Elevation (Beta) Action', :action, :ms_intune do
  let(:action_template_id) { '01a1c8f9-25d3-73ba-a936-156576ddab8e' }
  let(:request_id) { '3df245af-45af-3df2-af45-f23daf45f23d' }
  let(:deny_url) { "#{beta}/deviceManagement/elevationRequests/#{request_id}/deny" }
  let(:revoke_url) { "#{beta}/deviceManagement/elevationRequests/#{request_id}/revoke" }
  let(:review_url) { %r{\A#{Regexp.escape(beta)}/deviceManagement/elevationRequests/#{request_id}/(deny|revoke)\z} }

  def stub_review(status: 200, request_status: 'denied')
    stub_request(:post, review_url)
      .with { |request| @sent = JSON.parse(request.body) }
      .to_return(status: status, body: { value: { id: request_id, status: request_status } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe 'input_schema' do
    it 'requires the elevation request id and a deny or revoke decision' do
      schema = action.input_schema
      expect(schema.field(:elevation_request_id).required).to be_truthy
      expect(schema.field(:decision).required).to be_truthy
      expect(schema.field(:decision).enumeration.pluck(:id)).to eq(%w[deny revoke])
    end
  end

  describe 'output_schema' do
    it 'returns the request id and the nested application detail' do
      schema = action.output_schema.first
      expect(schema.field(:elevation_request_id).required).to be_truthy
      expect(schema.field(:application_detail).field(:product_version).type).to eq(:string)
    end
  end

  describe 'run' do
    it 'posts the justification to the beta deny endpoint for a deny decision' do
      stub_review
      output = run_action({ elevation_request_id: request_id, decision: 'deny',
                            reviewer_justification: 'Not approved', })
      expect(output).to eq('elevation_request_id' => request_id, 'status' => 'denied', 'application_detail' => {})
      expect(@sent).to eq('reviewerJustification' => 'Not approved')
      expect(a_request(:post, deny_url)).to have_been_made.once
      expect(a_request(:post, revoke_url)).not_to have_been_made
    end

    it 'posts an empty justification to the beta revoke endpoint for a revoke decision with no justification' do
      stub_review(request_status: 'revoked')
      output = run_action({ elevation_request_id: request_id, decision: 'revoke' })
      expect(output['status']).to eq('revoked')
      expect(@sent).to eq('reviewerJustification' => '')
      expect(a_request(:post, revoke_url)).to have_been_made.once
      expect(a_request(:post, deny_url)).not_to have_been_made
    end

    it 'fails naming DeviceManagementConfiguration.ReadWrite.All on 403' do
      stub_request(:post, review_url).to_return(status: 403, body: access_denied)
      expect { run_action({ elevation_request_id: request_id, decision: 'deny' }) }
        .to raise_error(IPaaS::Job::FailJob,
                        access_denied_failure('DeviceManagementConfiguration.ReadWrite.All'))
    end

    it 'fails with no request when the elevation request id is not a GUID' do
      expect { run_action({ elevation_request_id: 'request-1', decision: 'deny' }) }
        .to raise_error(IPaaS::Job::FailJob, "Elevation request ID 'request-1' is not a valid id (a GUID).")
      expect(a_request(:post, /graph\.microsoft\.com/)).not_to have_been_made
    end

    context 'when the Graph API endpoint does not end in /v1.0' do
      let(:outbound_connection_config) { super().merge(environment: { graph_endpoint: endpoint_outside_v1 }) }

      it 'fails before calling Microsoft' do
        expect { run_action({ elevation_request_id: request_id, decision: 'revoke' }) }
          .to raise_error(IPaaS::Job::FailJob, beta_refusal)
        expect(a_request(:post, /graph\./)).not_to have_been_made
      end
    end
  end
end
