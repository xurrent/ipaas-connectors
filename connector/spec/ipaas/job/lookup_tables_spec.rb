require 'spec_helper'

describe IPaaS::Job::LookupTables do
  let(:context) { Class.new { include IPaaS::Job::Context }.new }
  let(:table) { '01a0f6b1-2680-76e4-aee8-b520070475d4' }
  let(:device) { '01a0f6b1-3a08-7373-ae49-1852b349bd32' }
  let(:tables) { instance_double(IPaaS::Job::MemoryLookupTables) }

  before do
    IPaaS::Job::MemoryLookupTables.reset!
    IPaaS::Job::MemoryLookupTables.define(table, name: 'device_map', columns: [{ key: device, label: 'Device ID' }])
  end

  it 'lets connector code and expressions name every operation' do
    expect(IPaaS::Connector::Common::ProcRules::ProcSafe.registry).to include(
      :lookup_table_add_entry, :lookup_table_lookup_entry, :lookup_table_search_page, :lookup_table_get_all_page,
      :lookup_table_update_entry, :lookup_table_delete_entry, :lookup_table_truncate, :lookup_table_mapped_keys
    )
  end

  it 'reaches the in-memory tables by default' do
    added = context.lookup_table_add_entry(table, { device => 'JAMF-0042' })

    expect(context.lookup_table_lookup_entry(table, { device => 'JAMF-0042' })).to eq(added)
  end

  it 'hands each operation on one entry, with its arguments, to the tables the class makes for the instance' do
    allow(context.class).to receive(:lookup_tables_for).with(context).and_return(tables)
    calls = {
      add_entry: [[table, { device => 'x' }], {}, {}],
      lookup_entry: [[table, { device => 'x' }], {}, {}],
      update_entry: [[table, 'e1', { device => 'y' }], { ignore_if_not_found: true }, { ignore_missing: true }],
      delete_entry: [[table, 'e1'], { ignore_if_not_found: false }, { ignore_missing: false }],
      truncate: [[table], {}, {}],
    }
    calls.each_key { |operation| allow(tables).to receive(operation).and_return(operation) }

    results = calls.map do |operation, (args, options, _passed)|
      context.public_send(:"lookup_table_#{operation}", *args, **options)
    end

    expect(results).to eq(calls.keys)
    calls.each do |operation, (args, _options, passed)|
      expect(tables).to have_received(operation).with(*args, **passed)
    end
  end

  it 'reads Ignore if not found as off for Update Entry and on for Delete Entry when a step maps none or null' do
    allow(context.class).to receive(:lookup_tables_for).and_return(tables)
    allow(tables).to receive_messages(update_entry: nil, delete_entry: nil)

    context.lookup_table_update_entry(table, 'e1', {})
    context.lookup_table_update_entry(table, 'e1', {}, ignore_if_not_found: nil)
    context.lookup_table_delete_entry(table, 'e1')
    context.lookup_table_delete_entry(table, 'e1', ignore_if_not_found: nil)

    expect(tables).to have_received(:update_entry).with(table, 'e1', {}, ignore_missing: false).twice
    expect(tables).to have_received(:delete_entry).with(table, 'e1', ignore_missing: true).twice
  end

  it 'leaves a caller that is not a step to the tables, which refuse it, before any paging state is touched' do
    allow(context.class).to receive(:lookup_tables_for).with(context).and_return(tables)
    allow(tables).to receive(:search_page).and_raise(IPaaS::Job::FailJob, 'refused')
    allow(tables).to receive(:get_all_page).and_raise(IPaaS::Job::FailJob, 'refused')

    expect { context.lookup_table_search_page(table, {}) }.to raise_error(IPaaS::Job::FailJob, 'refused')
    expect { context.lookup_table_get_all_page(table) }.to raise_error(IPaaS::Job::FailJob, 'refused')
  end

  it 'lists the keys a step maps into a field, and none for a caller without a mapping' do
    step = Class.new do
      include IPaaS::Job::Context

      attr_accessor :input_mapping
    end.new
    step.input_mapping = [IPaaS::Connector::Mapping::FieldMapping.parse(
      { field_id: 'values', nested: [{ field_id: device, fixed: 'x' }, { field_id: 'gone', proc: '"y"' }] }
    )]

    expect([step.lookup_table_mapped_keys(:values), step.lookup_table_mapped_keys('match'),
            context.lookup_table_mapped_keys(:values),]).to eq([[device, 'gone'], [], []])
  end

  describe 'paging' do
    around { |example| IPaaS::Connector::Connector.uuid_scope({}) { example.run } }

    let(:runbook) do
      IPaaS::Connector::Runbook.new(SecureRandom.uuid_v7).tap do |runbook|
        solution = double(:solution)
        allow(solution).to receive(:test_cases_for).with(runbook.uuid).and_return([])
        allow(runbook).to receive(:solution).and_return(solution)
      end
    end

    before do
      skip_function_capture_validation
      IPaaS::Connector::Connector.new('lookup-tables-paging') do
        page_schema = -> do
          output_schema 'page' do
            field :entries, 'Entries', :nested, array: true do
              field :entry_id, 'Entry ID', :string
            end
          end
          iteration_state_schema do
            field :after, 'After', :string
            field :returned, 'Returned', :integer
          end
        end

        action 'search' do
          nested true
          input_schema do
            field :table, 'Table', :string
            field :match, 'Match', :hash
            field :at_most, 'At most', :any
          end
          instance_exec(&page_schema)
          run do
            page = lookup_table_search_page(input[:table], input[:match].to_h, at_most: input[:at_most])
            page ? [{ output: page, schema_reference: 'page' }] : []
          end
        end

        action 'all' do
          nested true
          input_schema { field :table, 'Table', :string }
          instance_exec(&page_schema)
          run do
            page = lookup_table_get_all_page(input[:table])
            page ? [{ output: page, schema_reference: 'page' }] : []
          end
        end
      end
    end

    def add_entries(count, values = { device => 'a' })
      Array.new(count) { IPaaS::Job::MemoryLookupTables.new.add_entry(table, values)[:entry_id] }
    end

    def search(at_most: nil, value: 'a')
      mappings = { table: table, match: { device => value }, at_most: at_most }.compact
      paging_step('search', mappings)
    end

    def paging_step(template, mappings)
      IPaaS::Connector::Action.parse(
        runbook,
        { reference: SecureRandom.uuid, action_template: { uuid: template },
          input_mapping: mappings.map { |field_id, value| { field_id: field_id, fixed: value } }, }
      )
    end

    def run_page(step, state = :kept)
      step.send(:iteration_state_value=, state) unless state == :kept
      pages = step.run.map { |result| result[:output]['entries'].pluck('entry_id') }
      [pages, step.iteration_state_value&.to_h&.symbolize_keys]
    end

    it 'pages a search 100 entries at a time in Entry ID order, keeping its place and count in the step state' do
      ids = add_entries(101)
      step = search

      expect(run_page(step, nil)).to eq([[ids.first(100)], { after: ids[99], returned: 100 }])
      expect(run_page(step)).to eq([[[ids.last]], nil])
    end

    it 'gives the steps inside one empty page when the first page matches nothing' do
      add_entries(2)

      expect(run_page(search(value: 'NOPE'), nil)).to eq([[[]], nil])
    end

    it 'stops, giving the steps inside no page, when a later page is empty' do
      ids = add_entries(2)

      expect(run_page(search, { after: ids.last, returned: 100 })).to eq([[], nil])
    end

    it 'stops once it has returned At most entries in all' do
      ids = add_entries(250)
      step = search(at_most: 150)

      expect(run_page(search(at_most: 3), nil)).to eq([[ids.first(3)], nil])
      expect(run_page(step, nil)).to eq([[ids.first(100)], { after: ids[99], returned: 100 }])
      expect(run_page(step)).to eq([[ids[100, 50]], nil])
    end

    it 'asks the tables only for what At most leaves, after the last entry it returned' do
      allow(IPaaS::Connector::Action).to receive(:lookup_tables_for).and_return(tables)
      allow(tables).to receive(:search_page).and_return({ entries: [], columns: [], more: false })

      run_page(search(at_most: '5'), { after: 'e1', returned: 3 })
      run_page(search, { after: 'e1', returned: 3 })

      expect(tables).to have_received(:search_page).with(table, { device => 'a' }, after: 'e1', limit: 2)
      expect(tables).to have_received(:search_page).with(table, { device => 'a' }, after: 'e1', limit: nil)
    end

    it 'asks the tables for no entries once At most falls to what it has already returned, and stops' do
      allow(IPaaS::Connector::Action).to receive(:lookup_tables_for).and_return(tables)
      allow(tables).to receive(:search_page).and_return({ entries: [], columns: [], more: true })

      [50, 100].each do |at_most|
        expect(run_page(search(at_most: at_most), { after: 'e1', returned: 100 })).to eq([[], nil])
      end
      expect(tables).to have_received(:search_page).with(table, { device => 'a' }, after: 'e1', limit: 0).twice
    end

    it 'takes At most as a whole number given as a number or as digits only, and blank as no limit' do
      allow(IPaaS::Connector::Action).to receive(:lookup_tables_for).and_return(tables)
      limits = []
      allow(tables).to receive(:search_page) do |*, limit:, **|
        limits << limit
        { entries: [], columns: [], more: false }
      end
      readings = { 5 => 5, '5' => 5, '05' => 5, 5.0 => 5, BigDecimal('5') => 5, Rational(10, 2) => 5,
                   100_000 => 100_000, '' => nil, " \t\r\n" => nil, }

      readings.each_key { |at_most| run_page(search(at_most: at_most), nil) }

      expect(limits).to eq(readings.values)
    end

    it 'fails any other At most with one text, asking the tables nothing' do
      allow(IPaaS::Connector::Action).to receive(:lookup_tables_for).and_return(tables)
      allow(tables).to receive(:search_page)

      [1.5, '1.5', 'abc', true, [1], 0, 100_001, -1, '05x', ' 5', "\u00a0", Rational(3, 2)].each do |at_most|
        expect { run_page(search(at_most: at_most), nil) }.to raise_error(IPaaS::Job::FailJob, described_class::AT_MOST)
      end
      expect(tables).not_to have_received(:search_page)
    end

    it 'pages every entry with Get All, and gives an empty table one empty page' do
      ids = add_entries(101)
      step = paging_step('all', table: table)

      expect(run_page(step, nil)).to eq([[ids.first(100)], { after: ids[99], returned: 100 }])
      expect(run_page(step)).to eq([[[ids.last]], nil])
      expect(run_page(step, { after: ids.last, returned: 101 })).to eq([[], nil])
      IPaaS::Job::MemoryLookupTables.new.truncate(table)
      expect(run_page(paging_step('all', table: table), nil)).to eq([[[]], nil])
    end
  end
end
