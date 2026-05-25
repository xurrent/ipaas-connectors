require 'spec_helper'

describe 'Fetch Software from Xurrent for CMDB Action', :action do
  let(:connector_id) { '01962529-c8eb-7a89-a682-73d6f09541d6' }
  let(:action_template_id) { '01973456-abcd-7890-b1c2-d3e4f5a6b7c9' }

  describe 'input_schema' do
    it 'should define the software_names field' do
      field = action.input_schema.field(:software_names)
      expect(field.label).to eq('Software Names')
      expect(field.type).to eq(:string)
      expect(field.array).to be_truthy
      expect(field.required).to be_truthy
    end

    it 'should define the statuses field with defaults' do
      field = action.input_schema.field(:statuses)
      expect(field.label).to eq('CI Statuses')
      expect(field.type).to eq(:string)
      expect(field.array).to be_truthy
      expect(field.required).to be_falsey
      expect(field.visibility).to eq('optional')
      expect(field.default).to eq(%w[reserved being_built installed being_tested standby_for_continuity in_production])
    end

    it 'should define the filter_fields field with defaults' do
      field = action.input_schema.field(:filter_fields)
      expect(field.label).to eq('Filter fields')
      expect(field.type).to eq(:string)
      expect(field.array).to be_truthy
      expect(field.required).to be_falsey
      expect(field.visibility).to eq('optional')
      expect(field.default).to eq(%w[name alternateName])
      expect(field.hint).to eq('Fields to filter on (e.g., ["name", "alternateName"])')
    end

    it 'should define the node_fields field' do
      field = action.input_schema.field(:node_fields)
      expect(field.label).to eq('Node fields')
      expect(field.type).to eq(:string)
      expect(field.required).to be_falsey
      expect(field.visibility).to eq('optional')
      expect(field.hint).to eq('Additional GraphQL fields to retrieve (e.g., "version vendor description")')
    end

    it 'should define the page_size field' do
      field = action.input_schema.field(:page_size)
      expect(field.label).to eq('Page size')
      expect(field.type).to eq(:integer)
      expect(field.required).to be_falsey
      expect(field.visibility).to eq('optional')
      expect(field.default).to eq(100)
      expect(field.min).to eq(1)
      expect(field.max).to eq(100)
    end
  end

  describe 'output_schema' do
    let(:output_schema) { action.output_schema.find { |schema| schema.reference == 'page' } }

    it 'should have page output schema' do
      expect(action.output_schema.map(&:reference)).to include('page')
    end

    it 'should define the records field' do
      field = output_schema.field(:records)
      expect(field.label).to eq('Software records')
      expect(field.type).to eq(:hash)
      expect(field.array).to be_truthy
    end

    it 'should define the name_to_record_map field' do
      field = output_schema.field(:name_to_record_map)
      expect(field.label).to eq('Name to record map')
      expect(field.type).to eq(:hash)
      expect(field.hint).to eq('Hash mapping software names (including alternate names) to their corresponding records')
    end

    it 'should define the has_next_page field' do
      field = output_schema.field(:has_next_page)
      expect(field.label).to eq('Has next page')
      expect(field.type).to eq(:boolean)
    end

    it 'should define the stats field' do
      stats_field = output_schema.field(:stats)
      expect(stats_field.label).to eq('Statistics')
      expect(stats_field.type).to eq(:nested)
      expect(stats_field.visibility).to eq('optional')

      stats_field.field(:total_found).tap do |field|
        expect(field.label).to eq('Total found')
        expect(field.type).to eq(:integer)
      end

      stats_field.field(:total_searched).tap do |field|
        expect(field.label).to eq('Total searched')
        expect(field.type).to eq(:integer)
      end
    end

    it 'should define the ratelimit field' do
      ratelimit_field = output_schema.field(:ratelimit)
      expect(ratelimit_field.label).to eq('Rate limit')
      expect(ratelimit_field.type).to eq(:nested)
      expect(ratelimit_field.visibility).to eq('optional')

      ratelimit_field.field(:limit).tap do |field|
        expect(field.label).to eq('Limit')
        expect(field.type).to eq(:integer)
      end

      ratelimit_field.field(:remaining).tap do |field|
        expect(field.label).to eq('Remaining')
        expect(field.type).to eq(:integer)
      end

      ratelimit_field.field(:reset).tap do |field|
        expect(field.label).to eq('Reset')
        expect(field.type).to eq(:integer)
      end
    end

    it 'should define the costlimit field' do
      costlimit_field = output_schema.field(:costlimit)
      expect(costlimit_field.label).to eq('Cost limit')
      expect(costlimit_field.type).to eq(:nested)
      expect(costlimit_field.visibility).to eq('optional')

      costlimit_field.field(:limit).tap do |field|
        expect(field.label).to eq('Limit')
        expect(field.type).to eq(:integer)
      end

      costlimit_field.field(:cost).tap do |field|
        expect(field.label).to eq('Cost')
        expect(field.type).to eq(:integer)
      end

      costlimit_field.field(:remaining).tap do |field|
        expect(field.label).to eq('Remaining')
        expect(field.type).to eq(:integer)
      end

      costlimit_field.field(:reset).tap do |field|
        expect(field.label).to eq('Reset')
        expect(field.type).to eq(:integer)
      end
    end

    it 'should define the request_id field' do
      field = output_schema.field(:request_id)
      expect(field.label).to eq('Request ID')
      expect(field.type).to eq(:string)
      expect(field.visibility).to eq('optional')
    end
  end

  describe 'iteration_state_schema' do
    it 'should define the batch_index field' do
      field = action.iteration_state_schema.field(:batch_index)
      expect(field.label).to eq('Batch index')
      expect(field.type).to eq(:integer)
      expect(field.required).to be_truthy
    end
  end

  describe 'run' do
    let(:endpoint) do
      outbound_connection_config[:environment][:graphql_endpoint]
    end

    let(:outbound_connection_config) do
      {
        credentials: {
          account_id: 'wdc',
          client_id: 'abc',
          client_secret: make_secret_string('def'),
        },
        environment: {
          stage: 'Demo',
          graphql_endpoint: 'https://graphql.example.com/graphql',
        },
      }
    end

    let(:content_type_json) { { 'content-type' => 'application/json' } }
    let(:software_names) { ['Windows 10', 'Linux Ubuntu', 'macOS'] }
    let(:statuses) { %w[in_production installed] }

    let(:response_headers) do
      {
        'x-request-id' => 'req-123',
        'x-ratelimit-limit' => '1000',
        'x-ratelimit-remaining' => '999',
        'x-ratelimit-reset' => '1234567890',
        'x-costlimit-limit' => '10000',
        'x-costlimit-cost' => '10',
        'x-costlimit-remaining' => '9990',
        'x-costlimit-reset' => '1234567890',
      }
    end

    let(:windows_node) do
      { 'id' => 'ci-1', 'name' => 'Windows 10', 'alternateNames' => ['Win10', 'Windows 10 Pro'] }
    end

    let(:linux_node) do
      { 'id' => 'ci-2', 'name' => 'Linux Ubuntu', 'alternateNames' => ['Ubuntu'] }
    end

    let(:macos_node) do
      { 'id' => 'ci-3', 'name' => 'macOS Monterey', 'alternateNames' => ['macOS', 'Mac OS'] }
    end

    let(:default_response_data) do
      {
        'name' => { 'nodes' => [windows_node, linux_node] },
        'alternateName' => { 'nodes' => [macos_node] },
      }
    end

    before(:each) do
      stub_xurrent_oauth2_token(outbound_connection_config)
      stub_graphql_request
    end

    def stub_graphql_request(response_data: default_response_data)
      stub_request(:post, endpoint)
        .with(headers: content_type_json)
        .to_return(status: 200, body: { data: response_data }.to_json, headers: response_headers)
    end

    context 'with default parameters' do
      it 'should successfully fetch software records' do
        output = run_action({ software_names: software_names })

        expect(output[:records]).to be_an(Array)
        expect(output[:records].length).to eq(3)

        record_ids = output[:records].map { |r| r['id'] }
        expect(record_ids).to contain_exactly('ci-1', 'ci-2', 'ci-3')

        windows_record = output[:records].find { |r| r['id'] == 'ci-1' }
        expect(windows_record['name']).to eq('Windows 10')
        expect(windows_record['alternateNames']).to contain_exactly('Win10', 'Windows 10 Pro')

        linux_record = output[:records].find { |r| r['id'] == 'ci-2' }
        expect(linux_record['name']).to eq('Linux Ubuntu')
        expect(linux_record['alternateNames']).to contain_exactly('Ubuntu')

        macos_record = output[:records].find { |r| r['id'] == 'ci-3' }
        expect(macos_record['name']).to eq('macOS Monterey')
        expect(macos_record['alternateNames']).to contain_exactly('macOS', 'Mac OS')

        expect(output[:name_to_record_map]).to be_a(Hash)
        expect(output[:has_next_page]).to be_falsey
      end

      it 'should create name_to_record_map with all names' do
        output = run_action({ software_names: software_names })

        expect(output[:name_to_record_map]['Windows 10']).to be_present
        expect(output[:name_to_record_map]['Windows 10']['id']).to eq('ci-1')
        expect(output[:name_to_record_map]['Windows 10']['name']).to eq('Windows 10')

        expect(output[:name_to_record_map]['Linux Ubuntu']).to be_present
        expect(output[:name_to_record_map]['Linux Ubuntu']['id']).to eq('ci-2')
        expect(output[:name_to_record_map]['Linux Ubuntu']['name']).to eq('Linux Ubuntu')

        expect(output[:name_to_record_map]['macOS']).to be_present
        expect(output[:name_to_record_map]['macOS']['id']).to eq('ci-3')
        expect(output[:name_to_record_map]['macOS']['name']).to eq('macOS Monterey')

        expect(output[:name_to_record_map].keys).to contain_exactly('Windows 10', 'Linux Ubuntu', 'macOS')
      end

      it 'should only include requested names in name_to_record_map' do
        output = run_action({ software_names: ['Windows 10'] })

        expect(output[:name_to_record_map].keys).to contain_exactly('Windows 10')
        expect(output[:name_to_record_map]).not_to have_key('Linux Ubuntu')
        expect(output[:name_to_record_map]).not_to have_key('Win10')
        expect(output[:name_to_record_map]).not_to have_key('Windows 10 Pro')
      end
    end

    context 'with custom filter_fields' do
      it 'should use custom filter fields in query' do
        stub = stub_request(:post, endpoint)
               .with(headers: content_type_json) do |req|
          body = JSON.parse(req.body)
          body['query'].include?('name: configurationItems') &&
            body['query'].include?('description: configurationItems') &&
            !body['query'].include?('alternateName: configurationItems')
        end
          .to_return(
            status: 200,
            body: { data: { 'name' => { 'nodes' => [] }, 'description' => { 'nodes' => [] } } }.to_json,
            headers: response_headers
          )

        run_action({
          software_names: ['Windows 10'],
          filter_fields: %w[name description],
        })

        expect(stub).to have_been_requested.once
      end
    end

    context 'with custom node_fields' do
      it 'should include additional fields in query' do
        stub = stub_request(:post, endpoint)
               .with(headers: content_type_json) do |req|
          body = JSON.parse(req.body)
          body['query'].include?('version') && body['query'].include?('vendor')
        end
          .to_return(
            status: 200,
            body: { data: { 'name' => { 'nodes' => [] }, 'alternateName' => { 'nodes' => [] } } }.to_json,
            headers: response_headers
          )

        run_action({
          software_names: ['Windows 10'],
          node_fields: 'version vendor',
        })

        expect(stub).to have_been_requested.once
      end
    end

    context 'with pagination' do
      let(:large_software_list) { (1..150).map { |i| "Software #{i}" } }

      it 'should handle pagination with page_size' do
        action_instance = action({ software_names: large_software_list, page_size: 50 })
        results = action_instance.run
        output = results.first&.[](:output)

        expect(output[:has_next_page]).to be_truthy
        expect(output[:stats][:total_searched]).to eq(50)
        expect(action_instance.send(:iteration_state_value)).to eq({ 'batch_index' => 1 })
      end

      it 'should process second batch' do
        action_instance = action({ software_names: large_software_list, page_size: 50 })
        results = action_instance.run
        results.first&.[](:output)

        expect(action_instance.send(:iteration_state_value)).to eq({ 'batch_index' => 1 })

        action_instance2 = action({ software_names: large_software_list, page_size: 50 })
        action_instance2.send(:iteration_state_value=, { batch_index: 1 })
        results2 = action_instance2.run
        output2 = results2.first&.[](:output)

        expect(output2[:stats][:total_searched]).to eq(50)
        expect(output2[:has_next_page]).to be_truthy
        expect(action_instance2.send(:iteration_state_value)).to eq({ 'batch_index' => 2 })
      end

      it 'should indicate no next page on last batch' do
        action_instance1 = action({ software_names: large_software_list, page_size: 50 })
        results1 = action_instance1.run
        output1 = results1.first&.[](:output)

        expect(output1[:has_next_page]).to be_truthy
        expect(action_instance1.send(:iteration_state_value)['batch_index']).to eq(1)

        action_instance2 = action({ software_names: large_software_list, page_size: 50 })
        action_instance2.send(:iteration_state_value=, { batch_index: 1 })
        results2 = action_instance2.run
        output2 = results2.first&.[](:output)

        expect(output2[:has_next_page]).to be_truthy
        expect(action_instance2.send(:iteration_state_value)['batch_index']).to eq(2)

        action_instance3 = action({ software_names: large_software_list, page_size: 50 })
        action_instance3.send(:iteration_state_value=, { batch_index: 2 })
        results3 = action_instance3.run
        output3 = results3.first&.[](:output)

        expect(output3[:has_next_page]).to be_falsey
        expect(output3[:stats][:total_searched]).to eq(50)
        expect(action_instance3.send(:iteration_state_value)).to be_nil
      end
    end

    context 'with custom statuses' do
      it 'should pass custom statuses to GraphQL query' do
        stub = stub_request(:post, endpoint)
               .with(headers: content_type_json) do |req|
          body = JSON.parse(req.body)
          body['variables']['statuses'] == %w[in_production standby_for_continuity]
        end
          .to_return(
            status: 200,
            body: { data: { 'name' => { 'nodes' => [] }, 'alternateName' => { 'nodes' => [] } } }.to_json,
            headers: response_headers
          )

        run_action({
          software_names: ['Windows 10'],
          statuses: %w[in_production standby_for_continuity],
        })

        expect(stub).to have_been_requested.once
      end
    end

    context 'with empty results' do
      it 'should handle no results gracefully' do
        stub_graphql_request(response_data: {
          'name' => { 'nodes' => [] },
          'alternateName' => { 'nodes' => [] },
        })

        output = run_action({ software_names: ['NonExistent Software'] })

        expect(output[:records]).to eq([])
        expect(output[:name_to_record_map]).to eq({})
        expect(output[:stats][:total_found]).to eq(0)
      end
    end

    context 'with rate limit info' do
      it 'should include rate limit information in output' do
        output = run_action({ software_names: software_names })

        expect(output[:ratelimit]).to be_present
        expect(output[:ratelimit][:limit]).to eq('1000')
        expect(output[:ratelimit][:remaining]).to eq('999')
      end

      it 'should include cost limit information in output' do
        output = run_action({ software_names: software_names })

        expect(output[:costlimit]).to be_present
        expect(output[:costlimit][:limit]).to eq('10000')
        expect(output[:costlimit][:remaining]).to eq('9990')
      end

      it 'should include request_id in output' do
        output = run_action({ software_names: software_names })

        expect(output[:request_id]).to eq('req-123')
      end
    end

    context 'with statistics' do
      it 'should provide accurate statistics' do
        output = run_action({ software_names: software_names })

        expect(output[:stats][:total_found]).to eq(3)
        expect(output[:stats][:total_searched]).to eq(3)
      end
    end

    context 'with edge cases' do
      it 'should handle empty alternateNames array' do
        stub_graphql_request(response_data: {
          'name' => {
            'nodes' => [
              { 'id' => 'ci-1', 'name' => 'Windows 10', 'alternateNames' => [] },
            ],
          },
          'alternateName' => { 'nodes' => [] },
        })

        output = run_action({ software_names: ['Windows 10'] })

        expect(output[:records].length).to eq(1)
        expect(output[:name_to_record_map]['Windows 10']).to be_present
      end

      it 'should handle empty strings in alternateNames' do
        stub_graphql_request(response_data: {
          'name' => {
            'nodes' => [
              { 'id' => 'ci-1', 'name' => 'Windows 10', 'alternateNames' => ['', '  ', 'Win10'] },
            ],
          },
          'alternateName' => { 'nodes' => [] },
        })

        output = run_action({ software_names: ['Windows 10'] })

        expect(output[:records].length).to eq(1)
        expect(output[:name_to_record_map].keys).to contain_exactly('Windows 10')
        expect(output[:name_to_record_map]).not_to have_key('')
        expect(output[:name_to_record_map]).not_to have_key('  ')
      end

      it 'should handle node found only by alternateName' do
        stub_graphql_request(response_data: {
          'name' => { 'nodes' => [] },
          'alternateName' => {
            'nodes' => [
              { 'id' => 'ci-1', 'name' => 'Microsoft Windows 10', 'alternateNames' => ['Windows 10', 'Win10'] },
            ],
          },
        })

        output = run_action({ software_names: ['Windows 10'] })

        expect(output[:records].length).to eq(1)
        expect(output[:records].first['id']).to eq('ci-1')
        expect(output[:records].first['name']).to eq('Microsoft Windows 10')
        expect(output[:records].first['alternateNames']).to contain_exactly('Windows 10', 'Win10')

        expect(output[:name_to_record_map]['Windows 10']).to be_present
        expect(output[:name_to_record_map]['Windows 10']['id']).to eq('ci-1')
        expect(output[:name_to_record_map]['Windows 10']['name']).to eq('Microsoft Windows 10')

        expect(output[:name_to_record_map]).not_to have_key('Win10')
      end

      it 'should handle node found in both name and alternateName filters' do
        stub_graphql_request(response_data: {
          'name' => {
            'nodes' => [
              { 'id' => 'ci-1', 'name' => 'Windows 10', 'alternateNames' => ['Win10'] },
            ],
          },
          'alternateName' => {
            'nodes' => [
              { 'id' => 'ci-1', 'name' => 'Win 10', 'alternateNames' => ['Windows 10'] },
            ],
          },
        })

        output = run_action({ software_names: ['Windows 10'] })

        expect(output[:records].length).to eq(1)
        expect(output[:name_to_record_map]['Windows 10']).to be_present
        expect(output[:name_to_record_map]['Windows 10']['id']).to eq('ci-1')
      end

      it 'should deduplicate when same CI returned from multiple filters with identical data' do
        stub_graphql_request(response_data: {
          'name' => {
            'nodes' => [
              { 'id' => 'ci-1', 'name' => 'Windows 10', 'alternateNames' => ['Win10', 'Windows 10 Pro'] },
              { 'id' => 'ci-2', 'name' => 'Linux Ubuntu', 'alternateNames' => ['Ubuntu'] },
            ],
          },
          'alternateName' => {
            'nodes' => [
              { 'id' => 'ci-1', 'name' => 'Windows 10', 'alternateNames' => ['Win10', 'Windows 10 Pro'] },
            ],
          },
        })

        output = run_action({ software_names: ['Windows 10', 'Linux Ubuntu'] })

        expect(output[:records].length).to eq(2)
        expect(output[:records].map { |r| r['id'] }).to contain_exactly('ci-1', 'ci-2')

        ci1_record = output[:records].find { |r| r['id'] == 'ci-1' }
        expect(ci1_record['name']).to eq('Windows 10')
        expect(ci1_record['alternateNames']).to contain_exactly('Win10', 'Windows 10 Pro')
      end

      it 'should deduplicate across multiple filter fields with 3+ duplicates' do
        stub_graphql_request(response_data: {
          'name' => {
            'nodes' => [
              { 'id' => 'ci-1', 'name' => 'Windows 10', 'alternateNames' => ['Win10'] },
              { 'id' => 'ci-2', 'name' => 'Linux', 'alternateNames' => [] },
            ],
          },
          'alternateName' => {
            'nodes' => [
              { 'id' => 'ci-1', 'name' => 'Windows 10', 'alternateNames' => ['Win10'] },
              { 'id' => 'ci-3', 'name' => 'macOS', 'alternateNames' => ['Mac OS'] },
            ],
          },
          'description' => {
            'nodes' => [
              { 'id' => 'ci-1', 'name' => 'Windows 10', 'alternateNames' => ['Win10'] },
              { 'id' => 'ci-2', 'name' => 'Linux', 'alternateNames' => [] },
            ],
          },
        })

        output = run_action({
          software_names: ['Windows 10', 'Linux', 'macOS'],
          filter_fields: %w[name alternateName description],
        })

        expect(output[:records].length).to eq(3)
        expect(output[:records].map { |r| r['id'] }).to contain_exactly('ci-1', 'ci-2', 'ci-3')
      end

      it 'should deduplicate when searching for alternate name that matches multiple CIs' do
        stub_graphql_request(response_data: {
          'name' => {
            'nodes' => [
              { 'id' => 'ci-1', 'name' => 'Win10', 'alternateNames' => ['Windows 10'] },
            ],
          },
          'alternateName' => {
            'nodes' => [
              { 'id' => 'ci-2', 'name' => 'Microsoft Windows 10', 'alternateNames' => ['Win10', 'Windows 10'] },
              { 'id' => 'ci-3', 'name' => 'Windows 10 Enterprise', 'alternateNames' => ['Win10'] },
            ],
          },
        })

        output = run_action({ software_names: ['Win10'] })

        expect(output[:records].length).to eq(3)
        expect(output[:records].map { |r| r['id'] }).to contain_exactly('ci-1', 'ci-2', 'ci-3')

        expect(output[:name_to_record_map].keys).to contain_exactly('Win10')
        expect(output[:name_to_record_map]['Win10']).to be_present
      end
    end
  end
end
