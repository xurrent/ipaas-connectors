require 'spec_helper'

# Two pins that make a Ruby upgrade loud instead of silent. `ProcessedSource` accepts a stale
# target version without complaint (3.5 and 4.0 both parse today).
# This spec notices when the interpreter moves past the pinned target and the rules start walking an AST
# shape they were never reviewed against.
describe IPaaS::Connector::Common::ProcHelper do
  # A fixed corpus, not a sample: NODE_FORMS is the exact set of node types these sources emit at
  # TARGET_RUBY_VERSION. Changing either half without re-reviewing the rules is what this catches.
  NODE_FORM_CORPUS = [
    'params[:a]',
    'params.dig(:a, :b)',
    '{ a: 1, "b" => 2 }',
    '[1, 2, 3].map { |n| n * 2 }',
    '[1, 2, 3].map { it * 2 }',
    '[1, 2, 3].map { _1 + _2 }',
    '[1, 2].each_with_object({}) { |(k, v), acc| acc[k] = v }',
    '[1, 2].reduce(:+)',
    '[1, 2].sum(&:to_i)',
    'x = 1; y = x + 1; y',
    '@ivar',
    '@ivar = 1',
    '@@count',
    '@@count = 1',
    '$stdout',
    'CONST',
    'IPaaS::Job::Outbound::HTTP',
    '::JSON',
    'a = 1; a += 2; a',
    'a = nil; a ||= 3; a',
    'a = 1; a &&= 2; a',
    'a = [1]; a |= [2]; a',
    'params[:h][:k] ||= 1',
    'config.present? ? config : nil',
    'if params[:a] then 1 elsif params[:b] then 2 else 3 end',
    'unless params[:a] then 1 end',
    'while params[:a] do break end',
    'until params[:a] do next end',
    'case params[:a] when 1, 2 then :low else :high end',
    'case params[:a]; in { k: Integer => v } then v; else nil; end',
    '(1..5).to_a + (1...5).to_a',
    "\"str \#{params[:a]} tail\"", # literal source text: "#{params[:a]}"
    ":\"sym \#{params[:a]}\"",
    "/re\#{params[:a]}/i =~ 'x'",
    'begin; params[:a].to_s; rescue StandardError => e; e.message; ensure; nil; end',
    'raise "boom" if params[:a] && !params[:b] || params[:c]',
    'def foo(a, b = 1, *rest, k:, kw: 2, **opts, &blk); [a, b, rest, k, kw, opts, blk]; end',
    '->(v) { v.to_s }.call(1)',
    'lambda { |*| nil }',
    '[1, 2, *params[:a]]',
    '{ **params[:h], a: 1 }',
    'params[:a]&.to_s',
    'defined?(params)',
    'true && false || nil',
    'self.to_s',
    'class Foo < Bar; BAZ = 1; def self.x; end; end',
    'module Mod; end',
    'params[:a] = 1',
    'a, b = 1, 2',
    '1.0 + 2 - 3',
    'return 1 if params[:a]',
    'alias_method :a, :b',
    '__FILE__',
    'yield 1',
    'super',
    'RESULT = defined?(x) ? 1 : 2',
  ].freeze

  # rubocop:disable-next Lint/BooleanSymbol -- :true and :false are AST node type names
  NODE_FORMS = [
    :and, :arg, :args, :array, :begin, :block, :block_pass, :blockarg, :break, :case,
    :case_match, :casgn, :cbase, :class, :const, :csend, :cvar, :cvasgn, :def, :defined?,
    :defs, :dstr, :dsym, :ensure, :erange, :false, :float, :gvar, :hash, :hash_pattern,
    :if, :in_pattern, :int, :irange, :itblock, :ivar, :ivasgn, :kwarg, :kwbegin, :kwoptarg,
    :kwrestarg, :kwsplat, :lvar, :lvasgn, :masgn, :match_as, :match_var, :mlhs, :module,
    :and_asgn, :next, :nil, :numblock, :op_asgn, :optarg, :or, :or_asgn, :pair, :regexp, :regopt,
    :resbody, :rescue, :restarg, :return, :self, :send, :splat, :str, :sym, :true, :until,
    :when, :while, :yield, :zsuper,
  ].freeze

  def processed(source)
    RuboCop::AST::ProcessedSource.new(source, described_class::TARGET_RUBY_VERSION)
  end

  def emitted_node_forms
    NODE_FORM_CORPUS.each_with_object(Set.new) do |source, forms|
      processed(source).ast.each_node { |node| forms << node.type }
    end
  end

  describe 'the target Ruby version pin' do
    it 'matches the running Ruby major.minor' do
      running = RUBY_VERSION[/\d+\.\d+/].to_f
      target = described_class::TARGET_RUBY_VERSION

      expect(target).to eq(running),
                        "TARGET_RUBY_VERSION (#{target}) no longer matches the running Ruby (#{running}). " \
                        'Re-review the pinned node forms against every rule before raising the target.'
    end

    it 'is the version production parses proc sources at' do
      expect(processed('[1, 2, 3].map { it * 2 }').ast.type).to eq(:itblock)
      expect(described_class.new(nil, '[1, 2, 3].map { it * 2 }')).to be_valid
    end
  end

  describe 'the node form pin' do
    it 'emits exactly the pinned set of node types' do
      emitted = emitted_node_forms
      added = (emitted - NODE_FORMS).to_a.sort
      removed = (NODE_FORMS.to_set - emitted).to_a.sort

      expect(emitted.to_a.sort).to eq(NODE_FORMS.sort),
                                   'Node forms emitted at target ' \
                                   "#{described_class::TARGET_RUBY_VERSION} drifted. " \
                                   "Added: #{added.inspect}. Removed: #{removed.inspect}. " \
                                   'Re-review every ProcRule against the changed forms before re-pinning.'
    end

    it 'parses every corpus source, so no entry silently contributes nothing' do
      unparsed = NODE_FORM_CORPUS.reject { |source| processed(source).ast }

      expect(unparsed).to be_empty
    end

    it 'pins each node form once' do
      duplicates = NODE_FORMS.tally.select { |_, count| count > 1 }.keys

      expect(duplicates).to be_empty
    end
  end

  # `ValidMethodsRule` handles exactly these three node types, and reads an operator child from
  # `op_asgn` alone. A parser upgrade that adds a fourth shorthand form would route it past the
  # handler silently, so the set is pinned where the rest of the grammar drift is caught.
  describe 'the shorthand assignment pin' do
    it 'pins the set ValidMethodsRule handles' do
      expect(RuboCop::AST::Node::SHORTHAND_ASSIGNMENTS).to eq(Set[:op_asgn, :or_asgn, :and_asgn]),
                                                           'A shorthand assignment form was added or removed. ' \
                                                           'Re-review ValidMethodsRule#on_op_asgn against it ' \
                                                           'before re-pinning.'
    end

    it 'emits an operator child for op_asgn only' do
      operators = { 'a = 1; a += 1' => :op_asgn, 'a = nil; a ||= 1' => :or_asgn, 'a = 1; a &&= 1' => :and_asgn }

      shapes = operators.keys.to_h do |source|
        node = processed(source).ast.each_node(:op_asgn, :or_asgn, :and_asgn).first
        [node.type, node.children[1].is_a?(Symbol)]
      end

      expect(shapes).to eq(op_asgn: true, or_asgn: false, and_asgn: false)
    end
  end
end
