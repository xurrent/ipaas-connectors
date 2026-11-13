require 'spec_helper'

describe 'endoflife.date: list categories', :action, :endoflife_date do
  let(:action_template_id) { '01a1d2ed-543b-7290-aedb-4a3ccc557b9a' }

  it 'returns the names with their API links' do
    items = [{ name: 'os', uri: "#{eol_api}/categories/os" }, { name: 'other', uri: "#{eol_api}/categories/other" }]
    stub_eol('/categories', body: eol_body(items, total: 2))
    output = run_action({})
    expect(output[:total]).to eq(2)
    expect(output[:categories].map { |item| item[:name] }).to eq(['os', 'other'])
    expect(output[:categories].first[:uri]).to eq("#{eol_api}/categories/os")
    expect(output[:schema_version]).to eq('1.2.1')
  end

  it 'fails when endoflife.date has no such list' do
    stub_eol('/categories', status: 404, body: '<html>Not found</html>')
    expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, /has no list/)
  end
end
