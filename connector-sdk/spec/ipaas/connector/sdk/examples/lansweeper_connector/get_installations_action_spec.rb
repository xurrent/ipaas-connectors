require 'spec_helper'

describe 'Lansweeper Get Installations Action', :action do
  let(:connector_id) { '019b22da-f781-7c72-b3c6-5e796a404308' }
  let(:action_template_id) { '019b22dc-f781-7c72-b3c6-5e796a404308' }

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
    it 'should define the installations field' do
      installations_field = action.output_schema.first.field(:installations).tap do |field|
        expect(field.label).to eq('Installations')
        expect(field.type).to eq(:nested)
        expect(field.array).to eq(true)
      end

      installations_field.field(:installation_id).tap do |field|
        expect(field.label).to eq('Installation ID')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end

      installations_field.field(:name).tap do |field|
        expect(field.label).to eq('Name')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end
    end
  end

  describe 'run' do
    include_context 'lansweeper graphql'

    def trigger_action(site_id: 'test-site-id')
      run_action({ site_id: site_id })
    end

    describe 'returns installations' do
      it 'gets values for installations' do
        site_id = 'test-site-id'

        graphql_response = {
          data: {
            site: {
              allInstallations: [
                {
                  id: 'inst-1',
                  siteId: site_id,
                  name: 'Main Server',
                  fqdn: 'lansweeper.example.com',
                  description: 'Primary installation',
                  type: 'OnPremise',
                  totalAssets: 1500,
                  syncServerStatus: 'Online',
                  lastAvailable: '2024-01-15T10:30:00Z',
                  version: '10.0.0',
                },
                {
                  id: 'inst-2',
                  siteId: site_id,
                  name: 'Backup Server',
                  fqdn: 'backup.example.com',
                  description: nil,
                  type: 'Cloud',
                  totalAssets: 500,
                  syncServerStatus: 'Offline',
                  lastAvailable: nil,
                  version: '9.5.0',
                },
              ],
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .with(body: hash_including(
                 query: /query getInstallations/,
                 variables: { siteId: site_id },
               ))
               .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id)
        installations = output[:installations]
        expect(installations.length).to eq(2)
        expect(installations.pluck(:installation_id)).to contain_exactly('inst-1', 'inst-2')
        expect(installations.pluck(:name)).to contain_exactly('Main Server', 'Backup Server')
        expect(installations.pluck(:site_id)).to contain_exactly(site_id, site_id)
        expect(installations.pluck(:fqdn)).to contain_exactly('lansweeper.example.com', 'backup.example.com')
        expect(stub).to have_been_requested.once
      end

      it 'handles empty installations array' do
        site_id = 'test-site-id'
        graphql_response = {
          data: {
            site: {
              allInstallations: [],
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id)
        expect(output[:installations]).to eq([])
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
          expect(message).to start_with('Unable to query all installations : GraphQL errors: ')
          expect(message).to include('Site not found')
        end
        expect(stub).to have_been_requested.once
      end
    end
  end
end
