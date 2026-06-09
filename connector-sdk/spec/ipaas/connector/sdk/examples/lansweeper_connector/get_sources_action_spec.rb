require 'spec_helper'

describe 'Lansweeper Get Sources Action', :action do
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

    it 'should define the optional page_size field defaulting to 100, bounded 1..100' do
      action.input_schema.field(:page_size).tap do |field|
        expect(field.label).to eq('Page Size')
        expect(field.type).to eq(:integer)
        expect(field.required).to be_falsey
        expect(field.visibility).to eq('optional')
        expect(field.default).to eq(100)
        expect(field.min).to eq(1)
        expect(field.max).to eq(100)
      end
    end
  end

  describe 'output_schema' do
    it 'should define the total field' do
      action.output_schema.first.field(:total).tap do |field|
        expect(field.label).to eq('Total')
        expect(field.type).to eq(:integer)
      end
    end

    it 'should define the has_next_page field' do
      action.output_schema.first.field(:has_next_page).tap do |field|
        expect(field.label).to eq('Has next page')
        expect(field.type).to eq(:boolean)
        expect(field.required).to be_truthy
      end
    end

    it 'should define the sources field with sources-API fields' do
      sources_field = action.output_schema.first.field(:sources).tap do |field|
        expect(field.label).to eq('Sources')
        expect(field.type).to eq(:nested)
        expect(field.array).to eq(true)
      end

      sources_field.field(:source_id).tap do |field|
        expect(field.label).to eq('Source ID')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end

      sources_field.field(:name).tap do |field|
        expect(field.label).to eq('Name')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end

      sources_field.field(:external_id).tap do |field|
        expect(field.label).to eq('External ID')
        expect(field.type).to eq(:string)
      end

      sources_field.field(:created_at).tap do |field|
        expect(field.label).to eq('Created At')
        expect(field.type).to eq(:date_time)
      end

      sources_field.field(:state).tap do |field|
        expect(field.label).to eq('State')
        expect(field.type).to eq(:string)
      end

      sources_field.field(:first_sync_completed_on).tap do |field|
        expect(field.label).to eq('First Sync Completed On')
        expect(field.type).to eq(:date_time)
      end
    end
  end

  describe 'iteration_state_schema' do
    it 'persists only the pagination cursor' do
      action.iteration_state_schema.field(:next_cursor).tap do |field|
        expect(field.label).to eq('Next cursor')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end
    end
  end

  describe 'run' do
    include_context 'lansweeper graphql'

    def trigger_action(site_id: 'test-site-id', page_size: nil)
      input = { site_id: site_id }
      input[:page_size] = page_size unless page_size.nil?
      run_action(input)
    end

    describe 'returns sources' do
      it 'gets values for sources' do
        site_id = 'test-site-id'

        graphql_response = {
          data: {
            site: {
              sources: {
                total: 2,
                pagination: { limit: 100, current: 1, next: nil, page: 'FIRST' },
                items: [
                  {
                    id: 'inst-1',
                    type: 'IT',
                    state: {
                      value: 'ACTIVE',
                      unlinkedOnDate: nil,
                      deletedOnDate: nil,
                      firstSyncCompletedOn: '2024-01-15T11:30:00Z',
                    },
                    siteId: site_id,
                    createdAt: '2024-01-15T10:00:00Z',
                    externalId: 'ext-1',
                    displayName: 'Main Server',
                  },
                  {
                    id: 'inst-2',
                    type: 'CLOUD',
                    state: {
                      value: 'UNLINKED',
                      unlinkedOnDate: '2024-03-01T08:00:00Z',
                      deletedOnDate: nil,
                      firstSyncCompletedOn: '2024-02-01T12:00:00Z',
                    },
                    siteId: site_id,
                    createdAt: '2024-02-01T09:00:00Z',
                    externalId: 'ext-2',
                    displayName: 'Backup Cloud',
                  },
                ],
              },
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .with(body: hash_including(
                 query: /query listSources/,
                 variables: { siteId: site_id },
               ))
               .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id)

        expect(output[:total]).to eq(2)

        sources = output[:sources]
        expect(sources.length).to eq(2)
        expect(sources.pluck(:source_id)).to contain_exactly('inst-1', 'inst-2')
        expect(sources.pluck(:name)).to contain_exactly('Main Server', 'Backup Cloud')
        expect(sources.pluck(:site_id)).to contain_exactly(site_id, site_id)
        expect(sources.pluck(:type)).to contain_exactly('IT', 'CLOUD')
        expect(sources.pluck(:external_id)).to contain_exactly('ext-1', 'ext-2')
        expect(sources.pluck(:created_at)).to contain_exactly('2024-01-15T10:00:00Z', '2024-02-01T09:00:00Z')
        expect(sources.pluck(:state)).to contain_exactly('ACTIVE', 'UNLINKED')

        inst1 = sources.find { |i| i[:source_id] == 'inst-1' }
        expect(inst1[:unlinked_on_date]).to be_nil
        expect(inst1[:deleted_on_date]).to be_nil
        expect(inst1[:first_sync_completed_on]).to eq('2024-01-15T11:30:00Z')

        inst2 = sources.find { |i| i[:source_id] == 'inst-2' }
        expect(inst2[:unlinked_on_date]).to eq('2024-03-01T08:00:00Z')
        expect(inst2[:deleted_on_date]).to be_nil
        expect(inst2[:first_sync_completed_on]).to eq('2024-02-01T12:00:00Z')

        expect(stub).to have_been_requested.once
      end

      it 'handles empty sources array' do
        site_id = 'test-site-id'
        graphql_response = {
          data: {
            site: {
              sources: {
                total: 0,
                items: [],
              },
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id)
        expect(output[:total]).to eq(0)
        expect(output[:sources]).to eq([])
        expect(stub).to have_been_requested.once
      end

      it 'handles source with nil state nested object' do
        site_id = 'test-site-id'
        graphql_response = {
          data: {
            site: {
              sources: {
                total: 1,
                items: [
                  {
                    id: 'inst-3',
                    type: 'MANUAL',
                    state: nil,
                    siteId: site_id,
                    createdAt: nil,
                    externalId: nil,
                    displayName: 'Manual Source',
                  },
                ],
              },
            },
          },
        }

        stub_request(:post, generate_expected_url)
          .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id)
        inst = output[:sources].first
        expect(inst[:name]).to eq('Manual Source')
        expect(inst[:state]).to be_nil
        expect(inst[:unlinked_on_date]).to be_nil
        expect(inst[:deleted_on_date]).to be_nil
        expect(inst[:first_sync_completed_on]).to be_nil
      end

      it 'falls back to id when displayName is nil (name is required)' do
        site_id = 'test-site-id'
        graphql_response = {
          data: { site: { sources: {
            total: 1,
            items: [
              { id: 'src-without-name', type: 'IT', state: nil, siteId: site_id,
                createdAt: nil, externalId: nil, displayName: nil, },
            ],
          } } },
        }
        stub_request(:post, generate_expected_url).to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id)
        expect(output[:sources].first[:name]).to eq('src-without-name')
      end

      it 'defaults total to the number of sources when the API omits it' do
        site_id = 'test-site-id'
        graphql_response = {
          data: { site: { sources: {
            items: [
              { id: 'src-1', type: 'IT', state: nil, siteId: site_id,
                createdAt: nil, externalId: nil, displayName: 'S1', },
            ],
          } } },
        }
        stub_request(:post, generate_expected_url).to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id)
        expect(output[:total]).to eq(1)
      end
    end

    describe 'iteration state handling' do
      def source_page(next_cursor:, ids:)
        {
          data: { site: { sources: {
            total: 3,
            pagination: { next: next_cursor },
            items: ids.map do |id|
              { id: id, type: 'IT', state: { value: 'ACTIVE' }, siteId: 'test-site-id',
                createdAt: nil, externalId: nil, displayName: "Name #{id}", }
            end,
          } } },
        }
      end

      it 'reports has_next_page and stores the cursor when more pages remain' do
        stub_request(:post, generate_expected_url)
          .to_return(body: source_page(next_cursor: 'cursor-2', ids: %w[src-1 src-2]).to_json)

        expect(action(site_id: 'test-site-id')).to receive(:iteration_state_value=)
          .with(hash_including(next_cursor: 'cursor-2'))
          .and_call_original

        output = run_action({ site_id: 'test-site-id' })
        expect(output[:has_next_page]).to eq(true)
        expect(output[:sources].pluck(:source_id)).to contain_exactly('src-1', 'src-2')
      end

      it 'clears iteration state and reports no next page on the last page' do
        stub_request(:post, generate_expected_url)
          .to_return(body: source_page(next_cursor: nil, ids: %w[src-3]).to_json)

        expect(action(site_id: 'test-site-id')).to receive(:iteration_state_value=).with(nil)

        output = run_action({ site_id: 'test-site-id' })
        expect(output[:has_next_page]).to eq(false)
      end

      it 'requests the next page with the stored cursor' do
        next_cursor = 'cursor-abc'
        stub = stub_request(:post, generate_expected_url)
               .with do |request|
                 q = JSON.parse(request.body)['query']
                 q.include?('page: NEXT') && q.include?(%(cursor: "#{next_cursor}"))
               end
               .to_return(body: source_page(next_cursor: nil, ids: %w[src-9]).to_json)

        action(site_id: 'test-site-id').send(:iteration_state_value=, { next_cursor: next_cursor })

        output = run_action({ site_id: 'test-site-id' })
        expect(output[:sources].pluck(:source_id)).to contain_exactly('src-9')
        expect(stub).to have_been_requested.once
      end
    end

    describe 'page size' do
      def empty_page_body
        { data: { site: { sources: { total: 0, pagination: { next: nil }, items: [] } } } }.to_json
      end

      it 'defaults to a page size of 100 when none is provided' do
        stub = stub_request(:post, generate_expected_url)
               .with { |req| JSON.parse(req.body)['query'].include?('limit: 100') }
               .to_return(body: empty_page_body)

        trigger_action
        expect(stub).to have_been_requested.once
      end

      it 'uses a user-provided page size' do
        stub = stub_request(:post, generate_expected_url)
               .with { |req| JSON.parse(req.body)['query'].include?('limit: 25') }
               .to_return(body: empty_page_body)

        trigger_action(page_size: 25)
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
          expect(message).to start_with('Unable to query sources : GraphQL errors: ')
          expect(message).to include('Site not found')
        end
        expect(stub).to have_been_requested.once
      end
    end
  end
end
