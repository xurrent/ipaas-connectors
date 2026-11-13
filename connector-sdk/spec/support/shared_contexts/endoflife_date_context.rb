shared_context 'endoflife_date', :endoflife_date do
  let(:connector_id) { '01a1d2c9-68c7-71ec-8c2c-aa7df921ca0f' }
  let(:eol_api) { 'https://endoflife.date/api/v1' }
  let(:generated_at) { '2026-11-13T00:09:58+00:00' }

  # Wraps a result the way every endoflife.date v1 response does.
  def eol_body(result, **meta)
    { schema_version: '1.2.1', generated_at: generated_at }.merge(meta).merge(result: result).to_json
  end

  def stub_eol(path, status: 200, body: nil, headers: {})
    stub_request(:get, "#{eol_api}#{path}").to_return(status: status, body: body, headers: headers)
  end

  # Ubuntu 22.04 as the v1 API returns it (camelCase keys, as built by _plugins/generate-api-v1.rb).
  def release_json(overrides = {})
    {
      name: '22.04',
      codename: 'Jammy Jellyfish',
      label: "22.04 'Jammy Jellyfish' (LTS)",
      releaseDate: '2022-04-21',
      isLts: true,
      ltsFrom: nil,
      isEoas: true,
      eoasFrom: '2024-09-30',
      isEol: false,
      eolFrom: '2027-06-01',
      isEoes: false,
      eoesFrom: '2032-04-21',
      isMaintained: true,
      latest: { name: '22.04.5', date: '2024-09-12', link: 'https://wiki.ubuntu.com/JammyJellyfish/ReleaseNotes/' },
      custom: nil,
    }.merge(overrides)
  end

  def product_summary_json(name, overrides = {})
    {
      name: name,
      aliases: [],
      label: name.capitalize,
      category: 'os',
      tags: ['os'],
      uri: "#{eol_api}/products/#{name}",
    }.merge(overrides)
  end

  # expect_any_instance_of(Logger) races with the other log lines, so collect instead.
  def captured_logs
    messages = []
    allow_any_instance_of(Logger).to receive(:info).and_wrap_original do |original, *args, &block|
      messages << args.first.to_s
      original.call(*args, &block)
    end
    messages
  end
end
