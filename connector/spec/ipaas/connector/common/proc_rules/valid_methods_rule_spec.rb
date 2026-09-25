require 'spec_helper'

describe IPaaS::Connector::Common::ProcRules::ValidMethodsRule do
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
    def errors_for(source)
      errors = []
      rule = described_class.new(nil, on_invalid: ->(message) { errors << message })
      target = IPaaS::Connector::Common::ProcHelper::TARGET_RUBY_VERSION
      RuboCop::AST::ProcessedSource.new(source, target).ast.each_node { |node| rule.process(node) }
      errors
    end

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
end
