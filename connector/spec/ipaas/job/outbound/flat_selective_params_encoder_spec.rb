require 'spec_helper'
require 'faraday'

describe IPaaS::Job::Outbound::FlatSelectiveParamsEncoder do
  let(:raw) { ->(value) { IPaaS::Job::Outbound::RawParamValue.new(value) } }

  describe '.encode' do
    # The flat variant is what `array_params: :flat` installs, so with nothing marked raw it has to
    # be indistinguishable from Faraday's flat encoder rather than from the default nested one.
    [
      ['ordinary and repeated', { 'note' => 'x y&z', 'q' => %w[A B] }],
      ['nil value', { 'a' => nil }],
      ['symbol keys', { a: '1', b: 2 }],
      ['non-ascii', { 'u' => 'ü ø' }],
      ['empty', {}],
    ].each do |label, params|
      it "should be byte-identical to Faraday's flat encoder for #{label} when nothing is marked raw" do
        expect(described_class.encode(params)).to eq(Faraday::FlatParamsEncoder.encode(params))
      end
    end

    # The contrast case: every shape above except a repeated parameter encodes the same under both
    # encoders, so only this one proves the flat encoder is the one in charge.
    it 'should repeat the parameter name where the default encoder brackets it' do
      params = { 'q' => %w[A B] }
      expect(described_class.encode(params)).to eq('q=A&q=B')
      expect(IPaaS::Job::Outbound::SelectiveParamsEncoder.encode(params)).to eq('q%5B%5D=A&q%5B%5D=B')
    end

    # The raw branch bypasses the Faraday encoder entirely, so these two cannot differ from the
    # nested variant by output. They are here to pin the mixin wiring: a flat variant that failed to
    # pick up the shared raw handling would escape these instead.
    it 'should emit a raw value without escaping it' do
      expect(described_class.encode({ 'd' => raw.call('a%3Bb+c') })).to eq('d=a%3Bb+c')
    end

    it 'should repeat the parameter name for a raw repeated parameter' do
      expect(described_class.encode({ 'h' => [raw.call('a%3Bb'), 'c d'] })).to eq('h=a%3Bb&h=c+d')
    end

    [
      ['a hash value', { 'a' => { 'b' => 1 } }],
      ['an array holding a hash', { 'h' => [{ 'k' => 'v' }] }],
      ['an array holding an array', { 'h' => ['x', %w[y z]] }],
    ].each do |label, params|
      it "should refuse #{label}" do
        expect { described_class.encode(params) }
          .to raise_error(IPaaS::Error, /array_params: :flat needs scalar values/)

        # contrast: SelectiveParamsEncoder does support recursing into parameters
        nested = IPaaS::Job::Outbound::SelectiveParamsEncoder
        expect { nested.encode(params) }.not_to raise_error
      end
    end
  end

  describe '.decode' do
    it "should decode through Faraday's flat encoder" do
      # A flat query decodes identically under both Faraday encoders, so use a bracketed one: this
      # example has to fail if decode is ever pointed at NestedParamsEncoder.
      nested = 'a%5Bb%5D=1&q%5B%5D=A&q%5B%5D=B'
      expect(described_class.decode(nested)).to eq(Faraday::FlatParamsEncoder.decode(nested))
      expect(described_class.decode(nested)).not_to eq(Faraday::NestedParamsEncoder.decode(nested))
    end
  end
end
