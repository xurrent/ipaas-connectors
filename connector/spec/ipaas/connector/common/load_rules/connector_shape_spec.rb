require 'spec_helper'

describe IPaaS::Connector::Common::LoadRules::ConnectorShape do
  # Defined on the example group rather than at the top level: a top-level `def` becomes a private
  # method on Object, which would pollute any set this suite compares verb names against.
  def check(source)
    described_class.check(source, 'spec')
  end

  def wrap(class_body)
    <<~RUBY
      class MyConnector < IPaaS::Connector::Definition
        #{class_body}
      end
    RUBY
  end

  def with_constant(assignment)
    wrap("#{assignment}\n  connector 'uuid' do\n    name 'My'\n  end")
  end

  def with_connector_statement(statement)
    wrap("connector 'uuid' do\n    #{statement}\n  end")
  end

  def findings_for(source)
    check(source).findings
  end

  let(:minimal) { with_connector_statement("name 'My'") }

  describe 'a source in shape' do
    it 'accepts the minimal connector definition, carrying the label a finding needs' do
      expect(check(minimal)).to have_attributes(in_shape?: true, checked?: true, findings: [],
                                                label: 'spec')
    end

    it 'accepts every structural position, nested as a connector nests them' do
      source = with_connector_statement(<<~DSL.strip)
        name 'My'
            inbound_connection do
              validate do |request|
                request
              end
            end
            outbound_connection do
              authenticate do |connection|
                connection
              end
            end
            trigger 'trigger-uuid' do
              name 'Trigger'
              parse do |request|
                request
              end
            end
            action 'action-uuid' do
              name 'Action'
              run do |input|
                input
              end
            end
      DSL
      expect(check(source)).to have_attributes(in_shape?: true, findings: [])
    end
  end

  describe 'file level' do
    {
      'holds more than one top-level expression' => "class A < IPaaS::Connector::Definition\nend\nB = 1\n",
      'does not define a class' => "IPaaS::Connector::Definition\n",
      'defines a namespaced class' => "class Outer::Inner < IPaaS::Connector::Definition\nend\n",
      'does not subclass IPaaS::Connector::Definition' => "class MyConnector < Object\nend\n",
      'does not hold exactly one connector declaration' => "class MyConnector < IPaaS::Connector::Definition\nend\n",
      'declares the connector with something other than a single literal uuid' =>
        "class MyConnector < IPaaS::Connector::Definition\n  connector do\n    name 'My'\n  end\nend\n",
    }.each do |message, source|
      it "refuses a source that #{message}" do
        expect(findings_for(source)).to eq([message])
      end
    end

    # The class name binds in the same scope and reaches as far as a class-body constant, so the
    # shadow rule has to cover it too — a permitted alias beside it would otherwise resolve through
    # the connector class rather than the real namespace.
    it 'refuses a class named after the root of a permitted path' do
      source = "class IPaaS < IPaaS::Connector::Definition\n  " \
               "connector 'uuid' do\n    name 'My'\n  end\nend\n"
      expect(findings_for(source)).to eq(
        ["names the class 'IPaaS', which shadows a permitted constant path"],
      )
    end

    it 'accepts an ordinary class name, so the refusal above is about the shadow' do
      source = "class AcmeConnector < IPaaS::Connector::Definition\n  " \
               "connector 'uuid' do\n    name 'My'\n  end\nend\n"
      expect(check(source)).to have_attributes(in_shape?: true)
    end

    it 'refuses two connector declarations, which is not exactly one' do
      source = wrap("connector 'a' do\n    name 'A'\n  end\n  connector 'b' do\n    name 'B'\n  end")
      expect(findings_for(source)).to eq(['does not hold exactly one connector declaration'])
    end
  end

  describe 'class body statements' do
    it 'accepts a constant beside the declaration' do
      expect(check(with_constant("A = 'x'.freeze"))).to have_attributes(in_shape?: true)
    end

    {
      'def sneaky; end' => 'def',
      'class String; end' => 'class',
      'module Extra; end' => 'module',
      'class << self; end' => 'sclass',
      'A ||= 1' => 'or_asgn',
      'A += 1' => 'op_asgn',
      'alias_method :a, :b' => 'send',
    }.each do |statement, node_type|
      it "refuses #{node_type} in the class body" do
        source = with_constant(statement)
        expect(findings_for(source)).to eq(
          ["holds #{node_type} where only constants and the connector declaration are allowed"],
        )
      end
    end
  end

  describe 'constant assignment, at every walked position' do
    # Interpolation inside single quotes is deliberate: these strings are the source under test, so
    # the checker must see the interpolation rather than this suite evaluating it.
    # A block-local rather than a constant: a constant assigned in a `describe` block lands on
    # Object, and a screaming-case name there can reach lists this suite must not perturb.
    # rubocop:disable-next Lint/InterpolationCheck
    constant_cases = {
      "A = 'x'" => nil,
      'A = 30.seconds.freeze' => nil,
      'A = 10.minutes' => nil,
      "A = <<-P.chomp.freeze\n    text\n  P" => nil,
      "A = { us: 'x' }.freeze" => nil,
      "A = ['x', :y, 1, 1.5, true, false, nil].freeze" => nil,
      'A = /plain/i' => nil,
      'A = 2 * 3' => nil,
      'A = __FILE__' => "assigns 'A' a value that is not a constant expression",
      'A = "x #{__FILE__}"' => "assigns 'A' a value that is not a constant expression",
      'A = __LINE__ * 2' => "assigns 'A' a value that is not a constant expression",
      'A = 2 * __LINE__' => "assigns 'A' a value that is not a constant expression",
      'A = [__LINE__]' => "assigns 'A' a value that is not a constant expression",
      'A = { a: __FILE__ }' => "assigns 'A' a value that is not a constant expression",
      'A = __FILE__.freeze' => "assigns 'A' a value that is not a constant expression",
      'A = [__FILE__].freeze' => "assigns 'A' a value that is not a constant expression",
      'A = %w[__FILE__ __LINE__]' => nil,
      'A = "#{1}__FILE__"' => nil,
      'A = IPaaS::Job::CompactHash' => nil,
      'A = IPaaS::Job::GraphQL::Schema' => nil,
      'A = [IPaaS::Job::Humanize]' => nil,
      'A = { humanize: IPaaS::Job::Humanize }' => nil,
      # A permitted-method call reaches its receiver through `literal?`, so a collection holding a
      # constant may not be frozen. No known connector needs it, and the obvious widening (accepting any
      # constant expression as a receiver) has implications we do not need to tackle when blocking.
      'A = [IPaaS::Job::Humanize].freeze' => "assigns 'A' a value that is not a constant expression",
      "A = 'x'\n  B = \"\#{A}/y\"" => nil,
      "A = 'x'.freeze\n  B = \"\#{A}/y\".freeze" => nil,
      'A = IPaaS::Job::Solution' => "assigns 'A' a value that is not a constant expression",
      'A = File' => "assigns 'A' a value that is not a constant expression",
      "A = File.write('/tmp/x', 'y')" => "assigns 'A' a value that is not a constant expression",
      'A = [1].map { |n| n }' => "assigns 'A' a value that is not a constant expression",
      'A = -> { 1 }' => "assigns 'A' a value that is not a constant expression",
      'A = [1]; B = [A]' => "assigns 'B' on a line that already assigns a constant",
      "A = 'x'; B = 'y'" => "assigns 'B' on a line that already assigns a constant",
      'A = /#{Time.now}/' => "assigns 'A' a value that is not a constant expression",
      'A = 1 + 2' => "assigns 'A' a value that is not a constant expression",
      "A = 'x' * 3" => "assigns 'A' a value that is not a constant expression",
      'A = B' => "assigns 'A' a value that is not a constant expression",
      "A = 'x'.upcase" => "assigns 'A' a value that is not a constant expression",
      # A permitted method is permitted on the receiver types it is defined on, and nowhere else,
      # so adding the same name to another type cannot widen what a constant may be built from.
      # A chained call's receiver is another call, whose class is not knowable from the tree, so a
      # typed method may only be applied to the literal itself. `freeze` is not typed, so it still
      # chains — in that order only.
      "A = 'x'.strip.freeze" => nil,
      "A = 'x'.freeze.strip" => "assigns 'A' a value that is not a constant expression",
      "A = 'x'.strip.chomp" => "assigns 'A' a value that is not a constant expression",
      # A regexp reaches a permitted method through `const_expr?` rather than `literal?`, so it
      # is not allowed to be frozen. Same asymmetry as the collection above: opening it introduces
      # complexity that is not warranted today.
      'A = /re/.freeze' => "assigns 'A' a value that is not a constant expression",
      "A = 'x'.seconds" => "assigns 'A' a value that is not a constant expression",
      'A = nil.minutes' => "assigns 'A' a value that is not a constant expression",
      'A = [1].strip' => "assigns 'A' a value that is not a constant expression",
      'A = {}.chomp' => "assigns 'A' a value that is not a constant expression",
      'A = 2.5.seconds' => nil,
      "A = 'x'.chomp" => nil,
      'A::B = 1' => 'assigns a namespaced constant',
      "IPaaS = 'decoy'" => "assigns 'IPaaS', which shadows a permitted constant path",
    }

    constant_cases.each do |assignment, message|
      context "with `#{assignment.lines.first.strip}` in the class body" do
        it message.nil? ? 'accepts it' : "refuses it: #{message}" do
          expect(findings_for(with_constant(assignment))).to eq([message].compact)
        end
      end

      it "applies the same rule inside a structural block: `#{assignment.lines.first.strip}`" do
        expect(findings_for(with_connector_statement(assignment))).to eq([message].compact)
      end
    end

    it 'accepts a reference to a constant assigned earlier in the same file' do
      expect(check(with_constant("A = IPaaS::Job::Humanize\n  B = A"))).to have_attributes(in_shape?: true)
    end

    # The absolute guard refuses this before the `@assigned` branch is reached, and that guard is
    # what this example pins. Remove it and the seeding assignment would carry `PWN` into
    # `@assigned`, where a name bound absolutely resolves to the top-level constant while the
    # checker sees a back-reference. A row without the seeding assignment cannot show that, because
    # it is refused either way.
    it 'refuses a one-segment absolute path even when the file assigned that name' do
      source = with_constant("File = nil\n  PWN = ::File")
      expect(findings_for(source)).to eq(["assigns 'PWN' a value that is not a constant expression"])
    end

    it 'still accepts an absolute permitted path, so the refusal above is about the one segment' do
      expect(check(with_constant('A = ::IPaaS::Job::CompactHash'))).to have_attributes(in_shape?: true)
    end

    it 'refuses a forward reference, because only earlier assignments are known' do
      source = with_constant("B = LATER\n  LATER = 'x'")
      expect(findings_for(source)).to eq(["assigns 'B' a value that is not a constant expression"])
    end

    it 'refuses a path rooted at a local alias, so a chain cannot reach an unpermitted constant' do
      source = with_constant("A = IPaaS::Job::CompactHash\n  B = A::Inner")
      expect(findings_for(source)).to eq(["assigns 'B' a value that is not a constant expression"])
    end

    it 'refuses both lines when the aliased target was itself refused' do
      source = with_constant("A = File\n  B = A")
      expect(findings_for(source)).to eq(
        ["assigns 'A' a value that is not a constant expression",
         "assigns 'B' a value that is not a constant expression",],
      )
    end
  end

  describe 'structural block statements' do
    it 'refuses a verb outside the position vocabulary' do
      expect(findings_for(with_connector_statement("ruby_eval '1'"))).to eq(
        ["uses 'ruby_eval', which is not part of the connector vocabulary"],
      )
    end

    it 'refuses a capability verb that would execute at load' do
      expect(findings_for(with_connector_statement("instance_eval 'x'"))).to eq(
        ["uses 'instance_eval', which is not part of the connector vocabulary"],
      )
    end

    it 'refuses a verb belonging to another position, so the sets are not a union' do
      expect(findings_for(with_connector_statement('nested true'))).to eq(
        ["uses 'nested', which is not part of the connector vocabulary"],
      )
    end

    it 'refuses a call with a receiver' do
      expect(findings_for(with_connector_statement("helpers.name 'My'"))).to eq(
        ['calls a method on a receiver in the connector block'],
      )
    end

    it 'refuses a non-literal argument' do
      expect(findings_for(with_connector_statement('name File.read("/etc/passwd")'))).to eq(
        ["passes a non-literal argument to 'name'"],
      )
    end

    it 'accepts an interpolated literal argument' do
      source = with_connector_statement('name "My #{1}"') # rubocop:disable Lint/InterpolationCheck
      expect(check(source)).to have_attributes(in_shape?: true)
    end

    it 'refuses a statement that is neither a constant, a call nor a block' do
      expect(findings_for(with_connector_statement('@ivar = 1'))).to eq(
        ['holds ivasgn in the connector block'],
      )
    end

    it 'refuses parameters on a structural block' do
      source = wrap("connector 'uuid' do |x|\n    name 'My'\n  end")
      expect(findings_for(source)).to eq(['connector block takes parameters'])
    end

    it 'accepts parameters on a proc-bearing block, which the proc rules govern' do
      source = with_connector_statement("helper :thing do |argument|\n      argument\n    end")
      expect(check(source)).to have_attributes(in_shape?: true)
    end

    it 'refuses a block opened on a verb that is neither an expression nor a position' do
      source = with_connector_statement("name 'My' do\n      description 'x'\n    end")
      expect(findings_for(source)).to eq(
        ["opens a block on 'name', which is neither an expression nor a structural position"],
      )
    end

    it 'refuses a numbered-parameter block, which is not a block node' do
      source = with_connector_statement("action 'a' do\n      name 'A'\n      [1].each { _1 }\n    end")
      expect(findings_for(source)).to eq(['holds numblock in the action block'])
    end

    it 'refuses a verb from a sibling position, so one vocabulary cannot leak into another' do
      source = with_connector_statement("action 'a' do\n      name 'A'\n      outbound_traffic true\n    end")
      expect(findings_for(source)).to eq(
        ["uses 'outbound_traffic', which is not part of the action vocabulary"],
      )
    end
  end

  describe 'location keywords' do
    # rubocop:disable-next Lint/InterpolationCheck
    {
      'name __FILE__' => "passes a non-literal argument to 'name'",
      'name __LINE__' => "passes a non-literal argument to 'name'",
      'name "x #{__FILE__}"' => "passes a non-literal argument to 'name'",
      'name "x #{__LINE__}"' => "passes a non-literal argument to 'name'",
      'name __FILE__.freeze' => "passes a non-literal argument to 'name'",
      'description [__LINE__]' => "passes a non-literal argument to 'description'",
      'description({ a: __FILE__ })' => "passes a non-literal argument to 'description'",
      "name 'x'" => nil,
      'name "x #{7}"' => nil,
      "name <<~N.chomp\n      __FILE__\n    N" => nil,
      'name "#{1}__FILE__"' => nil,
      'description %w[__FILE__]' => nil,
      "name '__FILE__'" => nil,
    }.each do |statement, message|
      it message.nil? ? "accepts `#{statement.lines.first.strip}`" : "refuses `#{statement}`: #{message}" do
        expect(findings_for(with_connector_statement(statement))).to eq([message].compact)
      end
    end

    it 'refuses a location keyword as the connector uuid' do
      source = wrap("connector __FILE__ do\n    name 'My'\n  end")
      expect(findings_for(source)).to eq(['declares the connector with something other than a single literal uuid'])
    end
  end

  describe 'an outcome that establishes nothing' do
    {
      too_large: 'x' * (IPaaS::Connector::Connector::MAX_SOURCE_FILE_BYTES + 1),
      unparseable: 'class MyConnector <',
      too_deeply_nested: begin
        depth = IPaaS::Connector::Common::ProcHelper::MAX_NESTING_DEPTH + 1
        "A = #{'[' * depth}#{']' * depth}"
      end,
      no_definition: '',
    }.each do |reason, source|
      it "reports #{reason} rather than an empty finding list" do
        expect(check(source)).to have_attributes(checked?: false, in_shape?: false,
                                                 uncheckable: reason, findings: [])
      end
    end

    # The bound applied before parsing consults a different parser, which accepts bytes the one
    # building the tree refuses. The first expectation is what makes this example about the syntax
    # check: without it, a source the earlier bound already caught would pass here too.
    it 'reports unparseable for bytes only the parser building the tree rejects' do
      source = "# \xFF\nclass MyConnector < IPaaS::Connector::Definition\nend\n"

      expect(IPaaS::Connector::Common::ProcHelper.unevaluable_reason(source)).to be_nil
      expect(check(source)).to have_attributes(checked?: false, uncheckable: :unparseable, findings: [])
    end
  end

  describe 'the shipped vocabulary' do
    it 'holds one set per structural position' do
      expect(described_class::VERBS.keys).to match_array(described_class::POSITIONS.to_a)
    end

    it 'keeps the descend-or-recurse decision unambiguous' do
      expect(described_class::PROC_BEARING & described_class::POSITIONS).to be_empty
    end

    it 'permits no verb that any object already answers to' do
      callable = BasicObject.instance_methods | Object.instance_methods |
                 Object.private_instance_methods | Kernel.private_instance_methods
      expect(described_class::VERBS.values.reduce(:|).to_a & callable).to be_empty
    end

    it 'derives the shadow refusal from the permitted paths rather than a second list' do
      expect(described_class::ROOT_SEGMENTS)
        .to contain_exactly(*described_class::PERMITTED_PATHS.map(&:first).uniq)
    end

    it 'names only constants that exist, so an entry cannot silently mean nothing' do
      described_class::PERMITTED_PATHS.each do |path|
        expect { path.inject(Object) { |namespace, part| namespace.const_get(part) } }.not_to raise_error
      end
    end
  end
end
