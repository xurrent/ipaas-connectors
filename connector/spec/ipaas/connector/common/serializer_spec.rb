require 'spec_helper'

describe IPaaS::Connector::Common::Serializer do
  it 'should parse a YAML string' do
    expect(subject.class.parse('foo: bar')).to eq({ 'foo' => 'bar' })
  end

  it 'should parse a YAML string and add UUID if requested' do
    result = subject.class.parse('foo: bar', with_uuid: true)
    expect(result['foo']).to eq('bar')
    expect(result['uuid']).to be_present
    expect(result.keys).to contain_exactly('foo', 'uuid')
  end

  it 'should add a UUID to a YAML string if requested' do
    result = subject.class.parse('foo: bar', with_uuid: true)
    expect(result['foo']).to eq('bar')
    expect(result['uuid']).to be_present
    expect(result.keys).to contain_exactly('foo', 'uuid')
  end

  it 'should add a UUID to a hash if requested' do
    result = subject.class.parse({ foo: :baz }, with_uuid: true)
    expect(result[:foo]).to eq(:baz)
    expect(result['uuid']).to be_present
    expect(result.keys).to contain_exactly(:foo, 'uuid')
  end

  it 'should not add a UUID to a hash if already present as string' do
    result = subject.class.parse({ foo: :baz, 'uuid' => 'sadasd' }, with_uuid: true)
    expect(result[:foo]).to eq(:baz)
    expect(result['uuid']).to eq('sadasd')
    expect(result.keys).to contain_exactly(:foo, 'uuid')
  end

  it 'should not add a UUID to a hash if already present as symbol' do
    result = subject.class.parse({ foo: :baz, uuid: 'sadasd' }, with_uuid: true)
    expect(result[:foo]).to eq(:baz)
    expect(result[:uuid]).to eq('sadasd')
    expect(result.keys).to contain_exactly(:foo, :uuid)
  end

  it 'should return the value when it is not a string' do
    expect(subject.class.parse(:foo)).to eq(:foo)
  end

  it 'should parse a YAML file' do
    file = Tempfile.new(%w[my-file .yaml])
    begin
      uuid = SecureRandom.uuid_v7
      file << "uuid: #{uuid}"
      file.close

      f = File.new(file.path)
      expect(subject.class.parse(f, with_uuid: true)).to eq({ 'uuid' => uuid })
    ensure
      file.close!
    end
  end

  it 'should not default uuid when parsing a YAML file unless requested' do
    file = Tempfile.new(%w[my-file .yaml])
    begin
      file << 'foo: baz'
      file.close

      f = File.new(file.path)
      expect(subject.class.parse(f)).to eq({ 'foo' => 'baz' })
    ensure
      file.close!
    end
  end

  it 'should default uuid when parsing a YAML file if requested' do
    file = Tempfile.new(%w[my-file .yaml])
    begin
      file << 'foo: baz'
      file.close

      f = File.new(file.path)
      expect(subject.class.parse(f,
                                 with_uuid: true)).to eq({ 'foo' => 'baz',
                                                           'uuid' => File.basename(file.path, '.yaml'), })
    ensure
      file.close!
    end
  end

  it 'should default uuid when parsing a YML file if requested' do
    file = Tempfile.new(%w[my-file2 .yml])
    begin
      file << 'foo: baz'
      file.close

      f = File.new(file.path)
      expect(subject.class.parse(f,
                                 with_uuid: true)).to eq({ 'foo' => 'baz', 'uuid' => File.basename(file.path, '.yml') })
    ensure
      file.close!
    end
  end

  context 'to_h' do
    it 'should create a hash with all attributes' do
      expect(subject.class.to_h(double(foo: 'a', bar: 1), :foo, :bar)).to eq({ foo: 'a', bar: 1 })
    end

    it 'should create a hash with selected attributes' do
      expect(subject.class.to_h(double(foo: 'a', bar: 1), :bar)).to eq({ bar: 1 })
    end

    it 'should add nested attributes' do
      expect(subject.class.to_h(double(foo: double(to_h_ref: 'nested')), :foo)).to eq({ foo: 'nested' })
    end

    it 'should add array nested attributes' do
      expect(subject.class.to_h(double(foo: [double(to_h_ref: 1), double(to_h_ref: 2)]), :foo)).to eq({ foo: [1, 2] })
    end
  end
end
