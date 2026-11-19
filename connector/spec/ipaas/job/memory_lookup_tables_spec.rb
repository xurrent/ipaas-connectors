require 'spec_helper'

describe IPaaS::Job::MemoryLookupTables do
  subject(:tables) { described_class.new }

  let(:table) { '01a0f6b1-2680-76e4-aee8-b520070475d4' }
  let(:other_table) { '01a0f6b1-2680-76e4-aee8-b520070475d5' }
  let(:device) { '01a0f6b1-3a08-7373-ae49-1852b349bd32' }
  let(:ci) { '01a0f6b1-3df0-769b-b08f-87f514d5c544' }
  let(:missing) { '00000000-0000-7000-8000-0000000000ff' }
  let(:columns) { [{ column: device, label: 'Device ID' }, { column: ci, label: 'CI ID' }] }

  before do
    described_class.reset!
    [table, other_table].each do |uuid|
      described_class.define(uuid, name: 'device_map', columns: [{ key: device, label: 'Device ID' },
                                                                 { 'key' => ci, 'label' => 'CI ID' },])
    end
  end

  def add(count, values)
    Array.new(count) { tables.add_entry(table, values)[:entry_id] }
  end

  it 'adds an entry with every column, unmapped ones null, and finds the oldest match' do
    tables.add_entry(table, { device => 'OTHER' })
    first = tables.add_entry(table, { device.to_sym => 'JAMF-0042' })
    tables.add_entry(table, { device => 'JAMF-0042', ci => 'ci_1' })

    expect(first).to include(entry: { device => 'JAMF-0042', ci => nil }, columns: columns)
    expect(tables.lookup_entry(table, { device => %w[NOPE JAMF-0042] })).to eq(first)
    expect(described_class.entries(table).size).to eq(3)
  end

  it 'fails a lookup that matches nothing, a null or a map given as the value included, and a table it lacks' do
    tables.add_entry(table, { device => 'JAMF-0042' })

    [{ device => 'NOPE' }, { ci => nil }, { device => { 'JAMF-0042' => 'JAMF-0042' } }].each do |match|
      expect { tables.lookup_entry(table, match) }
        .to raise_error(IPaaS::Job::FailJob, 'No entry in "device_map" matches')
    end
    expect { tables.truncate(missing) }.to raise_error(IPaaS::Job::FailJob, %(Table "#{missing}" not found))
  end

  it 'pages a search in Entry ID order, at most 100 or the limit at a time, and says whether more match' do
    ids = add(101, { device => 'a' })
    add(1, { device => 'b' })

    first = tables.search_page(table, { device => 'a' })
    second = tables.search_page(table, { device => 'a' }, after: ids[99])
    limited = tables.search_page(table, { device => 'a' }, limit: 3)
    beyond = tables.search_page(table, { device => 'a' }, limit: 150)

    expect([first[:entries].pluck(:entry_id), first[:more]]).to eq([ids.first(100), true])
    expect([second[:entries].pluck(:entry_id), second[:more]]).to eq([[ids.last], false])
    expect([limited[:entries].pluck(:entry_id), limited[:more]]).to eq([ids.first(3), true])
    expect([beyond[:entries].size, beyond[:more]]).to eq([100, true])
    expect(first[:columns]).to eq(columns)
  end

  it 'pages every entry with Get All, 100 at a time' do
    ids = add(101, { ci => 'x' })

    first = tables.get_all_page(table)
    second = tables.get_all_page(table, after: ids[99])

    expect([first[:entries].pluck(:entry_id), first[:more]]).to eq([ids.first(100), true])
    expect(second).to include(entries: [a_hash_including(entry_id: ids.last)], more: false)
  end

  it 'updates the mapped columns only, and answers a missing entry by Ignore if not found' do
    id = tables.add_entry(table, { device => 'd', ci => 'c' })[:entry_id]
    sibling = tables.add_entry(table, { device => 'e', ci => 'f' })[:entry_id]

    expect(tables.update_entry(table, id, { ci => 'changed' }, ignore_missing: false)[:entry])
      .to eq(device => 'd', ci => 'changed')
    expect { tables.update_entry(table, missing, { ci => 'x' }, ignore_missing: false) }
      .to raise_error(IPaaS::Job::FailJob, %(Entry #{missing} not found in "device_map"))
    expect(tables.update_entry(table, missing, {}, ignore_missing: true))
      .to eq(entry_id: nil, entry: nil, columns: columns)
    expect(described_class.entries(table).to_h { |entry| [entry[:entry_id], entry[:values]] })
      .to eq(id => { device => 'd', ci => 'changed' }, sibling => { device => 'e', ci => 'f' })
  end

  it 'deletes an entry, ignoring a missing one unless Ignore if not found is off' do
    id = tables.add_entry(table, { device => 'd' })[:entry_id]
    sibling = tables.add_entry(table, { device => 'e' })[:entry_id]

    expect(tables.delete_entry(table, id, ignore_missing: true)).to eq(id)
    expect(tables.delete_entry(table, id, ignore_missing: true)).to be_nil
    expect { tables.delete_entry(table, id, ignore_missing: false) }
      .to raise_error(IPaaS::Job::FailJob, %(Entry #{id} not found in "device_map"))
    expect(described_class.entries(table).pluck(:entry_id)).to eq([sibling])
  end

  it 'truncates only the table it names, counting the entries it held' do
    add(2, { device => 'd' })
    kept = tables.add_entry(other_table, { device => 'd' })[:entry_id]

    expect([tables.truncate(table), tables.truncate(table)]).to eq([2, 0])
    expect(described_class.entries(other_table).pluck(:entry_id)).to eq([kept])
  end
end
