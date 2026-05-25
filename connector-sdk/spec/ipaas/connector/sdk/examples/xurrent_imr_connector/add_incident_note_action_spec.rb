require 'spec_helper'

describe 'Xurrent IMR Add Incident Note Action', :action, :xurrent_imr do
  let(:action_template_id) { '019d6d9a-3230-76d1-be11-716ea42d26e8' }
  describe 'input_schema' do
    it 'defines the incident_number field' do
      action.input_schema.field(:incident_number).tap do |field|
        expect(field.label).to eq('Incident Number')
        expect(field.type).to eq(:integer)
        expect(field.required).to be_truthy
      end
    end

    it 'defines the note field' do
      action.input_schema.field(:note).tap do |field|
        expect(field.label).to eq('Note')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
        expect(field.hint).to eq('Note content')
      end
    end
  end

  describe 'output_schema' do
    let(:schema) { action.output_schema.first }

    it 'defines the unique_id field' do
      schema.field(:unique_id).tap do |field|
        expect(field.label).to eq('Unique ID')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end
    end

    it 'defines the note field' do
      schema.field(:note).tap do |field|
        expect(field.label).to eq('Note')
        expect(field.type).to eq(:string)
      end
    end

    it 'defines the creation_date field' do
      schema.field(:creation_date).tap do |field|
        expect(field.label).to eq('Creation Date')
        expect(field.type).to eq(:string)
      end
    end

    it 'defines the user field' do
      schema.field(:user).tap do |field|
        expect(field.label).to eq('User')
        expect(field.type).to eq(:string)
      end
    end
  end

  describe 'run' do
    let(:api_endpoint) { 'https://www.zenduty.com' }

    def note_url(incident_number)
      "#{api_endpoint}/api/incidents/#{incident_number}/note/"
    end

    def trigger_action(incident_number: 42, note: 'Investigation started')
      run_action({ incident_number: incident_number, note: note })
    end

    let(:note_response) do
      {
        unique_id: 'note-uuid-123',
        incident: 42,
        note: 'Investigation started',
        creation_date: '2026-04-08T11:00:00Z',
        user: 'user-unique-id-456',
      }
    end

    describe 'successful response' do
      it 'creates a note and returns the result' do
        stub = stub_request(:post, note_url(42))
               .with(body: { note: 'Investigation started' }.to_json)
               .to_return(status: 201, body: note_response.to_json)

        output = trigger_action
        expect(output[:unique_id]).to eq('note-uuid-123')
        expect(output[:note]).to eq('Investigation started')
        expect(output[:creation_date]).to eq('2026-04-08T11:00:00Z')
        expect(output[:user]).to eq('user-unique-id-456')
        expect(stub).to have_been_requested.once
      end
    end

    describe 'with custom base URL' do
      let(:outbound_connection_config) do
        {
          credentials: { api_key: make_secret_string('test-api-key') },
          base_url: 'https://staging.zenduty.com',
        }
      end

      it 'uses the custom base URL' do
        stub = stub_request(:post, 'https://staging.zenduty.com/api/incidents/42/note/')
               .with(body: { note: 'Investigation started' }.to_json)
               .to_return(status: 201, body: note_response.to_json)

        output = trigger_action
        expect(output[:unique_id]).to eq('note-uuid-123')
        expect(stub).to have_been_requested.once
      end

      it 'strips a trailing slash from the custom base URL' do
        stub = stub_request(:post, 'https://staging.zenduty.com/api/incidents/42/note/')
               .with(body: { note: 'Investigation started' }.to_json)
               .to_return(status: 201, body: note_response.to_json)

        outbound_connection_config[:base_url] = 'https://staging.zenduty.com/'
        output = trigger_action
        expect(output[:unique_id]).to eq('note-uuid-123')
        expect(stub).to have_been_requested.once
      end
    end

    describe 'error handling' do
      let(:rate_limit_url) { note_url(42) }
      let(:rate_limit_http_method) { :post }
      let(:rate_limit_input) { { incident_number: 42, note: 'test' } }

      it_behaves_like 'xurrent_imr rate limiting'

      it 'handles 401 authentication error' do
        stub = stub_request(:post, note_url(42))
               .to_return(status: 401, body: 'Unauthorized')

        expect { trigger_action }
          .to raise_error(IPaaS::Job::FailJob,
                          "Xurrent IMR API error (HTTP 401): 'Unauthorized'")
        expect(stub).to have_been_requested.once
      end

      it 'handles 500 server error' do
        stub = stub_request(:post, note_url(42))
               .to_return(status: 500, body: 'Internal Server Error')

        expect { trigger_action }
          .to raise_error(IPaaS::Job::FailJob,
                          "Xurrent IMR API error (HTTP 500): 'Internal Server Error'")
        expect(stub).to have_been_requested.once
      end
    end
  end
end
