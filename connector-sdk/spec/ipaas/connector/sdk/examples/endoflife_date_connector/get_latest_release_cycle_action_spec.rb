require 'spec_helper'

describe 'endoflife.date: get latest release cycle', :action, :endoflife_date do
  let(:action_template_id) { '01a1d2ed-53db-7cbd-bfa7-b20997bab05c' }

  it 'requires a product' do
    expect(action.input_schema.field(:product).required).to be true
  end

  it 'returns the newest release cycle' do
    latest = release_json(name: '25.10', codename: 'Questing Quokka', isLts: false)
    stub_eol('/products/ubuntu/releases/latest', body: eol_body(latest))
    output = run_action({ product: 'ubuntu' })
    expect(output[:found]).to be true
    expect(output[:product]).to eq('ubuntu')
    expect(output[:name]).to eq('25.10')
    expect(output[:is_lts]).to be false
  end

  it 'succeeds with found false for an unknown product' do
    stub_eol('/products/nope/releases/latest', status: 404, body: '<html>Not found</html>')
    output = run_action({ product: 'nope' })
    expect(output[:found]).to be false
    expect(output[:product]).to eq('nope')
    expect(output[:name]).to be_nil
  end
end
