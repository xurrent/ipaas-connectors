require 'spec_helper'

describe 'endoflife.date: find products by identifier', :action, :endoflife_date do
  let(:action_template_id) { '01a1d2ed-5497-77f8-bee3-775277ee081c' }

  def entry(identifier, product)
    { identifier: identifier, product: { name: product, uri: "#{eol_api}/products/#{product}" } }
  end

  let(:purls) do
    [
      entry('pkg:npm/express', 'express'),
      entry('pkg:npm/express-session', 'express-session'),
      entry('pkg:npm/%40angular/core', 'angular'),
    ]
  end

  before { stub_eol('/identifiers/purl', body: eol_body(purls, total: 3)) }

  it 'requires an identifier type and makes the identifier optional' do
    expect(action.input_schema.field(:identifier_type).required).to be true
    expect(action.input_schema.field(:identifier).required).to be_falsey
  end

  it 'lists every identifier of the type when no identifier is given' do
    output = run_action({ identifier_type: 'PURL' })
    expect(output[:found]).to be true
    expect(output[:identifier_type]).to eq('purl')
    expect(output[:total]).to eq(3)
    expect(output[:identifiers].first[:product][:name]).to eq('express')
  end

  it 'matches an identifier exactly' do
    output = run_action({ identifier_type: 'purl', identifier: 'pkg:npm/express' })
    expect(output[:identifiers].map { |item| item[:identifier] }).to eq(['pkg:npm/express'])
  end

  it 'matches a more specific identifier at a separator' do
    output = run_action({ identifier_type: 'purl', identifier: 'pkg:npm/express@4.18.2' })
    expect(output[:found]).to be true
    expect(output[:identifier]).to eq('pkg:npm/express@4.18.2')
    expect(output[:identifiers].map { |item| item[:product][:name] }).to eq(['express'])
  end

  it 'does not match a look-alike that only shares a prefix' do
    output = run_action({ identifier_type: 'purl', identifier: 'pkg:npm/expressive' })
    expect(output[:found]).to be false
    expect(output[:total]).to eq(0)
  end

  it 'is case-sensitive, as identifiers appear on endoflife.date' do
    output = run_action({ identifier_type: 'purl', identifier: 'pkg:npm/%40Angular/core' })
    expect(output[:found]).to be false
  end

  it 'succeeds with found false for an unknown identifier type' do
    stub_eol('/identifiers/nope', status: 404, body: '<html>Not found</html>')
    output = run_action({ identifier_type: 'nope' })
    expect(output[:found]).to be false
    expect(output[:total]).to eq(0)
    expect(output[:identifiers]).to eq([])
    expect(output[:schema_version]).to be_nil
  end
end
