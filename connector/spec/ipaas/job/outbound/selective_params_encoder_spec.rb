require 'spec_helper'
require 'faraday'

describe IPaaS::Job::Outbound::SelectiveParamsEncoder do
  let(:raw) { ->(value) { IPaaS::Job::Outbound::RawParamValue.new(value) } }

  describe '.encode' do
    # This encoder is installed on every outbound connection, so with nothing marked raw it has to
    # be indistinguishable from Faraday's default, ordering included. These shapes are the ones
    # where a hand-rolled encoder would drift: nil values, nesting, arrays of hashes, symbol keys.
    [
      ['ordinary and repeated', { 'note' => 'x y&z', 'q' => %w[A B] }],
      ['nested hash', { 'nested' => { 'a' => '1', 'b' => '2' } }],
      ['array of hashes', { 'x' => [{ 'k' => 'v' }] }],
      ['nil value', { 'a' => nil }],
      ['symbol keys', { a: '1', b: 2 }],
      ['non-ascii', { 'u' => 'ü ø' }],
      ['empty', {}],
    ].each do |label, params|
      it "should be byte-identical to Faraday for #{label} when nothing is marked raw" do
        expect(described_class.encode(params)).to eq(Faraday::NestedParamsEncoder.encode(params))
      end
    end

    it 'should let Faraday sort when nothing is marked raw' do
      # sort_params is a mutable class-level default owned by the gem, so if a future Faraday
      # flips it that first line fails here rather than silently changing what this example means.
      expect(Faraday::NestedParamsEncoder.sort_params).to be(true)
      expect(described_class.encode({ 'note' => '1', 'a' => '2' })).to eq('a=2&note=1')
    end

    it 'should keep the given order once any value is marked raw' do
      params = { 'note' => raw.call('1'), 'a' => '2' }
      expect(Faraday::NestedParamsEncoder.encode({ 'note' => '1', 'a' => '2' })).to eq('a=2&note=1')
      expect(described_class.encode(params)).to eq('note=1&a=2')
    end

    it 'should emit a raw value without escaping it' do
      expect(described_class.encode({ 'd' => raw.call('a%3Bb+c') })).to eq('d=a%3Bb+c')
    end

    it 'should emit a bare name for a nil element inside a raw repeated group' do
      # `q=` and a bare `q` are different requests to an API that distinguishes them, and Faraday
      # makes the same distinction (q%5B%5D vs q%5B%5D=), so raw mode must not collapse them.
      expect(described_class.encode({ 'q' => [raw.call('A'), nil] })).to eq('q=A&q')
    end

    it 'should keep the equals sign for an empty-string element inside a raw repeated group' do
      expect(described_class.encode({ 'q' => [raw.call('A'), ''] })).to eq('q=A&q=')
    end

    it 'should escape an ordinary value that sits beside a raw one' do
      params = { 'd' => raw.call('a%3Bb'), 'note' => 'x y' }
      expect(described_class.encode(params)).to eq('d=a%3Bb&note=x+y')
    end

    it 'should preserve insertion order' do
      params = { 'z' => raw.call('1'), 'a' => raw.call('2'), 'm' => raw.call('3') }
      expect(described_class.encode(params)).to eq('z=1&a=2&m=3')
    end

    it 'should escape the name of a raw parameter' do
      expect(described_class.encode({ '$top' => raw.call('a%3Bb') })).to eq('%24top=a%3Bb')
    end

    it 'should emit repeated raw values bare rather than appending []' do
      expect(described_class.encode({ 'q' => [raw.call('A'), raw.call('B')] })).to eq('q=A&q=B')
    end

    it 'should emit a bare semicolon inside a raw value untouched' do
      expect(described_class.encode({ 'd' => raw.call('sig;api_key=EVIL') })).to eq('d=sig;api_key=EVIL')
    end

    it 'should escape only the ordinary element of a mixed repeated parameter' do
      expect(described_class.encode({ 'q' => [raw.call('a%3B'), 'x y'] })).to eq('q=a%3B&q=x+y')
    end

    it 'should delegate an array of pairs, the other shape Faraday accepts' do
      expect(described_class.encode([%w[b 2], %w[a 1]])).to eq(Faraday::NestedParamsEncoder.encode([%w[b 2], %w[a 1]]))
    end

    it 'should honour a marker in an array of pairs rather than double-encoding it' do
      # Faraday's encoder contract accepts this shape too; missing it here would silently reproduce
      # the double-encoding this class exists to prevent.
      expect(described_class.encode([['sig', raw.call('a%3Bb')], %w[x y]])).to eq('sig=a%3Bb&x=y')
    end

    it 'should refuse a hash or array grouped with a marker instead of emitting its to_s' do
      # Faraday would nest these; raw mode has already fixed the group's wire format, so a silent
      # `{"k" => "v"}.to_s` on the wire is the one outcome that must not happen.
      [{ 'k' => 'v' }, %w[x y]].each do |element|
        expect { described_class.encode({ 'h' => [raw.call('a%3Bb'), element] }) }
          .to raise_error(IPaaS::Error, /must be a scalar/)
      end
    end

    it 'should still escape an ordinary non-string element grouped with a marker' do
      expect(described_class.encode({ 'h' => [raw.call('a%3Bb'), 123] })).to eq('h=a%3Bb&h=123')
    end

    it 'should return nil for nil params' do
      expect(described_class.encode(nil)).to be_nil
    end
  end

  describe '.encode with a raw value that escaped its own guard' do
    # RawParamValue refuses these at construction, so the only way to reach the wire with one is a
    # forged instance. The assertions exist for that impossible state, and these examples forge it.
    def forged_raw(value)
      IPaaS::Job::Outbound::RawParamValue.new('ok').tap do |raw_value|
        raw_value.instance_variable_set(:@value, value.dup.freeze)
      end
    end

    it 'should raise on a raw value that reached the wire with a bare ampersand' do
      expect { described_class.encode({ 'd' => forged_raw('sig&api_key=EVIL') }) }
        .to raise_error(IPaaS::Error, /reached the wire with a bare '&' at index 3/)
    end

    it 'should raise on an encoded query that still carries a character the URL layer deletes' do
      ["a\tb", "a\rb", "a\nb"].each do |value|
        expect { described_class.encode({ 'd' => forged_raw(value) }) }
          .to raise_error(IPaaS::Error, /carries a tab, carriage return or newline/)
      end
    end
  end

  describe '.decode' do
    it 'should decode through Faraday so a round trip behaves as before' do
      # A flat query decodes identically under both Faraday encoders, so use a nested one: this
      # example has to fail if decode is ever pointed at FlatParamsEncoder.
      nested = 'a%5Bb%5D=1&q%5B%5D=A&q%5B%5D=B'
      expect(described_class.decode(nested)).to eq(Faraday::NestedParamsEncoder.decode(nested))
      expect(described_class.decode(nested)).not_to eq(Faraday::FlatParamsEncoder.decode(nested))
    end
  end

  describe '.raw?' do
    it 'should be true when any value is raw' do
      expect(described_class.raw?({ 'a' => '1', 'd' => raw.call('x') })).to be(true)
    end

    it 'should be true when a raw value is nested in a repeated parameter' do
      expect(described_class.raw?({ 'q' => ['A', raw.call('B')] })).to be(true)
    end

    it 'should be false for a marker below the top level, which is therefore escaped as usual' do
      # Stated limitation: only top-level values carry the marker. A nested one is escaped even
      # when a sibling puts the encoder into raw mode, so pin both halves.
      expect(described_class.raw?({ 'filter' => { 'sig' => raw.call('a%3Bb') } })).to be(false)
      expect(described_class.encode({ 'd' => raw.call('x'), 'filter' => { 'sig' => raw.call('a%3Bb') } }))
        .to eq('d=x&filter%5Bsig%5D=a%253Bb')
    end

    it 'should be false when no value is raw' do
      expect(described_class.raw?({ 'a' => '1', 'q' => %w[A B] })).to be(false)
    end

    it 'should be false for blank params' do
      expect(described_class.raw?(nil)).to be(false)
      expect(described_class.raw?({})).to be(false)
    end
  end
