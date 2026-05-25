require 'spec_helper'

describe 'Checkmk Get Hosts Action', :action do
  let(:connector_id) { '019d1f4e-7837-7a72-a0b5-df0ba9a5d44f' }
  let(:action_template_id) { '019d1f4e-7837-7a35-bf23-ad7603241aca' }

  let(:outbound_connection_config) do
    {
      domain: 'myserver.example.com',
      site_name: 'mysite',
      username: 'cmkadmin',
      password: make_secret_string('secret123'),
    }
  end

  let(:base_url) { 'https://myserver.example.com/mysite/check_mk' }

  describe 'input_schema' do
    context 'effective_attributes field' do
      let(:field) { action.input_schema.field(:effective_attributes) }

      it { expect(field.label).to eq('Effective attributes') }
      it { expect(field.type).to eq(:boolean) }
      it { expect(field.visibility).to eq('optional') }
      it { expect(field.default).to eq(false) }
    end

    context 'include_links field' do
      let(:field) { action.input_schema.field(:include_links) }

      it { expect(field.label).to eq('Include links') }
      it { expect(field.type).to eq(:boolean) }
      it { expect(field.visibility).to eq('optional') }
      it { expect(field.default).to eq(false) }
    end

    context 'fields filter field' do
      let(:field) { action.input_schema.field(:fields) }

      it { expect(field.label).to eq('Fields filter') }
      it { expect(field.type).to eq(:string) }
      it { expect(field.visibility).to eq('optional') }
    end

    context 'hostnames field' do
      let(:field) { action.input_schema.field(:hostnames) }

      it { expect(field.label).to eq('Hostnames') }
      it { expect(field.type).to eq(:string) }
      it { expect(field.array).to eq(true) }
      it { expect(field.visibility).to eq('optional') }
    end

    context 'site field' do
      let(:field) { action.input_schema.field(:site) }

      it { expect(field.label).to eq('Site') }
      it { expect(field.type).to eq(:string) }
      it { expect(field.visibility).to eq('optional') }
    end
  end

  describe 'output_schema' do
    let(:schema) { action.output_schema.first }
    let(:hosts_field) { schema.field(:hosts) }

    context 'top-level fields' do
      it { expect(schema.field(:domain_type).type).to eq(:string) }
      it { expect(schema.field(:id).type).to eq(:string) }
      it { expect(schema.field(:title).type).to eq(:string) }
      it { expect(schema.field(:extensions).type).to eq(:hash) }
    end

    context 'hosts field' do
      it { expect(hosts_field.label).to eq('Hosts') }
      it { expect(hosts_field.type).to eq(:nested) }
      it { expect(hosts_field.array).to eq(true) }
    end

    context 'host identification' do
      it { expect(hosts_field.field(:id).type).to eq(:string) }
      it { expect(hosts_field.field(:id).required).to be_truthy }
      it { expect(hosts_field.field(:title).type).to eq(:string) }
      it { expect(hosts_field.field(:domain_type).type).to eq(:string) }
      it { expect(hosts_field.field(:members).type).to eq(:nested) }
    end

    context 'members folder_config' do
      let(:folder_config) { hosts_field.field(:members).field(:folder_config) }

      it { expect(folder_config.type).to eq(:nested) }
      it { expect(folder_config.field(:domain_type).type).to eq(:string) }
      it { expect(folder_config.field(:id).type).to eq(:string) }
      it { expect(folder_config.field(:title).type).to eq(:string) }
      it { expect(folder_config.field(:links).type).to eq(:nested) }
      it { expect(folder_config.field(:links).array).to eq(true) }

      context 'folder_config members' do
        let(:fc_members) { folder_config.field(:members) }

        it { expect(fc_members.type).to eq(:nested) }

        context 'hosts member' do
          let(:hosts_member) { fc_members.field(:hosts) }

          it { expect(hosts_member.type).to eq(:nested) }
          it { expect(hosts_member.field(:id).type).to eq(:string) }
          it { expect(hosts_member.field(:disabled_reason).type).to eq(:string) }
          it { expect(hosts_member.field(:invalid_reason).type).to eq(:string) }
          it { expect(hosts_member.field(:member_type).type).to eq(:string) }
          it { expect(hosts_member.field(:value).type).to eq(:nested) }
          it { expect(hosts_member.field(:value).array).to eq(true) }
          it { expect(hosts_member.field(:name).type).to eq(:string) }
          it { expect(hosts_member.field(:title).type).to eq(:string) }
        end

        context 'move member' do
          let(:move_member) { fc_members.field(:move) }

          it { expect(move_member.type).to eq(:nested) }
          it { expect(move_member.field(:id).type).to eq(:string) }
          it { expect(move_member.field(:disabled_reason).type).to eq(:string) }
          it { expect(move_member.field(:member_type).type).to eq(:string) }
          it { expect(move_member.field(:parameters).type).to eq(:hash) }
          it { expect(move_member.field(:name).type).to eq(:string) }
        end
      end

      context 'folder_config extensions' do
        let(:fc_extensions) { folder_config.field(:extensions) }

        it { expect(fc_extensions.type).to eq(:nested) }
        it { expect(fc_extensions.field(:path).type).to eq(:string) }
        it { expect(fc_extensions.field(:attributes).type).to eq(:hash) }
      end
    end

    context 'links' do
      let(:links) { hosts_field.field(:links) }

      it { expect(links.type).to eq(:nested) }
      it { expect(links.array).to eq(true) }
      it { expect(links.field(:domain_type).type).to eq(:string) }
      it { expect(links.field(:rel).type).to eq(:string) }
      it { expect(links.field(:href).type).to eq(:string) }
      it { expect(links.field(:method).type).to eq(:string) }
      it { expect(links.field(:type).type).to eq(:string) }
      it { expect(links.field(:title).type).to eq(:string) }
      it { expect(links.field(:body_params).type).to eq(:hash) }
    end

    context 'extensions' do
      let(:extensions) { hosts_field.field(:extensions) }

      it { expect(extensions.type).to eq(:nested) }
      it { expect(extensions.field(:folder).type).to eq(:string) }
      it { expect(extensions.field(:is_cluster).type).to eq(:boolean) }
      it { expect(extensions.field(:is_offline).type).to eq(:boolean) }
      it { expect(extensions.field(:cluster_nodes).type).to eq(:string) }
      it { expect(extensions.field(:cluster_nodes).array).to eq(true) }
      it { expect(extensions.field(:effective_attributes).type).to eq(:hash) }
    end

    context 'attributes' do
      let(:attributes) { hosts_field.field(:extensions).field(:attributes) }

      it { expect(attributes.type).to eq(:nested) }
      it { expect(attributes.remove_unmapped_fields).to be_falsey }
      it { expect(attributes.field(:ipaddress).type).to eq(:string) }
      it { expect(attributes.field(:ipv6address).type).to eq(:string) }
      it { expect(attributes.field(:alias).type).to eq(:string) }
      it { expect(attributes.field(:site).type).to eq(:string) }
      it { expect(attributes.field(:labels).type).to eq(:hash) }
      it { expect(attributes.field(:snmp_community).type).to eq(:hash) }
      it { expect(attributes.field(:network_scan).type).to eq(:hash) }
    end

    context 'meta_data' do
      let(:meta_data) { hosts_field.field(:extensions).field(:attributes).field(:meta_data) }

      it { expect(meta_data.type).to eq(:nested) }
      it { expect(meta_data.field(:created_at).type).to eq(:date_time) }
      it { expect(meta_data.field(:updated_at).type).to eq(:date_time) }
      it { expect(meta_data.field(:created_by).type).to eq(:string) }
    end

    context 'contactgroups' do
      let(:contactgroups) { hosts_field.field(:extensions).field(:attributes).field(:contactgroups) }

      it { expect(contactgroups.type).to eq(:nested) }
      it { expect(contactgroups.field(:groups).type).to eq(:string) }
      it { expect(contactgroups.field(:groups).array).to eq(true) }
      it { expect(contactgroups.field(:use).type).to eq(:boolean) }
    end

    context 'locked_by' do
      let(:locked_by) { hosts_field.field(:extensions).field(:attributes).field(:locked_by) }

      it { expect(locked_by.type).to eq(:nested) }
      it { expect(locked_by.field(:site_id).type).to eq(:string) }
      it { expect(locked_by.field(:program_id).type).to eq(:string) }
      it { expect(locked_by.field(:instance_id).type).to eq(:string) }
    end
  end

  describe 'run' do
    let(:hosts_url) { "#{base_url}/api/1.0/domain-types/host_config/collections/all" }

    def trigger_action(input = {})
      run_action(input)
    end

    context 'without input filters' do
      before do
        stub_request(:get, hosts_url)
          .with(query: {})
          .to_return(body: {
            value: [
              {
                id: 'monitoring-container',
                title: 'monitoring-container',
                extensions: {
                  folder: '/',
                  attributes: {
                    ipaddress: '127.0.0.1',
                    meta_data: { created_at: '2026-02-19T07:18:24Z' },
                  },
                },
              },
              {
                id: 'web-server-01',
                title: 'Web Server 01',
                extensions: {
                  folder: '/production',
                  attributes: {
                    ipaddress: '10.0.1.5',
                    meta_data: { created_at: '2026-03-01T12:00:00Z' },
                  },
                },
              },
            ],
          }.to_json)
      end

      it 'returns all hosts' do
        output = trigger_action
        hosts = output[:hosts]
        expect(hosts.size).to eq(2)
        expect(hosts.first[:id]).to eq('monitoring-container')
        expect(hosts.first[:extensions][:folder]).to eq('/')
        expect(hosts.first[:extensions][:attributes][:ipaddress]).to eq('127.0.0.1')
        expect(hosts.second[:id]).to eq('web-server-01')
      end
    end

    context 'with input filters' do
      before do
        stub_request(:get, hosts_url)
          .with(query: {
            'effective_attributes' => 'true',
            'include_links' => 'false',
            'fields' => '(value(id,title))',
            'site' => 'site1',
          })
          .to_return(body: { value: [] }.to_json)
      end

      it 'passes filters as query params' do
        trigger_action(
          effective_attributes: true,
          include_links: false,
          fields: '(value(id,title))',
          site: 'site1',
        )
      end
    end

    context 'with hostnames filter' do
      let!(:stub) do
        stub_request(:get, hosts_url)
          .with(query: 'hostnames=host1&hostnames=host2')
          .to_return(body: { value: [] }.to_json)
      end

      it 'encodes as explode-form array' do
        trigger_action(hostnames: %w[host1 host2])
        expect(stub).to have_been_requested.once
      end
    end

    context 'with hostnames and other filters combined' do
      let!(:stub) do
        stub_request(:get, hosts_url)
          .with(query: 'effective_attributes=false&include_links=false&hostnames=host1&hostnames=host2')
          .to_return(body: { value: [] }.to_json)
      end

      it 'encodes both standard params and exploded hostnames' do
        trigger_action(
          effective_attributes: false,
          include_links: false,
          hostnames: %w[host1 host2],
        )
        expect(stub).to have_been_requested.once
      end
    end

    context 'when API returns empty list' do
      before do
        stub_request(:get, hosts_url)
          .with(query: {})
          .to_return(body: { value: [] }.to_json)
      end

      it 'returns empty hosts array' do
        output = trigger_action
        expect(output[:hosts]).to eq([])
      end
    end

    describe 'error handling' do
      context 'when API returns 401' do
        before { stub_request(:get, hosts_url).to_return(status: 401, body: 'Unauthorized') }

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Checkmk authentication error: 401/) }
      end

      context 'when API returns 403' do
        before { stub_request(:get, hosts_url).to_return(status: 403, body: 'Forbidden') }

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Checkmk authentication error: 403/) }
      end

      context 'when API returns 403 with problem+json' do
        before do
          stub_request(:get, hosts_url)
            .to_return(
              status: 403,
              body: { status: 403, title: 'Forbidden',
                      detail: 'You do not have the permission for agent pairing.', }.to_json,
              headers: { 'Content-Type' => 'application/problem+json' },
            )
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Forbidden - You do not have the permission/) }
      end

      context 'when API returns 500' do
        before { stub_request(:get, hosts_url).to_return(status: 500, body: 'Internal Server Error') }

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Checkmk HTTP error: 500/) }
      end

      context 'when API returns 503' do
        before { stub_request(:get, hosts_url).to_return(status: 503, body: 'Service Unavailable') }

        it 'reschedules with backoff' do
          Timecop.freeze do
            expect { trigger_action }
              .to raise_error(IPaaS::Job::RescheduleJob) { |e| expect(e.reschedule_after).to eq(60.seconds.from_now) }
          end
        end
      end

      context 'when response is invalid JSON' do
        before { stub_request(:get, hosts_url).to_return(body: 'Not JSON') }

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /not valid JSON/) }
      end
    end
  end
end
