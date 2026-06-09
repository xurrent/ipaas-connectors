require 'spec_helper'

describe 'Lansweeper Get Assets Action', :action do
  let(:connector_id) { '019b22da-f781-7c72-b3c6-5e796a404308' }
  let(:action_template_id) { '019b22de-f781-7c72-b3c6-5e796a404308' }

  describe 'input_schema' do
    it 'should define the site_id field' do
      action.input_schema.field(:site_id).tap do |field|
        expect(field.label).to eq('Site ID')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end
    end

    it 'should define the import_type field' do
      action.input_schema.field(:import_type).tap do |field|
        expect(field.label).to eq('Import Type')
        expect(field.type).to eq(:string)
        expect(field.required).to be_falsey
        expect(field.visibility).to eq('optional')
        expect(field.default).to eq('all')
      end
    end

    it 'should define the source_ids field' do
      action.input_schema.field(:source_ids).tap do |field|
        expect(field.label).to eq('Source IDs')
        expect(field.type).to eq(:string)
        expect(field.array).to eq(true)
        expect(field.required).to be_falsey
        expect(field.visibility).to eq('optional')
      end
    end

    it 'should define the asset_types field' do
      action.input_schema.field(:asset_types).tap do |field|
        expect(field.label).to eq('Asset Types')
        expect(field.type).to eq(:string)
        expect(field.array).to eq(true)
        expect(field.required).to be_falsey
      end
    end

    it 'should define the cutoff_time field' do
      action.input_schema.field(:cutoff_time).tap do |field|
        expect(field.label).to eq('Cutoff Time')
        expect(field.type).to eq(:date_time)
        expect(field.required).to be_falsey
        expect(field.visibility).to eq('optional')
      end
    end
  end

  describe 'output_schema' do
    it 'should only have page output schema' do
      expect(action.output_schema.map(&:reference)).to contain_exactly('page')
    end

    describe 'page schema' do
      let(:page_schema) { action.output_schema.first }

      it 'should define the total field' do
        page_schema.field(:total).tap do |field|
          expect(field.label).to eq('Total')
          expect(field.type).to eq(:integer)
        end
      end

      it 'should define the has_next_page field' do
        page_schema.field(:has_next_page).tap do |field|
          expect(field.label).to eq('Has next page')
          expect(field.type).to eq(:boolean)
          expect(field.required).to be_truthy
        end
      end

      it 'should define the assets field' do
        assets_field = page_schema.field(:assets).tap do |field|
          expect(field.label).to eq('Assets')
          expect(field.type).to eq(:nested)
          expect(field.array).to eq(true)
        end

        assets_field.field(:key).tap do |field|
          expect(field.label).to eq('Key')
          expect(field.type).to eq(:string)
          expect(field.required).to be_truthy
        end

        assets_field.field(:name).tap do |field|
          expect(field.label).to eq('Name')
          expect(field.type).to eq(:string)
        end

        assets_field.field(:type).tap do |field|
          expect(field.label).to eq('Type')
          expect(field.type).to eq(:string)
        end

        assets_field.field(:user_name).tap do |field|
          expect(field.label).to eq('User Name')
          expect(field.type).to eq(:secret_string)
        end

        users_field = assets_field.field(:users).tap do |field|
          expect(field.label).to eq('Users')
          expect(field.type).to eq(:nested)
          expect(field.array).to eq(true)
        end

        users_field.field(:name).tap do |field|
          expect(field.label).to eq('Name')
          expect(field.type).to eq(:secret_string)
        end

        users_field.field(:email).tap do |field|
          expect(field.label).to eq('Email')
          expect(field.type).to eq(:secret_string)
        end

        users_field.field(:full_name).tap do |field|
          expect(field.label).to eq('Full Name')
          expect(field.type).to eq(:secret_string)
        end
      end
    end
  end

  describe 'iteration_state_schema' do
    it 'should define the required fields' do
      action.iteration_state_schema.field(:next_cursor).tap do |field|
        expect(field.label).to eq('Next cursor')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end

      action.iteration_state_schema.field(:site_id).tap do |field|
        expect(field.label).to eq('Site ID')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
      end

      action.iteration_state_schema.field(:page_size).tap do |field|
        expect(field.label).to eq('Page size')
        expect(field.type).to eq(:integer)
        expect(field.required).to be_truthy
      end
    end
  end

  describe 'run' do
    include_context 'lansweeper graphql'

    def trigger_action(site_id: 'test-site-id', import_type: 'all',
                       source_ids: nil, asset_types: nil, source_handling: nil, cutoff_time: nil)
      input = { site_id: site_id, import_type: import_type }
      input[:source_ids] = source_ids if source_ids
      input[:asset_types] = asset_types if asset_types
      input[:source_handling] = source_handling if source_handling
      input[:cutoff_time] = cutoff_time if cutoff_time
      run_action(input)
    end

    describe 'returns assets' do
      it 'gets values for assets with default settings' do
        site_id = 'test-site-id'
        cutoff_date = 30.days.ago
        cutoff_date.to_datetime.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')

        graphql_response = {
          data: {
            site: {
              assetResources: {
                total: 2,
                pagination: {
                  next: nil,
                },
                items: [
                  {
                    key: 'asset-1',
                    _id: 'asset-1',
                    url: 'https://lansweeper.com/asset/1',
                    assetBasicInfo: {
                      name: 'Computer-01',
                      type: 'Computer',
                      description: 'Test computer',
                      ipAddress: '192.168.1.100',
                      firstSeen: '2024-01-01T00:00:00Z',
                      lastSeen: '2024-01-15T10:30:00Z',
                      lastChanged: '2024-01-15T10:30:00Z',
                      userName: 'john.doe',
                      userDomain: 'DOMAIN',
                    },
                    assetCustom: {
                      model: 'Dell OptiPlex',
                      manufacturer: 'Dell',
                      stateName: 'Active',
                      purchaseDate: nil,
                      warrantyDate: nil,
                      serialNumber: 'SN123456',
                      sku: 'SKU123',
                    },
                    operatingSystem: {
                      name: 'Windows 10',
                    },
                    recognitionInfo: {
                      osMetadata: {
                        endOfSupportDate: '2025-10-14',
                      },
                    },
                    users: [
                      {
                        name: 'john.doe',
                        email: 'john.doe@example.com',
                        fullName: 'John Doe',
                      },
                    ],
                    softwares: [
                      {
                        name: 'Microsoft Office',
                      },
                    ],
                    processors: [
                      {
                        numberOfCores: 4,
                      },
                    ],
                    memoryModules: [
                      {
                        size: 8_589_934_592,
                      },
                    ],
                  },
                  {
                    key: 'asset-2',
                    _id: 'asset-2',
                    url: 'https://lansweeper.com/asset/2',
                    assetBasicInfo: {
                      name: 'Printer-01',
                      type: 'Printer',
                      description: nil,
                      ipAddress: '192.168.1.101',
                      firstSeen: '2024-01-02T00:00:00Z',
                      lastSeen: '2024-01-16T11:00:00Z',
                      lastChanged: '2024-01-16T11:00:00Z',
                      userName: nil,
                      userDomain: nil,
                    },
                    assetCustom: {
                      model: 'HP LaserJet',
                      manufacturer: 'HP',
                      stateName: 'Active',
                      purchaseDate: nil,
                      warrantyDate: nil,
                      serialNumber: 'SN789012',
                      sku: nil,
                    },
                    operatingSystem: nil,
                    recognitionInfo: {},
                    users: [],
                    softwares: [],
                    processors: [],
                    memoryModules: [],
                  },
                ],
              },
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .with do |request|
                 body = JSON.parse(request.body)
                 body['query'].include?('query getAssetResources') &&
                   body['variables']['siteId'] == site_id &&
                   body['variables']['pagination']['limit'] == 100 &&
                   body['variables']['pagination']['page'] == 'FIRST'
               end
               .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id)
        expect(output[:total]).to eq(2)
        expect(output[:has_next_page]).to eq(false)
        assets = output[:assets]
        expect(assets.length).to eq(2)
        expect(assets.pluck(:key)).to contain_exactly('asset-1', 'asset-2')
        expect(assets.pluck(:name)).to contain_exactly('Computer-01', 'Printer-01')
        expect(assets.pluck(:type)).to contain_exactly('Computer', 'Printer')
        expect(stub).to have_been_requested.once
      end

      it 'validates asset_types when import_type is selected_types_only' do
        expect do
          trigger_action(import_type: 'selected_types_only', asset_types: [])
        end.to raise_error(IPaaS::Job::FailJob,
                           'Asset Types is required when Import Type is "selected_types_only". ' \
                           'Please provide at least one asset type.')
      end

      it 'uses custom cutoff_time when provided' do
        site_id = 'test-site-id'
        custom_cutoff = DateTime.new(2024, 6, 1, 0, 0, 0)
        graphql_response = {
          data: {
            site: {
              assetResources: {
                total: 1,
                pagination: { next: nil },
                items: [
                  {
                    key: 'asset-1',
                    _id: 'asset-1',
                    url: 'https://lansweeper.com/asset/1',
                    assetBasicInfo: {
                      name: 'Computer-01',
                      type: 'Computer',
                      lastSeen: '2024-06-15T10:30:00Z',
                    },
                    assetCustom: {},
                    operatingSystem: {},
                    recognitionInfo: {},
                    users: [],
                    softwares: [],
                    processors: [],
                    memoryModules: [],
                  },
                ],
              },
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .with do |request|
                 body = JSON.parse(request.body)
                 query = body['query']
                 # Check that the cutoff time is used in the filter
                 query.include?('query getAssetResources') &&
                   query.include?('GREATER_THAN') &&
                   query.include?('2024-06-01T00:00:00.000Z')
               end
               .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id, cutoff_time: custom_cutoff)
        expect(output[:total]).to eq(1)
        expect(output[:assets].length).to eq(1)
        expect(stub).to have_been_requested.once
      end

      it 'handles assets with user data as secret strings' do
        site_id = 'test-site-id'
        graphql_response = {
          data: {
            site: {
              assetResources: {
                total: 1,
                pagination: { next: nil },
                items: [
                  {
                    key: 'asset-1',
                    _id: 'asset-1',
                    url: 'https://lansweeper.com/asset/1',
                    assetBasicInfo: {
                      name: 'Computer-01',
                      type: 'Computer',
                      userName: 'john.doe',
                    },
                    assetCustom: {},
                    operatingSystem: {},
                    recognitionInfo: {},
                    users: [
                      {
                        name: 'John Doe',
                        email: 'john.doe@example.com',
                        fullName: 'John William Doe',
                      },
                    ],
                    softwares: [],
                    processors: [],
                    memoryModules: [],
                  },
                ],
              },
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id)
        expect(output[:assets].length).to eq(1)
        asset = output[:assets].first
        # user_name should be present as a secret string (encrypted)
        expect(asset).to have_key(:user_name)
        expect(asset[:user_name]).not_to be_nil
        # users should have secret string fields (encrypted)
        expect(asset[:users].length).to eq(1)
        expect(asset[:users].first).to have_key(:name)
        expect(asset[:users].first).to have_key(:email)
        expect(asset[:users].first).to have_key(:full_name)
        expect(stub).to have_been_requested.once
      end

      it 'handles assets without user data gracefully' do
        site_id = 'test-site-id'
        graphql_response = {
          data: {
            site: {
              assetResources: {
                total: 1,
                pagination: { next: nil },
                items: [
                  {
                    key: 'asset-1',
                    _id: 'asset-1',
                    url: 'https://lansweeper.com/asset/1',
                    assetBasicInfo: {
                      name: 'Computer-01',
                      type: 'Computer',
                      userName: nil,
                    },
                    assetCustom: {},
                    operatingSystem: {},
                    recognitionInfo: {},
                    users: [],
                    softwares: [],
                    processors: [],
                    memoryModules: [],
                  },
                ],
              },
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id)
        expect(output[:assets].length).to eq(1)
        asset = output[:assets].first
        # user_name should be present as encrypted empty string
        expect(asset).to have_key(:user_name)
        expect(asset[:user_name]).not_to be_nil
        # users array should be empty
        expect(asset[:users]).to eq([])
        expect(stub).to have_been_requested.once
      end

      it 'filters by ip_only import type' do
        site_id = 'test-site-id'
        graphql_response = {
          data: {
            site: {
              assetResources: {
                total: 1,
                pagination: { next: nil },
                items: [
                  {
                    key: 'asset-1',
                    _id: 'asset-1',
                    url: 'https://lansweeper.com/asset/1',
                    assetBasicInfo: {
                      name: 'Computer-01',
                      type: 'Computer',
                      ipAddress: '192.168.1.100',
                      lastSeen: '2024-01-15T10:30:00Z',
                    },
                    assetCustom: {},
                    operatingSystem: {},
                    recognitionInfo: {},
                    users: [],
                    softwares: [],
                    processors: [],
                    memoryModules: [],
                  },
                ],
              },
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .with(body: hash_including(
                 query: /EXISTS.*assetBasicInfo\.ipAddress.*true/,
               ))
               .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id, import_type: 'ip_only')
        expect(output[:assets].length).to eq(1)
        expect(stub).to have_been_requested.once
      end

      it 'filters by selected asset types' do
        site_id = 'test-site-id'
        graphql_response = {
          data: {
            site: {
              assetResources: {
                total: 1,
                pagination: { next: nil },
                items: [
                  {
                    key: 'asset-1',
                    _id: 'asset-1',
                    url: 'https://lansweeper.com/asset/1',
                    assetBasicInfo: {
                      name: 'Computer-01',
                      type: 'Computer',
                      lastSeen: '2024-01-15T10:30:00Z',
                    },
                    assetCustom: {},
                    operatingSystem: {},
                    recognitionInfo: {},
                    users: [],
                    softwares: [],
                    processors: [],
                    memoryModules: [],
                  },
                ],
              },
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .with(body: hash_including(
                 query: /REGEXP.*path:\s*"assetBasicInfo\.type",\s*value:\s*"\^Monitor\$\|\^Computer\$"/,
               ))
               .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id, import_type: 'selected_types_only',
                                asset_types: %w[Monitor Computer])
        expect(output[:assets].length).to eq(1)
        expect(stub).to have_been_requested.once
      end

      it 'filters by selected sources' do
        site_id = 'test-site-id'
        source_ids = %w[inst-1 inst-2]
        graphql_response = {
          data: {
            site: {
              assetResources: {
                total: 1,
                pagination: { next: nil },
                items: [
                  {
                    key: 'asset-1',
                    _id: 'asset-1',
                    url: 'https://lansweeper.com/asset/1',
                    assetBasicInfo: {
                      name: 'Computer-01',
                      type: 'Computer',
                      lastSeen: '2024-01-15T10:30:00Z',
                    },
                    assetCustom: {},
                    operatingSystem: {},
                    recognitionInfo: {},
                    users: [],
                    softwares: [],
                    processors: [],
                    memoryModules: [],
                  },
                ],
              },
            },
          },
        }

        stub = stub_request(:post, generate_expected_url)
               .with do |request|
                 body = JSON.parse(request.body)
                 body['query'].include?('query getAssetResources')
               end
               .to_return(body: graphql_response.to_json)

        output = trigger_action(site_id: site_id,
                                source_ids: source_ids,
                                source_handling: 'selected_only')
        expect(output[:assets].length).to eq(1)
        expect(stub).to have_been_requested.once
      end

      describe 'iteration state handling' do
        it 'clears iteration_state_value when next cursor is absent' do
          graphql_response = {
            data: {
              site: {
                assetResources: {
                  total: 0,
                  pagination: { next: nil },
                  items: [],
                },
              },
            },
          }

          stub = stub_request(:post, generate_expected_url)
                 .to_return(body: graphql_response.to_json)

          expect(action(site_id: 'test-site-id')).to receive(:iteration_state_value=).with(nil)

          output = trigger_action
          expect(output[:has_next_page]).to eq(false)
          expect(stub).to have_been_requested.once
        end

        it 'stores iteration_state_value when next cursor is present' do
          next_cursor = 'cursor-123'
          graphql_response = {
            data: {
              site: {
                assetResources: {
                  total: 100,
                  pagination: { next: next_cursor },
                  items: [
                    {
                      key: 'asset-1',
                      _id: 'asset-1',
                      url: 'https://lansweeper.com/asset/1',
                      assetBasicInfo: {
                        name: 'Computer-01',
                        type: 'Computer',
                        lastSeen: '2024-01-15T10:30:00Z',
                      },
                      assetCustom: {},
                      operatingSystem: {},
                      recognitionInfo: {},
                      users: [],
                      softwares: [],
                      processors: [],
                      memoryModules: [],
                    },
                  ],
                },
              },
            },
          }

          stub = stub_request(:post, generate_expected_url)
                 .to_return(body: graphql_response.to_json)

          expect(action(site_id: 'test-site-id')).to receive(:iteration_state_value=)
            .with(hash_including(next_cursor: next_cursor))
            .and_call_original

          output = run_action({ site_id: 'test-site-id' })
          expect(output[:has_next_page]).to eq(true)
          expect(output[:assets].pluck(:key)).to contain_exactly('asset-1')
          expect(stub).to have_been_requested.once
        end

        it 'uses iteration_state_value for pagination' do
          old_cursor = 'cursor-456'
          graphql_response = {
            data: {
              site: {
                assetResources: {
                  pagination: { next: nil },
                  items: [
                    {
                      key: 'asset-2',
                      _id: 'asset-2',
                      url: 'https://lansweeper.com/asset/2',
                      assetBasicInfo: {
                        name: 'Computer-02',
                        type: 'Computer',
                        lastSeen: '2024-01-16T10:30:00Z',
                      },
                      assetCustom: {},
                      operatingSystem: {},
                      recognitionInfo: {},
                      users: [],
                      softwares: [],
                      processors: [],
                      memoryModules: [],
                    },
                  ],
                },
              },
            },
          }

          stub = stub_request(:post, generate_expected_url)
                 .with do |request|
                   body = JSON.parse(request.body)
                   body['query'].include?('query getAssetResources') &&
                     body['variables']['pagination']['page'] == 'NEXT' &&
                     body['variables']['pagination']['cursor'] == old_cursor
                 end
                 .to_return(body: graphql_response.to_json)

          action(site_id: 'test-site-id').send(:iteration_state_value=, {
            next_cursor: old_cursor,
            site_id: 'test-site-id',
            source_ids: nil,
            asset_types: nil,
            networked_assets_only: true,
            last_seen_after: (DateTime.now - 30),
            page_size: 100,
          })

          output = run_action({ site_id: 'test-site-id' })
          expect(output[:has_next_page]).to eq(false)
          expect(output[:assets].pluck(:key)).to contain_exactly('asset-2')
          expect(stub).to have_been_requested.once
        end
      end
    end

    describe 'error handling' do
      # NOTE: 429/503 retry logic cannot be tested in SDK due to method restrictions
      # (reschedule_job!, Time methods, etc. are not allowed in SDK context)
      # Retry logic is tested in the platform connector tests

      it 'handles GraphQL errors' do
        graphql_response = {
          errors: [
            { message: 'Invalid site ID' },
          ],
        }

        stub = stub_request(:post, generate_expected_url)
               .to_return(body: graphql_response.to_json)

        expect { trigger_action }.to raise_error(IPaaS::Job::FailJob) do |error|
          message = error.message
          expect(message).to start_with('Unable to query assets: GraphQL errors: ')
          expect(message).to include('Invalid site ID')
        end
        expect(stub).to have_been_requested.once
      end

      it 'handles missing site data' do
        graphql_response = {
          data: {},
        }

        stub = stub_request(:post, generate_expected_url)
               .to_return(body: graphql_response.to_json)

        expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, 'No site data in Lansweeper response')
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

      it 'handles invalid JSON response' do
        stub = stub_request(:post, generate_expected_url)
               .to_return(body: 'Invalid JSON')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           "Lansweeper GraphQL API response was not JSON: 'Invalid JSON'")
        expect(stub).to have_been_requested.once
      end
    end
  end
end
