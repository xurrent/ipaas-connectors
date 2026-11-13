require 'spec_helper'

describe 'endoflife.date: get product', :action, :endoflife_date do
  let(:action_template_id) { '01a1d2ed-53fc-7cd9-9375-842ac90f1caf' }

  let(:product_json) do
    {
      name: 'ubuntu',
      aliases: ['ubuntu-linux'],
      label: 'Ubuntu',
      category: 'os',
      tags: ['canonical', 'linux-distribution', 'os'],
      versionCommand: 'lsb_release --release',
      identifiers: [{ type: 'cpe', id: 'cpe:/o:canonical:ubuntu_linux' }],
      labels: {
        eoas: 'Hardware & Maintenance',
        discontinued: nil,
        eol: 'Maintenance & Security Support',
        eoes: 'Extended Security Maintenance',
      },
      links: {
        icon: 'https://cdn.jsdelivr.net/npm/simple-icons/icons/ubuntu.svg',
        html: 'https://endoflife.date/ubuntu',
        releasePolicy: 'https://wiki.ubuntu.com/Releases',
      },
      releases: [release_json, release_json(name: '20.04', codename: 'Focal Fossa')],
    }
  end

  it 'requires a product' do
    expect(action.input_schema.field(:product).required).to be true
  end

  context 'when the product exists' do
    before { stub_eol('/products/ubuntu', body: eol_body(product_json, last_modified: '2026-11-01T10:00:00+00:00')) }

    let(:output) { run_action({ product: 'ubuntu' }) }

    it 'returns the product details' do
      expect(output[:found]).to be true
      expect(output[:product]).to eq('ubuntu')
      expect(output[:name]).to eq('ubuntu')
      expect(output[:label]).to eq('Ubuntu')
      expect(output[:aliases]).to eq(['ubuntu-linux'])
      expect(output[:category]).to eq('os')
      expect(output[:tags]).to eq(['canonical', 'linux-distribution', 'os'])
      expect(output[:version_command]).to eq('lsb_release --release')
    end

    it 'returns identifiers, phase labels and links' do
      expect(output[:identifiers].first[:id]).to eq('cpe:/o:canonical:ubuntu_linux')
      expect(output[:identifiers].first[:type]).to eq('cpe')
      expect(output[:labels][:eol]).to eq('Maintenance & Security Support')
      expect(output[:links][:release_policy]).to eq('https://wiki.ubuntu.com/Releases')
    end

    it 'returns every release cycle with its support dates' do
      expect(output[:releases].map { |release| release[:name] }).to eq(['22.04', '20.04'])
      expect(output[:releases].first[:eol_from].to_s).to eq('2027-06-01')
      expect(output[:releases].first[:latest][:name]).to eq('22.04.5')
    end

    it 'returns the last modified time' do
      expect(output[:last_modified]).to be_present
    end
  end

  it 'succeeds with found false for an unknown product' do
    stub_eol('/products/nope', status: 404, body: '<html>Not found</html>')
    output = run_action({ product: 'nope' })
    expect(output[:found]).to be false
    expect(output[:product]).to eq('nope')
  end

  describe 'unmodelled fields' do
    it 'stays silent when every field is modelled' do
      messages = captured_logs
      stub_eol('/products/ubuntu', body: eol_body(product_json))
      run_action({ product: 'ubuntu' })
      expect(messages.grep(/does not model/)).to be_empty
    end

    it 'names a product field the output schema does not model' do
      messages = captured_logs
      stub_eol('/products/ubuntu', body: eol_body(product_json.merge(brandNewField: 1)))
      run_action({ product: 'ubuntu' })
      expect(messages.grep(/product fields/).first).to include('brand_new_field')
    end

    it 'names a release cycle field the output schema does not model' do
      messages = captured_logs
      body = product_json.merge(releases: [release_json(newReleaseField: 1)])
      stub_eol('/products/ubuntu', body: eol_body(body))
      run_action({ product: 'ubuntu' })
      expect(messages.grep(/release cycle fields/).first).to include('new_release_field')
    end
  end
end
