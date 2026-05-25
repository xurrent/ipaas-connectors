require 'spec_helper'

describe 'Datadog Fetch Hosts Action', :action do
  let(:connector_id) { '019ccf8a-e9c0-70ea-980c-ee7ed4fa2e80' }
  let(:action_template_id) { '019ccf8a-e9c0-7284-a577-29862f618496' }

  let(:region) { 'us1' }
  let(:hosts_url) { "#{DatadogConnector::REGIONS.dig(region, :url)}/api/v1/hosts" }

  let(:outbound_connection_config) do
    {
      credentials: {
        api_key: make_secret_string('test-api-key'),
        application_key: make_secret_string('test-application-key'),
      },
      region: region,
    }
  end

  let(:sample_gohai) do
    {
      cpu: {
        cache_size: '8192 KB',
        cpu_cores: '12',
        cpu_logical_processors: '12',
        family: '6',
        mhz: '4464.000',
        model: '191',
        model_name: 'Apple M4 Pro',
        stepping: '1',
        vendor_id: 'Apple',
      },
      filesystem: [
        {
          kb_size: '482797652',
          mounted_on: '/',
          name: '/dev/disk3s1s1',
        },
      ],
      memory: {
        swap_total: '2097152kB',
        total: '25769803776',
      },
      network: {
        interfaces: [
          {
            ipv4: ['10.1.161.39'],
            'ipv4-network': '10.1.160.0/23',
            ipv6: ['fe80::40af:b3ff:fe89:cd4'],
            'ipv6-network': 'fe80::/64',
            macaddress: 'a2:37:28:6f:98:0a',
            name: 'en0',
          },
        ],
        ipaddress: '10.1.161.39',
        ipaddressv6: 'fe80::40af:b3ff:fe89:cd4',
        macaddress: 'a2:37:28:6f:98:0a',
      },
      platform: {
        GOOARCH: 'arm64',
        GOOS: 'darwin',
        goV: '1.25.6',
        hardware_platform: 'Apple',
        hostname: 'Xurrent-FNX2Y3Q7FK',
        kernel_name: 'Darwin',
        kernel_release: '25.2.0',
        kernel_version: 'Darwin Kernel Version 25.2.0',
        machine: 'arm64',
        os: 'Darwin',
        processor: 'arm',
        pythonV: '3.13.11',
      },
    }
  end

  let(:sample_host) do
    {
      id: 123_145_537_712_914,
      name: 'Xurrent-FNX2Y3Q7FK',
      host_name: 'Xurrent-FNX2Y3Q7FK',
      aws_name: 'i-0abc123def4567890',
      aliases: ['Xurrent-FNX2Y3Q7FK'],
      apps: %w[agent ntp],
      sources: ['agent'],
      up: true,
      is_muted: false,
      mute_timeout: nil,
      last_reported_time: 1_770_967_634,
      tags_by_source: {
        'Datadog' => ['host:Xurrent-FNX2Y3Q7FK'],
      },
      meta: {
        'timezones' => ['IST'],
        'fbsdV' => ['', '', ''],
        'cpuCores' => 12,
        'pythonV' => '3.13.11',
        'nixV' => ['ubuntu', '18.04', ''],
        'network' => nil,
        'macV' => ['26.2', ['', '', ''], 'arm64'],
        'fips_mode' => false,
        'agent_checks' => [
          ['ntp', 'ntp', 'ntp:3c427a42a70bbf8', 'OK', '', '', []],
          ['network', 'network', 'network:4b0649b7e11f0772', 'OK', '', '', []],
        ],
        'install_method' => {
          'installer_version' => nil,
          'tool' => nil,
          'tool_version' => 'install_script_mac',
        },
        'agent_version' => '7.75.3',
        'logs_agent' => {
          'auto_multi_line_detection_enabled' => false,
          'transport' => '',
        },
        'socket-hostname' => 'Xurrent-FNX2Y3Q7FK',
        'platform' => 'darwin',
        'machine' => 'arm64',
        'processor' => 'Apple M4 Pro',
        'socket-fqdn' => 'Xurrent-FNX2Y3Q7FK',
        'agent_flavor' => 'agent',
        'host_id' => 123_145_537_712_914,
        'winV' => ['', nil, ''],
        'gohai' => sample_gohai.to_json,
      },
      metrics: {
        'cpu' => 8.087143,
        'iowait' => 0,
        'load' => 0.1817419,
      },
    }
  end

  describe 'input_schema' do
    context 'page_size field' do
      let(:field) { action.input_schema.field(:page_size) }

      it { expect(field.type).to eq(:integer) }
      it { expect(field.default).to eq(100) }
      it { expect(field.required).to be_falsey }
    end

    context 'from field' do
      let(:field) { action.input_schema.field(:from) }

      it { expect(field.type).to eq(:integer) }
      it { expect(field.required).to be_falsey }
    end

    context 'filter field' do
      let(:field) { action.input_schema.field(:filter) }

      it { expect(field.type).to eq(:string) }
      it { expect(field.required).to be_falsey }
      it { expect(field.hint).to eq('String to filter search results') }
    end

    context 'sort_field field' do
      let(:field) { action.input_schema.field(:sort_field) }

      it { expect(field.type).to eq(:string) }
      it { expect(field.required).to be_falsey }
      it { expect(field.hint).to eq('Field to sort hosts by') }
    end

    context 'sort_dir field' do
      let(:field) { action.input_schema.field(:sort_dir) }

      it { expect(field.type).to eq(:string) }
      it { expect(field.required).to be_falsey }

      it 'enumerates sort directions' do
        expect(field.enumeration.map { |e| e[:id] }).to contain_exactly('asc', 'desc')
      end
    end

    context 'include_muted_hosts_data field' do
      let(:field) { action.input_schema.field(:include_muted_hosts_data) }

      it { expect(field.type).to eq(:boolean) }
      it { expect(field.required).to be_falsey }
    end

    context 'include_hosts_metadata field' do
      let(:field) { action.input_schema.field(:include_hosts_metadata) }

      it { expect(field.type).to eq(:boolean) }
      it { expect(field.required).to be_falsey }
    end
  end

  describe 'output_schema' do
    let(:page_schema) { action.output_schema.first }
    let(:host_list_field) { page_schema.field(:host_list) }
    let(:tags_by_source_field) { host_list_field.field(:tags_by_source) }
    let(:meta_field) { host_list_field.field(:meta) }
    let(:gohai_field) { meta_field.field(:gohai) }
    let(:metrics_field) { host_list_field.field(:metrics) }

    context 'page level' do
      it { expect(page_schema.field(:total_matching).type).to eq(:integer) }
      it { expect(page_schema.field(:total_matching).required).to be_truthy }
      it { expect(page_schema.field(:total_returned).type).to eq(:integer) }
      it { expect(page_schema.field(:total_returned).required).to be_truthy }
      it { expect(page_schema.field(:has_next_page).type).to eq(:boolean) }
      it { expect(page_schema.field(:has_next_page).required).to be_truthy }
      it { expect(page_schema.field(:host_list).required).to be_falsey }
    end

    context 'host_list' do
      it { expect(host_list_field.array).to be_truthy }
      it { expect(host_list_field.type).to eq(:nested) }
      it { expect(host_list_field.remove_unmapped_fields).to be_truthy }
    end

    context 'host identification' do
      it { expect(host_list_field.field(:id).type).to eq(:integer) }
      it { expect(host_list_field.field(:aws_id).type).to eq(:integer) }
      it { expect(host_list_field.field(:name).type).to eq(:string) }
      it { expect(host_list_field.field(:host_name).type).to eq(:string) }
      it { expect(host_list_field.field(:aws_name).type).to eq(:string) }
    end

    context 'host array fields' do
      it { expect(host_list_field.field(:aliases).type).to eq(:string) }
      it { expect(host_list_field.field(:aliases).array).to be_truthy }
      it { expect(host_list_field.field(:apps).type).to eq(:string) }
      it { expect(host_list_field.field(:apps).array).to be_truthy }
      it { expect(host_list_field.field(:sources).type).to eq(:string) }
      it { expect(host_list_field.field(:sources).array).to be_truthy }
    end

    context 'host status' do
      it { expect(host_list_field.field(:up).type).to eq(:boolean) }
      it { expect(host_list_field.field(:is_muted).type).to eq(:boolean) }
      it { expect(host_list_field.field(:mute_timeout).type).to eq(:integer) }
      it { expect(host_list_field.field(:last_reported_time).type).to eq(:integer) }
    end

    context 'tags_by_source' do
      it { expect(tags_by_source_field.type).to eq(:hash) }
    end

    context 'meta field' do
      it { expect(meta_field.type).to eq(:nested) }
      it { expect(meta_field.remove_unmapped_fields).to be_truthy }
      it { expect(meta_field.field(:agent_checks).type).to eq(:any_item_type) }
      it { expect(meta_field.field(:agent_checks).array).to be_truthy }
      it { expect(meta_field.field(:agent_flavor).type).to eq(:string) }
      it { expect(meta_field.field(:agent_version).type).to eq(:string) }
      it { expect(meta_field.field(:cpu_cores).type).to eq(:integer) }
      it { expect(meta_field.field(:fbsd_v).type).to eq(:string) }
      it { expect(meta_field.field(:fbsd_v).array).to be_truthy }
      it { expect(meta_field.field(:host_id).type).to eq(:integer) }
      it { expect(meta_field.field(:logs_agent).type).to eq(:nested) }
      it { expect(meta_field.field(:logs_agent).remove_unmapped_fields).to be_truthy }
      it { expect(meta_field.field(:mac_v).type).to eq(:any_item_type) }
      it { expect(meta_field.field(:mac_v).array).to be_truthy }
      it { expect(meta_field.field(:python_v).type).to eq(:string) }
      it { expect(meta_field.field(:machine).type).to eq(:string) }
      it { expect(meta_field.field(:network).type).to eq(:nested) }
      it { expect(meta_field.field(:network).remove_unmapped_fields).to be_truthy }
      it { expect(meta_field.field(:nix_v).type).to eq(:string) }
      it { expect(meta_field.field(:nix_v).array).to be_truthy }
      it { expect(meta_field.field(:platform).type).to eq(:string) }
      it { expect(meta_field.field(:processor).type).to eq(:string) }
      it { expect(meta_field.field(:install_method).type).to eq(:nested) }
      it { expect(meta_field.field(:socket_hostname).type).to eq(:string) }
      it { expect(meta_field.field(:socket_fqdn).type).to eq(:string) }
      it { expect(meta_field.field(:timezones).type).to eq(:string) }
      it { expect(meta_field.field(:timezones).array).to be_truthy }
      it { expect(meta_field.field(:win_v).type).to eq(:string) }
      it { expect(meta_field.field(:win_v).array).to be_truthy }
      it { expect(meta_field.field(:network).field(:network_id).type).to eq(:string) }
      it { expect(meta_field.field(:network).field(:public_ipv4).type).to eq(:string) }
    end

    context 'gohai field' do
      it { expect(gohai_field.type).to eq(:nested) }
      it { expect(gohai_field.remove_unmapped_fields).to be_truthy }
      it { expect(gohai_field.field(:cpu).type).to eq(:nested) }
      it { expect(gohai_field.field(:cpu).remove_unmapped_fields).to be_truthy }
      it { expect(gohai_field.field(:cpu).field(:cache_size).type).to eq(:string) }
      it { expect(gohai_field.field(:cpu).field(:family).type).to eq(:string) }
      it { expect(gohai_field.field(:cpu).field(:mhz).type).to eq(:string) }
      it { expect(gohai_field.field(:cpu).field(:model).type).to eq(:string) }
      it { expect(gohai_field.field(:cpu).field(:stepping).type).to eq(:string) }
      it { expect(gohai_field.field(:cpu).field(:vendor_id).type).to eq(:string) }
      it { expect(gohai_field.field(:filesystem).type).to eq(:nested) }
      it { expect(gohai_field.field(:filesystem).array).to be_truthy }
      it { expect(gohai_field.field(:memory).type).to eq(:nested) }
      it { expect(gohai_field.field(:network).type).to eq(:nested) }
      it { expect(gohai_field.field(:network).field(:interfaces).type).to eq(:nested) }
      it { expect(gohai_field.field(:network).field(:interfaces).array).to be_truthy }
      it { expect(gohai_field.field(:network).field(:interfaces).remove_unmapped_fields).to be_truthy }
      it { expect(gohai_field.field(:network).field(:interfaces).field(:ipv4).type).to eq(:any_value_type) }
      it { expect(gohai_field.field(:network).field(:interfaces).field(:ipv4_network).type).to eq(:string) }
      it { expect(gohai_field.field(:network).field(:interfaces).field(:ipv6).type).to eq(:any_value_type) }
      it { expect(gohai_field.field(:network).field(:interfaces).field(:ipv6_network).type).to eq(:string) }
      it { expect(gohai_field.field(:platform).type).to eq(:nested) }
      it { expect(gohai_field.field(:platform).field(:gooarch).type).to eq(:string) }
      it { expect(gohai_field.field(:platform).field(:goos).type).to eq(:string) }
      it { expect(gohai_field.field(:platform).field(:go_v).type).to eq(:string) }
      it { expect(gohai_field.field(:platform).field(:python_v).type).to eq(:string) }
    end

    context 'metrics field' do
      it { expect(metrics_field.type).to eq(:nested) }
      it { expect(metrics_field.remove_unmapped_fields).to be_truthy }
      it { expect(metrics_field.field(:cpu).type).to eq(:float) }
      it { expect(metrics_field.field(:iowait).type).to eq(:float) }
      it { expect(metrics_field.field(:load).type).to eq(:float) }
    end
  end

  describe 'iteration_state_schema' do
    it { expect(action.iteration_state_schema.field(:offset).type).to eq(:integer) }
  end

  describe 'run' do
    context 'when fetch is successful' do
      it 'fetches hosts with correct headers' do
        stub = stub_request(:get, hosts_url)
               .with(
                 query: { start: '0', count: '100' },
                 headers: {
                   'DD-API-KEY' => 'test-api-key',
                   'DD-APPLICATION-KEY' => 'test-application-key',
                   'Content-Type' => 'application/json',
                 }
               )
               .to_return(
                 status: 200,
                 body: {
                   total_matching: 1,
                   total_returned: 1,
                   host_list: [sample_host],
                 }.to_json
               )

        output = run_action({})

        expect(output[:total_matching]).to eq(1)
        expect(output[:total_returned]).to eq(1)
        expect(output[:host_list].first[:name]).to eq('Xurrent-FNX2Y3Q7FK')
        expect(stub).to have_been_requested.once
      end

      it 'returns host fields' do
        stub_request(:get, hosts_url)
          .with(query: { start: '0', count: '100' })
          .to_return(status: 200, body: {
            total_matching: 1,
            total_returned: 1,
            host_list: [sample_host],
          }.to_json)

        output = run_action({})
        host = output[:host_list].first

        expect(host[:id]).to eq(123_145_537_712_914)
        expect(host[:host_name]).to eq('Xurrent-FNX2Y3Q7FK')
        expect(host[:aws_name]).to eq('i-0abc123def4567890')
        expect(host[:aliases]).to eq(['Xurrent-FNX2Y3Q7FK'])
        expect(host[:apps]).to eq(%w[agent ntp])
        expect(host[:up]).to eq(true)
        expect(host[:tags_by_source]).to be_a(Hash)
        expect(host[:meta]).to be_a(Hash)
        expect(host[:metrics]).to be_a(Hash)
        expect(host[:meta][:cpu_cores]).to eq(12)
        expect(host[:meta][:socket_hostname]).to eq('Xurrent-FNX2Y3Q7FK')
      end

      it 'parses stringified gohai' do
        stub_request(:get, hosts_url)
          .with(query: { start: '0', count: '100' })
          .to_return(status: 200, body: {
            total_matching: 1,
            total_returned: 1,
            host_list: [sample_host],
          }.to_json)

        output = run_action({})
        meta = output[:host_list].first[:meta]

        expect(meta[:gohai]).to be_a(Hash)
        expect(meta[:gohai][:cpu][:model_name]).to eq('Apple M4 Pro')
        expect(meta[:gohai][:cpu][:cache_size]).to eq('8192 KB')
        expect(meta[:gohai][:cpu][:family]).to eq('6')
        expect(meta[:gohai][:memory][:total]).to eq('25769803776')
        expect(meta[:gohai][:network][:interfaces].first[:ipv4]).to eq(['10.1.161.39'])
        expect(meta[:gohai][:network][:interfaces].first[:ipv4_network]).to eq('10.1.160.0/23')
        expect(meta[:gohai][:platform][:hardware_platform]).to eq('Apple')
        expect(meta[:gohai][:platform][:gooarch]).to eq('arm64')
        expect(meta[:gohai][:platform][:goos]).to eq('darwin')
        expect(meta[:gohai][:platform][:go_v]).to eq('1.25.6')
      end

      it 'preserves nullable install_method' do
        stub_request(:get, hosts_url)
          .with(query: { start: '0', count: '100' })
          .to_return(status: 200, body: {
            total_matching: 1,
            total_returned: 1,
            host_list: [sample_host],
          }.to_json)

        output = run_action({})
        install_method = output[:host_list].first[:meta][:install_method]

        expect(install_method[:installer_version]).to be_nil
        expect(install_method[:tool]).to be_nil
        expect(install_method[:tool_version]).to eq('install_script_mac')
      end

      it 'returns nullable meta fields' do
        stub_request(:get, hosts_url)
          .with(query: { start: '0', count: '100' })
          .to_return(status: 200, body: {
            total_matching: 1,
            total_returned: 1,
            host_list: [sample_host],
          }.to_json)

        output = run_action({})
        meta = output[:host_list].first[:meta]

        expect(meta[:timezones]).to eq(['IST'])
        expect(meta[:fbsd_v]).to eq(['', '', ''])
        expect(meta[:nix_v]).to eq(['ubuntu', '18.04', ''])
        expect(meta[:mac_v]).to eq(['26.2', ['', '', ''], 'arm64'])
        expect(meta[:network]).to be_nil
        expect(meta[:agent_checks].first).to eq(['ntp', 'ntp', 'ntp:3c427a42a70bbf8', 'OK', '', '', []])
        expect(meta[:logs_agent][:auto_multi_line_detection_enabled]).to eq(false)
        expect(meta[:logs_agent][:transport]).to eq('')
        expect(meta[:agent_flavor]).to eq('agent')
        expect(meta[:host_id]).to eq(123_145_537_712_914)
        expect(meta[:win_v]).to eq(['', nil, ''])
        expect(meta[:python_v]).to eq('3.13.11')
        expect(meta[:socket_fqdn]).to eq('Xurrent-FNX2Y3Q7FK')
      end

      context 'with unmapped fields' do
        it 'strips them from nested objects' do
          host_with_extra_fields = sample_host.deep_dup
          host_with_extra_fields[:unexpected] = 'drop me'
          host_with_extra_fields[:meta]['fips_mode'] = false
          host_with_extra_fields[:meta]['logs_agent']['experimental'] = true
          host_with_extra_fields[:meta]['network'] = {
            'network-id' => 'vpc-1234567890abcdef0',
            'public-ipv4' => '203.0.113.10',
            'private-ipv4' => '10.0.0.1',
          }

          gohai_with_extra_fields = sample_gohai.deep_dup
          gohai_with_extra_fields[:extra_top] = 'drop me'
          gohai_with_extra_fields[:cpu][:bogus] = 'drop me'
          gohai_with_extra_fields[:filesystem].first[:uuid] = 'drop me'
          gohai_with_extra_fields[:memory][:available] = 'drop me'
          gohai_with_extra_fields[:network][:extra] = 'drop me'
          gohai_with_extra_fields[:network][:interfaces].first[:mtu] = '1500'
          gohai_with_extra_fields[:platform][:arch] = 'drop me'
          host_with_extra_fields[:meta]['gohai'] = gohai_with_extra_fields.to_json
          host_with_extra_fields[:metrics]['extra'] = 123

          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 200, body: {
              total_matching: 1,
              total_returned: 1,
              host_list: [host_with_extra_fields],
            }.to_json)

          output = run_action({})
          host = output[:host_list].first
          meta = host[:meta]
          gohai = meta[:gohai]

          expect(host).not_to have_key(:unexpected)
          expect(meta).not_to have_key(:fips_mode)
          expect(meta[:logs_agent]).not_to have_key(:experimental)
          expect(meta[:network]).not_to have_key(:private_ipv4)
          expect(gohai).not_to have_key(:extra_top)
          expect(gohai[:cpu]).not_to have_key(:bogus)
          expect(gohai[:filesystem].first).not_to have_key(:uuid)
          expect(gohai[:memory]).not_to have_key(:available)
          expect(gohai[:network]).not_to have_key(:extra)
          expect(gohai[:network][:interfaces].first).not_to have_key(:mtu)
          expect(gohai[:platform]).not_to have_key(:arch)
          expect(host[:metrics]).not_to have_key(:extra)
        end
      end

      context 'with multiple tag sources' do
        it 'preserves tag arrays' do
          host_with_aws_tags = sample_host.deep_dup
          host_with_aws_tags[:tags_by_source]['AWS'] = ['instance-id:i-0abc123def4567890']

          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 200, body: {
              total_matching: 1,
              total_returned: 1,
              host_list: [host_with_aws_tags],
            }.to_json)

          output = run_action({})
          tags_by_source = output[:host_list].first[:tags_by_source]

          expect(tags_by_source['Datadog']).to eq(['host:Xurrent-FNX2Y3Q7FK'])
          expect(tags_by_source['AWS']).to eq(['instance-id:i-0abc123def4567890'])
        end
      end

      context 'with structured network meta' do
        it 'returns network fields' do
          host_with_network = sample_host.deep_dup
          host_with_network[:meta]['network'] = {
            'network-id' => 'vpc-1234567890abcdef0',
            'public-ipv4' => '203.0.113.10',
          }

          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 200, body: {
              total_matching: 1,
              total_returned: 1,
              host_list: [host_with_network],
            }.to_json)

          output = run_action({})
          network = output[:host_list].first[:meta][:network]

          expect(network[:network_id]).to eq('vpc-1234567890abcdef0')
          expect(network[:public_ipv4]).to eq('203.0.113.10')
        end
      end

      context 'with nil metric values' do
        it 'allows nil' do
          host_with_nil_metrics = sample_host.deep_dup
          host_with_nil_metrics[:metrics] = {
            'cpu' => nil,
            'iowait' => nil,
            'load' => nil,
          }

          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 200, body: {
              total_matching: 1,
              total_returned: 1,
              host_list: [host_with_nil_metrics],
            }.to_json)

          output = run_action({})
          metrics = output[:host_list].first[:metrics]

          expect(metrics[:cpu]).to be_nil
          expect(metrics[:iowait]).to be_nil
          expect(metrics[:load]).to be_nil
        end
      end

      context 'with integer load value' do
        it 'coerces to float' do
          host_with_integer_load = sample_host.deep_dup
          host_with_integer_load[:metrics]['load'] = 0

          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 200, body: {
              total_matching: 1,
              total_returned: 1,
              host_list: [host_with_integer_load],
            }.to_json)

          output = run_action({})
          metrics = output[:host_list].first[:metrics]

          expect(metrics[:load]).to eq(0.0)
        end
      end

      context 'with string gohai interfaces' do
        it 'accepts string values' do
          host_with_string_interface_values = sample_host.deep_dup
          gohai_with_string_interface_values = sample_gohai.deep_dup
          gohai_with_string_interface_values[:network][:interfaces].first[:ipv4] = '10.1.161.39'
          gohai_with_string_interface_values[:network][:interfaces].first[:ipv6] = 'fe80::40af:b3ff:fe89:cd4'
          host_with_string_interface_values[:meta]['gohai'] = gohai_with_string_interface_values.to_json

          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 200, body: {
              total_matching: 1,
              total_returned: 1,
              host_list: [host_with_string_interface_values],
            }.to_json)

          output = run_action({})
          interface = output[:host_list].first[:meta][:gohai][:network][:interfaces].first

          expect(interface[:ipv4]).to eq('10.1.161.39')
          expect(interface[:ipv6]).to eq('fe80::40af:b3ff:fe89:cd4')
        end
      end

      context 'when gohai is nil' do
        it 'returns nil gohai' do
          host_without_gohai = sample_host.deep_dup
          host_without_gohai[:meta].delete('gohai')

          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 200, body: {
              total_matching: 1,
              total_returned: 1,
              host_list: [host_without_gohai],
            }.to_json)

          output = run_action({})
          meta = output[:host_list].first[:meta]

          expect(meta[:gohai]).to be_nil
        end
      end

      context 'when gohai is invalid JSON' do
        it 'fails the job' do
          host_with_bad_gohai = sample_host.deep_dup
          host_with_bad_gohai[:meta]['gohai'] = 'not valid json'

          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 200, body: {
              total_matching: 1,
              total_returned: 1,
              host_list: [host_with_bad_gohai],
            }.to_json)

          expect { run_action({}) }
            .to raise_error(IPaaS::Job::FailJob, /Failed to parse gohai JSON/)
        end
      end

      context 'when no hosts exist' do
        it 'returns empty host_list' do
          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 200, body: {
              total_matching: 0,
              total_returned: 0,
              host_list: [],
            }.to_json)

          output = run_action({})

          expect(output[:total_matching]).to eq(0)
          expect(output[:has_next_page]).to eq(false)
          expect(output[:host_list]).to eq([])
        end
      end

      context 'with from parameter' do
        it 'passes epoch seconds in query' do
          stub = stub_request(:get, hosts_url)
                 .with(query: { start: '0', count: '100', from: '1771410150' })
                 .to_return(status: 200, body: {
                   total_matching: 1,
                   total_returned: 1,
                   host_list: [sample_host],
                 }.to_json)

          run_action({ from: 1_771_410_150 })

          expect(stub).to have_been_requested.once
        end
      end

      context 'with custom page_size' do
        it 'uses specified count' do
          stub = stub_request(:get, hosts_url)
                 .with(query: { start: '0', count: '500' })
                 .to_return(status: 200, body: {
                   total_matching: 1,
                   total_returned: 1,
                   host_list: [sample_host],
                 }.to_json)

          run_action({ page_size: 500 })

          expect(stub).to have_been_requested.once
        end
      end

      context 'with filter parameter' do
        it 'passes filter in query' do
          stub = stub_request(:get, hosts_url)
                 .with(query: { start: '0', count: '100', filter: 'my-host' })
                 .to_return(status: 200, body: {
                   total_matching: 1,
                   total_returned: 1,
                   host_list: [sample_host],
                 }.to_json)

          run_action({ filter: 'my-host' })

          expect(stub).to have_been_requested.once
        end
      end

      context 'with sort parameters' do
        it 'passes sort_field and sort_dir in query' do
          stub = stub_request(:get, hosts_url)
                 .with(query: { start: '0', count: '100', sort_field: 'name', sort_dir: 'asc' })
                 .to_return(status: 200, body: {
                   total_matching: 1,
                   total_returned: 1,
                   host_list: [sample_host],
                 }.to_json)

          run_action({ sort_field: 'name', sort_dir: 'asc' })

          expect(stub).to have_been_requested.once
        end
      end

      context 'with include flags' do
        it 'passes include_muted_hosts_data and include_hosts_metadata in query' do
          stub = stub_request(:get, hosts_url)
                 .with(query: {
                   start: '0', count: '100',
                   include_muted_hosts_data: 'true',
                   include_hosts_metadata: 'true',
                 })
                 .to_return(status: 200, body: {
                   total_matching: 1,
                   total_returned: 1,
                   host_list: [sample_host],
                 }.to_json)

          run_action({ include_muted_hosts_data: true, include_hosts_metadata: true })

          expect(stub).to have_been_requested.once
        end
      end
    end

    context 'when paginating' do
      context 'when more pages available' do
        it 'sets iteration state' do
          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 200, body: {
              total_matching: 200,
              total_returned: 100,
              host_list: Array.new(100) { sample_host },
            }.to_json)

          expect(action(page_size: 100))
            .to receive(:iteration_state_value=)
            .with({ offset: 100 })
            .and_call_original

          output = run_action({ page_size: 100 })
          expect(output[:has_next_page]).to eq(true)
        end
      end

      context 'when on last page' do
        it 'clears iteration state' do
          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 200, body: {
              total_matching: 50,
              total_returned: 50,
              host_list: Array.new(50) { sample_host },
            }.to_json)

          expect(action(page_size: 100))
            .to receive(:iteration_state_value=)
            .with(nil)
            .and_call_original

          output = run_action({ page_size: 100 })
          expect(output[:has_next_page]).to eq(false)
        end
      end

      context 'with existing offset' do
        it 'uses offset in query params' do
          stub = stub_request(:get, hosts_url)
                 .with(query: { start: '100', count: '100' })
                 .to_return(status: 200, body: {
                   total_matching: 150,
                   total_returned: 50,
                   host_list: Array.new(50) { sample_host },
                 }.to_json)

          action(page_size: 100).send(:iteration_state_value=, { offset: 100 })
          run_action({ page_size: 100 })

          expect(stub).to have_been_requested.once
        end
      end

      context 'when total equals fetched' do
        it 'returns has_next_page false' do
          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 200, body: {
              total_matching: 100,
              total_returned: 100,
              host_list: Array.new(100) { sample_host },
            }.to_json)

          output = run_action({ page_size: 100 })
          expect(output[:has_next_page]).to eq(false)
        end
      end

      context 'when host_list is empty' do
        it 'returns has_next_page false' do
          stub_request(:get, hosts_url)
            .with(query: { start: '100', count: '100' })
            .to_return(status: 200, body: {
              total_matching: 100,
              total_returned: 0,
              host_list: [],
            }.to_json)

          action(page_size: 100).send(:iteration_state_value=, { offset: 100 })
          output = run_action({ page_size: 100 })
          expect(output[:has_next_page]).to eq(false)
        end
      end
    end

    context 'when an error occurs' do
      it 'fails on 400 bad request' do
        stub_request(:get, hosts_url)
          .with(query: { start: '0', count: '100' })
          .to_return(
            status: 400,
            body: { errors: ['Bad Request'] }.to_json
          )

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /Bad Request/)
      end

      it 'fails on 401 auth error' do
        stub_request(:get, hosts_url)
          .with(query: { start: '0', count: '100' })
          .to_return(
            status: 401,
            body: { errors: ['Invalid API key'] }.to_json
          )

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /authentication error.*Invalid API key/)
      end

      it 'fails on 403 forbidden' do
        stub_request(:get, hosts_url)
          .with(query: { start: '0', count: '100' })
          .to_return(
            status: 403,
            body: { errors: ['Forbidden'] }.to_json
          )

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /forbidden error.*Forbidden/)
      end

      it 'backs off on 429 rate limit' do
        stub_request(:get, hosts_url)
          .with(query: { start: '0', count: '100' })
          .to_return(status: 429, headers: { 'X-RateLimit-Reset' => '60' })

        Timecop.freeze do
          expect { run_action({}) }
            .to raise_error(IPaaS::Job::RescheduleJob) do |error|
              expect(error.reschedule_after).to eq(60.seconds.from_now)
            end
        end
      end

      it 'backs off on 500 server error' do
        stub_request(:get, hosts_url)
          .with(query: { start: '0', count: '100' })
          .to_return(status: 500, headers: { 'X-RateLimit-Reset' => '30' })

        Timecop.freeze do
          expect { run_action({}) }
            .to raise_error(IPaaS::Job::RescheduleJob, /Datadog API not available/) do |error|
              expect(error.reschedule_after).to eq(30.seconds.from_now)
            end
        end
      end

      it 'backs off on 503 unavailable' do
        stub_request(:get, hosts_url)
          .with(query: { start: '0', count: '100' })
          .to_return(status: 503)

        Timecop.freeze do
          expect { run_action({}) }
            .to raise_error(IPaaS::Job::RescheduleJob, /Datadog API not available/) do |error|
              expect(error.reschedule_after).to eq(60.seconds.from_now)
            end
        end
      end

      context 'without X-RateLimit-Reset header' do
        it 'defaults to 60 seconds' do
          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 502)

          Timecop.freeze do
            expect { run_action({}) }
              .to raise_error(IPaaS::Job::RescheduleJob) do |error|
                expect(error.reschedule_after).to eq(60.seconds.from_now)
              end
          end
        end
      end

      context 'with non-numeric X-RateLimit-Reset header' do
        it 'defaults to 60 seconds' do
          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 429, headers: { 'X-RateLimit-Reset' => 'abc' })

          Timecop.freeze do
            expect { run_action({}) }
              .to raise_error(IPaaS::Job::RescheduleJob) do |error|
                expect(error.reschedule_after).to eq(60.seconds.from_now)
              end
          end
        end
      end

      context 'with zero X-RateLimit-Reset header' do
        it 'defaults to 60 seconds' do
          stub_request(:get, hosts_url)
            .with(query: { start: '0', count: '100' })
            .to_return(status: 429, headers: { 'X-RateLimit-Reset' => '0' })

          Timecop.freeze do
            expect { run_action({}) }
              .to raise_error(IPaaS::Job::RescheduleJob) do |error|
                expect(error.reschedule_after).to eq(60.seconds.from_now)
              end
          end
        end
      end

      it 'fails on invalid JSON response' do
        stub_request(:get, hosts_url)
          .with(query: { start: '0', count: '100' })
          .to_return(status: 200, body: 'not json')

        expect { run_action({}) }
          .to raise_error(IPaaS::Job::FailJob, /HTTP error/)
      end
    end
  end
end
