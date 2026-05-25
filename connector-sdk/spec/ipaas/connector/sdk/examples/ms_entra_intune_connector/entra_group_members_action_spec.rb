require 'spec_helper'

describe 'Microsoft Entra Group Members Action', :action do
  let(:connector_id) { '01983ca8-546f-7610-93c9-c6cc164300fc' }
  let(:action_template_id) { '01983cb4-b1b5-75fa-8320-b9350012a886' }

  describe 'input_schema' do
    it 'should define the group ID field' do
      action.input_schema.field(:group_id).tap do |field|
        expect(field.label).to eq('Group ID')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
        expect(field.visibility).to eq('visible')
      end
    end

    it 'should define the page_size field' do
      action.input_schema.field(:page_size).tap do |field|
        expect(field.label).to eq('Page size')
        expect(field.type).to eq(:integer)
        expect(field.required).to be_falsey
        expect(field.visibility).to eq('optional')
        expect(field.min).to eq(1)
        expect(field.max).to eq(999)
        expect(field.default).to eq(100)
      end
    end
  end

  describe 'output_schema' do
    it 'should only have page output schema' do
      expect(action.output_schema.map(&:reference)).to contain_exactly('page')
    end

    describe 'page schema' do
      let(:page_schema) { action.output_schema.first }

      it 'should define the OData count field' do
        page_schema.field(:odata_count).tap do |field|
          expect(field.label).to eq('OData count')
          expect(field.type).to eq(:integer)
        end
      end

      it 'should define the has_next_page field' do
        page_schema.field(:has_next_page).tap do |field|
          expect(field.label).to eq('Has next page')
          expect(field.type).to eq(:boolean)
        end
      end

      it 'should define the members field' do
        members_field = page_schema.field(:members).tap do |field|
          expect(field.label).to eq('Members')
          expect(field.type).to eq(:nested)
          expect(field.array).to eq(true)
        end

        members_field.field(:member_id).tap do |field|
          expect(field.label).to eq('Member ID')
          expect(field.type).to eq(:string)
          expect(field.required).to be_truthy
        end
        members_field.field(:device_id).tap do |field|
          expect(field.label).to eq('Device ID')
          expect(field.type).to eq(:string)
        end
        members_field.field(:odata_type).tap do |field|
          expect(field.label).to eq('OData type')
          expect(field.type).to eq(:string)
        end
      end
    end
  end

  describe 'iteration_state_schema' do
    it 'should define the OData next link field' do
      action.iteration_state_schema.field(:odata_nextLink).tap do |field|
        expect(field.label).to eq('OData next link')
        expect(field.type).to eq(:string)
        expect(field.required).to be_truthy
        expect(field.visibility).to eq('visible')
      end
    end
  end

  describe 'run' do
    let(:endpoint) do
      outbound_connection_config[:environment][:graph_endpoint]
    end

    let(:outbound_connection_config) do
      {
        credentials: {
          tenant_id: 'wdc',
          client_id: 'abc',
          client_secret: make_secret_string('def'),
        },
        environment: {
          graph_endpoint: 'https://graph.example.com/v1',
        },
      }
    end

    def fill_authorization_cache
      url = outbound_connection_config[:environment][:oauth2_endpoint]
      url ||= "https://login.microsoftonline.com/#{outbound_connection_config[:credentials][:tenant_id]}/oauth2/v2.0/token"

      body = {
        client_id: outbound_connection_config[:credentials][:client_id],
        client_secret: encryptor.decrypt(outbound_connection_config[:credentials][:client_secret]),
        grant_type: 'client_credentials',
        scope: 'https://graph.microsoft.com/.default',
      }
      store_oauth2_header(url, body)
    end

    before(:each) do
      fill_authorization_cache
    end

    def generate_expected_url(group_id = 'qwerty')
      "#{endpoint}/groups/#{group_id}/members"
    end

    def trigger_action(page_size: nil)
      run_action({ group_id: 'qwerty', page_size: page_size })
    end

    describe 'returns members' do
      it 'gets values for group' do
        group_id = 'foo'
        stub = stub_request(:get, generate_expected_url(group_id))
               .with(query: { '$top': 100, '$select': 'id,deviceId' })
               .to_return(body: {
                 value: [
                   {
                     '@odata.type': '#microsoft.graph.device',
                     id: '1d6',
                     deviceId: 'xyz',
                   },
                   {
                     '@odata.type': '#microsoft.graph.user',
                     id: 'ed6',
                   },
                   {
                     '@odata.type': '#microsoft.graph.device',
                     id: '2d7',
                     deviceId: 'def',
                   },
                   {
                     '@odata.type': '#microsoft.graph.device',
                     id: '3d8',
                     deviceId: 'abc',
                   },
                 ],
               }.to_json)

        output = run_action({ group_id: group_id })
        expect(output[:has_next_page]).to eq(false)
        members = output[:members]
        expect(members.pluck(:member_id)).to contain_exactly('1d6', 'ed6', '2d7', '3d8')
        expect(members.pluck(:device_id)).to contain_exactly('xyz', nil, 'def', 'abc')
        expect(members.pluck(:odata_type)).to contain_exactly('#microsoft.graph.device',
                                                              '#microsoft.graph.user',
                                                              '#microsoft.graph.device',
                                                              '#microsoft.graph.device')
        expect(stub).to have_been_requested.once
      end

      it 'uses page_size' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 55, '$select': 'id,deviceId' })
               .to_return(body: { value: [] }.to_json)

        trigger_action(page_size: '55')
        expect(stub).to have_been_requested.once
      end

      describe 'iteration state handling' do
        it 'clears iteration_state_value when next link is absent' do
          group_id = 'qwerty'
          stub = stub_request(:get, generate_expected_url(group_id))
                 .with(query: { '$top': 100, '$select': 'id,deviceId' })
                 .to_return(body: { value: [] }.to_json)

          expect(action({ group_id: group_id })).to receive(:iteration_state_value=).with(nil)

          output = run_action({ group_id: group_id })
          expect(output[:has_next_page]).to eq(false)
          expect(stub).to have_been_requested.once
        end

        it 'stores iteration_state_value when next link is present' do
          group_id = 'bar'
          stub = stub_request(:get, generate_expected_url(group_id))
                 .with(query: { '$top': 100, '$select': 'id,deviceId' })
                 .to_return(body: {
                   '@odata.nextLink': 'https://foo/bar',
                   value: [
                     {
                       '@odata.type': '#microsoft.graph.device',
                       id: '1d6',
                       deviceId: 'xyz',
                     },
                   ],
                 }.to_json)

          expect(action({ group_id: group_id })).to receive(:iteration_state_value=)
            .with({ odata_nextLink: 'https://foo/bar' })
            .and_call_original

          output = run_action({ group_id: group_id })
          expect(output[:has_next_page]).to eq(true)
          expect(output[:members].pluck(:member_id)).to contain_exactly('1d6')
          expect(stub).to have_been_requested.once
        end

        it 'uses iteration_state_value' do
          old_next_link = 'https://foo/baz'
          group_id = 'baz'
          stub = stub_request(:get, old_next_link)
                 .with(query: nil)
                 .to_return(body: {
                   value: [
                     {
                       '@odata.type': '#microsoft.graph.device',
                       id: '2d6',
                       deviceId: 'xyz',
                     },
                   ],
                 }.to_json)

          action({ group_id: group_id }).send(:iteration_state_value=, { odata_nextLink: old_next_link })

          output = run_action({ group_id: group_id })
          expect(output[:has_next_page]).to eq(false)
          expect(output[:members].pluck(:member_id)).to contain_exactly('2d6')
          expect(stub).to have_been_requested.once
        end
      end
    end

    describe 'error handling' do
      describe 'temporary errors' do
        describe 'without retry-after' do
          it 'handles 429' do
            stub = stub_request(:get, generate_expected_url)
                   .with(query: { '$top': 100, '$select': 'id,deviceId' })
                   .to_return(status: 429, body: 'Wait 10 seconds')

            Timecop.freeze do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob, "Microsoft API rate limit hit. 'Wait 10 seconds'") do |e|
                expect(e.reschedule_after).to eq(1.minute.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles 503' do
            stub = stub_request(:get, generate_expected_url)
                   .with(query: { '$top': 100, '$select': 'id,deviceId' })
                   .to_return(status: 503, body: 'Service Unavailable')

            Timecop.freeze do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                %(Microsoft API not available. 'Service Unavailable')) do |e|
                expect(e.reschedule_after).to eq(1.minute.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end
        end

        describe 'with retry-after' do
          it 'handles 429' do
            stub = stub_request(:get, generate_expected_url)
                   .with(query: { '$top': 100, '$select': 'id,deviceId' })
                   .to_return(status: 429, body: 'Wait 2 seconds', headers: { 'retry-after' => 2 })

            Timecop.freeze do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                "Microsoft API rate limit hit (retry after: 2). 'Wait 2 seconds'") do |e|
                expect(e.reschedule_after).to eq(2.seconds.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles 503' do
            stub = stub_request(:get, generate_expected_url)
                   .with(query: { '$top': 100, '$select': 'id,deviceId' })
                   .to_return(status: 503,
                              body: 'Service Unavailable',
                              headers: { 'retry-after' => 'Wed, 21 Oct 2015 07:28:00 GMT' })

            Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 +01:00')) do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                'Microsoft API not available (retry after: Wed, 21 Oct 2015 07:28:00 GMT). ' \
                                "'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(8.minutes.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles retry after header in the past in 503' do
            stub = stub_request(:get, generate_expected_url)
                   .with(query: { '$top': 100, '$select': 'id,deviceId' })
                   .to_return(status: 503,
                              body: 'Service Unavailable',
                              headers: { 'retry-after' => 'Wed, 21 Oct 2015 07:19:00 GMT' })

            Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 +01:00')) do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                'Microsoft API not available (retry after: Wed, 21 Oct 2015 07:19:00 GMT). ' \
                                "'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(1.minutes.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end

          it 'handles invalid retry after header in 503' do
            stub = stub_request(:get, generate_expected_url)
                   .with(query: { '$top': 100, '$select': 'id,deviceId' })
                   .to_return(status: 503,
                              body: 'Service Unavailable',
                              headers: { 'retry-after' => '642 Bla 2015 07:28:00 GMT' })

            Timecop.freeze(Time.parse('Wed, 21 Oct 2015 08:20:00 CET')) do
              expect { trigger_action }
                .to raise_error(IPaaS::Job::RescheduleJob,
                                'Microsoft API not available (retry after: 642 Bla 2015 07:28:00 GMT). ' \
                                "'Service Unavailable'") do |e|
                expect(e.reschedule_after).to eq(1.minutes.from_now)
              end
              expect(stub).to have_been_requested.once
            end
          end
        end
      end

      it 'handles 400' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100, '$select': 'id,deviceId' })
               .to_return(status: 400, body: '{"message":"Bad request"} foo nba')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(HTTP error from Microsoft Graph API: 400 '{"message":"Bad request"} foo nba'))
        expect(stub).to have_been_requested.once
      end

      it 'handles 401' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100, '$select': 'id,deviceId' })
               .to_return(status: 401, body: '{"message":"Unauthorized"}')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(HTTP error from Microsoft Graph API: 401 '{"message":"Unauthorized"}'))
        expect(stub).to have_been_requested.once
      end

      it 'handles 500' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100, '$select': 'id,deviceId' })
               .to_return(status: 500, body: '{"message":"Internal Server Error"}')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(HTTP error from Microsoft Graph API: 500 '{"message":"Internal Server Error"}'))
        expect(stub).to have_been_requested.once
      end

      it 'handles complex error in body' do
        json = {
          error: {
            code: 'Request_UnsupportedQuery',
            message: "Property 'a' does not exist as a declared property or extension property.",
            innerError: {
              date: '2025-07-25T08:54:06',
              'request-id': '42fc-9905-b911303df336',
              'client-request-id': '42fc-9905-b911303df336',
            },
          },
        }.to_json

        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100, '$select': 'id,deviceId' })
               .to_return(body: json)

        expect { trigger_action }.to raise_error(IPaaS::Job::FailJob) do |error|
          message = error.message
          expect(message).to start_with('Error from Microsoft Graph API: ')
          expect(message).to end_with(JSON.parse(json)['error'].to_json)
        end

        expect(stub).to have_been_requested.once
      end

      it 'ignores empty error in body' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100, '$select': 'id,deviceId' })
               .to_return(body: { error: [],
                                  value: [], }.to_json)

        output = trigger_action
        expect(output[:members]).to eq([])

        expect(stub).to have_been_requested.once
      end

      it 'handles missing value' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100, '$select': 'id,deviceId' })
               .to_return(body: { boo: :ba }.to_json)

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob, %(No value in Microsoft Graph API response: '{"boo":"ba"}'))

        expect(stub).to have_been_requested.once
      end

      it 'fails when member_id is missing' do
        response_body = {
          value: [
            {
              '@odata.type': '#microsoft.graph.device',
              id: '1d6',
              deviceId: 'abc',
            },
            {
              '@odata.type': '#microsoft.graph.device',
              deviceId: 'xyz',
            },
          ],
        }

        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100, '$select': 'id,deviceId' })
               .to_return(body: response_body.to_json)

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob, /Not all values have id/)

        expect(stub).to have_been_requested.once
      end

      it 'fails when device_id is missing for odata type device' do
        response_body = {
          value: [
            {
              '@odata.type': '#microsoft.graph.device',
              id: '1d6',
              deviceId: 'abc',
            },
            {
              '@odata.type': '#microsoft.graph.device',
              id: '2d6',
            },
          ],
        }

        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100, '$select': 'id,deviceId' })
               .to_return(body: response_body.to_json)

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob, /Not all devices have deviceId/)

        expect(stub).to have_been_requested.once
      end

      it 'succeeds when device_id is missing for odata types other than device' do
        response_body = {
          value: [
            {
              '@odata.type': '#microsoft.graph.device',
              id: '1d6',
              deviceId: 'abc',
            },
            {
              '@odata.type': '#microsoft.graph.user',
              id: '2d6',
            },
          ],
        }

        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$top': 100, '$select': 'id,deviceId' })
               .to_return(body: response_body.to_json)

        expect do
          trigger_action
        end.not_to raise_error

        expect(stub).to have_been_requested.once
      end
    end
  end
end
