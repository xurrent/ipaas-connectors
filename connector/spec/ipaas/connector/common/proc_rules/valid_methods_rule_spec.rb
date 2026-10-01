require 'spec_helper'

describe IPaaS::Connector::Common::ProcRules::ValidMethodsRule do
  def process_source(rule, source)
    target = IPaaS::Connector::Common::ProcHelper::TARGET_RUBY_VERSION
    RuboCop::AST::ProcessedSource.new(source, target).ast.each_node { |node| rule.process(node) }
  end

  def errors_for(source)
    errors = []
    process_source(described_class.new(nil, on_invalid: ->(message) { errors << message }), source)
    errors
  end

  let(:rule) do
    IPaaS::Connector::Common::ProcRules::ValidMethodsRule.new(
      ->(msg) { raise "Unexpected error: #{msg}" }
    )
  end

  [
    :method,
    :Method,
    :UnboundMethod,
    :define_method,
    :method_missing,
    :respond_to_missing?,
    :instance_method,
    :to_proc,
    # `Proc#>>` and `Method#>>` compose two callables into a third.
    :>>,
    # Refused here, a class-row grant of `new` still instantiates nothing.
    :new,
    # Support the `methods:` option, which calls private methods.
    :as_json,
    :serializable_hash,
    :to_xml,
  ].each do |unsafe_method|
    it "does not allow #{unsafe_method}" do
      expect(IPaaS::Connector::Common::ProcRules::ValidMethodsRule::RUBY_METHODS).not_to include(unsafe_method)
      expect(IPaaS::Connector::Common::ProcRules::ValidMethodsRule::ADDITIONAL_METHODS).not_to include(unsafe_method)
      expect(IPaaS::Connector::Common::ProcRules::ProcSafe.registry).not_to include(unsafe_method)
    end
  end

  [
    :drill,
    :number_to_human_size,
    :finish_job!,
    :backoff_if_needed,
    :parse_json_response,
    :parse_csv,
    :psa_validate_secret,
    :psa_extract_basic_auth,
    :psa_generate_secret_for,
    :psa_secret_for,
    :psa_delete_secret_for,
    :secure_compare,
    :kind_of?,
    :instance_of?,
    :today,
    :date,
    :beginning_of_day,
    :since,
    :saturday?,
    :setup_info,
    :'path=',
    :'fields=',
    :|,
  ].each do |allowed_method|
    it "allows #{allowed_method}" do
      expect { rule.validate_method(allowed_method) }.not_to raise_error
    end
  end

  describe 'allow-listed ActiveSupport time methods exist on real objects' do
    # Guards against typos: a whitelisted name that no longer maps to a real
    # method would silently widen the allow-list without ever working.
    it 'are available on Time and Date' do
      now = Time.now
      today = Date.new(2026, 6, 11)

      expect(now.beginning_of_day).to be_a(Time)
      expect(now.end_of_month).to be_a(Time)
      expect(now.since(2.days)).to be_a(Time)
      expect(now.in_time_zone).to respond_to(:zone)
      expect(today.beginning_of_week).to be_a(Date)
      expect(today.saturday?).to be(false)
      expect(2.days.in_seconds).to eq(172_800)
    end
  end

  [
    :new,
    :parse,
    :load,
    :strptime,
    :step,
    :upto,
    :downto,
  ].each do |unsafe_time_method|
    it "does not allow unsafe time-adjacent method #{unsafe_time_method}" do
      expect(IPaaS::Connector::Common::ProcRules::ValidMethodsRule::TIME_METHODS).not_to include(unsafe_time_method)
    end
  end

  # A look-alike character reads as the operator it resembles and allow-lists nothing: `:ˆ`
  # (U+02C6) sat among the arithmetic operators without ever matching a method name.
  describe 'every allowed method is named in ASCII' do
    it 'has no unreachable look-alike entry, on any of the three lists validate_method consults' do
      allowed = described_class::RUBY_METHODS +
                described_class::ADDITIONAL_METHODS +
                IPaaS::Connector::Common::ProcRules::ProcSafe.registry
      non_ascii = allowed.reject { |method_name| method_name.to_s.ascii_only? }

      expect(non_ascii).to be_empty
    end
  end

  describe 'method constants' do
    method_constants = [
      :BASE_METHODS, :COMPARISON_METHODS, :STRING_METHODS, :NUMBER_METHODS,
      :HASH_METHODS, :ARRAY_METHODS, :BASE64_METHODS, :TIME_METHODS,
      :URI_METHODS, :CRYPTO_METHODS, :ERROR_METHODS, :XML_METHODS, :DEBUG_METHODS,
    ].freeze

    method_constants.each do |const|
      it "has no duplicates within #{const}" do
        methods = described_class.const_get(const).to_a
        duplicates = methods.group_by(&:itself).select { |_, v| v.size > 1 }.keys
        expect(duplicates).to be_empty, "Duplicate methods in #{const}: #{duplicates.join(', ')}"
      end
    end
  end

  describe 'reflective dispatch: a symbol argument that becomes the dispatched method name' do
    # These cases must name no constant off the list. `Kernel` is refused by ValidConstantsRule, so a
    # `Kernel`-bearing source is rejected even with REFLECTIVE_METHODS empty and proves nothing here.
    def not_a_literal_symbol(method_name)
      "Method name argument to '#{method_name}' must be a literal symbol."
    end

    describe 'a literal symbol argument is validated as a method name' do
      {
        '[1, 2].reduce(:eval)' => "Method 'eval' not allowed.",
        '[1, 2].reduce(:public_send)' => "Method 'public_send' not allowed.",
        '[1, 2].reduce(:instance_variable_get)' => "Method 'instance_variable_get' not allowed.",
        '[1, 2].reduce(:method)' => "Method 'method' not allowed.",
        '[1].reduce(:eval, &:to_s)' => "Method 'eval' not allowed.",
        'params[:a]&.reduce(:eval)' => "Method 'eval' not allowed.",
      }.each do |source, message|
        it "reports #{source.inspect} as #{message.inspect}" do
          expect(errors_for(source)).to contain_exactly(message)
        end
      end

      it 'reports helpers.reduce(:eval), which the top-level helper exemption would otherwise skip' do
        expect(errors_for('helpers.reduce(:eval)')).to contain_exactly("Method 'eval' not allowed.")
      end
    end

    describe 'an argument the validator cannot read as a method name' do
      [
        '[1].reduce(0, "x".to_sym) { |a, b| a }',
        '[1].reduce("x".to_sym)',
        '["a"].reduce(*[1, :eval]) { |a, b| a }',
        '[1, 2].reduce(:+, 0)',
        '[1, 2].reduce(:+, foo: 1)',
      ].each do |source|
        it "reports #{source.inspect} as requiring a literal symbol" do
          expect(errors_for(source)).to contain_exactly(not_a_literal_symbol('reduce'))
        end
      end

      it 'reports once per reflective method, so reduce and inject each report separately' do
        source = '[[1].reduce("a".to_sym), [2].reduce("b".to_sym), [3].inject("c".to_sym)]'

        expect(errors_for(source)).to contain_exactly(
          not_a_literal_symbol('reduce'),
          not_a_literal_symbol('inject'),
          "Method 'inject' not allowed."
        )
      end
    end

    describe 'permitted reduce forms' do
      [
        '[1, 2].reduce(:+)',
        '["a"].reduce(:+) { |a, b| a }',
        '[1, 2].reduce(0) { |a, b| a + b }',
        'params[:h].reduce({}) { |a, (k, v)| a }',
        '[[1], [2]].reduce',
      ].each do |source|
        it "permits #{source.inspect}" do
          expect(errors_for(source)).to be_empty
        end
      end
    end

    it 'pins REFLECTIVE_METHODS, so adding an entry forces cases for it here' do
      covered = [:reduce, :inject]
      covered.each do |method_name|
        expect(errors_for(%([1].#{method_name}("x".to_sym)))).to include(not_a_literal_symbol(method_name))
      end

      expect(described_class::REFLECTIVE_METHODS.to_a).to match_array(covered)
    end

    describe 'a block-pass argument the validator cannot read' do
      [
        's = :instance_eval; [self, "1+1"].reduce(&s)',
        '[self, "1+1"].reduce(&"instance_eval".to_sym)',
        's = :instance_eval; [self].each_with_object("1+1", &s)',
        's = :freeze; params[:a].map(&s)',
      ].each do |source|
        it "reports #{source.inspect} as requiring a literal symbol" do
          expect(errors_for(source)).to include('Block argument must be a literal symbol.')
        end
      end

      it 'reports an unreadable block-pass once per proc' do
        source = 's = :instance_eval; [[1].reduce(&s), [2].reduce(&s)]'

        expect(errors_for(source)).to contain_exactly('Block argument must be a literal symbol.')
      end

      [
        '[1, 2].reduce(&:+)',
        'params[:a].map(&:to_s)',
        'params[:a].select(&:present?)',
      ].each do |source|
        it "permits the literal form #{source.inspect}" do
          expect(errors_for(source)).to be_empty
        end
      end
    end

    it 'leaves symbols passed to non-reflective methods as data' do
      expect(errors_for('params[:a].dig(:eval, :system)')).to be_empty
    end
  end

  describe 'reporting a call to class' do
    def class_calls_for(source)
      calls = []
      rule = described_class.new(nil, on_invalid: ->(_message) {})
      rule.on_class_call = ->(node) { calls << node }
      process_source(rule, source)
      calls.uniq(&:object_id).map { |node| [node.type, node.source] }
    end

    it 'hands over every dispatch of class, safe navigation and block-pass included' do
      expect(class_calls_for('[params.class, params&.class, [1].map(&:class)]'))
        .to contain_exactly([:send, 'params.class'], [:csend, 'params&.class'], [:block_pass, '&:class'])
    end

    it 'hands over class called on helpers, which the method list does not judge' do
      expect(class_calls_for('helpers.class')).to eq([[:send, 'helpers.class']])
    end

    it 'hands over nothing for other methods, or class spelled as data' do
      expect(class_calls_for("[params.klass, 'class', { class: 1 }, [1].map(&:to_s)]")).to be_empty
    end

    it 'hands over nothing for class dispatched from a positional symbol' do
      expect(class_calls_for('[1].reduce(:class)')).to be_empty
    end

    it 'still refuses when no observer is set' do
      errors = []
      rule = described_class.new(nil, on_invalid: ->(message) { errors << message })

      expect { process_source(rule, '[params.class, [1].map(&:class)]') }.not_to raise_error
      expect(errors).to eq([described_class::CLASS_CALL_MESSAGE])
    end
  end

  describe 'refusing a class call used for more than its name' do
    let(:message) { described_class::CLASS_CALL_MESSAGE }

    it 'reports once for a source with several such calls beside a permitted one' do
      expect(errors_for("[\"a \#{params.class}\", params.class.present?, params&.class, [1].map(&:class)]"))
        .to eq([message])
    end

    it 'refuses a method called on class' do
      expect(errors_for('params.class.present?')).to eq([message])
    end

    it 'refuses class passed as a block' do
      expect(errors_for('[1].map(&:class)')).to eq([message])
    end

    it 'refuses class passed as a block to a helper' do
      expect(errors_for('helpers.fmt(&:class)')).to eq([message])
    end

    it 'accepts class used for its name' do
      expect(errors_for("[\"a \#{params.class}\", params.class.name, params.class.to_s, log(params.class)]"))
        .to be_empty
    end

    it 'accepts reduce(:class), which hands class an argument and so cannot return a class' do
      expect(errors_for('[1].reduce(:class)')).to be_empty
    end
  end

  describe 'refusing to_json with arguments' do
    let(:message) { described_class::TO_JSON_MESSAGE }

    it 'reports once for a call and a symbol dispatch, one of them nested in a block' do
      expect(errors_for('[1].reduce(:to_json); [params[:a]].each { |v| v.to_json(1) }')).to eq([message])
    end

    it 'accepts the same source with to_json called without arguments and another symbol dispatched' do
      expect(errors_for('[1].reduce(:to_s); [params[:a]].each { |v| v.to_json }')).to be_empty
    end

    it 'refuses to_json as the seed of a reduce with a block, where it is only a value' do
      expect(errors_for('[1].reduce(:to_json) { |a, b| a }')).to eq([message])
    end

    it 'accepts another symbol as the seed of a reduce with a block' do
      expect(errors_for('[1].reduce(:to_s) { |a, b| a }')).to be_empty
    end

    it 'accepts to_json with an argument on helpers, which dispatches only to a registered helper' do
      expect(errors_for('helpers.to_json(1)')).to be_empty
    end

    it 'refuses to_json passed to helpers as a reflective symbol' do
      expect(errors_for('helpers.reduce(:to_json)')).to eq([message])
    end

    it 'refuses to_json passed to helpers as a block' do
      expect(errors_for('helpers.fmt(&:to_json)')).to eq([message])
    end

    it 'accepts another symbol dispatched through helpers' do
      expect(errors_for('[helpers.reduce(:+), helpers.fmt(&:to_s)]')).to be_empty
    end
  end

  it 'keeps every dispatcher and record reader off every method list' do
    dispatchers = [
      :send, :public_send, :__send__, :try, :try!, :method, :public_method, :singleton_method,
      :define_singleton_method, :to_proc, :values_at, :with,
      :read_attribute_for_validation, :read_attribute_for_serialization,
      :instance_variable_get, :instance_values, :record,
    ]
    aggregate_failures do
      dispatchers.each do |name|
        expect(described_class::RUBY_METHODS).not_to include(name), "#{name} is on RUBY_METHODS"
        expect(described_class::ADDITIONAL_METHODS).not_to include(name), "#{name} is on ADDITIONAL_METHODS"
        expect(described_class::DEBUG_METHODS_SET).not_to include(name), "#{name} is on DEBUG_METHODS_SET"
      end
    end
  end

  describe 'restricting solution to its listed methods' do
    let(:message) { described_class::SOLUTION_CALL_MESSAGE }

    [
      "solution&.name&.presence || 'x'",
      'solution.create_schedule!(runbook.uuid, {})',
      "solution.soft_delete_schedule('ref')",
      "solution.runbooks.detect { |r| r.name == 'x' }",
      'runbook.solution.uuid',
      'solution&.uuid',
      '(solution).uuid',
      "\"a \#{solution.name}\"",
      'x = 1; x ||= solution.uuid',
      '@name ||= solution.name',
      'a = solution.name; a += solution.uuid',
    ].each do |source|
      it "accepts #{source}" do
        expect(errors_for(source)).to be_empty
      end
    end

    it 'accepts solution as the receiver of every listed method' do
      aggregate_failures do
        described_class::SOLUTION_METHODS.each do |name|
          expect(errors_for("solution.#{name}")).to be_empty, "expected solution.#{name} to be accepted"
        end
      end
    end

    {
      'solution.first' => 'a method the list allows elsewhere',
      'solution.keys' => 'another listed method, refused on solution',
      "solution.update_schedule('ref', {})" => 'a registered but unlisted method',
      'solution.tap { |s| s }' => 'a method yielding the record',
      'solution.to_s' => 'a stringifying method that is not listed',
      "solution.runbooks.detect { |r| r.name == 'x' }.solution.first" => 'a second solution send',
      'solution' => 'the record returned',
      's = solution' => 'the record bound',
      '[solution]' => 'the record in a literal',
      '{ a: solution }' => 'the record as a hash value',
      'log(solution)' => 'the record as an argument',
      "\"a \#{solution}\"" => 'the record interpolated',
      'solution == params' => 'the record compared',
      "case solution\nin s then s\nend" => 'the record matched',
      '[1].map { solution }.first.name' => 'the record passed out of a block',
      '(params ? solution : params).to_s' => 'the record through a branch',
      'runbook.uuid(solution)' => 'the record as an argument to a listed method',
      '[1].map { solution }.uuid' => 'the record reaching a listed method out of a block',
    }.each do |source, reason|
      it "refuses #{source}: #{reason}" do
        expect(errors_for(source)).to eq([message])
      end
    end

    {
      "solution.uuid ||= 'x'" => "Method 'uuid=' not allowed.",
      "solution.uuid += 'x'" => "Method 'uuid=' not allowed.",
      "solution.uuid = 'x'" => "Method 'uuid=' not allowed.",
      'solution.uuid, a = 1, 2' => "Method 'uuid=' not allowed.",
      'solution.inspect' => "Method 'inspect' not allowed.",
    }.each do |source, other|
      it "refuses #{source} by position as well as by the method list" do
        expect(errors_for(source)).to contain_exactly(message, other)
      end
    end

    it 'refuses solution passed as a block, by name' do
      expect(errors_for('[runbook].map(&:solution)')).to eq([message])
    end

    it 'refuses solution dispatched from a positional symbol, by name' do
      expect(errors_for('[runbook].reduce(nil, :solution)')).to eq([message])
    end

    it 'keeps the symbol routes refused even if solution is registered, so proc_safe cannot reopen them' do
      IPaaS::Connector::Common::ProcRules::ProcSafe.registry.add(:solution)
      aggregate_failures do
        expect(errors_for('[runbook].map(&:solution)')).to eq([message])
        expect(errors_for('[runbook].reduce(nil, :solution)')).to eq([message])
      end
    ensure
      IPaaS::Connector::Common::ProcRules::ProcSafe.registry.delete(:solution)
    end

    it 'accepts solution on helpers, which dispatches only to a registered helper' do
      expect(errors_for('helpers.solution')).to be_empty
    end

    it 'refuses solution passed to helpers as a reflective symbol or a block' do
      expect(errors_for('helpers.reduce(:solution)')).to eq([message])
      expect(errors_for('helpers.fmt(&:solution)')).to eq([message])
    end

    it 'reports once for a source with several refused uses beside an accepted one' do
      expect(errors_for('solution.uuid; solution.first; s = solution')).to eq([message])
    end

    it 'names every listed method in the message' do
      described_class::SOLUTION_METHODS.each { |name| expect(message).to include(name.to_s) }
    end

    it 'lists no setter, so an assignment to solution is never a listed call' do
      expect(described_class::SOLUTION_METHODS.select { |name| name.end_with?('=') }).to be_empty
    end

    it 'keeps solution off every method list' do
      expect(described_class::RUBY_METHODS).not_to include(:solution)
      expect(described_class::ADDITIONAL_METHODS).not_to include(:solution)
      expect(described_class::DEBUG_METHODS_SET).not_to include(:solution)
    end
  end

  describe 'reporting a use of solution' do
    def solution_uses_for(source)
      uses = []
      rule = described_class.new(nil, on_invalid: ->(_message) {})
      rule.on_solution_call = ->(node) { uses << node }
      process_source(rule, source)
      uses.uniq(&:object_id).map { |node| [node.type, node.source] }
    end

    it 'hands over every send, block pass and reflective symbol naming solution' do
      source = '[solution.uuid, runbook&.solution, [runbook].map(&:solution), [1].reduce(nil, :solution)]'
      expect(solution_uses_for(source))
        .to contain_exactly([:send, 'solution'], [:csend, 'runbook&.solution'], [:block_pass, '&:solution'],
                            [:sym, ':solution'])
    end

    it 'hands over solution called on helpers, which the method list does not judge' do
      expect(solution_uses_for('helpers.solution')).to eq([[:send, 'helpers.solution']])
    end

    it 'hands over nothing for other methods, or solution spelled as data' do
      expect(solution_uses_for("[params.solutions, 'solution', { solution: 1 }, [1].map(&:to_s)]")).to be_empty
    end
  end
end
