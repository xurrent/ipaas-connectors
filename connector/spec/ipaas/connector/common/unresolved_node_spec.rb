require 'spec_helper'

describe IPaaS::Connector::Common::UnresolvedNode do
  it 'captures the original class name and a message' do
    node = unresolved_node

    expect(node.unresolved_class).to eq(UnresolvedNodeHelper::UNPERMITTED_CLASS)
    expect(node.message).to eq("could not load value of type '#{UnresolvedNodeHelper::UNPERMITTED_CLASS}'")
  end

  it 'round-trips the original node verbatim through a save' do
    yaml = unpermitted_mapping_yaml

    parsed = IPaaS::Connector::Common::Serializer.parse(yaml, tolerant: true)

    expect(IPaaS::Connector::Common::Serializer.dump(parsed)).to eq("---\n#{yaml}")
  end

  it 'returns no payload for JSON so a placeholder cannot leak through a JSON prop' do
    node = unresolved_node('secret_blob==')

    expect(node.as_json).to be_nil
    expect(node.to_json).not_to include('secret_blob==')
  end

  {
    'a leading-zero integer' => '0755',
    'a sexagesimal-looking value' => '1:30',
    'a boolean-looking value' => 'yes',
    'a zero-padded number' => '00123',
    'a date-looking value' => '2026-01-01',
  }.each do |description, raw|
    it "keeps #{description} unquoted and unconverted across a save" do
      yaml = unpermitted_mapping_yaml(raw)

      expect(dump_unresolved(unresolved_node(raw))).to eq(yaml)
    end
  end

  it 'keeps an explicit merge key instead of flattening it into the value' do
    yaml = "v: !ruby/object:#{UnresolvedNodeHelper::UNPERMITTED_CLASS}\n  a: 2\n  <<: {a: 1, c: 3}\n"

    expect(dump_unresolved(IPaaS::Connector::Common::Serializer.parse(yaml, tolerant: true)['v']))
      .to eq(yaml)
  end

  {
    'a nested unpermitted object' => "  inner: !ruby/object:Legacy::Inner\n    a: 1\n",
    'a nested symbol' => "  sym: !ruby/symbol foo\n",
    'nested binary' => "  bin: !!binary |-\n    aGVsbG8=\n",
    'a nested regexp' => "  re: !ruby/regexp /abc/i\n",
    'a nested permitted secret' => "  secret: !ruby/object:IPaaS::Encryption::SecretString\n    encrypted: cipher\n",
  }.each do |description, body|
    it "keeps #{description} tagged across a save" do
      yaml = "v: !ruby/object:#{UnresolvedNodeHelper::UNPERMITTED_CLASS}\n#{body}"

      expect(dump_unresolved(IPaaS::Connector::Common::Serializer.parse(yaml, tolerant: true)['v']))
        .to eq(yaml)
    end
  end

  it 'keeps every spelling of null a null rather than quoting it into a string' do
    %w[null nulL nuLl nuLL nUll nUlL nULl nULL Null NulL NuLl NuLL NUll NUlL NULl NULL].each do |spelling|
      yaml = "v: !ruby/object:#{UnresolvedNodeHelper::UNPERMITTED_CLASS}\n  encrypted: #{spelling}\n"

      expect(dump_unresolved(IPaaS::Connector::Common::Serializer.parse(yaml, tolerant: true)['v']))
        .to eq(yaml)
    end
  end

  it 'ignores a serialized encryptor so a secret written by an older release revives usable' do
    yaml = "v: !ruby/object:IPaaS::Encryption::SecretString\n  encrypted: cipher\n  " \
           "encryptor: !ruby/object:Legacy::KeyProvider\n    id: 1\n"
    secret = IPaaS::Connector::Common::Serializer.parse(yaml, tolerant: true)['v']

    expect(secret.encrypted).to eq('cipher')
    expect(secret.encryptor).to be_nil
    expect(described_class.within?(secret)).to be(false)
  end

  it 'reports a placeholder held in a permitted object instance variable' do
    secret = IPaaS::Encryption::SecretString.new('cipher', unresolved_node)

    expect(described_class.within?(secret)).to be(true)
    expect(described_class.all_within(secret).map(&:unresolved_class))
      .to eq([UnresolvedNodeHelper::UNPERMITTED_CLASS])
  end

  it 'keeps a tagged sequence and its scalar styles across a save' do
    yaml = unpermitted_sequence_yaml

    expect(dump_unresolved(IPaaS::Connector::Common::Serializer.parse(yaml, tolerant: true)['v']))
      .to eq(yaml)
  end

  it 'reads as its message rather than a heap address' do
    expect(unresolved_node.to_s).to eq("could not load value of type '#{UnresolvedNodeHelper::UNPERMITTED_CLASS}'")
  end

  describe 'sorting alongside the strings it stands in for' do
    it 'compares by its message from either side' do
      node = unresolved_node

      expect(node <=> 'a').to eq(1)
      expect('a' <=> node).to eq(-1)
    end

    it 'is what keeps a sort of names alive once one of them is a placeholder' do
      node = unresolved_node

      expect(['zebra', node, 'apple'].sort.map(&:to_s))
        .to eq(['apple', node.message, 'zebra'])
    end

    it 'stays incomparable with a value that is not a name' do
      expect(unresolved_node <=> 42).to be_nil
    end
  end

  describe 'finding placeholders in a structure' do
    it 'stops walking once it finds one' do
      node = unresolved_node
      visited = []
      probe = IPaaS::Encryption::SecretString.new('cipher')
      probe.define_singleton_method(:instance_variables) do
        visited << :probed
        []
      end

      expect(described_class.within?({ 'a' => probe })).to be(false)
      expect(visited).to eq([:probed])

      visited.clear
      expect(described_class.within?([node, probe])).to be(true)
      expect(visited).to be_empty
    end

    it 'finds a placeholder held in the instance variable of a permitted class' do
      node = unresolved_node
      holder = IPaaS::Encryption::SecretString.new('cipher')
      holder.instance_variable_set(:@probe, [node])

      expect(described_class.within?({ 'a' => holder })).to be(true)
      expect(described_class.all_within({ 'a' => holder })).to eq([node])
    end

    it 'returns rather than recursing forever on a self-referential structure' do
      node = unresolved_node
      cyclic = { 'bad' => node }
      cyclic['self'] = cyclic

      expect(described_class.within?(cyclic)).to be(true)
      expect(described_class.all_within(cyclic)).to eq([node])
    end

    it 'returns false rather than overflowing on a cycle that holds no placeholder' do
      cyclic = []
      cyclic << cyclic

      expect(described_class.within?(cyclic)).to be(false)
      expect(described_class.all_within(cyclic)).to be_empty
    end

    it 'visits a shared subtree once rather than once per path to it' do
      leaf = { 'x' => 1 }
      tree = leaf
      24.times { tree = { 'a' => tree, 'b' => tree } }

      expect { Timeout.timeout(5) { described_class.within?(tree) } }.not_to raise_error
    end

    it 'walks nesting deeper than a recursive walk survives' do
      node = unresolved_node
      with_node = (1..10_000).reduce([node]) { |inner, _| [inner] }
      without_node = (1..10_000).reduce([1]) { |inner, _| [inner] }

      expect(Thread.new { [described_class.within?(with_node), described_class.all_within(with_node)] }.value)
        .to eq([true, [node]])
      expect(Thread.new { [described_class.within?(without_node), described_class.all_within(without_node)] }.value)
        .to eq([false, []])
    end

    it 'finds every placeholder when it has to collect them all' do
      first = unresolved_node('one')
      second = unresolved_node('two')

      expect(described_class.all_within({ 'a' => first, 'b' => [second] })).to eq([first, second])
    end
  end

  it 'visits each node of a deeply nested disallowed tag once, not once per level' do
    visits = 0
    allow(described_class).to receive(:reject_aliases!).and_wrap_original do |original, node|
      visits += 1
      original.call(node)
    end

    depth = 16
    yaml = 'x'
    depth.times { yaml = "!ruby/exception:Nope\n  message: #{yaml}\n".gsub(/^/, '  ').sub('  ', '') }
    IPaaS::Connector::Common::Serializer.parse("v: #{yaml.lstrip}", tolerant: true)

    expect(visits).to be <= 3 * depth
  end

  it 'forgets what it checked between parses so a reused node object is rechecked' do
    depth = 4
    yaml = 'x'
    depth.times { yaml = "!ruby/exception:Nope\n  message: #{yaml}\n".gsub(/^/, '  ').sub('  ', '') }
    document = "v: #{yaml.lstrip}"

    first = IPaaS::Connector::Common::Serializer.parse(document, tolerant: true)['v']
    second = IPaaS::Connector::Common::Serializer.parse(document, tolerant: true)['v']

    expect(first).to be_a(described_class)
    expect(second).to be_a(described_class)
    expect(dump_unresolved(second)).to eq(dump_unresolved(first))
  end
end
