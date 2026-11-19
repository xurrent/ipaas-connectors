require 'spec_helper'

describe 'Get All Entries', :action, :lookup_tables do
  let(:action_template_id) { '01a19c65-623b-7579-96e6-934ea378ec73' }

  it 'pages every entry 100 at a time with the table columns, keeping its place between pages' do
    ids = Array.new(101) { add(ci => 'x')[:entry_id] }

    first = action([]).run.first[:output]

    expect([first['entries'].pluck('entry_id'), first['columns']]).to eq([ids.first(100), columns_output])
    expect(action.iteration_state_value.to_h).to eq('after' => ids[99], 'returned' => 100)
    expect(run_page).to eq([[['page', [ids.last]]], nil])
  end

  it 'gives the steps inside one empty page when the table is empty' do
    results = action([]).run

    expect(results).to eq([{ schema_reference: 'page', output: { 'entries' => [], 'columns' => columns_output } }])
  end
end
