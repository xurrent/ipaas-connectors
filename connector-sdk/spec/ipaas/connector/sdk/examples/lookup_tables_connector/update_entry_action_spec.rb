require 'spec_helper'

describe 'Update Entry', :action, :lookup_tables do
  let(:action_template_id) { '01a19c65-623e-776d-a4ce-9239740e7cae' }

  it 'writes the mapped columns, leaves the others and the other entries, and returns the whole entry' do
    entry_id = add(device => 'd', ci => 'c')[:entry_id]
    sibling = add(device => 'e', ci => 'f')[:entry_id]

    output = run_action(per_column(:values, { ci => 'changed' }, entry_id: entry_id))

    expect(output).to include('entry_id' => entry_id, 'entry' => { device => 'd', ci => 'changed' })
    expect(stored).to eq(entry_id => { device => 'd', ci => 'changed' }, sibling => { device => 'e', ci => 'f' })
  end

  it 'fails a missing entry, as Ignore if not found is off by default' do
    expect(action_template.input_schema.field(:ignore_if_not_found).default).to be(false)
    expect { run_action(per_column(:values, {}, entry_id: missing_entry_id)) }
      .to raise_error(IPaaS::Job::FailJob, %(Entry #{missing_entry_id} not found in "device_map"))
  end

  it 'returns no entry and the table columns for a missing entry with Ignore if not found on' do
    output = run_action(per_column(:values, {}, entry_id: missing_entry_id, ignore_if_not_found: true))

    expect(output).to eq('entry_id' => nil, 'entry' => nil, 'columns' => columns_output)
  end
end
