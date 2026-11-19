require 'spec_helper'

describe 'Truncate Table', :action, :lookup_tables do
  let(:action_template_id) { '01a19c65-6243-7f7d-9e10-97402a9c848d' }
  let(:other_table) { '01a0f6b1-2680-76e4-aee8-b520070475d5' }

  it 'TRN-01 TRN-11 deletes every entry of its own table, counts them, and says so in its description' do
    IPaaS::Job::MemoryLookupTables.define(other_table, name: 'other_map', columns: listed)
    kept = IPaaS::Job::MemoryLookupTables.new.add_entry(other_table, { device => 'd' })[:entry_id]
    2.times { add(device => 'd') }

    expect(run_action([])).to eq('count' => 2)
    expect(stored).to eq({})
    expect(IPaaS::Job::MemoryLookupTables.entries(other_table).pluck(:entry_id)).to eq([kept])
    expect(action_template.description.squish).to eq(
      "Permanently deletes every entry of the table, for every solution that uses it. This can't be undone. " \
      'Count is how many entries were deleted.'
    )
  end
end
