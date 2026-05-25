require 'spec_helper'

describe 'Lansweeper Get Sites Action', :action do
  let(:connector_id) { '019b22da-f781-7c72-b3c6-5e796a404308' }
  let(:action_template_id) { '019b22db-f781-7c72-b3c6-5e796a404308' }

  describe 'input_schema' do
    it 'should have no required input fields' do
      expect(action.input_schema.fields).to be_empty
    end
  end

  describe 'output_schema' do
    it 'should define the sites field' do
      sites_field = action.output_schema.first.field(:sites).tap do |field|
        expect(field.label).to eq('Sites')
        expect(field.type).to eq(:nested)
        expect(field.array).to eq(true)
      end

      sites_field.field(:site_id).tap do |field|
        expect(field.label).to eq('Site ID')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end

      sites_field.field(:site_name).tap do |field|
        expect(field.label).to eq('Site Name')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end
    end
  end

  describe 'run' do
    include_context 'lansweeper graphql'

    def trigger_action
      run_action({})
    end

    describe 'returns sites' do
      it 'gets values for sites' do
        graphql_response = {
          data: {
            authorizedSites: {
              sites: [
                {
                  id: 'site-1',
                  name: 'Main Site',
                },
                {
                  id: 'site-2',
                  name: 'Remote Office',
                },
              ],
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .with(body: hash_including(
                 query: /authorizedSites/,
               ))
               .to_return(body: graphql_response.to_json)

        output = trigger_action
        sites = output[:sites]
        expect(sites.pluck(:site_id)).to contain_exactly('site-1', 'site-2')
        expect(sites.pluck(:site_name)).to contain_exactly('Main Site', 'Remote Office')
        expect(stub).to have_been_requested.once
      end

      it 'handles empty sites array' do
        graphql_response = {
          data: {
            authorizedSites: {
              sites: [],
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .to_return(body: graphql_response.to_json)

        expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, 'Not authorized for any sites')
        expect(stub).to have_been_requested.once
      end

      it 'handles missing authorizedSites in response' do
        graphql_response = {
          data: {},
        }

        stub = stub_request(:post, generate_expected_url)
               .to_return(body: graphql_response.to_json)

        expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, 'No authorizedSites in Lansweeper response')
        expect(stub).to have_been_requested.once
      end
    end

    describe 'error handling' do
      it 'handles GraphQL errors' do
        graphql_response = {
          errors: [
            { message: 'Unauthorized' },
            { message: 'Invalid query' },
          ],
        }

        stub = stub_request(:post, generate_expected_url)
               .to_return(body: graphql_response.to_json)

        expect { trigger_action }.to raise_error(IPaaS::Job::FailJob) do |error|
          message = error.message
          expect(message).to start_with('Unable to query accessible Lansweeper sites: GraphQL errors: ')
          expect(message).to include('Unauthorized')
          expect(message).to include('Invalid query')
        end
        expect(stub).to have_been_requested.once
      end

      it 'handles 400' do
        stub = stub_request(:post, generate_expected_url)
               .to_return(status: 400, body: 'Bad request')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           "HTTP error from Lansweeper GraphQL API: 400 'Bad request'")
        expect(stub).to have_been_requested.once
      end

      it 'handles 401' do
        stub = stub_request(:post, generate_expected_url)
               .to_return(status: 401, body: 'Unauthorized')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           "HTTP error from Lansweeper GraphQL API: 401 'Unauthorized'")
        expect(stub).to have_been_requested.once
      end

      it 'handles invalid JSON response' do
        stub = stub_request(:post, generate_expected_url)
               .to_return(body: 'Invalid JSON')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           "Lansweeper GraphQL API response was not JSON: 'Invalid JSON'")
        expect(stub).to have_been_requested.once
      end

      it 'handles missing data in response' do
        graphql_response = {}

        stub = stub_request(:post, generate_expected_url)
               .to_return(body: graphql_response.to_json)

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           "No data in Lansweeper GraphQL response: '{}'")
        expect(stub).to have_been_requested.once
      end
    end
  end
end
