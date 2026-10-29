require 'spec_helper'

# Two pins that make a Ruby upgrade loud rather than silent, in the direction an allowlist can
# actually drift. An unlisted node type is already refused by construction, so a *new* node type
# needs no pin. What does need one is a new construct that desugars into a type the allowlist
# names: `__FILE__` already arrives as `str` and `__LINE__` as `int`, refused only because
# `LocationKeyword` names them, so a future construct reaching the same forms would be accepted
# with nobody reviewing it. The target version itself is pinned to the running Ruby by the
# sibling `parser_target_drift_spec`, which asserts the same
# `ProcHelper::TARGET_RUBY_VERSION` this checker parses at.
describe IPaaS::Connector::Common::LoadRules::ConnectorShape do
  def verdict(source)
    outcome = described_class.check(source, 'drift')
    return :"uncheckable_#{outcome.uncheckable}" unless outcome.checked?

    outcome.in_shape? ? :accepted : :refused
  end

  def constant_verdict(value)
    verdict("class C < IPaaS::Connector::Definition\n  A = #{value}\n  " \
            "connector 'u' do\n    name 'C'\n  end\nend\n")
  end

  def statement_verdict(statement)
    verdict("class C < IPaaS::Connector::Definition\n  connector 'u' do\n    #{statement}\n  end\nend\n")
  end

  describe 'the verdict pin for constant values' do
    # rubocop:disable-next Lint/InterpolationCheck
    values = {
      "'plain'" => :accepted, '1' => :accepted, '1.5' => :accepted, ':sym' => :accepted,
      'true' => :accepted, 'false' => :accepted, 'nil' => :accepted, '-1' => :accepted,
      "'x'.freeze" => :accepted, "'  x '.strip" => :accepted, '30.seconds' => :accepted,
      '10.minutes' => :accepted, '2 * 3' => :accepted, '/re/i' => :accepted,
      "['a', :b, 1].freeze" => :accepted, "{ a: 1, 'b' => 2 }.freeze" => :accepted,
      '"tail #{1}"' => :accepted, '%w[a b]' => :accepted, '%i[a b]' => :accepted,
      '?a' => :accepted, '%q(x)' => :accepted, '"a" "b"' => :accepted,
      'IPaaS::Job::CompactHash' => :accepted, '[IPaaS::Job::Humanize]' => :accepted,
      # A `::`-prefixed path bottoms out in a cbase and names the same constant.
      '::IPaaS::Job::CompactHash' => :accepted, '::IPaaS::Job::Solution' => :refused,
      '::File' => :refused,
      '{ h: IPaaS::Job::Humanize }' => :accepted,
      # Literal by the time the checker sees them and refused by name, the reason this pin exists:
      # a future construct reaching `str` or `int` the same way would be accepted unreviewed.
      '__FILE__' => :refused, '__LINE__' => :refused,
      '__dir__' => :refused, '__method__' => :refused, 'defined?(x)' => :refused,
      'ENV' => :refused, 'DATA' => :refused, 'File' => :refused, 'Object' => :refused,
      'IPaaS::Job::Solution' => :refused,
      '1 + 2' => :refused, "'x' * 3" => :refused, "'x'.upcase" => :refused,
      '[1].map { |n| n }' => :refused, '/#{Time.now}/' => :refused, ':"dyn#{1}"' => :refused,
      # Interpolation is accepted, so what it may contain is the whole of its safety: each part is
      # itself a constant expression, which is what keeps the values it converts a closed set.
      '"at #{Time.now}"' => :refused, '"#{1 + 1}"' => :refused, %q{"#{File.read('/x')}"} => :refused,
      '(1..2)' => :refused, '(1...2)' => :refused, '[1, *[2]]' => :refused,
      '{ **{ a: 1 } }' => :refused, 'begin; 1; rescue; 2; end' => :refused,
      '1 if true' => :refused, 'x = 1' => :refused, '@ivar' => :refused, '@@cvar' => :refused,
      '$gvar' => :refused, 'self' => :refused, '%x{id}' => :refused,
      'Rational(1, 2)' => :refused, 'Complex(1, 2)' => :refused,
      '[1].each { it }' => :refused, '[1].each { _1 }' => :refused,
      'proc { 1 }' => :refused, '->(v) { v }' => :refused,
    }

    values.each do |value, expected|
      it "#{expected} as a constant value: #{value.lines.first.strip}" do
        expect(constant_verdict(value)).to eq(expected)
      end
    end

    it 'pins a value that reaches every branch of the value grammar' do
      expect(values.values.tally).to include(accepted: be_positive, refused: be_positive)
    end
  end

  describe 'the verdict pin for statements in a structural block' do
    statements = {
      "name 'My'" => :accepted, "description 'd'" => :accepted, "name 'a', 'b'" => :accepted,
      'helper :h do; 1; end' => :accepted, "action 'a' do; name 'A'; end" => :accepted,
      "trigger 't' do; name 'T'; end" => :accepted,
      'inbound_connection do; end' => :accepted, 'outbound_connection do; end' => :accepted,
      'name File.read("/x")' => :refused, "ruby_eval '1'" => :refused,
      "instance_eval 'x'" => :refused, 'send :x' => :refused, "eval '1'" => :refused,
      "require 'x'" => :refused, 'define_method(:x) { 1 }' => :refused,
      'undef_method :x' => :refused, 'extend Object' => :refused,
      'instance_variable_set :@x, 1' => :refused, "helpers.name 'x'" => :refused,
      '@ivar = 1' => :refused, '$g = 1' => :refused, 'x = 1' => :refused,
      'def m; end' => :refused, 'class K; end' => :refused, 'module M; end' => :refused,
      'class << self; end' => :refused, 'A ||= 1' => :refused, 'A += 1' => :refused,
      'alias_method :a, :b' => :refused, 'return' => :refused, 'if true; end' => :refused,
      'while false; end' => :refused, '[1].each { it }' => :refused,
      '[1].each { _1 }' => :refused, "name 'x' do; end" => :refused,
    }

    statements.each do |statement, expected|
      it "#{expected} in a connector block: #{statement}" do
        expect(statement_verdict(statement)).to eq(expected)
      end
    end
  end

  describe 'reopening, at every position this checker walks' do
    ['undef foo', 'alias a b', 'undef_method :foo', 'alias_method :a, :b',
     'remove_method :foo', 'define_method(:foo) { 1 }',].each do |statement|
      it "refuses `#{statement}` in the class body" do
        source = "class C < IPaaS::Connector::Definition\n  #{statement}\n  " \
                 "connector 'u' do\n    name 'C'\n  end\nend\n"
        expect(verdict(source)).to eq(:refused)
      end

      it "refuses `#{statement}` in a structural block" do
        expect(statement_verdict(statement)).to eq(:refused)
      end
    end
  end

  describe 'the allowlist table pin' do
    it 'names exactly the scalar node types reviewed against the grammar' do
      expect(described_class::SCALAR_LITERAL_TYPES).to contain_exactly(:str, :sym, :int, :float)
    end

    it 'names exactly the composite node types a literal may be built from' do
      expect(described_class::LITERAL_HANDLERS.keys).to contain_exactly(:array, :hash, :dstr, :send)
    end

    it 'names exactly the node types a constant expression may be built from' do
      expect(described_class::CONST_EXPR_HANDLERS.keys)
        .to contain_exactly(:const, :regexp, :array, :hash, :dstr, :send)
    end

    it 'permits only the methods reviewed as safe on a literal' do
      expect(described_class::LITERAL_METHODS.to_a)
        .to contain_exactly(:freeze, :strip, :chomp, :minutes, :seconds)
    end

    # The untyped branch answers first, so a method in both tables would make its receiver types
    # dead: it would be accepted on every receiver while the table said otherwise.
    it 'gives every permitted method exactly one of the two receiver rules' do
      expect(described_class::TYPED_RECEIVER_METHODS.keys).not_to include(*described_class::ANY_RECEIVER_METHODS)
      expect(described_class::LITERAL_METHODS - described_class::ANY_RECEIVER_METHODS)
        .to contain_exactly(*described_class::TYPED_RECEIVER_METHODS.keys)
    end

    it 'names the receiver types each of those methods is permitted on' do
      expect(described_class::ANY_RECEIVER_METHODS.to_a).to contain_exactly(:freeze)
      expect(described_class::TYPED_RECEIVER_METHODS.transform_values(&:to_a))
        .to contain_exactly(
          [:strip, [:str, :dstr]],
          [:chomp, [:str, :dstr]],
          [:minutes, [:int, :float]],
          [:seconds, [:int, :float]],
        )
    end

    it 'refuses a node type absent from the tables, so a new construct is denied until allowed' do
      expect(described_class::CONST_EXPR_HANDLERS).not_to have_key(:xstr)
      expect(constant_verdict('%x{id}')).to eq(:refused)
    end
  end
end
