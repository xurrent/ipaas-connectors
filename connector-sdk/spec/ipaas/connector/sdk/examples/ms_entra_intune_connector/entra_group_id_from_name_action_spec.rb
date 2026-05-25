require 'spec_helper'

describe 'Microsoft Entra Group ID from Name Action', :action do
  let(:connector_id) { '01983ca8-546f-7610-93c9-c6cc164300fc' }
  let(:action_template_id) { '01983cb0-b8c0-7d91-a381-79e30c4d572e' }

  describe 'input_schema' do
    it 'should define the group ID field' do
      action.input_schema.field(:group_names).tap do |field|
        expect(field.label).to eq('Group display names')
        expect(field.type).to eq(:string)
        expect(field.array).to eq(true)
        expect(field.required).to be_truthy
        expect(field.max_length).to eq(10)
      end
    end
  end

  describe 'output_schema' do
    it 'should only have page output schema' do
      expect(action.output_schema.map(&:reference)).to contain_exactly('output')
    end

    describe 'schema' do
      let(:page_schema) { action.output_schema.first }

      it 'should define the members field' do
        members_field = page_schema.field(:results).tap do |field|
          expect(field.label).to eq('Results')
          expect(field.type).to eq(:nested)
          expect(field.array).to eq(true)
        end

        members_field.field(:display_name).tap do |field|
          expect(field.label).to eq('Display name')
          expect(field.type).to eq(:string)
          expect(field.required).to be_truthy
        end

        members_field.field(:group_id).tap do |field|
          expect(field.label).to eq('Group ID')
          expect(field.type).to eq(:string)
          expect(field.required).to be_truthy
        end
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

    def generate_expected_url
      "#{endpoint}/groups"
    end

    def trigger_action
      run_action({ group_names: ['MDM_Users'] })
    end

    describe 'returns members' do
      it 'gets values for groups' do
        names = ['MDM_Users', 'Intune Devices']
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$filter': "displayName in (#{names.map do |name|
                 "'#{name}'"
               end.join(',')})", '$select': 'id,displayName', })
               .to_return(body: {
                 value: [
                   {
                     id: 'a',
                     displayName: 'MDM_Users',
                   },
                   {
                     id: 'b',
                     displayName: 'Intune Devices',
                   },
                 ],
               }.to_json)

        output = run_action({ group_names: names })
        results = output[:results]
        expect(results.pluck(:group_id)).to contain_exactly('a', 'b')
        expect(results.pluck(:display_name)).to contain_exactly(*names)
        expect(stub).to have_been_requested.once
      end

      it 'gets empty when names are not present' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$filter': 'displayName in ()', '$select': 'id,displayName' })
               .to_return(body: { value: [] }.to_json)

        output = run_action({ group_names: [''] })
        results = output[:results]
        expect(results.pluck(:group_id)).to eq([])
        expect(results.pluck(:display_name)).to eq([])
        expect(stub).not_to have_been_requested
      end
    end

    describe 'error handling' do
      describe 'temporary errors' do
        describe 'without retry-after' do
          it 'handles 429' do
            stub = stub_request(:get, generate_expected_url)
                   .with(query: { '$filter': "displayName in ('MDM_Users')", '$select': 'id,displayName' })
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
                   .with(query: { '$filter': "displayName in ('MDM_Users')", '$select': 'id,displayName' })
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
                   .with(query: { '$filter': "displayName in ('MDM_Users')", '$select': 'id,displayName' })
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
                   .with(query: { '$filter': "displayName in ('MDM_Users')", '$select': 'id,displayName' })
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
                   .with(query: { '$filter': "displayName in ('MDM_Users')", '$select': 'id,displayName' })
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
                   .with(query: { '$filter': "displayName in ('MDM_Users')", '$select': 'id,displayName' })
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
               .with(query: { '$filter': "displayName in ('MDM_Users')", '$select': 'id,displayName' })
               .to_return(status: 400, body: '{"message":"Bad request"} foo nba')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(HTTP error from Microsoft Graph API: 400 '{"message":"Bad request"} foo nba'))
        expect(stub).to have_been_requested.once
      end

      it 'handles 401' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$filter': "displayName in ('MDM_Users')", '$select': 'id,displayName' })
               .to_return(status: 401, body: '{"message":"Unauthorized"}')

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob,
                           %(HTTP error from Microsoft Graph API: 401 '{"message":"Unauthorized"}'))
        expect(stub).to have_been_requested.once
      end

      it 'handles 500' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$filter': "displayName in ('MDM_Users')", '$select': 'id,displayName' })
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
            message: 'Unsupported Query.',
            innerError: {
              date: '2025-07-28T12:30:54',
              'request-id': 'tmp',
              'client-request-id': 'tmp',
            },
          },
        }.to_json

        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$filter': "displayName in ('MDM_Users')", '$select': 'id,displayName' })
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
               .with(query: { '$filter': "displayName in ('MDM_Users')", '$select': 'id,displayName' })
               .to_return(body: { error: [],
                                  value: [], }.to_json)

        output = trigger_action
        expect(output[:members]).to eq(nil)
        expect(stub).to have_been_requested.once
      end

      it 'handles missing value' do
        stub = stub_request(:get, generate_expected_url)
               .with(query: { '$filter': "displayName in ('MDM_Users')", '$select': 'id,displayName' })
               .to_return(body: { boo: :ba }.to_json)

        expect do
          trigger_action
        end.to raise_error(IPaaS::Job::FailJob, %(No value in Microsoft Graph API response: '{"boo":"ba"}'))
        expect(stub).to have_been_requested.once
      end
    end
  end
end
