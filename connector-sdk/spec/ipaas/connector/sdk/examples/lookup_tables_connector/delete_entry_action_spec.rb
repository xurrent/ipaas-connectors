require 'spec_helper'

describe 'Delete Entry', :action, :lookup_tables do
  let(:action_template_id) { '01a19c65-6241-79da-ba41-1510015dac80' }

  it 'deletes the entry, returns its Entry ID and leaves the other entries' do
    entry_id = add(device => 'd')[:entry_id]
    sibling = add(device => 'e')[:entry_id]

    expect(run_action({ entry_id: entry_id })).to eq('deleted_entry_id' => entry_id)
    expect(stored.keys).to eq([sibling])
  end

  it 'returns null for a missing entry, as Ignore if not found is on by default' do
    expect(action_template.input_schema.field(:ignore_if_not_found).default).to be(true)
    expect(run_action({ entry_id: missing_entry_id })).to eq('deleted_entry_id' => nil)
  end

  it 'fails a missing entry with Ignore if not found off' do
    expect { run_action({ entry_id: missing_entry_id, ignore_if_not_found: false }) }
      .to raise_error(IPaaS::Job::FailJob, %(Entry #{missing_entry_id} not found in "device_map"))
  end
end
