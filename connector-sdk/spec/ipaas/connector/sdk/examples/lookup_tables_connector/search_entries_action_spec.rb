require 'spec_helper'

describe 'Search Entries', :action, :lookup_tables do
  let(:action_template_id) { '01a19c65-6239-79c7-ae02-52ac9d367bd2' }

  it 'pages matching entries 100 at a time, keeping its place and count between pages' do
    ids = Array.new(101) { add(device => 'a')[:entry_id] }
    add(device => 'b')

    first = run_page(per_column(:match, { device => 'a' }), state: nil)

    expect(first).to eq([[['page', ids.first(100)]], { 'after' => ids[99], 'returned' => 100 }])
    expect(run_page).to eq([[['page', [ids.last]]], nil])
  end

  it 'gives the steps inside one empty page with the table columns when the first page matches nothing' do
    add(device => 'a')

    results = action(per_column(:match, { device => 'NOPE' })).run

    expect(results).to eq([{ schema_reference: 'page', output: { 'entries' => [], 'columns' => columns_output } }])
    expect(action.iteration_state).to be_nil
  end

  it 'stops without running the steps inside when a later page is empty' do
    id = add(device => 'a')[:entry_id]

    expect(run_page(per_column(:match, { device => 'a' }), state: { after: id, returned: 100 })).to eq([[], nil])
  end

  it 'stops once it has returned At most entries in all' do
    ids = Array.new(7) { add(device => 'a')[:entry_id] }

    expect(run_page(per_column(:match, { device => 'a' }, at_most: '5'), state: nil))
      .to eq([[['page', ids.first(5)]], nil])
  end
end