end

describe IPaaS::Job::Outbound::RawParamValue do
  it 'should stringify to the wrapped value' do
    expect(described_class.new('a%3Bb').to_s).to eq('a%3Bb')
  end

  it 'should refuse a value containing a bare ampersand' do
    # Unescaped, it would split into a second query parameter on an authenticated request.
    expect { described_class.new('sig&api_key=EVIL') }
      .to raise_error(IPaaS::Error, /must not contain '&', a tab/)
  end

  it 'should accept an encoded ampersand, which is what a signed URL actually carries' do
    expect(described_class.new('sig%26api_key').to_s).to eq('sig%26api_key')
  end

  it 'should accept a bare semicolon, which a CloudFront signed URL carries as is' do
    # The encoder joins parameters with `&` only, so a `;` stays inside its value on the wire.
    expect(described_class.new('text/plain;charset=utf-8').to_s).to eq('text/plain;charset=utf-8')
  end

  it 'should accept an encoded semicolon, which is what a signed URL actually carries' do
    expect(described_class.new('attachment%3B+filename').to_s).to eq('attachment%3B+filename')
  end

  it 'should refuse a value containing a character the URL layer would silently delete' do
    # URI::Generic#query= runs delete!("\t\r\n"), so these corrupt the signature with no error.
    ["sig\nature", "sig\tature", "sig\rature"].each do |value|
      expect { described_class.new(value) }
        .to raise_error(IPaaS::Error, /must not contain '&', a tab/)
    end
  end

  it 'should refuse a malformed percent escape the URL layer raises on' do
    expect { described_class.new('100%zz') }
      .to raise_error(IPaaS::Error, /must not contain a '%' that is not followed by two hex digits/)
  end

  it 'should refuse a malformed percent escape the URL layer would ship verbatim' do
    # URI::Generic#query= only raises on %<non-hex><non-hex>; every other malformed escape reaches
    # the target unchanged, which is a silent 403 on a signed URL.
    ['discount%off', '50%', 'a%2G', 'report%.csv'].each do |value|
      expect { described_class.new(value) }
        .to raise_error(IPaaS::Error, /must not contain a '%' that is not followed by two hex digits/)
    end
  end

  it 'should accept the well-formed escapes a signed URL is made of' do
    signed = 'attachment%3B+filename%2A%3DUTF-8%27%2720260811-products-1.csv'
    expect(described_class.new(signed).to_s).to eq(signed)
  end

  it 'should name the offending character and its position rather than echoing the value' do
    # The documented payload is a signature, so the message must not put it in the job log.
    expect { described_class.new('SUPER&SECRET') }
      .to raise_error(IPaaS::Error, /found one at index 5/)
    expect { described_class.new('SUPER&SECRET') }
      .to(raise_error { |error| expect(error.message).not_to include('SUPER&SECRET') })
  end

  it 'should not read a later mutation of the string it was built from' do
    # String#to_s returns self, so without the dup the guard would be check-then-use.
    original = +'sig'
    wrapper = described_class.new(original)
    original << '&api_key=EVIL'
    expect(wrapper.to_s).to eq('sig')
  end

  it 'should coerce a non-string value' do
    expect(described_class.new(42).to_s).to eq('42')
  end

  it 'should inspect as the wrapped value so connector logs read unchanged' do
    expect({ 'd' => described_class.new('a%3Bb') }.to_s).to eq({ 'd' => 'a%3Bb' }.to_s)
  end

  it 'should stay atomic under Array(), which unwraps a Struct into its members' do
    # A one-member Struct would yield ['a%3Bb'] here, which is the same size but has lost the
    # marker, so assert on the element's type rather than just the count.
    wrapped = Array(described_class.new('a%3Bb'))
    expect(wrapped.size).to eq(1)
    expect(wrapped.first).to be_a(described_class)
  end
end
