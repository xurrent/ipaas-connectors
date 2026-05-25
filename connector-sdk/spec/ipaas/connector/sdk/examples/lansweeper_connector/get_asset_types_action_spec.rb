require 'spec_helper'

describe 'Lansweeper Get Asset Types Action', :action do
  let(:connector_id) { '019b22da-f781-7c72-b3c6-5e796a404308' }
  let(:action_template_id) { '019b22dd-f781-7c72-b3c6-5e796a404308' }

  describe 'input_schema' do
    it 'should define the site_id field' do
      action.input_schema.field(:site_id).tap do |field|
        expect(field.label).to eq('Site ID')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end
    end
  end

  describe 'output_schema' do
    it 'should define the asset_types field' do
      action.output_schema.first.field(:asset_types).tap do |field|
        expect(field.label).to eq('Asset Types')
        expect(field.type).to eq(:string)
        expect(field.array).to eq(true)
      end
    end
  end

  describe 'run' do
    include_context 'lansweeper graphql'

    def trigger_action(site_id: 'test-site-id')
      run_action({ site_id: site_id })
    end

    describe 'returns asset types' do
      it 'gets values for asset types' do
        site_id = 'test-site-id'

        graphql_response = {
          data: {
            site: {
              id: site_id,
              assetTypes: ['Computer', 'Printer', 'Network Device', 'Mobile Device'],
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .with(body: hash_including(
                 query: /query getAssetTypes/,
                 variables: { siteId: site_id },
               ))
               .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id)
        asset_types = output[:asset_types]
        expect(asset_types).to contain_exactly('Computer', 'Printer', 'Network Device', 'Mobile Device')
        expect(stub).to have_been_requested.once
      end

      it 'handles empty asset types array' do
        site_id = 'test-site-id'
        graphql_response = {
          data: {
            site: {
              id: site_id,
              assetTypes: [],
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id)
        expect(output[:asset_types]).to eq([])
        expect(stub).to have_been_requested.once
      end
    end

    describe 'error handling' do
      it 'handles GraphQL errors' do
        graphql_response = {
          errors: [
            { message: 'Site not found' },
          ],
        }

        stub = stub_request(:post, generate_expected_url)
               .to_return(body: graphql_response.to_json)

        expect { trigger_action }.to raise_error(IPaaS::Job::FailJob) do |error|
          message = error.message
          expect(message).to start_with('Unable to query asset types: GraphQL errors: ')
          expect(message).to include('Site not found')
        end
        expect(stub).to have_been_requested.once
      end
    end
  end
end
