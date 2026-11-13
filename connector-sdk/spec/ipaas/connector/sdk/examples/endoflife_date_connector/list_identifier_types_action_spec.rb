require 'spec_helper'

describe 'endoflife.date: list identifier types', :action, :endoflife_date do
  let(:action_template_id) { '01a1d2ed-5478-709b-9009-0aef4ed32cd9' }

  it 'returns the names with their API links' do
    items = [{ name: 'cpe', uri: "#{eol_api}/identifiers/cpe" }, { name: 'other', uri: "#{eol_api}/identifiers/other" }]
    stub_eol('/identifiers', body: eol_body(items, total: 2))
    output = run_action({})
    expect(output[:total]).to eq(2)
    expect(output[:identifier_types].map { |item| item[:name] }).to eq(['cpe', 'other'])
    expect(output[:identifier_types].first[:uri]).to eq("#{eol_api}/identifiers/cpe")
    expect(output[:schema_version]).to eq('1.2.1')
  end

  it 'fails when endoflife.date has no such list' do
    stub_eol('/identifiers', status: 404, body: '<html>Not found</html>')
    expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, /has no list/)
  end
end
