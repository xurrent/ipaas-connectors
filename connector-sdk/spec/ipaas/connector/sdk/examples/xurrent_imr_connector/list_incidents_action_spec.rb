require 'spec_helper'

describe 'Xurrent IMR List Incidents Action', :action, :xurrent_imr do
  let(:action_template_id) { '019d6d9a-3230-726a-8739-21d20b569a55' }
  describe 'input_schema' do
    it 'defines the status field' do
      action.input_schema.field(:status).tap do |field|
        expect(field.label).to eq('Status')
        expect(field.type).to eq(:integer)
        expect(field.visibility).to eq('optional')
        expect(field.enumeration).to eq([
          { id: -1, label: 'Open (triggered + acknowledged)' },
          { id: 0, label: 'All' },
          { id: 1, label: 'Triggered' },
          { id: 2, label: 'Acknowledged' },
          { id: 3, label: 'Resolved' },
        ])
      end
    end

    it 'defines the team_ids field' do
      action.input_schema.field(:team_ids).tap do |field|
        expect(field.label).to eq('Team IDs')
        expect(field.type).to eq(:string)
        expect(field.array).to eq(true)
        expect(field.visibility).to eq('optional')
      end
    end

    it 'defines the service_ids field' do
      action.input_schema.field(:service_ids).tap do |field|
        expect(field.label).to eq('Service IDs')
        expect(field.type).to eq(:string)
        expect(field.array).to eq(true)
        expect(field.visibility).to eq('optional')
      end
    end

    it 'defines the from_date field' do
      action.input_schema.field(:from_date).tap do |field|
        expect(field.label).to eq('From Date')
        expect(field.type).to eq(:date_time)
        expect(field.visibility).to eq('optional')
      end
    end

    it 'defines the to_date field' do
      action.input_schema.field(:to_date).tap do |field|
        expect(field.label).to eq('To Date')
        expect(field.type).to eq(:date_time)
        expect(field.visibility).to eq('optional')
      end
    end
  end

  describe 'output_schema' do
    it 'has only the page schema' do
      expect(action.output_schema.map(&:reference)).to contain_exactly('page')
    end

    describe 'page schema' do
      let(:page_schema) { action.output_schema.first }

      it 'defines the has_next_page field' do
        page_schema.field(:has_next_page).tap do |field|
          expect(field.label).to eq('Has Next Page')
          expect(field.type).to eq(:boolean)
          expect(field.required).to be_truthy
        end
      end

      it 'defines the incidents field with nested fields' do
        incidents_field = page_schema.field(:incidents).tap do |field|
          expect(field.label).to eq('Incidents')
          expect(field.type).to eq(:nested)
          expect(field.array).to eq(true)
        end

        incidents_field.field(:unique_id).tap do |field|
          expect(field.label).to eq('Unique ID')
          expect(field.type).to eq(:string)
        end

        incidents_field.field(:incident_number).tap do |field|
          expect(field.label).to eq('Incident Number')
          expect(field.type).to eq(:integer)
        end

        incidents_field.field(:title).tap do |field|
          expect(field.label).to eq('Title')
          expect(field.type).to eq(:string)
        end

        incidents_field.field(:summary).tap do |field|
          expect(field.label).to eq('Summary')
          expect(field.type).to eq(:string)
        end

        incidents_field.field(:status).tap do |field|
          expect(field.label).to eq('Status')
          expect(field.type).to eq(:integer)
        end

        incidents_field.field(:urgency).tap do |field|
          expect(field.label).to eq('Urgency')
          expect(field.type).to eq(:integer)
        end

        incidents_field.field(:creation_date).tap do |field|
          expect(field.label).to eq('Creation Date')
          expect(field.type).to eq(:string)
        end

        incidents_field.field(:resolved_date).tap do |field|
          expect(field.label).to eq('Resolved Date')
          expect(field.type).to eq(:string)
        end

        incidents_field.field(:acknowledged_date).tap do |field|
          expect(field.label).to eq('Acknowledged Date')
          expect(field.type).to eq(:string)
        end

        incidents_field.field(:assigned_to).tap do |field|
          expect(field.label).to eq('Assigned To')
          expect(field.type).to eq(:string)
        end

        incidents_field.field(:assigned_to_name).tap do |field|
          expect(field.label).to eq('Assigned To Name')
          expect(field.type).to eq(:string)
        end

        incidents_field.field(:service).tap do |field|
          expect(field.label).to eq('Service')
          expect(field.type).to eq(:string)
        end

        incidents_field.field(:escalation_policy).tap do |field|
          expect(field.label).to eq('Escalation Policy')
          expect(field.type).to eq(:string)
        end

        incidents_field.field(:incident_key).tap do |field|
          expect(field.label).to eq('Incident Key')
          expect(field.type).to eq(:string)
        end
      end
    end
  end

  describe 'iteration_state_schema' do
    it 'defines the page field' do
      action.iteration_state_schema.field(:page).tap do |field|
        expect(field.label).to eq('Page')
        expect(field.type).to eq(:integer)
        expect(field.required).to be_truthy
      end
    end
  end

  describe 'run' do
    let(:api_endpoint) { 'https://www.zenduty.com' }

    def filter_url(page: 1)
      "#{api_endpoint}/api/incidents/filter/?page=#{page}"
    end

    def trigger_action(input = {})
      run_action(input, schema_reference: 'page')
    end

    let(:incident_data) do
      {
        unique_id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        incident_number: 42,
        title: 'High CPU Alert',
        summary: 'High CPU usage on production server',
        status: 1,
        urgency: 1,
        creation_date: '2026-04-08T10:30:00Z',
        resolved_date: nil,
        acknowledged_date: nil,
        assigned_to: 'jdoe',
        assigned_to_name: 'John Doe',
        service: 'b2c3d4e5-f6a7-8901-bcde-f23456789012',
        escalation_policy: 'c3d4e5f6-a7b8-9012-cdef-345678901234',
        incident_key: 'cpu-alert-prod-001',
      }
    end

    describe 'successful responses' do
      it 'returns incidents from the first page with next page available' do
        stub = stub_request(:post, filter_url)
               .to_return(body: {
                 results: [incident_data],
                 next: "#{api_endpoint}/api/incidents/filter/?page=2",
                 previous: nil,
               }.to_json)

        expect(action({})).to receive(:iteration_state_value=).with({ page: 2 }).and_call_original

        output = trigger_action
        expect(output[:has_next_page]).to eq(true)
        expect(output[:incidents].length).to eq(1)
        expect(output[:incidents].first['unique_id']).to eq('a1b2c3d4-e5f6-7890-abcd-ef1234567890')
        expect(output[:incidents].first['incident_number']).to eq(42)
        expect(output[:incidents].first['title']).to eq('High CPU Alert')
        expect(stub).to have_been_requested.once
      end

      it 'returns incidents from the last page with no next page' do
        stub = stub_request(:post, filter_url)
               .to_return(body: {
                 results: [incident_data],
                 next: nil,
                 previous: nil,
               }.to_json)

        expect(action({})).to receive(:iteration_state_value=).with(nil).and_call_original

        output = trigger_action
        expect(output[:has_next_page]).to eq(false)
        expect(output[:incidents].length).to eq(1)
        expect(stub).to have_been_requested.once
      end

      it 'sends filter parameters in the request body' do
        filter_input = {
          status: 1,
          team_ids: ['team-uuid-1'],
          service_ids: ['svc-uuid-1'],
          from_date: '2026-04-01T00:00:00Z',
          to_date: '2026-04-08T00:00:00Z',
        }

        stub = stub_request(:post, filter_url)
               .to_return(body: { results: [], next: nil, previous: nil }.to_json)

        output = trigger_action(filter_input)
        expect(output[:has_next_page]).to eq(false)
        expect(output[:incidents]).to eq([])

        expect(stub).to have_been_requested.once
        expect(WebMock).to have_requested(:post, filter_url)
          .with { |req|
            body = JSON.parse(req.body)
            body['status'] == 1 &&
              body['team_ids'] == ['team-uuid-1'] &&
              body['service_ids'] == ['svc-uuid-1'] &&
              body['from_date'].present? &&
              body['to_date'].present?
          }
      end

      it 'uses iteration_state_value for subsequent pages' do
        stub = stub_request(:post, filter_url(page: 3))
               .to_return(body: {
                 results: [incident_data],
                 next: nil,
                 previous: "#{api_endpoint}/api/incidents/filter/?page=2",
               }.to_json)

        action({}).send(:iteration_state_value=, { page: 3 })

        output = trigger_action
        expect(output[:has_next_page]).to eq(false)
        expect(output[:incidents].length).to eq(1)
        expect(stub).to have_been_requested.once
      end
    end

    describe 'error handling' do
      let(:rate_limit_url) { filter_url }
      let(:rate_limit_http_method) { :post }
      let(:rate_limit_input) { {} }

      it_behaves_like 'xurrent_imr rate limiting'

      it 'handles 500 server error' do
        stub = stub_request(:post, filter_url)
               .to_return(status: 500, body: 'Internal Server Error')

        expect { trigger_action }
          .to raise_error(IPaaS::Job::FailJob,
                          "Xurrent IMR API error (HTTP 500): 'Internal Server Error'")
        expect(stub).to have_been_requested.once
      end

      it 'handles 401 authentication error' do
        stub = stub_request(:post, filter_url)
               .to_return(status: 401, body: 'Unauthorized')

        expect { trigger_action }
          .to raise_error(IPaaS::Job::FailJob,
                          "Xurrent IMR API error (HTTP 401): 'Unauthorized'")
        expect(stub).to have_been_requested.once
      end
    end
  end
end
