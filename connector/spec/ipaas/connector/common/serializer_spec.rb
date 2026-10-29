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

  it 'should parse a Regexp value' do
    expect(subject.class.parse('default: !ruby/regexp /\d+/')).to eq({ 'default' => /\d+/ })
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

  describe 'parsing with a name' do
    it 'defaults the uuid to the base name of a .yaml or .yml name, as a file at that path would' do
      expect(subject.class.parse('foo: baz', with_uuid: true, name: '/solution/runbooks/r-1.yaml'))
        .to eq({ 'foo' => 'baz', 'uuid' => 'r-1' })
      expect(subject.class.parse('foo: baz', with_uuid: true, name: '/solution/runbooks/r-2.yml'))
        .to eq({ 'foo' => 'baz', 'uuid' => 'r-2' })
    end

    it 'defaults to a random uuid for a name that is not a YAML file, as without a name' do
      named = subject.class.parse('foo: baz', with_uuid: true, name: '/solution/runbooks/r-1.txt')
      unnamed = subject.class.parse('foo: baz', with_uuid: true)

      expect([named['uuid'], unnamed['uuid']]).to all(match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/))
      expect(named['uuid']).not_to eq('r-1')
    end

    it 'keeps the uuid the content holds' do
      expect(subject.class.parse("uuid: given\nfoo: baz", with_uuid: true, name: '/solution/runbooks/r-1.yaml'))
        .to eq({ 'uuid' => 'given', 'foo' => 'baz' })
    end

    it 'does not default the uuid unless requested' do
      expect(subject.class.parse('foo: baz', name: '/solution/runbooks/r-1.yaml')).to eq({ 'foo' => 'baz' })
    end

    it 'takes the uuid from the path of a file, not from the name' do
      file = Tempfile.new(%w[my-file .yaml])
      begin
        file << 'foo: baz'
        file.close

        name = '/solution/runbooks/r-1.yaml'
        parsed = File.open(file.path) { |f| subject.class.parse(f, with_uuid: true, name: name) }
        expect(parsed).to eq({ 'foo' => 'baz', 'uuid' => File.basename(file.path, '.yaml') })
      ensure
        file.close!
      end
    end
  end

  context 'a SecretString written by an older release' do
    let(:stored) do
      "---\n:id: :api_key\n:label: API Key\n:type: :secret_string\n" \
        ":default: !ruby/object:IPaaS::Encryption::SecretString\n  encrypted: gAAAA_blob==\n  encryptor:\n"
    end
    let(:field) { IPaaS::Connector::Schema::Field.new(**subject.class.parse(stored)) }

    it 'loads under strict parsing, keeps the ciphertext, and validates' do
      expect(field.default).to be_a(IPaaS::Encryption::SecretString)
      expect(field.default.encrypted).to eq('gAAAA_blob==')
      expect(field).to be_valid
    end

    it 'rewrites it to the untagged form on the next save' do
      dumped = field.to_h_ref.to_yaml

      expect(dumped).not_to include('!ruby/object:')
      expect(dumped).to include('gAAAA_blob==')
    end
  end

  # A YAML alias is not part of what a solution file may contain. That is a deliberate limit, not
  # an oversight: allowing them is a change that has to go through a full security review first.
  # Both load paths refuse them, and these pin that so the limit cannot lapse quietly.
  context 'YAML aliases' do
    let(:aliased) { "a: &x\n  b: 1\nc: *x\n" }

    it 'are refused on the strict path and on the tolerant one' do
      expect { subject.class.parse(aliased) }.to raise_error(Psych::AliasesNotEnabled)
      expect { subject.class.parse(aliased, tolerant: true) }.to raise_error(Psych::AliasesNotEnabled)
    end

    it 'are the only thing refused: the same document loads once the alias is written out' do
      written_out = "a:\n  b: 1\nc:\n  b: 1\n"

      expect(subject.class.parse(written_out)).to eq('a' => { 'b' => 1 }, 'c' => { 'b' => 1 })
    end
  end

  context 'tolerant loading' do
    after { described_class.reset_tolerant_substitution! }

    let(:unpermitted) { UnresolvedNodeHelper::UNPERMITTED_CLASS }
    let(:yaml_with_unpermitted) { "---\nname: rb\n#{unpermitted_mapping_yaml(key: 'value')}" }

    it 'raises on an unpermitted class when not tolerant' do
      expect { subject.class.parse(yaml_with_unpermitted) }
        .to raise_error(Psych::DisallowedClass, /#{unpermitted}/)
    end

    it 'substitutes an UnresolvedNode when tolerant and re-emits it byte-for-byte on save' do
      result = subject.class.parse(yaml_with_unpermitted, tolerant: true)
      expect(result['name']).to eq('rb')
      expect(result['value']).to be_a(IPaaS::Connector::Common::UnresolvedNode)
      expect(result['value'].unresolved_class).to eq(unpermitted)
      expect(subject.class.dump(result)).to eq(yaml_with_unpermitted)
    end

    it 'ignores documents after the first, as strict loading does' do
      trailing_junk = "#{unpermitted_mapping_yaml}---\nbroken: [1, 2\n"

      expect { subject.class.parse(trailing_junk) }.to raise_error(Psych::DisallowedClass)
      expect(subject.class.parse(trailing_junk, tolerant: true)['v'])
        .to be_a(IPaaS::Connector::Common::UnresolvedNode)
    end

    ['', "# only a comment\n", "---\n"].each do |content|
      it "returns nil for #{content.inspect} rather than failing to walk the stream" do
        expect(subject.class.parse(content, tolerant: true)).to be_nil
      end
    end

    it 'still parses a permitted Regexp on the tolerant path' do
      expect(subject.class.parse('default: !ruby/regexp /\d+/', tolerant: true)).to eq({ 'default' => /\d+/ })
    end

    it 'rejects a YAML alias outside the captured node, matching strict loading' do
      aliased = "z: !ruby/object:#{unpermitted} {}\na: &a [x]\nb: [*a]\n"
      expect { subject.class.parse(aliased, tolerant: true) }.to raise_error(Psych::AliasesNotEnabled)
    end

    it 'rejects a YAML alias nested inside the captured node' do
      aliased = "a: &a [x]\nv: !ruby/object:#{unpermitted}\n  data: *a\n"
      expect { subject.class.parse(aliased, tolerant: true) }.to raise_error(Psych::AliasesNotEnabled)
    end

    it 'records that a substitution occurred only when one happened' do
      subject.class.reset_tolerant_substitution!
      subject.class.parse('foo: bar', tolerant: true)
      expect(subject.class.tolerant_substitution_occurred?).to be(false)

      subject.class.parse(yaml_with_unpermitted, tolerant: true)
      expect(subject.class.tolerant_substitution_occurred?).to be(true)
    end

    context 'a legacy secret whose encryptor is not permitted' do
      let(:legacy_secret_yaml) do
        "value: !ruby/object:IPaaS::Encryption::SecretString\n  " \
          "encrypted: gAAAA_blob==\n  " \
          "encryptor: !ruby/object:IPaaS::Encryption::Encryptor\n    " \
          "key: k\n"
      end

      it 'loads the secret and keeps no placeholder in the result' do
        result = subject.class.parse(legacy_secret_yaml, tolerant: true)

        expect(result['value']).to be_a(IPaaS::Encryption::SecretString)
        expect(result['value'].encrypted).to eq('gAAAA_blob==')
        expect(result['value'].encryptor).to be_nil
        expect(IPaaS::Connector::Common::UnresolvedNode.within?(result)).to be(false)
      end

      it 'records no substitution, because the placeholder never survived the load' do
        subject.class.reset_tolerant_substitution!

        subject.class.parse(legacy_secret_yaml, tolerant: true)

        expect(subject.class.tolerant_substitution_occurred?).to be(false)
      end
    end

    {
      'a Complex mapping' => "v: !ruby/object:Complex\n  real: 1\n  image: 2\n",
      'a Complex scalar' => "v: !ruby/object:Complex 1+2i\n",
      'a Rational mapping' => "v: !ruby/object:Rational\n  numerator: 1\n  denominator: 3\n",
      'a Rational scalar' => "v: !ruby/object:Rational 1/3\n",
      'a BigDecimal' => "v: !ruby/object:BigDecimal '0:0.1e1'\n",
      'a Ruby class reference' => "v: !ruby/class File\n",
      'a Ruby module reference' => "v: !ruby/module Kernel\n",
      'a Range' => "v: !ruby/range 1..5\n",
      'an Exception' => "v: !ruby/exception\n  message: boom\n",
      'a Struct' => "v: !ruby/struct\n  a: 1\n",
      'a String subclass' => "v: !ruby/string:MyStr hello\n",
      'a tagged sequence' => "v: !ruby/array:MyArr\n- 1\n- 2\n",
    }.each do |description, yaml|
      it "does not materialize #{description} on the tolerant path" do
        expect { subject.class.parse(yaml) }.to raise_error(Psych::DisallowedClass)

        value = subject.class.parse(yaml, tolerant: true)['v']
        expect(value).to be_a(IPaaS::Connector::Common::UnresolvedNode)
      end

      it "keeps the tag and payload of #{description} byte-for-byte across a save" do
        dumped = subject.class.dump(subject.class.parse(yaml, tolerant: true)).delete_prefix("---\n")

        expect(dumped).to eq(yaml)
        expect(subject.class.parse(dumped, tolerant: true)['v'])
          .to be_a(IPaaS::Connector::Common::UnresolvedNode)
      end
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

    context 'a placeholder sharing an array with a healthy field' do
      let(:healthy) { IPaaS::Connector::Schema::Field.new(id: :ok, label: 'OK', type: :string) }

      it 'dereferences the healthy field when the placeholder is ahead of it' do
        node = unresolved_node
        result = subject.class.to_h(double(fields: [node, healthy]), :fields)

        expect(result[:fields].first).to be(node)
        expect(result[:fields].last).to eq({ id: :ok, label: 'OK', type: :string })
      end

      it 'dereferences the healthy field when the placeholder is behind it' do
        node = unresolved_node
        result = subject.class.to_h(double(fields: [healthy, node]), :fields)

        expect(result[:fields].first).to eq({ id: :ok, label: 'OK', type: :string })
        expect(result[:fields].last).to be(node)
      end

      it 'writes the healthy field as a plain mapping rather than a native object tag' do
        dumped = subject.class.dump(subject.class.to_h(double(fields: [unresolved_node, healthy]), :fields))

        expect(dumped).not_to include('!ruby/object:IPaaS::Connector::Schema::Field')
        expect(dumped).to include('gAAAA_blob==')
      end
    end
  end

  context 'dump' do
    it 'refuses to write a class it could not read back' do
      expect { subject.class.dump({ 'v' => Legacy::RemovedSecret.new('gAAAA_blob==') }) }
        .to raise_error(IPaaS::Error, /Legacy::RemovedSecret/)
    end

    it 'writes a permitted class that defines encode_with' do
      dumped = subject.class.dump({ 'v' => IPaaS::Encryption::SecretString.new('cipher') })

      expect(dumped).to include('cipher')
    end
  end

  context 'a file that breaks the YAML limits' do
    let(:limits) { IPaaS::Connector::Common::YamlLimits }

    def nested(levels)
      "#{(0...levels).map { |level| "#{'  ' * level}a:" }.join("\n")} 1\n"
    end

    # The subclass carries which limit broke, and stays in the family callers handle per file.
    it 'refuses content nested past the depth limit, naming the limit rather than the file' do
      expect { described_class.parse(nested(limits::MAX_DEPTH + 1)) }
        .to raise_error(limits::Exceeded, "exceeds the maximum nesting depth of #{limits::MAX_DEPTH}") { |e|
          expect(e.kind).to eq(:depth)
          expect(e).to be_a(IPaaS::Error)
        }
    end

    it 'refuses content over the size limit, naming that limit instead' do
      expect { described_class.parse("a: #{'x' * limits::MAX_BYTES}\n") }
        .to raise_error(limits::Exceeded, "exceeds the maximum size of #{limits::MAX_BYTES / 1024} KB") { |e|
          expect(e.kind).to eq(:size)
        }
    end

    it 'parses content sitting exactly on the depth limit, so the cap is reachable' do
      at_the_limit = nested(limits::MAX_DEPTH)
      expect(limits.depth(at_the_limit)).to eq(limits::MAX_DEPTH) # pins the helper's arithmetic

      expect(described_class.parse(at_the_limit)).to be_a(Hash)
    end

    it 'parses content sitting exactly on the size limit, so that cap is reachable too' do
      at_the_limit = "a: #{'x' * (limits::MAX_BYTES - 4)}\n"
      expect(limits.bytes(at_the_limit)).to eq(limits::MAX_BYTES) # pins the helper's arithmetic

      expect(described_class.parse(at_the_limit)).to be_a(Hash)
    end

    it 'parses content that is wide but shallow, however many collections it holds' do
      wide = (0...(limits::MAX_DEPTH * 4)).map { |index| "key#{index}: [#{index}]" }.join("\n")
      expect(limits.depth(wide)).to eq(2) # a node counter, not a depth counter, would reject this

      expect(described_class.parse(wide).size).to eq(limits::MAX_DEPTH * 4)
    end

    # One guard ahead of the parse covers the tolerant path too.
    it 'refuses over-depth content on the tolerant path too, rather than tolerating it' do
      over_depth_with_a_disallowed_class =
        "#{nested(limits::MAX_DEPTH + 1)}b: !ruby/object:Unknown {}\n"

      expect { described_class.parse(over_depth_with_a_disallowed_class, tolerant: true) }
        .to raise_error(limits::Exceeded, /maximum nesting depth/)
    end

    it 'leaves a value that was never YAML alone, since there is no file to judge' do
      deep_hash = (0...(limits::MAX_DEPTH + 1)).inject({ 'a' => 1 }) { |inner, _| { 'a' => inner } }

      expect(described_class.parse(deep_hash)).to eq(deep_hash)
    end
  end
end
