require 'spec_helper'

describe 'endoflife.date: list products', :action, :endoflife_date do
  let(:action_template_id) { '01a1d2ed-541c-7cb2-9215-74ae0e287076' }
  let(:products) { [product_summary_json('ubuntu'), product_summary_json('debian')] }

  it 'has optional category and tag inputs' do
    expect(action.input_schema.field(:category).required).to be_falsey
    expect(action.input_schema.field(:tag).required).to be_falsey
  end

  it 'lists every product when no filter is set' do
    stub_eol('/products', body: eol_body(products, total: 2))
    output = run_action({})
    expect(output[:found]).to be true
    expect(output[:total]).to eq(2)
    expect(output[:category]).to be_nil
    expect(output[:tag]).to be_nil
    expect(output[:products].map { |product| product[:name] }).to eq(['ubuntu', 'debian'])
    expect(output[:products].first[:uri]).to eq("#{eol_api}/products/ubuntu")
  end

  it 'lists products in a category, trimming and lowercasing it' do
    stub_eol('/categories/os', body: eol_body(products, total: 2))
    output = run_action({ category: ' OS ' })
    expect(output[:found]).to be true
    expect(output[:category]).to eq('os')
  end

  it 'lists products with a tag' do
    stub_eol('/tags/microsoft', body: eol_body([product_summary_json('windows')], total: 1))
    output = run_action({ tag: 'microsoft' })
    expect(output[:tag]).to eq('microsoft')
    expect(output[:total]).to eq(1)
  end

  it 'succeeds with found false for an unknown category' do
    stub_eol('/categories/nope', status: 404, body: '<html>Not found</html>')
    output = run_action({ category: 'nope' })
    expect(output[:found]).to be false
    expect(output[:total]).to eq(0)
    expect(output[:products]).to eq([])
  end

  it 'fails when both a category and a tag are set' do
    expect { run_action({ category: 'os', tag: 'microsoft' }) }
      .to raise_error(IPaaS::Job::FailJob, /not both/)
  end

  it 'names a product field the output schema does not model' do
    messages = captured_logs
    stub_eol('/products', body: eol_body([product_summary_json('ubuntu', brandNewField: 1)], total: 1))
    run_action({})
    expect(messages.grep(/does not model/).first).to include('brand_new_field')
  end
end
