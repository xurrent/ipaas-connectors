require 'spec_helper'

describe 'Checkmk Get Host Inventory Timestamps Action', :action do
  let(:connector_id) { '019d1f4e-7837-7a72-a0b5-df0ba9a5d44f' }
  let(:action_template_id) { '019db8d6-ceef-7783-b275-c6ee6a60662a' }

  let(:outbound_connection_config) do
    {
      domain: 'myserver.example.com',
      site_name: 'mysite',
      username: 'cmkadmin',
      password: make_secret_string('secret123'),
    }
  end

  let(:base_url) { 'https://myserver.example.com/mysite/check_mk' }
  let(:timestamps_url) { "#{base_url}/api/1.0/domain-types/host/collections/all" }
  let(:request_body) { { columns: %w[name mk_inventory_last] }.to_json }

  describe 'output_schema' do
    let(:schema) { action.output_schema.first }
    let(:hosts_field) { schema.field(:hosts) }

    it { expect(schema.field(:domain_type).type).to eq(:string) }
    it { expect(schema.field(:id).type).to eq(:string) }

    context 'hosts field' do
      it { expect(hosts_field.label).to eq('Hosts') }
      it { expect(hosts_field.type).to eq(:nested) }
      it { expect(hosts_field.array).to eq(true) }
      it { expect(hosts_field.field(:name).type).to eq(:string) }
      it { expect(hosts_field.field(:name).required).to be_truthy }
      it { expect(hosts_field.field(:mk_inventory_last).type).to eq(:integer) }
    end
  end

  describe 'run' do
    def trigger_action(input = {})
      run_action(input)
    end

    context 'with two hosts' do
      let!(:stub) do
        stub_request(:post, timestamps_url)
          .with(body: request_body, headers: { 'Content-Type' => 'application/json' })
          .to_return(body: {
            id: 'host',
            domainType: 'host',
            value: [
              {
                domainType: 'dict',
                id: 'cmk',
                title: 'cmk',
                extensions: { name: 'cmk', mk_inventory_last: 0 },
              },
              {
                domainType: 'dict',
                id: 'mysite',
                title: 'mysite',
                extensions: { name: 'mysite', mk_inventory_last: 1_776_179_669 },
              },
            ],
          }.to_json)
      end

      it 'flattens extensions into hosts list' do
        output = trigger_action
        expect(stub).to have_been_requested.once
        expect(output[:domain_type]).to eq('host')
        expect(output[:id]).to eq('host')
        expect(output[:hosts].size).to eq(2)
        expect(output[:hosts].first[:name]).to eq('cmk')
        expect(output[:hosts].first[:mk_inventory_last]).to eq(0)
        expect(output[:hosts].second[:name]).to eq('mysite')
        expect(output[:hosts].second[:mk_inventory_last]).to eq(1_776_179_669)
      end
    end

    context 'when API returns empty list' do
      before do
        stub_request(:post, timestamps_url)
          .with(body: request_body)
          .to_return(body: { id: 'host', domainType: 'host', value: [] }.to_json)
      end

      it 'returns empty hosts array' do
        output = trigger_action
        expect(output[:hosts]).to eq([])
      end
    end

    describe 'error handling' do
      context 'when API returns 401' do
        before { stub_request(:post, timestamps_url).to_return(status: 401, body: 'Unauthorized') }

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Checkmk authentication error: 401/) }
      end

      context 'when API returns 403' do
        before { stub_request(:post, timestamps_url).to_return(status: 403, body: 'Forbidden') }

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Checkmk authentication error: 403/) }
      end

      context 'when API returns 403 with problem+json' do
        before do
          stub_request(:post, timestamps_url)
            .to_return(
              status: 403,
              body: { status: 403, title: 'Forbidden', detail: 'Missing livestatus permission.' }.to_json,
              headers: { 'Content-Type' => 'application/problem+json' },
            )
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Forbidden - Missing livestatus permission/) }
      end

      context 'when API returns 500' do
        before { stub_request(:post, timestamps_url).to_return(status: 500, body: 'Internal Server Error') }

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Checkmk HTTP error: 500/) }
      end

      context 'when API returns 503' do
        before { stub_request(:post, timestamps_url).to_return(status: 503, body: 'Service Unavailable') }

        it 'reschedules with backoff' do
          Timecop.freeze do
            expect { trigger_action }
              .to raise_error(IPaaS::Job::RescheduleJob) { |e| expect(e.reschedule_after).to eq(60.seconds.from_now) }
          end
        end
      end

      context 'when response is invalid JSON' do
        before { stub_request(:post, timestamps_url).to_return(body: 'Not JSON') }

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /not valid JSON/) }
      end
    end
  end
end
