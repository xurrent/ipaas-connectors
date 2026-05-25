require 'spec_helper'

describe 'Fetch People from Xurrent Action', :action do
  let(:connector_id) { '01962529-c8eb-7a89-a682-73d6f09541d6' }
  let(:action_template_id) { '01973456-abcd-7890-b1c2-d3e4f5a6b7c8' }

  describe 'input_schema' do
    it 'should define the identifiers field' do
      field = action.input_schema.field(:identifiers)
      expect(field.label).to eq('Identifiers')
      expect(field.type).to eq(:secret_string)
      expect(field.array).to be_truthy
      expect(field.required).to be_truthy
      expect(field.visibility).to eq('visible')
    end

    it 'should define the identifier_fields field' do
      field = action.input_schema.field(:identifier_fields)
      expect(field.label).to eq('Identifier fields')
      expect(field.type).to eq(:string)
      expect(field.array).to be_truthy
      expect(field.required).to be_falsey
      expect(field.visibility).to eq('optional')
      expect(field.default).to eq(%w[authenticationID primaryEmail sourceID employeeID supportID])
    end

    it 'should define the node_fields field' do
      field = action.input_schema.field(:node_fields)
      expect(field.label).to eq('Node fields')
      expect(field.type).to eq(:string)
      expect(field.required).to be_falsey
      expect(field.visibility).to eq('optional')
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
    it 'should have page output schema' do
      expect(action.output_schema.map(&:reference)).to contain_exactly('page')
    end

    describe 'page schema' do
      let(:output_schema) { action.output_schema.first }

      it 'should define the identifier_map field' do
        output_schema.field(:identifier_map).tap do |field|
          expect(field.label).to eq('Identifier map')
          expect(field.type).to eq(:hash)
        end
      end

      it 'should define the records field' do
        output_schema.field(:records).tap do |field|
          expect(field.label).to eq('Person records')
          expect(field.type).to eq(:hash)
          expect(field.array).to be_truthy
        end
      end

      it 'should define the has_next_page field' do
        output_schema.field(:has_next_page).tap do |field|
          expect(field.label).to eq('Has next page')
          expect(field.type).to eq(:boolean)
        end
      end

      it 'should define the stats field' do
        stats_field = output_schema.field(:stats).tap do |field|
          expect(field.label).to eq('Statistics')
          expect(field.type).to eq(:nested)
          expect(field.visibility).to eq('optional')
        end

        stats_field.field(:total_found).tap do |field|
          expect(field.label).to eq('Total found')
          expect(field.type).to eq(:integer)
        end

        stats_field.field(:total_searched).tap do |field|
          expect(field.label).to eq('Total searched')
          expect(field.type).to eq(:integer)
        end

        stats_field.field(:batches_processed).tap do |field|
          expect(field.label).to eq('Batches processed')
          expect(field.type).to eq(:integer)
        end
      end

      it 'should define the ratelimit field' do
        ratelimit_field = output_schema.field(:ratelimit).tap do |field|
          expect(field.label).to eq('Rate limit')
          expect(field.type).to eq(:nested)
          expect(field.visibility).to eq('optional')
        end

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
        costlimit_field = output_schema.field(:costlimit).tap do |field|
          expect(field.label).to eq('Cost limit')
          expect(field.type).to eq(:nested)
          expect(field.visibility).to eq('optional')
        end

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
        output_schema.field(:request_id).tap do |field|
          expect(field.label).to eq('Request ID')
          expect(field.type).to eq(:string)
          expect(field.visibility).to eq('optional')
        end
      end
    end
  end

  describe 'iteration_state_schema' do
    it 'should define batch_index field' do
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

    before(:each) do
      stub_xurrent_oauth2_token(outbound_connection_config)
    end

    def valid_people_query_request?(body, values)
      return false unless body['variables'] == { 'values' => values }

      query = body['query']
      required_fields = %w[authenticationID primaryEmail sourceID employeeID supportID]

      query.include?('query ($values: [String!]!)') &&
        required_fields.all? { |field| query.include?("#{field}: people") } &&
        query.include?('externalIdentifier:') &&
        query.include?('nodeID: id')
    end

    def stub_people_query(values:, response_data:, headers: {})
      stub_request(:post, endpoint)
        .with { |request| valid_people_query_request?(JSON.parse(request.body), values) }
        .to_return(body: { data: response_data }.to_json, headers: headers)
    end

    describe 'single batch (no iteration)' do
      it 'fetches people by identifier and returns hash with person ID' do
        plain_identifiers = ['john@example.com', 'jane@example.com']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        response_data = {
          authenticationID: { nodes: [] },
          primaryEmail: {
            nodes: [
              { externalIdentifier: 'john@example.com', nodeID: 'person-123' },
              { externalIdentifier: 'jane@example.com', nodeID: 'person-456' },
            ],
          },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }

        stub = stub_people_query(
          values: plain_identifiers,
          response_data: response_data
        )

        output = run_action({ identifiers: identifiers })

        expect(output[:identifier_map]).to be_a(Hash)
        expect(output[:identifier_map].keys.length).to eq(2)

        output[:identifier_map].each_key do |key|
          expect(key).to be_a(IPaaS::Encryption::SecretString)
        end

        person_ids = output[:identifier_map].values.map { |person| person['id'] }
        expect(person_ids).to contain_exactly('person-123', 'person-456')

        john_key = make_secret_string('john@example.com')
        john_person = output[:identifier_map][john_key]
        expect(john_person['id']).to eq('person-123')

        jane_key = make_secret_string('jane@example.com')
        jane_person = output[:identifier_map][jane_key]
        expect(jane_person['id']).to eq('person-456')

        expect(output[:records]).to be_a(Array)
        expect(output[:records].length).to eq(2)
        output[:records].each do |record|
          expect(record['id']).to be_present
        end

        expect(output[:has_next_page]).to be_falsey

        expect(output[:stats][:total_found]).to eq(2)
        expect(output[:stats][:total_searched]).to eq(2)
        expect(output[:stats][:batches_processed]).to eq(1)

        expect(stub).to have_been_requested.once
      end

      it 'searches across multiple identifier fields' do
        plain_identifiers = %w[user123 employee456]
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        response_data = {
          authenticationID: {
            nodes: [
              { externalIdentifier: 'user123', nodeID: 'person-789' },
            ],
          },
          primaryEmail: { nodes: [] },
          sourceID: { nodes: [] },
          employeeID: {
            nodes: [
              { externalIdentifier: 'employee456', nodeID: 'person-999' },
            ],
          },
          supportID: { nodes: [] },
        }

        stub = stub_people_query(
          values: plain_identifiers,
          response_data: response_data
        )

        output = run_action({ identifiers: identifiers })

        expect(output[:identifier_map].keys.length).to eq(2)

        output[:identifier_map].each_key do |key|
          expect(key).to be_a(IPaaS::Encryption::SecretString)
        end

        person_ids = output[:identifier_map].values.map { |person| person['id'] }
        expect(person_ids).to contain_exactly('person-789', 'person-999')

        user123_key = make_secret_string('user123')
        user123_person = output[:identifier_map][user123_key]
        expect(user123_person['id']).to eq('person-789')

        employee456_key = make_secret_string('employee456')
        employee456_person = output[:identifier_map][employee456_key]
        expect(employee456_person['id']).to eq('person-999')

        expect(output[:records]).to be_a(Array)
        expect(output[:records].length).to eq(2)
        output[:records].each do |record|
          expect(record['id']).to be_present
        end

        expect(stub).to have_been_requested.once
      end

      it 'handles case-insensitive matching' do
        original_identifier = 'John@Example.COM'
        plain_identifiers = [original_identifier]
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        response_data = {
          authenticationID: { nodes: [] },
          primaryEmail: {
            nodes: [
              { externalIdentifier: 'john@example.com', nodeID: 'person-999' },
            ],
          },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }

        stub_people_query(
          values: plain_identifiers,
          response_data: response_data
        )

        output = run_action({ identifiers: identifiers })

        expect(output[:identifier_map].keys.length).to eq(1)

        key = output[:identifier_map].keys.first
        expect(key).to be_a(IPaaS::Encryption::SecretString)

        expect(plain_identifiers).to include(original_identifier)
        expect(original_identifier).to eq('John@Example.COM')

        person_key = make_secret_string('john@example.com')
        person = output[:identifier_map][person_key]
        expect(person['id']).to eq('person-999')
      end

      it 'handles empty results' do
        plain_identifiers = ['notfound@example.com']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        response_data = {
          authenticationID: { nodes: [] },
          primaryEmail: { nodes: [] },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }

        stub = stub_people_query(
          values: plain_identifiers,
          response_data: response_data
        )

        output = run_action({ identifiers: identifiers })

        expect(output[:identifier_map]).to eq({})
        expect(output[:records]).to eq([])
        expect(output[:has_next_page]).to be_falsey
        expect(output[:stats][:total_found]).to eq(0)
        expect(output[:stats][:total_searched]).to eq(1)
        expect(output[:stats][:batches_processed]).to eq(1)

        expect(stub).to have_been_requested.once
      end

      it 'deduplicates when same person found in multiple fields' do
        plain_identifiers = ['user@example.com']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        response_data = {
          authenticationID: {
            nodes: [
              { externalIdentifier: 'user@example.com', nodeID: 'person-789' },
            ],
          },
          primaryEmail: {
            nodes: [
              { externalIdentifier: 'user@example.com', nodeID: 'person-789' },
            ],
          },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }

        stub = stub_people_query(
          values: plain_identifiers,
          response_data: response_data
        )

        output = run_action({ identifiers: identifiers })

        expect(output[:identifier_map].keys.length).to eq(1)

        key = output[:identifier_map].keys.first
        expect(key).to be_a(IPaaS::Encryption::SecretString)

        person = output[:identifier_map].values.first
        expect(person['id']).to eq('person-789')

        expect(output[:records]).to be_a(Array)
        expect(output[:records].length).to eq(1)
        expect(output[:records].first['id']).to eq('person-789')

        expect(stub).to have_been_requested.once
      end

      it 'deduplicates records when multiple identifiers match the same person' do
        plain_identifiers = ['user@example.com', 'user123']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        response_data = {
          authenticationID: {
            nodes: [
              { externalIdentifier: 'user123', nodeID: 'person-789' },
            ],
          },
          primaryEmail: {
            nodes: [
              { externalIdentifier: 'user@example.com', nodeID: 'person-789' },
            ],
          },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }

        stub_people_query(
          values: plain_identifiers,
          response_data: response_data
        )

        output = run_action({ identifiers: identifiers })

        expect(output[:identifier_map].keys.length).to eq(2)

        output[:identifier_map].each_key do |key|
          expect(key).to be_a(IPaaS::Encryption::SecretString)
        end

        expect(output[:identifier_map].values.all? { |p| p['id'] == 'person-789' }).to be_truthy

        user_email_key = make_secret_string('user@example.com')
        user_email_person = output[:identifier_map][user_email_key]
        expect(user_email_person['id']).to eq('person-789')

        user123_key = make_secret_string('user123')
        user123_person = output[:identifier_map][user123_key]
        expect(user123_person['id']).to eq('person-789')

        expect(output[:records]).to be_a(Array)
        expect(output[:records].length).to eq(1)
        expect(output[:records].first['id']).to eq('person-789')

        expect(output[:stats][:total_found]).to eq(1)
      end

      it 'works without node_fields (returns id only)' do
        plain_identifiers = ['john@example.com']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        response_data = {
          authenticationID: { nodes: [] },
          primaryEmail: {
            nodes: [
              { externalIdentifier: 'john@example.com', nodeID: 'person-123' },
            ],
          },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }

        stub_people_query(
          values: plain_identifiers,
          response_data: response_data
        )

        output = run_action({ identifiers: identifiers })

        expect(output[:identifier_map].keys.length).to eq(1)

        key = output[:identifier_map].keys.first
        expect(key).to be_a(IPaaS::Encryption::SecretString)

        john_key = make_secret_string('john@example.com')
        john = output[:identifier_map][john_key]
        expect(john['id']).to eq('person-123')

        record = output[:records].first
        expect(record['id']).to eq('person-123')
      end

      it 'includes additional fields when node_fields is provided' do
        plain_identifiers = ['john@example.com']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        response_data = {
          authenticationID: { nodes: [] },
          primaryEmail: {
            nodes: [
              { externalIdentifier: 'john@example.com', nodeID: 'person-123', name: 'John Doe',
                primaryEmail: 'john@example.com', jobTitle: 'Engineer', },
            ],
          },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }

        stub_people_query(
          values: plain_identifiers,
          response_data: response_data
        )

        output = run_action({ identifiers: identifiers, node_fields: 'name primaryEmail jobTitle' })

        expect(output[:identifier_map].keys.length).to eq(1)

        key = output[:identifier_map].keys.first
        expect(key).to be_a(IPaaS::Encryption::SecretString)

        john_key = make_secret_string('john@example.com')
        john = output[:identifier_map][john_key]
        expect(john['id']).to eq('person-123')
        expect(john['name']).to eq('John Doe')
        expect(john['primaryEmail']).to eq('john@example.com')
        expect(john['jobTitle']).to eq('Engineer')

        expect(output[:records]).to be_a(Array)
        expect(output[:records].length).to eq(1)

        record = output[:records].first
        expect(record['id']).to eq('person-123')
        expect(record['name']).to eq('John Doe')
        expect(record['primaryEmail']).to eq('john@example.com')
        expect(record['jobTitle']).to eq('Engineer')
      end

      it 'uses custom identifier_fields when provided' do
        plain_identifiers = ['emp123']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        stub = stub_request(:post, endpoint)
               .with(body: ->(body_str) {
                 body = JSON.parse(body_str)
                 body['variables'] == { 'values' => plain_identifiers } &&
                   body['query'].include?('employeeID: people') &&
                   !body['query'].include?('authenticationID: people') &&
                   !body['query'].include?('primaryEmail: people')
               })
               .to_return(body: {
                 data: {
                   employeeID: {
                     nodes: [
                       { externalIdentifier: 'emp123', nodeID: 'person-456' },
                     ],
                   },
                 },
               }.to_json)

        output = run_action({ identifiers: identifiers, identifier_fields: ['employeeID'] })

        expect(output[:identifier_map].keys.length).to eq(1)

        key = output[:identifier_map].keys.first
        expect(key).to be_a(IPaaS::Encryption::SecretString)

        emp_key = make_secret_string('emp123')
        person = output[:identifier_map][emp_key]
        expect(person['id']).to eq('person-456')

        expect(output[:records].length).to eq(1)
        expect(output[:records].first['id']).to eq('person-456')
        expect(stub).to have_been_requested.once
      end
    end

    describe 'iteration (multiple batches)' do
      it 'processes first batch and sets has_next_page to true' do
        plain_identifiers = (1..150).map { |i| "user#{i}@example.com" }
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        first_batch_values = (1..100).map { |i| "user#{i}@example.com" }
        first_response_data = {
          authenticationID: { nodes: [] },
          primaryEmail: {
            nodes: (1..100).map do |i|
              { externalIdentifier: "user#{i}@example.com", nodeID: "person-#{i}" }
            end,
          },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }
        stub1 = stub_people_query(values: first_batch_values, response_data: first_response_data)

        action_instance = action({ identifiers: identifiers })
        results = action_instance.run
        output = results.first&.[](:output)

        expect(output[:identifier_map].keys.length).to eq(100)
        expect(output[:records]).to be_a(Array)
        expect(output[:records].length).to eq(100)
        expect(output[:has_next_page]).to be_truthy
        expect(output[:stats][:total_found]).to eq(100)
        expect(output[:stats][:total_searched]).to eq(100)
        expect(output[:stats][:batches_processed]).to eq(1)

        expect(action_instance.send(:iteration_state_value)).to eq({ 'batch_index' => 1 })

        expect(stub1).to have_been_requested.once
      end

      it 'processes second batch when iteration state is set' do
        plain_identifiers = (1..150).map { |i| "user#{i}@example.com" }
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        second_batch_values = (101..150).map { |i| "user#{i}@example.com" }
        second_response_data = {
          authenticationID: { nodes: [] },
          primaryEmail: {
            nodes: (101..150).map do |i|
              { externalIdentifier: "user#{i}@example.com", nodeID: "person-#{i}" }
            end,
          },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }
        stub2 = stub_people_query(values: second_batch_values, response_data: second_response_data)

        action_instance = action({ identifiers: identifiers })
        action_instance.send(:iteration_state_value=, { batch_index: 1 })
        results = action_instance.run
        output = results.first&.[](:output)

        expect(output[:identifier_map].keys.length).to eq(50)
        expect(output[:records]).to be_a(Array)
        expect(output[:records].length).to eq(50)
        expect(output[:has_next_page]).to be_falsey
        expect(output[:stats][:total_found]).to eq(50)
        expect(output[:stats][:total_searched]).to eq(50)
        expect(output[:stats][:batches_processed]).to eq(1)

        expect(action_instance.send(:iteration_state_value)).to be_nil

        expect(stub2).to have_been_requested.once
      end

      it 'respects custom page_size' do
        plain_identifiers = (1..50).map { |i| "user#{i}@example.com" }
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        first_batch_values = (1..25).map { |i| "user#{i}@example.com" }
        first_response_data = {
          authenticationID: { nodes: [] },
          primaryEmail: {
            nodes: (1..25).map do |i|
              { externalIdentifier: "user#{i}@example.com", nodeID: "person-#{i}" }
            end,
          },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }
        stub1 = stub_people_query(values: first_batch_values, response_data: first_response_data)

        action_instance = action({ identifiers: identifiers, page_size: 25 })
        results = action_instance.run
        output = results.first&.[](:output)

        expect(output[:identifier_map].keys.length).to eq(25)
        expect(output[:records]).to be_a(Array)
        expect(output[:records].length).to eq(25)
        expect(output[:has_next_page]).to be_truthy
        expect(output[:stats][:total_searched]).to eq(25)

        expect(action_instance.send(:iteration_state_value)).to eq({ 'batch_index' => 1 })

        expect(stub1).to have_been_requested.once
      end
    end

    describe 'extracts headers' do
      let(:xurrent_headers) do
        {
          'x-costlimit-limit' => 5000,
          'x-costlimit-cost' => 10,
          'x-costlimit-remaining' => 4990,
          'x-costlimit-reset' => 1_720_199_698,
          'x-ratelimit-limit' => 3600,
          'x-ratelimit-remaining' => 3590,
          'x-ratelimit-reset' => 1_720_199_697,
          'x-request-id' => 'FetchPeople-123456',
        }
      end

      before(:each) do
        plain_identifiers = ['user@example.com']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        response_data = {
          authenticationID: { nodes: [] },
          primaryEmail: {
            nodes: [
              { externalIdentifier: 'user@example.com', nodeID: 'person-123' },
            ],
          },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }

        stub_people_query(
          values: plain_identifiers,
          response_data: response_data,
          headers: xurrent_headers
        )

        @output = run_action({ identifiers: identifiers })
      end

      it 'extracts x-request-id header' do
        expect(@output[:request_id]).to eq('FetchPeople-123456')
      end

      it 'extracts x-ratelimit headers' do
        expect(@output[:ratelimit]).to eq({
          'limit' => '3600',
          'remaining' => '3590',
          'reset' => '1720199697',
        })
      end

      it 'extracts x-costlimit headers' do
        expect(@output[:costlimit]).to eq({
          'limit' => '5000',
          'cost' => '10',
          'remaining' => '4990',
          'reset' => '1720199698',
        })
      end
    end

    describe 'error handling' do
      it 'handles 429 rate limit error' do
        plain_identifiers = ['user@example.com']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        stub = stub_request(:post, endpoint)
               .with do |request|
                 body = JSON.parse(request.body)
                 body['variables'] == { 'values' => plain_identifiers }
               end
               .to_return(status: 429, body: 'Rate limit exceeded')

        Timecop.freeze do
          expect { run_action({ identifiers: identifiers }) }
            .to raise_error(IPaaS::Job::RescheduleJob, "Xurrent rate limit hit. 'Rate limit exceeded'") do |e|
            expect(e.reschedule_after).to eq(1.minute.from_now)
          end
          expect(stub).to have_been_requested.once
        end
      end

      it 'handles 503 service unavailable' do
        plain_identifiers = ['user@example.com']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        stub = stub_request(:post, endpoint)
               .with do |request|
                 body = JSON.parse(request.body)
                 body['variables'] == { 'values' => plain_identifiers }
               end
               .to_return(status: 503, body: 'Service Unavailable')

        Timecop.freeze do
          expect { run_action({ identifiers: identifiers }) }
            .to raise_error(IPaaS::Job::RescheduleJob, "Xurrent not available. 'Service Unavailable'") do |e|
            expect(e.reschedule_after).to eq(1.minute.from_now)
          end
          expect(stub).to have_been_requested.once
        end
      end

      it 'handles 401 unauthorized' do
        plain_identifiers = ['user@example.com']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        stub = stub_request(:post, endpoint)
               .with do |request|
                 body = JSON.parse(request.body)
                 body['variables'] == { 'values' => plain_identifiers }
               end
               .to_return(status: 401, body: '{"message":"Unauthorized"}')

        expect { run_action({ identifiers: identifiers }) }
          .to raise_error(IPaaS::Job::FailJob,
                          %(HTTP error from Xurrent GraphQL API: 401 '{"message":"Unauthorized"}'))
        expect(stub).to have_been_requested.once
      end

      it 'handles GraphQL errors in response' do
        plain_identifiers = ['user@example.com']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        stub = stub_request(:post, endpoint)
               .with do |request|
                 body = JSON.parse(request.body)
                 body['variables'] == { 'values' => plain_identifiers }
               end
               .to_return(body: { errors: [{ message: 'Missing required scope(s): people:Read' }] }.to_json)

        expect { run_action({ identifiers: identifiers }) }
          .to raise_error(IPaaS::Job::FailJob,
                          %(Errors from Xurrent GraphQL API: [{"message":"Missing required scope(s): people:Read"}]))
        expect(stub).to have_been_requested.once
      end
    end

    describe 'edge cases' do
      it 'handles null nodes in response' do
        plain_identifiers = ['user@example.com']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        response_data = {
          authenticationID: { nodes: [] },
          primaryEmail: {
            nodes: [
              nil,
              { externalIdentifier: 'user@example.com', nodeID: 'person-123' },
            ],
          },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }

        stub_people_query(values: plain_identifiers, response_data: response_data)

        output = run_action({ identifiers: identifiers })

        expect(output[:identifier_map].keys.length).to eq(1)

        key = output[:identifier_map].keys.first
        expect(key).to be_a(IPaaS::Encryption::SecretString)

        person = output[:identifier_map].values.first
        expect(person['id']).to eq('person-123')
      end

      it 'validates that identifiers array is not empty' do
        identifiers = []
        action_instance = action({ identifiers: identifiers })
        expect(action_instance.valid?).to be_falsey
        expect(action_instance.full_error_messages).to include("Field 'identifiers' is required")
      end

      it 'handles person with missing nodeID' do
        plain_identifiers = ['user@example.com']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        response_data = {
          authenticationID: { nodes: [] },
          primaryEmail: {
            nodes: [
              { externalIdentifier: 'user@example.com', nodeID: nil },
            ],
          },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }

        stub_people_query(values: plain_identifiers, response_data: response_data)

        output = run_action({ identifiers: identifiers })

        person = output[:identifier_map].values.first
        expect(person['id']).to eq(nil)
      end

      it 'handles person found by authenticationID' do
        plain_identifiers = ['user123']
        identifiers = plain_identifiers.map { |id| make_secret_string(id) }

        response_data = {
          authenticationID: {
            nodes: [
              { externalIdentifier: 'user123', nodeID: 'person-123' },
            ],
          },
          primaryEmail: { nodes: [] },
          sourceID: { nodes: [] },
          employeeID: { nodes: [] },
          supportID: { nodes: [] },
        }

        stub_people_query(values: plain_identifiers, response_data: response_data)

        output = run_action({ identifiers: identifiers })

        key = output[:identifier_map].keys.first
        expect(key).to be_a(IPaaS::Encryption::SecretString)

        user123_key = make_secret_string('user123')
        person = output[:identifier_map][user123_key]
        expect(person['id']).to eq('person-123')
      end
    end
  end
end
