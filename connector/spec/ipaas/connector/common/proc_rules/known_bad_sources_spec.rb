require 'spec_helper'

# Every source here is a construct that must stay rejected, paired with a near-identical one that
# must stay accepted. It drives `ProcHelper#valid?` rather than a single rule, because a source can
# be rejected by one rule while the rule under test does nothing — a single-rule harness cannot see
# that. Do not move these cases into a per-rule spec.
#
# Sources off a receiverless `helpers` do not belong here: the rules accept those by design and the
# refusal happens on dispatch. They live in `spec/ipaas/connector/common/helpers_proxy_spec.rb`.
describe IPaaS::Connector::Common::ProcHelper do
  # `validated_before` short-circuits `valid?` and returns no errors, so a warm entry turns a
  # rejection expectation green. spec_helper alone populates it, hence before(:each).
  before(:each) { described_class.validated_before.clear }

  def errors_for(source)
    helper = described_class.new(nil, source)
    helper.valid?
    helper.errors
  end

  def rejected?(source)
    described_class.new(nil, source).valid? == false
  end

  # Every constant off the list reads the same way whatever the construct around it.
  def self.refused_path(name)
    "Access to '#{name}' is not allowed in expressions; only an approved set of classes is available. " \
      'Please file a request if access is needed.'
  end

  CLASS_CALL_MESSAGE = IPaaS::Connector::Common::ProcRules::ValidMethodsRule::CLASS_CALL_MESSAGE
  TO_JSON_MESSAGE = IPaaS::Connector::Common::ProcRules::ValidMethodsRule::TO_JSON_MESSAGE
  SOLUTION_CALL_MESSAGE = IPaaS::Connector::Common::ProcRules::ValidMethodsRule::SOLUTION_CALL_MESSAGE

  ROUTES = [
    {
      route: 'reflective dispatch: reduce turns a symbol argument into the dispatched method',
      rejected: {
        '[1, 2].reduce(:eval)' => ["Method 'eval' not allowed."],
        '[1, 2].reduce(:public_send)' => ["Method 'public_send' not allowed."],
        '[1].reduce(0, "x".to_sym) { |a, b| a }' =>
          ["Method name argument to 'reduce' must be a literal symbol."],
        '["a"].reduce(*[1, :eval]) { |a, b| a }' =>
          ["Method name argument to 'reduce' must be a literal symbol."],
        '[1].reduce(0, "x".to_sym, &:+)' =>
          ["Method name argument to 'reduce' must be a literal symbol."],
        'helpers.reduce(:eval)' => ["Method 'eval' not allowed."],
        'params[:a]&.reduce(:eval)' => ["Method 'eval' not allowed."],
      },
      accepted: [
        '[1, 2].reduce(:+)',
        '[1, 2].reduce(0) { |a, b| a + b }',
        '[1, 2].reduce(0, &:+)',
        'params[:a].reduce(0, &:+)',
        'params[:h].reduce({}) { |a, (k, v)| a }',
        '[[1], [2]].reduce',
        'params[:a].dig(:eval, :system)',
      ],
    },
    {
      route: 'reflective dispatch: shapes naming an unlisted constant, refused by the path too and so ' \
             'not proof of the dispatch branch',
      rejected: {
        '[Kernel, "echo x"].reduce(:system)' =>
          ["Method 'system' not allowed.", refused_path('Kernel')],
        '["echo x"].reduce(Kernel, :system) { |a, b| a }' =>
          [refused_path('Kernel'), "Method 'system' not allowed."],
        '["echo x"].reduce(Kernel, &:system)' =>
          ["Method 'system' not allowed.", refused_path('Kernel')],
      },
      accepted: [
        '["echo x"].reduce(0) { |a, b| a }',
      ],
    },
    {
      route: 'block-pass dispatch: a symbol the validator cannot read becomes the called method',
      rejected: {
        's = :instance_eval; [self, "1+1"].reduce(&s)' => ['Block argument must be a literal symbol.'],
        '[self, "1+1"].reduce(&"instance_eval".to_sym)' => ['Block argument must be a literal symbol.'],
        's = :instance_eval; [self].each_with_object("1+1", &s)' =>
          ['Block argument must be a literal symbol.'],
        's = :instance_eval; params[:a]&.reduce(&s)' => ['Block argument must be a literal symbol.'],
        '[self, "1+1"].reduce(&[:instance_eval].first)' => ['Block argument must be a literal symbol.'],
        's = :freeze; params[:a].map(&s)' => ['Block argument must be a literal symbol.'],
      },
      accepted: [
        '[1, 2].reduce(&:+)',
        'params[:a].map(&:to_s)',
        'params[:a].select(&:present?)',
        'params[:h].transform_values(&:to_s)',
        'params[:a].each_with_object({}) { |item, acc| acc }',
      ],
    },
    {
      route: 'to_json options: a call or a symbol dispatch that can hand options to to_json',
      rejected: {
        'params[:a].to_json(1)' => [TO_JSON_MESSAGE],
        'params[:a].to_json(nil)' => [TO_JSON_MESSAGE],
        'params[:a].to_json(methods: [:name])' => [TO_JSON_MESSAGE],
        'params[:a].to_json({ methods: [:name] })' => [TO_JSON_MESSAGE],
        'params[:a].to_json(*params[:b])' => [TO_JSON_MESSAGE],
        'params[:a].to_json(**params[:b])' => [TO_JSON_MESSAGE],
        'params[:a].to_json(&:to_s)' => [TO_JSON_MESSAGE],
        'params[:a].to_json { |v| v }' => [TO_JSON_MESSAGE],
        'params[:a].to_json { _1 }' => [TO_JSON_MESSAGE],
        'params[:a].to_json { it }' => [TO_JSON_MESSAGE],
        'params[:a]&.to_json(1)' => [TO_JSON_MESSAGE],
        '{ a: params[:a] }.to_json(methods: [:name])' => [TO_JSON_MESSAGE],
        '[params[:a], { methods: [:name] }].reduce(:to_json)' => [TO_JSON_MESSAGE],
        '[{ methods: [:name] }].reduce(params[:a], :to_json)' => [TO_JSON_MESSAGE],
        '[params[:a], { methods: [:name] }].reduce(:"to_json")' => [TO_JSON_MESSAGE],
        '[params[:a], { methods: [:name] }].reduce(%s(to_json))' => [TO_JSON_MESSAGE],
        '[params[:a], { methods: [:name] }].reduce(&:to_json)' => [TO_JSON_MESSAGE],
        '[params[:a]].each_with_object({ methods: [:name] }, &:to_json)' => [TO_JSON_MESSAGE],
        '[params[:a], params[:b]].sort(&:to_json)' => [TO_JSON_MESSAGE],
        '[params[:a], params[:b]].min(&:to_json)' => [TO_JSON_MESSAGE],
        '[params[:a], params[:b]].max(&:to_json)' => [TO_JSON_MESSAGE],
        '[params[:a]].map(&:to_json)' => [TO_JSON_MESSAGE],
        'lambda(&:to_json)' => [TO_JSON_MESSAGE],
        'helpers.reduce(:to_json)' => [TO_JSON_MESSAGE],
        'helpers.fmt(&:to_json)' => [TO_JSON_MESSAGE],
      },
      accepted: [
        'params[:a].to_json',
        'params[:a]&.to_json',
        '{ a: params[:a] }.to_json',
        '[params[:a]].map { |v| v.to_json }',
        'JSON.pretty_generate(params[:a])',
        'JSON[params[:a], { a: 1 }]',
      ],
    },
    {
      route: 'to_json options: inject shapes, refused by the method list too and so not proof of the to_json check',
      rejected: {
        '[params[:a], { methods: [:name] }].inject(:to_json)' => [TO_JSON_MESSAGE, "Method 'inject' not allowed."],
        '[params[:a], { methods: [:name] }].inject(&:to_json)' => [TO_JSON_MESSAGE, "Method 'inject' not allowed."],
      },
      accepted: [
        '[params[:a], params[:b]].reduce { |a, b| a.to_json }',
      ],
    },
    {
      route: 'solution is refused as the receiver of any method but its listed ones',
      rejected: {
        'solution.first' => [SOLUTION_CALL_MESSAGE],
        'solution.keys' => [SOLUTION_CALL_MESSAGE],
        'solution.to_a' => [SOLUTION_CALL_MESSAGE],
        's = solution' => [SOLUTION_CALL_MESSAGE],
        '[runbook].map(&:solution)' => [SOLUTION_CALL_MESSAGE],
        '[runbook].reduce(nil, :solution)' => [SOLUTION_CALL_MESSAGE],
      },
      accepted: [
        "solution&.name&.presence || 'iPaaS Integration'",
        'solution.create_schedule!(runbook.uuid, {})',
        "solution.soft_delete_schedule('ref')",
        "solution.runbooks.detect { |r| r.name == 'x' }",
        'runbook.solution.uuid',
        '(solution).uuid',
      ],
    },
    {
      route: 'alias and undef re-point or remove a method, so an allowed name runs another',
      rejected: {
        "alias strip to_json\nstrip(methods: [:name])" => ["'alias' not allowed."],
        'alias :strip :to_json' => ["'alias' not allowed."],
        'class << params; alias m n; end' => ["'alias' not allowed."],
        'undef to_json' => ["'undef' not allowed."],
        'undef :strip, :to_json' => ["'undef' not allowed."],
        "alias strip to_s\nundef to_json" => ["'alias' not allowed.", "'undef' not allowed."],
      },
      accepted: [
        'params[:alias]',
        '{ alias: 1, undef: 2 }',
        '"alias strip to_json"',
        'params[:a].strip',
      ],
    },
    {
      route: 'unlisted constants: file and directory access',
      rejected: {
        'IO.read("/etc/hosts")' => [refused_path('IO')],
        'File.read("/x")' => [refused_path('File')],
        'File.write("/x", "y")' => [refused_path('File')],
        'File.delete("/x")' => [refused_path('File')],
        'File.path("/x")' => [refused_path('File')],
        'Dir["/*"]' => [refused_path('Dir')],
      },
      accepted: [
        'params[:io].read',
        'params[:file].path',
        'params[:dir]["/*"]',
      ],
    },
    {
      route: 'IO subclasses inherit its class methods, so blocking IO alone leaves them reachable',
      rejected: {
        'Socket.read("/etc/passwd")' => [refused_path('Socket')],
        'Socket.write("/tmp/x", "y")' => [refused_path('Socket')],
        '::Socket.read("/etc/passwd")' => [refused_path('Socket')],
        'TCPSocket.read("/etc/passwd")' => [refused_path('TCPSocket')],
        'UNIXServer.read("/etc/passwd")' => [refused_path('UNIXServer')],
      },
      accepted: [
        'params[:socket].read',
        'params[:socket_hostname]',
      ],
    },
    {
      route: 'unlisted constants: filesystem access that is not File, IO or Dir',
      rejected: {
        'FileTest.size("/etc/hosts")' => [refused_path('FileTest')],
        'FileTest.empty?("/etc/hosts")' => [refused_path('FileTest')],
        'FileUtils.options' => [refused_path('FileUtils')],
      },
      accepted: [
        'params[:stat].size',
        'params[:a].empty?',
        'params[:opts].options',
      ],
    },
    {
      route: 'unlisted constants: request-scoped state',
      rejected: {
        'RequestStore.clear!' => [refused_path('RequestStore')],
        'RequestStore[:xray] = "y"' => [refused_path('RequestStore')],
        'RequestStore.store["named_version_context"] = "x"' =>
          [refused_path('RequestStore')],
      },
      accepted: [
        'params[:store][:xray] = "y"',
        'params[:store].clear',
      ],
    },
    {
      route: 'unlisted constants: deserialization and reflection',
      rejected: {
        'x = YAML' => [refused_path('YAML')],
        'YAML.to_s' => [refused_path('YAML')],
        'Marshal.dig(:a)' => [refused_path('Marshal')],
        'Marshal.load("x")' =>
          [refused_path('Marshal'), "Method 'load' not allowed."],
        'ObjectSpace.each_value' => [refused_path('ObjectSpace')],
        'Binding.dig(:a)' => [refused_path('Binding')],
        'Method.dig(:a)' => [refused_path('Method')],
        'UnboundMethod.dig(:a)' => [refused_path('UnboundMethod')],
        'RubyVM.keys' => [refused_path('RubyVM')],
        'TracePoint.trace { |tp| tp }' => [refused_path('TracePoint')],
      },
      accepted: [
        'JSON.parse("{}")',
        'x = JSON.parse("{}")',
        'params[:marshal].dig(:a)',
        'params[:h].each_value',
        'params[:h].keys',
      ],
    },
    {
      route: 'unlisted constants: thread and fiber local state',
      rejected: {
        'Thread.current[:executing_procs] = []' => [refused_path('Thread')],
        'Thread.current[:ipaas_resolve_scope] = nil' => [refused_path('Thread')],
        'Fiber[:x]' => [refused_path('Fiber')],
        'Process.uuid' => [refused_path('Process')],
        'Kernel.reduce(:x)' =>
          [refused_path('Kernel'), "Method 'x' not allowed."],
      },
      accepted: [
        'Time.current',
        'params[:store][:executing_procs] = []',
        'params[:fiber][:x]',
      ],
    },
    {
      route: 'core classes off the list, refused on the path and on the method name',
      rejected: {
        'Struct.members' => [refused_path('Struct'), "Method 'members' not allowed."],
        'Random.new_seed' => [refused_path('Random'), "Method 'new_seed' not allowed."],
        'Data.define' => [refused_path('Data'), "Method 'define' not allowed."],
        'Signal.list' => [refused_path('Signal'), "Method 'list' not allowed."],
        'Object.const_get(:X)' => [refused_path('Object'), "Method 'const_get' not allowed."],
        'Psych.load("x")' => [refused_path('Psych'), "Method 'load' not allowed."],
      },
      accepted: [
        'Time.current',
      ],
    },
    {
      route: 'the validator machinery: the path and the method allowlist each reject it',
      rejected: {
        'IPaaS::Connector::Common::ProcHelper.validated_before' =>
          [refused_path('IPaaS::Connector::Common::ProcHelper'), "Method 'validated_before' not allowed."],
        'IPaaS::Connector::Common::ProcHelper.validated_before.clear' =>
          [refused_path('IPaaS::Connector::Common::ProcHelper'), "Method 'validated_before' not allowed."],
        'IPaaS::Connector::Common::ProcHelper.validated_before = 1' =>
          [refused_path('IPaaS::Connector::Common::ProcHelper'), "Method 'validated_before=' not allowed."],
        'IPaaS::Connector::Common::ProcRules::ProcSafe.registry << :system' =>
          [refused_path('IPaaS::Connector::Common::ProcRules::ProcSafe'), "Method 'registry' not allowed."],
        'IPaaS::Connector::Common::ProcRules::ProcSafe.to_s' =>
          [refused_path('IPaaS::Connector::Common::ProcRules::ProcSafe')],
        'IPaaS::Connector::Common::ProcHelper.to_s' =>
          [refused_path('IPaaS::Connector::Common::ProcHelper')],
        'IPaaS::Connector::Common::ProcRules::ValidMethodsRule::RUBY_METHODS' =>
          [refused_path('IPaaS::Connector::Common::ProcRules::ValidMethodsRule::RUBY_METHODS')],
        'IPaaS::Connector::Common::ProcRules::BASIC_RULES' =>
          [refused_path('IPaaS::Connector::Common::ProcRules::BASIC_RULES')],
      },
      accepted: [
        'params[:cache].clear',
        'params[:registry] << :system',
      ],
    },
    {
      route: 'instance and class variables on the execution context',
      rejected: {
        '@secret' => ["Access to '@secret' not allowed."],
        '@x = 1' => ["Access to '@x' not allowed."],
        '@@cv' => ["Access to '@@cv' not allowed."],
        '@@cv = 1' => ["Access to '@@cv' not allowed."],
      },
      accepted: [
        'x = 1; x',
        'local = params[:a]',
        'params[:a].each { |item| item.to_s }',
      ],
    },
    {
      route: 'rescue is only allowed for classes on the list',
      rejected: {
        'begin; params[:a].to_s; rescue Kernel; :ok; end' => [refused_path('Kernel')],
        'begin; params[:a].to_s; rescue Exception; retry; end' => [refused_path('Exception')],
        'begin; params[:a].to_s; rescue ::Exception; :ok; end' => [refused_path('Exception')],
        'begin; params[:a].to_s; rescue Foo::Exception; :ok; end' => [refused_path('Foo::Exception')],
        'begin; params[:a].to_s; rescue StandardError, Exception; :ok; end' => [refused_path('Exception')],
        'begin; params[:a].to_s; rescue Object; :ok; end' => [refused_path('Object')],
        'begin; params[:a].to_s; rescue BasicObject; :ok; end' => [refused_path('BasicObject')],
        'begin; params[:a].to_s; rescue SystemExit; :ok; end' => [refused_path('SystemExit')],
        'begin; params[:a].to_s; rescue SignalException; :ok; end' => [refused_path('SignalException')],
        'begin; params[:a].to_s; rescue SystemStackError; :ok; end' => [refused_path('SystemStackError')],
        'begin; params[:a].to_s; rescue StandardError; [Kernel]; end' => [refused_path('Kernel')],
        'begin; params[:a].to_s; rescue IPaaS::Job::JWT::MAX_TOKEN_BYTES; :ok; end' =>
          ["'IPaaS::Job::JWT::MAX_TOKEN_BYTES' is not an error class, so it cannot be rescued in expressions."],
        'begin; params[:a].to_s; rescue Hash; :ok; end' =>
          ["'Hash' is not an error class, so it cannot be rescued in expressions."],
      },
      accepted: [
        'begin; params[:a].to_s; rescue StandardError; :ok; end',
        'begin; params[:a].to_s; rescue StandardError; retry; end',
        'begin; params[:a].to_s; rescue IPaaS::Error, URI::InvalidURIError; :ok; end',
        'begin; params[:a].to_s; rescue JSON::ParserError => e; e.message; end',
        'begin; params[:a].to_s; rescue StandardError; [1]; end',
      ],
    },
    {
      route: 'op-assign setter dispatch: the shorthand form calls the setter its reader expands to',
      rejected: {
        'config.connector ||= 1' => ["Method 'connector=' not allowed."],
        'config.connector &&= 1' => ["Method 'connector=' not allowed."],
        'config.connector += 1' => ["Method 'connector=' not allowed."],
        'params[:a]&.connector ||= 1' => ["Method 'connector=' not allowed."],
        'params[:a].solution ||= 1' => [SOLUTION_CALL_MESSAGE, "Method 'solution=' not allowed."],
        'params[:a].runbooks ||= 1' => ["Method 'runbooks=' not allowed."],
        'params[:a].validators ||= 1' => ["Method 'validators=' not allowed."],
      },
      accepted: [
        'a = nil; a ||= 1',
        'a = 1; a += 1',
        'a = []; a[0] ||= 1',
        'params[:a][0] ||= 1',
        'u = params[:u]; u.path += "/c"',
        'field(:payload).fields += []',
        'params[:a].connector',
      ],
    },
    {
      route: 'op-assign operator dispatch: the operator is itself a method call',
      rejected: {
        'a = 1; a &= 2' => ["Method '&' not allowed."],
        'a = 1; a ^= 2' => ["Method '^' not allowed."],
        'a = 1; a >>= 2' => ["Method '>>' not allowed."],
      },
      accepted: [
        'a = 1; a += 1',
        'a = 1; a -= 1',
        'a = 2; a **= 2',
        'a = [1]; a |= params[:x]',
        'a = [1]; a <<= 2',
      ],
    },
    {
      route: 'global variable writes, in every form that reaches a gvasgn',
      rejected: {
        '$g = 1' => ["Access to '$g' not allowed."],
        '$g ||= 1' => ["Access to '$g' not allowed."],
        '$stdout = 1' => ["Access to '$stdout' not allowed."],
        '$g, $h = 1, 2' => ["Access to '$g' not allowed.", "Access to '$h' not allowed."],
        'for $g in [1] do end' => ["Access to '$g' not allowed."],
      },
      accepted: [
        'a = 1; a',
        'params[:a]',
        'a = {}; a[:g] = 1',
        'for a in [1] do end',
        'a, b = 1, 2',
      ],
    },
    {
      route: 'namespaced paths are matched whole, so neither a listed leaf nor a listed root admits them',
      rejected: {
        'Foo::File' => [refused_path('Foo::File')],
        'Zip::File' => [refused_path('Zip::File')],
        'Foo::Bar::Thread' => [refused_path('Foo::Bar::Thread')],
        'IPaaS::Job::JSON.parse("{}")' => [refused_path('IPaaS::Job::JSON')],
        'OpenSSL::Digest.new("sha256")' => [refused_path('OpenSSL::Digest'), "Method 'new' not allowed."],
      },
      accepted: [
        'IPaaS::Job::Outbound::HTTP.create_binary_part("n", "t", "d")',
        '::IPaaS::Job::Outbound::HTTP.create_binary_part("n", "t", "d")',
        'OpenSSL::HMAC.hexdigest("sha256", "k", "d")',
        'Digest::SHA256.hexdigest("d")',
        'Base64.encode64("x")',
        'URI.parse("http://x")',
        'Base64.strict_decode64(Base64.strict_encode64(params[:a].to_s))',
        'Base64.urlsafe_decode64(Base64.urlsafe_encode64("x"))',
        'Digest::SHA256.digest("d")',
        'URI.join("https://example.com/a/", "b")',
        'begin; params.fetch(:a); rescue KeyError, IndexError; 2; end',
        'raise RuntimeError, "x"',
        'params[:a].is_a?(Float)',
      ],
    },
    {
      route: '.class reaches the class of any value, so only its name may be taken from it',
      rejected: {
        'self.class.present?' => [CLASS_CALL_MESSAGE],
        'raise params.class' => [CLASS_CALL_MESSAGE],
        '[1].map(&:class)' => [CLASS_CALL_MESSAGE],
        '->(v) { v.class }' => [CLASS_CALL_MESSAGE],
        'log(params.class, {})' => [CLASS_CALL_MESSAGE],
        '"#{[params].map { |v| v.class }}"' => [CLASS_CALL_MESSAGE], # rubocop:disable Lint/InterpolationCheck
      },
      accepted: [
        'self.class.name',
        'raise params.class.name',
        '[1].map { |v| v.class.name }',
        'log(params.class)',
        '"#{[params].map { |v| v.class.name }}"', # rubocop:disable Lint/InterpolationCheck
        '->(v) { "#{v.class}" }', # rubocop:disable Lint/InterpolationCheck
      ],
    },
  ].freeze

  ROUTES.each do |entry|
    describe entry[:route] do
      entry[:rejected].each do |source, messages|
        it "rejects #{source.inspect} with exactly #{messages.inspect}" do
          expect(rejected?(source)).to be(true)
          expect(errors_for(source)).to contain_exactly(*messages)
        end
      end

      entry[:accepted].each do |source|
        it "accepts #{source.inspect}" do
          expect(errors_for(source)).to be_empty
        end
      end
    end
  end

  it 'pairs every route with both a rejected and an accepted side' do
    one_sided = ROUTES.reject { |entry| entry[:rejected].any? && entry[:accepted].any? }

    expect(one_sided.map { |entry| entry[:route] }).to be_empty
  end

  it 'names an exact message for every rejected source' do
    empty = ROUTES.flat_map { |entry| entry[:rejected].select { |_, messages| messages.empty? }.keys }

    expect(empty).to be_empty
  end

  # The property the op-assign handling exists to establish, asserted directly rather than through
  # the routes above: a shorthand form is judged exactly as the source it expands to.
  #
  # Scope matters. `a ||= 1` *defines* the local, so its expansion `a || a = 1` reads a bare `a`
  # that parses as a receiverless send — the two are not the same program. Pairs therefore
  # pre-declare the local, and the one non-equivalence is asserted below so the exclusion is
  # visible rather than silently dropped.
  describe 'an op-assign is validated as its explicit expansion' do
    # Both sides must report the SAME refusal. These carry the property: if the handler stopped
    # reading the setter or the operator, the shorthand side would fall silent while the expansion
    # kept reporting.
    OP_ASSIGN_REFUSED_PAIRS = {
      'config.connector ||= 1' => 'config.connector || config.connector = 1',
      'config.connector += 1' => 'config.connector = config.connector + 1',
      'config&.connector ||= 1' => 'config&.connector || config.connector = 1',
      'a = 1; a &= 2' => 'a = 1; a = a & 2',
      'a = 1; a ^= 2' => 'a = 1; a = a ^ 2',
      '$g ||= 1' => '$g || $g = 1',
    }.freeze

    # Both sides must stay accepted. These pin no refusal — they are the compatibility half, and
    # they would go red only by newly refusing something the corpus relies on.
    OP_ASSIGN_ACCEPTED_PAIRS = {
      'a = nil; a ||= 1' => 'a = nil; a || a = 1',
      'a = [1]; a |= params[:x]' => 'a = [1]; a = a | params[:x]',
      'u = params[:u]; u.path += "/c"' => 'u = params[:u]; u.path = u.path + "/c"',
      'a = {}; a[:k] ||= []' => 'a = {}; a[:k] || a[:k] = []',
    }.freeze

    OP_ASSIGN_REFUSED_PAIRS.merge(OP_ASSIGN_ACCEPTED_PAIRS).each do |shorthand, expansion|
      it "judges #{shorthand.inspect} as #{expansion.inspect}" do
        expect(errors_for(shorthand)).to contain_exactly(*errors_for(expansion))
      end
    end

    it 'keeps every refused pair reporting, so no pair is an empty-set comparison' do
      silent = OP_ASSIGN_REFUSED_PAIRS.keys.reject { |shorthand| errors_for(shorthand).any? }

      expect(silent).to be_empty
    end

    it 'keeps every accepted pair accepted on both sides' do
      noisy = OP_ASSIGN_ACCEPTED_PAIRS.flat_map { |a, b| [a, b] }.select { |source| errors_for(source).any? }

      expect(noisy).to be_empty
    end

    it 'excludes the one pair that is not the same program' do
      expect(errors_for('a ||= 1')).to be_empty
      expect(errors_for('a || a = 1')).to contain_exactly("Method 'a' not allowed.")
    end
  end

  # A handler fires once per node from `each_node` and again for every ancestor `ProcRule#process`
  # descends through, so a repeated report is suppressed only by the rules' dedup lists. These
  # sources are deliberately NOT top-level op-assigns: a top-level one is the AST root, has no
  # ancestor to be re-entered from, and so reports once whether or not the dedup exists — an
  # assertion over it cannot go red. Each source below reports twice without the dedup.
  describe 'a repeated dispatch is reported once' do
    {
      'x = 1; config.connector ||= 1' => "Method 'connector=' not allowed.",
      '[1].each { config.connector ||= 1 }' => "Method 'connector=' not allowed.",
      'a = 1; a &= 2' => "Method '&' not allowed.",
    }.each do |source, message|
      it "reports #{source.inspect} exactly once" do
        expect(errors_for(source)).to contain_exactly(message)
      end
    end

    it 'still reports each distinct name' do
      expect(errors_for('$g = 1; $h = 2'))
        .to contain_exactly("Access to '$g' not allowed.", "Access to '$h' not allowed.")
    end

    it 'collapses a read and a write of the same global' do
      expect(errors_for('$g; $g = 1')).to contain_exactly("Access to '$g' not allowed.")
    end
  end

  describe 'the validated_before short-circuit these examples clear' do
    let(:source) { '[1, 2].reduce(:eval)' }

    it 'reports a warm known-bad source as valid with no errors' do
      helper = described_class.new(nil, source)
      described_class.validated_before.add(helper.send(:validation_cache_key))

      expect(helper.valid?).to be(true)
      expect(helper.errors).to be_empty
    end

    it 'rejects the same source on a cold cache' do
      expect(errors_for(source)).to contain_exactly("Method 'eval' not allowed.")
    end
  end
end
