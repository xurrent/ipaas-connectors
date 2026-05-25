require 'spec_helper'

describe 'Checkmk Get Host Inventory Action', :action do
  let(:connector_id) { '019d1f4e-7837-7a72-a0b5-df0ba9a5d44f' }
  let(:action_template_id) { '019d1f4e-7837-73ad-8dc1-67280058d2c5' }

  let(:outbound_connection_config) do
    {
      domain: 'myserver.example.com',
      site_name: 'mysite',
      username: 'cmkadmin',
      password: make_secret_string('secret123'),
    }
  end

  let(:base_url) { 'https://myserver.example.com/mysite/check_mk' }
  let(:inventory_url) { "#{base_url}/host_inv_api.py" }

  describe 'input_schema' do
    context 'host_names field' do
      let(:field) { action.input_schema.field(:host_names) }

      it { expect(field.label).to eq('Host names') }
      it { expect(field.type).to eq(:string) }
      it { expect(field.array).to eq(true) }
      it { expect(field.required).to be_truthy }
    end

    context 'batch_size field' do
      let(:field) { action.input_schema.field(:batch_size) }

      it { expect(field.label).to eq('Batch size') }
      it { expect(field.type).to eq(:integer) }
      it { expect(field.required).to be_falsey }
      it { expect(field.visibility).to eq('optional') }
      it { expect(field.min).to eq(1) }
      it { expect(field.max).to eq(50) }
      it { expect(field.default).to eq(50) }
    end
  end

  describe 'output_schema' do
    it { expect(action.output_schema.map(&:reference)).to contain_exactly('page') }

    describe 'page schema' do
      let(:page_schema) { action.output_schema.first }

      context 'page level' do
        it { expect(page_schema.field(:has_next_page).type).to eq(:boolean) }
        it { expect(page_schema.field(:has_next_page).required).to be_truthy }
      end

      context 'hosts field' do
        let(:hosts_field) { page_schema.field(:hosts) }

        it { expect(hosts_field.label).to eq('Hosts') }
        it { expect(hosts_field.type).to eq(:nested) }
        it { expect(hosts_field.array).to eq(true) }

        context 'hostname' do
          let(:field) { hosts_field.field(:hostname) }

          it { expect(field.label).to eq('Hostname') }
          it { expect(field.type).to eq(:string) }
          it { expect(field.required).to be_truthy }
        end

        context 'inventory' do
          let(:inventory) { hosts_field.field(:inventory) }

          it { expect(inventory.label).to eq('Inventory') }
          it { expect(inventory.type).to eq(:nested) }
          it { expect(inventory.field(:attributes).type).to eq(:hash) }
          it { expect(inventory.field(:table).type).to eq(:hash) }

          context 'top-level nodes' do
            let(:nodes) { inventory.field(:nodes) }

            it { expect(nodes.type).to eq(:nested) }
            it { expect(nodes.remove_unmapped_fields).to be_falsey }
          end
        end
      end

      context 'hardware inventory' do
        let(:hardware) do
          page_schema.field(:hosts).field(:inventory).field(:nodes).field(:hardware)
        end
        let(:hw_nodes) { hardware.field(:nodes) }

        it { expect(hardware.field(:attributes).type).to eq(:hash) }
        it { expect(hardware.field(:table).type).to eq(:hash) }
        it { expect(hw_nodes.remove_unmapped_fields).to be_falsey }

        context 'system' do
          let(:system) { hw_nodes.field(:system) }
          let(:pairs) { system.field(:attributes).field(:pairs) }

          it { expect(pairs.field(:manufacturer).type).to eq(:string) }
          it { expect(pairs.field(:model).type).to eq(:string) }
          it { expect(pairs.remove_unmapped_fields).to be_falsey }
          it { expect(system.field(:nodes).type).to eq(:hash) }
          it { expect(system.field(:table).type).to eq(:hash) }
        end

        context 'cpu' do
          let(:cpu) { hw_nodes.field(:cpu) }
          let(:pairs) { cpu.field(:attributes).field(:pairs) }

          it { expect(pairs.field(:cores).type).to eq(:integer) }
          it { expect(pairs.remove_unmapped_fields).to be_falsey }
          it { expect(cpu.field(:nodes).type).to eq(:hash) }
          it { expect(cpu.field(:table).type).to eq(:hash) }
        end

        context 'memory' do
          let(:memory) { hw_nodes.field(:memory) }
          let(:pairs) { memory.field(:attributes).field(:pairs) }

          it { expect(pairs.field(:total_ram_usable).type).to eq(:integer) }
          it { expect(memory.field(:nodes).type).to eq(:hash) }
          it { expect(memory.field(:table).type).to eq(:hash) }
        end
      end

      context 'software inventory' do
        let(:software) do
          page_schema.field(:hosts).field(:inventory).field(:nodes).field(:software)
        end
        let(:sw_nodes) { software.field(:nodes) }

        it { expect(software.field(:attributes).type).to eq(:hash) }
        it { expect(software.field(:table).type).to eq(:hash) }
        it { expect(sw_nodes.remove_unmapped_fields).to be_falsey }

        context 'os' do
          let(:os) { sw_nodes.field(:os) }
          let(:pairs) { os.field(:attributes).field(:pairs) }

          it { expect(pairs.field(:name).type).to eq(:string) }
          it { expect(pairs.field(:version).type).to eq(:string) }
          it { expect(os.field(:nodes).type).to eq(:hash) }
          it { expect(os.field(:table).type).to eq(:hash) }
        end

        context 'applications' do
          let(:applications) { sw_nodes.field(:applications) }

          it { expect(applications.field(:attributes).type).to eq(:hash) }
          it { expect(applications.field(:table).type).to eq(:hash) }
          it { expect(applications.field(:nodes).remove_unmapped_fields).to be_falsey }
        end
      end

      context 'networking' do
        let(:networking) do
          page_schema.field(:hosts).field(:inventory).field(:nodes).field(:networking)
        end
        let(:net_pairs) { networking.field(:attributes).field(:pairs) }

        it { expect(net_pairs.field(:hostname).type).to eq(:string) }
        it { expect(net_pairs.remove_unmapped_fields).to be_falsey }
        it { expect(networking.field(:table).type).to eq(:hash) }
        it { expect(networking.field(:nodes).remove_unmapped_fields).to be_falsey }

        context 'interfaces' do
          let(:interfaces) { networking.field(:nodes).field(:interfaces) }

          it { expect(interfaces.field(:attributes).type).to eq(:hash) }
          it { expect(interfaces.field(:nodes).type).to eq(:hash) }
        end
      end
    end
  end

  describe 'iteration_state_schema' do
    context 'offset field' do
      let(:field) { action.iteration_state_schema.field(:offset) }

      it { expect(field.label).to eq('Offset') }
      it { expect(field.type).to eq(:integer) }
      it { expect(field.required).to be_truthy }
      it { expect(field.default).to eq(0) }
    end
  end

  describe 'run' do
    def inventory_node(nodes: {}, **pairs)
      { Attributes: pairs.any? ? { Pairs: pairs } : {}, Nodes: nodes, Table: {} }
    end

    def hardware_node
      inventory_node(nodes: {
        system: inventory_node(manufacturer: 'Amazon EC2', model: 'm5a.2xlarge'),
        cpu: inventory_node(cores: 4),
        memory: inventory_node(total_ram_usable: 33_688_150_016),
      })
    end

    def software_node
      inventory_node(nodes: {
        os: inventory_node(name: 'Microsoft Windows Server 2019 Datacenter'),
      })
    end

    def interface_row
      { index: 1, description: 'eth0', alias: 'Primary', speed: 10_000_000_000,
        oper_status: 1, phys_address: '00:11:22:33:44:55', port_type: 6, available: true, }
    end

    def interfaces_table_node
      {
        Attributes: {},
        Nodes: {},
        Table: { KeyColumns: ['index'], Rows: [interface_row] },
      }
    end

    def networking_node
      {
        Attributes: { Pairs: { hostname: 'host1', total_interfaces: 2 } },
        Nodes: { interfaces: interfaces_table_node },
        Table: {},
      }
    end

    def host_inventory_tree
      inventory_node(nodes: { hardware: hardware_node, software: software_node, networking: networking_node })
    end

    def inventory_response(*hostnames)
      { result_code: 0, result: hostnames.index_with { |_h| host_inventory_tree } }
    end

    def trigger_action(host_names: ['host1'], batch_size: nil)
      run_action({ host_names: host_names, batch_size: batch_size })
    end

    context 'with valid response' do
      before do
        stub_request(:get, inventory_url)
          .with(query: { request: { hosts: ['host1'] }.to_json, output_format: 'json' })
          .to_return(body: inventory_response('host1').to_json)
      end

      it 'returns inventory data with casing normalization' do
        output = trigger_action
        expect(output[:has_next_page]).to eq(false)
        hosts = output[:hosts]
        expect(hosts.size).to eq(1)
        expect(hosts.first[:hostname]).to eq('host1')
        inventory = hosts.first[:inventory]
        expect(inventory).to be_a(Hash)
        hw = inventory[:nodes][:hardware][:nodes]
        expect(hw[:system][:attributes][:pairs][:manufacturer]).to eq('Amazon EC2')
        expect(hw[:cpu][:attributes][:pairs][:cores]).to eq(4)
        expect(hw[:memory][:attributes][:pairs][:total_ram_usable]).to eq(33_688_150_016)
        expect(inventory[:nodes][:software][:nodes][:os][:attributes][:pairs][:name])
          .to eq('Microsoft Windows Server 2019 Datacenter')

        net = inventory[:nodes][:networking]
        expect(net[:attributes][:pairs][:hostname]).to eq('host1')
        expect(net[:attributes][:pairs][:total_interfaces]).to eq(2)

        interfaces_table = net[:nodes][:interfaces][:table]
        expect(interfaces_table[:key_columns]).to eq(['index'])
        expect(interfaces_table[:rows].size).to eq(1)

        iface = interfaces_table[:rows].first
        expect(iface[:description]).to eq('eth0')
        expect(iface[:speed]).to eq(10_000_000_000)
        expect(iface[:oper_status]).to eq(1)
        expect(iface[:phys_address]).to eq('00:11:22:33:44:55')
      end
    end

    context 'when host has missing inventory data' do
      before do
        stub_request(:get, inventory_url)
          .with(query: { request: { hosts: ['empty-host'] }.to_json, output_format: 'json' })
          .to_return(body: { result_code: 0, result: { 'empty-host' => {} } }.to_json)
      end

      it 'returns empty inventory hash' do
        output = trigger_action(host_names: ['empty-host'])
        host = output[:hosts].first
        expect(host[:hostname]).to eq('empty-host')
        expect(host[:inventory]).to eq({})
      end
    end

    context 'when offset exceeds host_names length' do
      before do
        action(host_names: ['host1'], batch_size: 1)
          .send(:iteration_state_value=, { offset: 5 })
      end

      it 'returns empty result without making API call' do
        output = trigger_action(host_names: ['host1'], batch_size: 1)
        expect(output[:has_next_page]).to eq(false)
        expect(output[:hosts]).to eq([])
      end
    end

    describe 'pagination' do
      let(:all_hosts) { (1..5).map { |i| "host-#{i}" } }

      context 'when more batches remain' do
        before do
          stub_request(:get, inventory_url)
            .with(query: { request: { hosts: %w[host-1 host-2] }.to_json, output_format: 'json' })
            .to_return(body: inventory_response('host-1', 'host-2').to_json)
        end

        it 'sets iteration state with next offset' do
          expect(action(host_names: all_hosts, batch_size: 2))
            .to receive(:iteration_state_value=)
            .with({ offset: 2 })
            .and_call_original

          output = trigger_action(host_names: all_hosts, batch_size: 2)
          expect(output[:has_next_page]).to eq(true)
          expect(output[:hosts].size).to eq(2)
        end
      end

      context 'when on last batch' do
        before do
          stub_request(:get, inventory_url)
            .with(query: { request: { hosts: %w[host-1 host-2] }.to_json, output_format: 'json' })
            .to_return(body: inventory_response('host-1', 'host-2').to_json)
        end

        it 'clears iteration state' do
          expect(action(host_names: %w[host-1 host-2], batch_size: 2))
            .to receive(:iteration_state_value=)
            .with(nil)

          output = trigger_action(host_names: %w[host-1 host-2], batch_size: 2)
          expect(output[:has_next_page]).to eq(false)
        end
      end

      context 'when last batch is smaller than batch_size' do
        before do
          action(host_names: all_hosts, batch_size: 2)
            .send(:iteration_state_value=, { offset: 4 })

          stub_request(:get, inventory_url)
            .with(query: { request: { hosts: %w[host-5] }.to_json, output_format: 'json' })
            .to_return(body: inventory_response('host-5').to_json)
        end

        it 'returns the partial batch with no next page' do
          output = trigger_action(host_names: all_hosts, batch_size: 2)
          expect(output[:has_next_page]).to eq(false)
          expect(output[:hosts].pluck(:hostname)).to contain_exactly('host-5')
        end
      end

      context 'when resuming from previous batch' do
        before do
          action(host_names: all_hosts, batch_size: 2)
            .send(:iteration_state_value=, { offset: 2 })
        end

        it 'fetches the correct batch slice' do
          stub = stub_request(:get, inventory_url)
                 .with(query: { request: { hosts: %w[host-3 host-4] }.to_json, output_format: 'json' })
                 .to_return(body: inventory_response('host-3', 'host-4').to_json)

          output = trigger_action(host_names: all_hosts, batch_size: 2)
          expect(output[:has_next_page]).to eq(true)
          expect(output[:hosts].pluck(:hostname)).to contain_exactly('host-3', 'host-4')
          expect(stub).to have_been_requested.once
        end
      end
    end

    describe 'error handling' do
      let(:default_query) { { request: { hosts: ['host1'] }.to_json, output_format: 'json' } }

      context 'when API returns 401' do
        before do
          stub_request(:get, inventory_url).with(query: default_query).to_return(status: 401, body: 'Unauthorized')
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Checkmk authentication error: 401/) }
      end

      context 'when API returns 403' do
        before do
          stub_request(:get, inventory_url).with(query: default_query).to_return(status: 403, body: 'Forbidden')
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Checkmk authentication error: 403/) }
      end

      context 'when API returns 500' do
        before do
          stub_request(:get, inventory_url).with(query: default_query).to_return(status: 500,
                                                                                 body: 'Internal Server Error')
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Internal Server Error/) }
      end

      context 'when API returns 503' do
        before do
          stub_request(:get, inventory_url).with(query: default_query).to_return(status: 503,
                                                                                 body: 'Service Unavailable')
        end

        it 'reschedules with backoff' do
          Timecop.freeze do
            expect { trigger_action }
              .to raise_error(IPaaS::Job::RescheduleJob) { |e| expect(e.reschedule_after).to eq(60.seconds.from_now) }
          end
        end
      end

      context 'when inventory API returns error result_code' do
        before do
          stub_request(:get, inventory_url)
            .with(query: default_query)
            .to_return(body: { result_code: 1, result: 'You need to provide a "host".' }.to_json)
        end

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /Checkmk inventory API error.*result_code=1/) }
      end

      context 'when response is invalid JSON' do
        before { stub_request(:get, inventory_url).with(query: default_query).to_return(body: 'Not JSON') }

        it { expect { trigger_action }.to raise_error(IPaaS::Job::FailJob, /not valid JSON/) }
      end
    end
  end
end
