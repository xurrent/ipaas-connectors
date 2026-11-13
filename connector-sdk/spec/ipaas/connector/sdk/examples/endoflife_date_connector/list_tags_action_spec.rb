require 'spec_helper'

describe 'endoflife.date: list tags', :action, :endoflife_date do
  let(:action_template_id) { '01a1d2ed-545b-7ddd-b968-ac921883831c' }

  it 'returns the names with their API links' do
    items = [{ name: 'microsoft', uri: "#{eol_api}/tags/microsoft" }, { name: 'other', uri: "#{eol_api}/tags/other" }]
    stub_eol('/tags', body: eol_body(items, total: 2))
    output = run_action({})
    expect(output[:total]).to eq(2)
    expect(output[:tags].map { |item| item[:name] }).to eq(['microsoft', 'other'])
    expect(output[:tags].first[:uri]).to eq("#{eol_api}/tags/microsoft")
    expect(output[:schema_version]).to eq('1.2.1')
  end

  it 'fails when endoflife.date has no such list' do
    stub_eol('/tags', status: 404, body: '<html>Not found</html>')
    expect { run_action({}) }.to raise_error(IPaaS::Job::FailJob, /has no list/)
  end
end
