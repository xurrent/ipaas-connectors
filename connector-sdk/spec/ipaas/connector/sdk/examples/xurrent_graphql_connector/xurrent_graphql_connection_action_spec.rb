require 'spec_helper'

describe 'Xurrent GraphQL Connection Action', :action do
  let(:connector_id) { '01962529-c8eb-7a89-a682-73d6f09541d6' }
  let(:action_template_id) { '01961a26-09f7-78e4-b6d9-7b61f43a949a' }

  describe 'input_schema' do
    it 'should define the connection field' do
      action.input_schema.field(:connection).tap do |field|
        expect(field.label).to eq('Connection')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
        expect(field.visibility).to eq('visible')
        expect(field.pattern).to eq(/\A[A-Za-z0-9]+\z/)
      end
    end

    it 'should define the node_fields field' do
      action.input_schema.field(:node_fields).tap do |field|
        expect(field.label).to eq('Node fields')
        expect(field.type).to eq(:string)
        expect(field.required).to be_falsey
        expect(field.visibility).to eq('visible')
      end
    end

    it 'should define the view field' do
      action.input_schema.field(:view).tap do |field|
        expect(field.label).to eq('View')
        expect(field.type).to eq(:string)
        expect(field.required).to be_falsey
        expect(field.visibility).to eq('optional')
      end
    end

    it 'should define the page_size field' do
      action.input_schema.field(:page_size).tap do |field|
        expect(field.label).to eq('Page size')
        expect(field.type).to eq(:integer)
        expect(field.required).to be_falsey
        expect(field.visibility).to eq('optional')
        expect(field.min).to eq(1)
        expect(field.max).to eq(100)
        expect(field.default).to eq(100)
      end
    end

    it 'should define the filter field' do
      filter_field = action.input_schema.field(:filter).tap do |field|
        expect(field.label).to eq('Filter')
        expect(field.type).to eq(:nested)
        expect(field.required).to be_falsey
        expect(field.visibility).to eq('optional')
        expect(field.array).to eq(true)
      end

      filter_field.field(:field).tap do |field|
        expect(field.label).to eq('Field')
        expect(field.type).to eq(:string)
        expect(field.pattern).to eq(/\A[A-Za-z0-9]+\z/)
        expect(field.required).to eq(true)
        expect(field.visibility).to eq('visible')
        expect(field.array).to eq(false)
      end

      filter_field.field(:value).tap do |field|
        expect(field.label).to eq('Filter value')
        expect(field.type).to eq(:string)
        expect(field.required).to eq(true)
        expect(field.visibility).to eq('visible')
        expect(field.array).to eq(false)
      end
    end

    it 'should define the order field' do
      order_field = action.input_schema.field(:order).tap do |field|
        expect(field.label).to eq('Order')
        expect(field.type).to eq(:nested)
        expect(field.required).to be_falsey
        expect(field.visibility).to eq('optional')
        expect(field.array).to eq(true)
      end

      order_field.field(:field).tap do |field|
        expect(field.label).to eq('Field')
        expect(field.type).to eq(:string)
        expect(field.pattern).to eq(/\A[A-Za-z0-9]+\z/)
        expect(field.required).to eq(true)
        expect(field.visibility).to eq('visible')
        expect(field.array).to eq(false)
      end

      order_field.field(:direction).tap do |field|
        expect(field.label).to eq('Direction')
        expect(field.type).to eq(:string)
        expect(field.enumeration).to contain_exactly(
          { id: 'asc', label: 'Ascending' },
          { id: 'desc', label: 'Descending' },
        )
        expect(field.required).to eq(false)
        expect(field.visibility).to eq('visible')
        expect(field.array).to eq(false)
        expect(field.default).to eq('asc')
      end
    end
  end

  describe 'output_schema' do
    it 'should only have page output schema' do
      expect(action.output_schema.map(&:reference)).to contain_exactly('page')
    end

    describe 'page schema' do
      let(:page_schema) { action.output_schema.first }

      it 'should define the total_count field' do
        page_schema.field(:total_count).tap do |field|
          expect(field.label).to eq('Total count')
          expect(field.type).to eq(:integer)
        end
      end

      it 'should define the has_next_page field' do
        page_schema.field(:has_next_page).tap do |field|
          expect(field.label).to eq('Has next page')
          expect(field.type).to eq(:boolean)
        end
      end

      it 'should define the nodes field' do
        page_schema.field(:nodes).tap do |field|
          expect(field.label).to eq('Records')
          expect(field.type).to eq(:hash)
          expect(field.array).to eq(true)
        end
      end

      it 'should define the request_id field' do
        page_schema.field(:request_id).tap do |field|
          expect(field.label).to eq('Request ID')
          expect(field.type).to eq(:string)
          expect(field.visibility).to eq('optional')
        end
      end

      it 'should define the ratelimit field' do
        ratelimit_field = page_schema.field(:ratelimit).tap do |field|
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
        costlimit_field = page_schema.field(:costlimit).tap do |field|
          expect(field.label).to eq('Cost limit')
          expect(field.type).to eq(:nested)
          expect(field.visibility).to eq('optional')
        end

        costlimit_field.field(:cost).tap do |field|
          expect(field.label).to eq('Cost')
          expect(field.type).to eq(:integer)
        end

        costlimit_field.field(:limit).tap do |field|
          expect(field.label).to eq('Limit')
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
    end
  end

  describe 'iteration_state_schema' do
    it 'should define the connection field' do
      action.iteration_state_schema.field(:end_cursor).tap do |field|
        expect(field.label).to eq('End cursor')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
        expect(field.visibility).to eq('visible')
      end
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

    def generate_expected_body(connection,
                               page_size: 100,
                               view: '',
                               filter: '',
                               order: '',
                               after: '',
                               node_fields: '')
      { query: <<~GRAPHQL.gsub(/\s+/, ' ').strip }
        { #{connection}(
            first: #{page_size}
            #{view}
            #{filter}
            #{order}
            #{after}
          ) {
            pageInfo { hasNextPage endCursor }
            totalCount
            nodes { id
              #{node_fields}
            }
          } }
      GRAPHQL
    end

    def trigger_action
      run_action({ connection: 'services' })
    end

    describe 'return query result as data' do
      it 'queries pageInfo totalCount and id by default' do
        stub = stub_request(:post, endpoint)
               .with(body: generate_expected_body('services'), headers: content_type_json)
               .to_return(body: { data: { services: {
                 totalCount: 10,
                 pageInfo: { hasNextPage: false, endCursor: 'theEnd' },
                 nodes: [{ id: 'id1' }],
               } } }.to_json)

        output = run_action({ connection: 'services' })
        expect(output[:total_count]).to eq(10)
        expect(output[:has_next_page]).to eq(false)
        expect(output[:nodes].pluck(:id)).to contain_exactly('id1')
        expect(stub).to have_been_requested.once
      end

      it 'queries requested connection' do
        stub = stub_request(:post, endpoint)
               .with(body: generate_expected_body('teams'), headers: content_type_json)
               .to_return(body: { data: { teams: {
                 totalCount: 21,
                 pageInfo: { hasNextPage: false, endCursor: 'theEnd' },
                 nodes: [{ id: 'teamId' }],
               } } }.to_json)

        output = run_action({ connection: 'teams' })
        expect(output[:total_count]).to eq(21)
        expect(output[:has_next_page]).to eq(false)
        expect(output[:nodes].pluck(:id)).to contain_exactly('teamId')
        expect(stub).to have_been_requested.once
      end

      it 'queries requested fields' do
        stub = stub_request(:post, endpoint)
               .with(body: generate_expected_body('services',
                                                  node_fields: 'name team { name }'), headers: content_type_json)
               .to_return(body: { data: { services: {
                 totalCount: 10,
                 pageInfo: { hasNextPage: false, endCursor: 'theEnd' },
                 nodes: [{ id: 'id1', name: 'my name', team: { name: 'my team' } }],
               } } }.to_json)

        output = run_action({ connection: 'services', node_fields: 'name team { name }' })
        expect(output[:nodes].pluck(:id)).to contain_exactly('id1')
        expect(output[:nodes].pluck(:name)).to contain_exactly('my name')
        expect(output[:nodes].pluck(:team)).to contain_exactly({ name: 'my team' })
        expect(stub).to have_been_requested.once
      end

      it 'uses page_size' do
        stub = stub_request(:post, endpoint)
               .with(body: generate_expected_body('services', page_size: 10), headers: content_type_json)
               .to_return(body: { data: { services: {
                 totalCount: 10,
                 pageInfo: { hasNextPage: false, endCursor: 'theEnd' },
                 nodes: [{ id: 'id1' }],
               } } }.to_json)

        output = run_action({ connection: 'services', page_size: 10 })
        expect(output[:nodes].pluck(:id)).to contain_exactly('id1')
        expect(stub).to have_been_requested.once
      end

      it 'uses view' do
        stub = stub_request(:post, endpoint)
               .with(body: generate_expected_body('services', view: 'view: all'), headers: content_type_json)
               .to_return(body: { data: { services: {
                 totalCount: 10,
                 pageInfo: { hasNextPage: false, endCursor: 'theEnd' },
                 nodes: [{ id: 'id1' }],
               } } }.to_json)

        output = run_action({ connection: 'services', view: 'all' })
        expect(output[:nodes].pluck(:id)).to contain_exactly('id1')
        expect(stub).to have_been_requested.once
      end

      describe 'iteration state handling' do
        it 'clears iteration_state_value when hasNextPage is false' do
          stub = stub_request(:post, endpoint)
                 .with(body: generate_expected_body('services'), headers: content_type_json)
                 .to_return(body: { data: { services: {
                   totalCount: 10,
                   pageInfo: { hasNextPage: false, endCursor: 'theEnd' },
                   nodes: [{ id: 'id1' }],
                 } } }.to_json)

          expect(action({ connection: 'services' })).to receive(:iteration_state_value=).with(nil)

          output = run_action({ connection: 'services' })
          expect(output[:nodes].pluck(:id)).to contain_exactly('id1')
          expect(stub).to have_been_requested.once
        end

        it 'stores iteration_state_value when hasNextPage is true' do
          stub = stub_request(:post, endpoint)
                 .with(body: generate_expected_body('services'), headers: content_type_json)
                 .to_return(body: { data: { services: {
                   totalCount: 10,
                   pageInfo: { hasNextPage: true, endCursor: 'theEnd' },
                   nodes: [{ id: 'id1' }],
                 } } }.to_json)

          expect(action({ connection: 'services' })).to receive(:iteration_state_value=).with({ end_cursor: 'theEnd' })

          output = run_action({ connection: 'services' })
          expect(output[:nodes].pluck(:id)).to contain_exactly('id1')
          expect(stub).to have_been_requested.once
        end

        it 'uses iteration_state_value' do
          stub = stub_request(:post, endpoint)
                 .with(body: generate_expected_body('services', after: 'after: "halfWay"'), headers: content_type_json)
                 .to_return(body: { data: { services: {
                   totalCount: 10,
                   pageInfo: { hasNextPage: false, endCursor: 'theEnd' },
                   nodes: [{ id: 'id1' }],
                 } } }.to_json)

          action({ connection: 'services' }).send(:iteration_state_value=, { end_cursor: 'halfWay' })

          output = run_action({ connection: 'services' })
          expect(output[:nodes].pluck(:id)).to contain_exactly('id1')
          expect(stub).to have_been_requested.once
        end
      end

      describe 'using filter' do
        it 'filters with single field' do
          stub = stub_request(:post, endpoint)
                 .with(body: generate_expected_body('services',
                                                    filter: 'filter: {name: {values: ["abc"]}}'),
                       headers: content_type_json)
                 .to_return(body: { data: { services: {
                   totalCount: 10,
                   pageInfo: { hasNextPage: false, endCursor: 'theEnd' },
                   nodes: [{ id: 'id1' }],
                 } } }.to_json)

          output = run_action({ connection: 'services', filter: [{ field: 'name', value: '{values: ["abc"]}' }] })
          expect(output[:nodes].pluck(:id)).to contain_exactly('id1')
          expect(stub).to have_been_requested.once
        end

        it 'filters with multiple fields' do
          expected_filter = 'filter: {disabled: false, name: {values: ["xyz"], negated: true}}'
          stub = stub_request(:post, endpoint)
                 .with(body: generate_expected_body('services', filter: expected_filter), headers: content_type_json)
                 .to_return(body: { data: { services: {
                   totalCount: 10,
                   pageInfo: { hasNextPage: false, endCursor: 'theEnd' },
                   nodes: [{ id: 'id1' }],
                 } } }.to_json)

          output = run_action(
            { connection: 'services',
              filter: [
                { field: 'disabled', value: 'false' },
                { field: 'name', value: '{values: ["xyz"], negated: true}' },
              ], }
          )
          expect(output[:nodes].pluck(:id)).to contain_exactly('id1')
          expect(stub).to have_been_requested.once
        end
      end

      describe 'using order' do
        it 'orders on single field' do
          stub = stub_request(:post, endpoint)
                 .with(body: generate_expected_body('services',
                                                    order: 'order: [{ field: name, direction: asc }]'),
                       headers: content_type_json)
                 .to_return(body: { data: { services: {
                   totalCount: 10,
                   pageInfo: { hasNextPage: false, endCursor: 'theEnd' },
                   nodes: [{ id: 'id1' }],
                 } } }.to_json)

          output = run_action({ connection: 'services', order: [{ field: 'name', direction: 'asc' }] })
          expect(output[:nodes].pluck(:id)).to contain_exactly('id1')
          expect(stub).to have_been_requested.once
        end

        it 'orders on multiple fields' do
          expected_order = 'order: [{ field: name, direction: desc }, { field: team, direction: asc }]'
          stub = stub_request(:post, endpoint)
                 .with(body: generate_expected_body('services', order: expected_order), headers: content_type_json)
                 .to_return(body: { data: { services: {
                   totalCount: 10,
                   pageInfo: { hasNextPage: false, endCursor: 'theEnd' },
                   nodes: [{ id: 'id1' }],
                 } } }.to_json)

          output = run_action(
            { connection: 'services',
              order: [
                { field: 'name', direction: 'desc' },
                { field: 'team', direction: 'asc' },
              ], }
          )
          expect(output[:nodes].pluck(:id)).to contain_exactly('id1')
          expect(stub).to have_been_requested.once
        end
      end
    end

    describe 'extracts headers' do
      before(:each) do
        stub_request(:post, endpoint)
          .with(body: generate_expected_body('services'))
          .to_return(body: { data: { services: {
            totalCount: 10,
            pageInfo: { hasNextPage: false, endCursor: 'theEnd' },
            nodes: [{ id: 'id1' }],
          } } }.to_json, headers: xurrent_headers)
      end

      let(:xurrent_headers) do
        {
          'x-costlimit-limit' => 5000,
          'x-costlimit-cost' => 1,
          'x-costlimit-remaining' => 4999,
          'x-costlimit-reset' => 1_720_199_698,
          'x-ratelimit-limit' => 3600,
          'x-ratelimit-remaining' => 3599,
          'x-ratelimit-reset' => 1_720_199_697,
          'x-request-id' => 'Root36a4573f-8036-463a-bf43-48d75c62218f',
        }
      end

      it 'extracts x-request-id header' do
        output = trigger_action
        expect(output[:request_id]).to eq('Root36a4573f-8036-463a-bf43-48d75c62218f')
      end

      it 'extracts x-costlimit headers' do
        output = trigger_action
        expect(output[:costlimit]).to eq({
          'cost' => '1',
          'limit' => '5000',
          'remaining' => '4999',
          'reset' => '1720199698',
        })
      end

      it 'extracts x-ratelimit headers' do
        output = trigger_action
        expect(output[:ratelimit]).to eq({
          'limit' => '3600',
          'remaining' => '3599',
          'reset' => '1720199697',
        })
      end
    end

    describe 'error handling' do
      describe 'temporary errors' do
        describe 'without retry-after' do
          it 'handles 429' do
            stub = stub_request(:post, endpoint)
                   .with(body: generate_expected_body('services'), headers: content_type_json)
                   .to_return(status: 429, body: 'Wait 10 seconds')

            Timecop.freeze do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob, "Xurrent rate limit hit. 'Wait 10 seconds'") do |e|
                expect(e.reschedule_after).to eq(1.minute.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles 503' do
            stub = stub_request(:post, endpoint)
                   .with(body: generate_expected_body('services'), headers: content_type_json)
                   .to_return(status: 503, body: 'Service Unavailable')

            Timecop.freeze do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                %(Xurrent not available. 'Service Unavailable')) do |e|
                expect(e.reschedule_after).to eq(1.minute.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end
        end

        describe 'with retry-after' do
          it 'handles 429' do
            stub = stub_request(:post, endpoint)
                   .with(body: generate_expected_body('services'), headers: content_type_json)
                   .to_return(status: 429, body: 'Wait 2 seconds', headers: { 'retry-after' => 2 })

            Timecop.freeze do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                "Xurrent rate limit hit (retry after: 2). 'Wait 2 seconds'") do |e|
                expect(e.reschedule_after).to eq(2.seconds.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles 503' do
            stub = stub_request(:post, endpoint)
                   .with(body: generate_expected_body('services'), headers: content_type_json)
                   .to_return(status: 503,
                              body: 'Service Unavailable',
                              headers: { 'retry-after' => 'Wed, 21 Oct 2015 07:28:00 GMT' })

            Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 +01:00')) do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                'Xurrent not available (retry after: Wed, 21 Oct 2015 07:28:00 GMT). ' \
                                "'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(8.minutes.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles retry after header in the past in 503' do
            stub = stub_request(:post, endpoint)
                   .with(body: generate_expected_body('services'), headers: content_type_json)
                   .to_return(status: 503,
                              body: 'Service Unavailable',
                              headers: { 'retry-after' => 'Wed, 21 Oct 2015 07:19:00 GMT' })

            Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 +01:00')) do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                'Xurrent not available (retry after: Wed, 21 Oct 2015 07:19:00 GMT). ' \
                                "'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(1.minutes.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles invalid retry after header in 503' do
            stub = stub_request(:post, endpoint)
                   .with(body: generate_expected_body('services'), headers: content_type_json)
                   .to_return(status: 503,
                              body: 'Service Unavailable',
                              headers: { 'retry-after' => '642 Bla 2015 07:28:00 GMT' })

            Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 CET')) do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                'Xurrent not available (retry after: 642 Bla 2015 07:28:00 GMT). ' \
                                "'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(1.minutes.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end
        end
      end

      it 'handles 401' do
        stub = stub_request(:post, endpoint)
               .with(body: generate_expected_body('services'), headers: content_type_json)
               .to_return(status: 401, body: '{"message":"Unauthorized"}')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(HTTP error from Xurrent GraphQL API: 401 '{"message":"Unauthorized"}'))
        expect(stub).to have_been_requested.once
      end

      it 'handles 500' do
        stub = stub_request(:post, endpoint)
               .with(body: generate_expected_body('services'), headers: content_type_json)
               .to_return(status: 500, body: '{"message":"Internal Server Error"}')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(HTTP error from Xurrent GraphQL API: 500 '{"message":"Internal Server Error"}'))
        expect(stub).to have_been_requested.once
      end

      it 'handles complex errors in body' do
        stub = stub_request(:post, endpoint)
               .with(body: generate_expected_body('services'), headers: content_type_json)
               .to_return(body: { errors: [{ message: 'bla', path: 'abc' }] }.to_json)

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(Errors from Xurrent GraphQL API: [{"message":"bla","path":"abc"}]))

        expect(stub).to have_been_requested.once
      end

      it 'handles missing scope error' do
        stub = stub_request(:post, endpoint)
               .with(body: generate_expected_body('services'), headers: content_type_json)
               .to_return(body: { errors: [{ message: 'Missing required scope(s): request:Read' }] }.to_json)

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(Errors from Xurrent GraphQL API: [{"message":"Missing required scope(s): request:Read"}]))

        expect(stub).to have_been_requested.once
      end

      it 'ignores empty errors in body' do
        stub = stub_request(:post, endpoint)
               .with(body: generate_expected_body('services'), headers: content_type_json)
               .to_return(body: { errors: [],
                                  data: { services: {
                                    totalCount: 10,
                                    pageInfo: { hasNextPage: false, endCursor: 'theEnd' },
                                    nodes: [{ id: 'id1' }],
                                  } }, }.to_json)

        output = trigger_action
        expect(output[:total_count]).to eq(10)

        expect(stub).to have_been_requested.once
      end

      it 'handles missing data' do
        stub = stub_request(:post, endpoint)
               .with(body: generate_expected_body('services'), headers: content_type_json)
               .to_return(body: {}.to_json)

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob, %(No data from Xurrent GraphQL API))

        expect(stub).to have_been_requested.once
      end
    end
  end
end
