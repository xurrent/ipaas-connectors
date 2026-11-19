require 'spec_helper'

describe 'Add Entry', :action, :lookup_tables do
  let(:action_template_id) { '01a19c65-6234-7803-bddf-646f76f381fd' }

  it 'shows a field per listed column, and one for every key the step already maps' do
    action(per_column(:values, { device => 'x', 'unlisted-key' => 'y' }))

    fields = action.input_schema.field(:values).fields
    expect(fields.map { |field| [field.id, field.label] })
      .to eq([[device.to_sym, 'Device ID'], [ci.to_sym, 'CI ID'], [:'unlisted-key', 'unlisted-key']])
  end

  it 'adds the mapped values to the connection table and returns the entry and its columns' do
    output = run_action(per_column(:values, { device => 'JAMF-0042' }))

    expect(output).to include('entry_id' => a_string_matching(/\A\h{8}-/), 'columns' => columns_output,
                              'entry' => { device => 'JAMF-0042', ci => nil })
    expect(stored.values).to eq([{ device => 'JAMF-0042' }])
  end
end
