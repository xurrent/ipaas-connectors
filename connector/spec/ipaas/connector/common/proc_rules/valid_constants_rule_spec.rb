require 'spec_helper'

# Block procs whose file assigns constants of its own, nested under a module another file defines
# so that "assigned in this file" and "present in the nesting" are different things the examples can
# tell apart. This module stays in this file: its file is what the rule compares against.
module IPaaS
  module Connector
    module Common
      module ProcRules
        module ValidConstantsRuleSpecOwner
          NOTE = 'x'.freeze
          Hum = IPaaS::Job::Humanize
          GqlSchema = IPaaS::Job::GraphQL::Schema
          MY = File
          Module = 'shadowed'.freeze # rubocop:disable Naming/ConstantName

          class << self
            def capture(&block)
              block
            end

            def owned_read
              capture { NOTE }
            end

            def absolute_read
              capture { ::NOTE }
            end

            def owned_through_nesting_module
              capture { ValidConstantsRuleSpecOwner::NOTE }
            end

            def bare_nesting_module
              capture { ValidConstantsRuleSpecOwner }
            end

            def nesting_module_as_receiver
              capture { ValidConstantsRuleSpecOwner.name }
            end

            def segment_below_owned_value
              capture { NOTE::Foo }
            end

            def segment_another_file_assigned
              capture { ValidConstantsRuleSpecOwner::ELSEWHERE }
            end

            def alias_with_permitted_call
              capture { Hum.humanize_field_name('a') }
            end

            def alias_with_unlisted_call
              capture { Hum.gql_cache_clear }
            end

            def alias_with_op_assigned_call
              capture { Hum.humanize_field_name ||= 1 }
            end

            def alias_bound
              capture do
                h = Hum
                h.name
              end
            end

            def alias_continued_into_listed_path
              capture { GqlSchema::INTROSPECTION_QUERY }
            end

            def alias_to_unpermitted_module
              capture { MY.read('x') }
            end

            def undefined_root
              capture { Nope }
            end

            def enclosing_module_constant_from_another_file
              capture { BASIC_RULES }
            end

            def pattern_on_alias
              capture { case params[:a]; in Hum then 1; end }
            end

            def listed_path
              capture { Time.now }
            end

            def owned_value_rescued
              capture do
                params[:a]
              rescue NOTE
                1
              end
            end
          end
        end
      end
    end
  end
end

require_relative '../../../../fixtures/constant_assigned_in_another_file'
require_relative '../../../../fixtures/proc_from_another_file'

require_relative '../../../../fixtures/top_level_probe_connector'

describe IPaaS::Connector::Common::ProcRules::ValidConstantsRule do
  let(:owner) { IPaaS::Connector::Common::ProcRules::ValidConstantsRuleSpecOwner }

  def judge(source, procedure: nil, on_invalid: :collect)
    errors = []
    uses = []
    sink = on_invalid == :collect ? ->(message) { errors << message } : on_invalid
    rule = described_class.new(nil, on_invalid: sink, procedure: procedure, on_use: ->(use) { uses << use })
    target = IPaaS::Connector::Common::ProcHelper::TARGET_RUBY_VERSION
    RuboCop::AST::ProcessedSource.new(source, target).ast.each_node { |node| rule.process(node) }
    [errors, uses]
  end

  def errors_for(source, procedure: nil)
    judge(source, procedure: procedure).first
  end

  def uses_for(source, procedure: nil)
    judge(source, procedure: procedure).last
  end

  def errors_for_block(procedure)
    errors_for(IPaaS::Connector::Common::ProcHelper.proc_source(procedure), procedure: procedure)
  end

  def uses_for_block(procedure)
    uses_for(IPaaS::Connector::Common::ProcHelper.proc_source(procedure), procedure: procedure)
  end

  def path_message(name)
    "Access to '#{name}' is not allowed in expressions; only an approved set of classes is available. " \
      'Please file a request if access is needed.'
  end

  def method_message(method, name)
    "Calling '#{method}' on '#{name}' is not allowed in expressions; only approved methods of approved " \
      'classes are available. Please file a request if access is needed.'
  end

  def reopening_message(name)
    "Reopening '#{name}' is not allowed in expressions."
  end

  def binding_message(name)
    "'#{name}' may only be called, rescued, raised or tested in expressions, not passed on as a value."
  end

  def rescue_message(name)
    "'#{name}' is not an error class, so it cannot be rescued in expressions."
  end

  def error_message(name)
    "'#{name}' could not be checked in expressions, so it is not available."
  end

  describe 'listed paths' do
    [
      'Time.now',
      '::Time.now',
      'Time&.now',
      'begin; 1; rescue JSON::ParserError; 2; end',
      'begin; 1; rescue ::JSON::ParserError, ArgumentError; 2; end',
      'raise ArgumentError, "x"',
      'x.is_a?(Time)',
      'x&.is_a?(Hash)',
      'params.is_a?(Time)',
      'helpers.raise(Time)',
      'h = helpers; h.is_a?(Time)',
      'case x; when Hash then 1; when Array then 2; end',
      'begin; 1; rescue ArgumentError => e; e; end',
      'limit = IPaaS::Job::JWT::MAX_TOKEN_BYTES',
      '[IPaaS::Job::JWT::MAX_TOKEN_BYTES, IPaaS::Job::JWT::SUPPORTED_ALGORITHMS]',
      'OpenSSL::HMAC.hexdigest("sha256", "k", "d")',
      'OpenSSL::Digest::SHA256.hexdigest("d")',
      'IPaaS::Job::Outbound::HTTP.create_binary_part("n", "t", "d")',
      'IPaaS::Job::JWT::ASYMMETRIC_JWK_KTYS.include?("RSA")',
      'JSON["{}"]',
      'IPaaS::Job::GraphQL::ArtifactCache.gql_write_root_options(1, 2, 3)',
      'x.kind_of?(Time)',
      'x&.instance_of?(Hash)',
      'helpers.kind_of?(Time)',
      'begin; 1; rescue ArgumentError, StandardError; 2; end',
      'begin; 1; rescue ::TypeError; 2; end',
      'begin; 1; rescue ArgumentError => e; e; end',
      'begin; 1; rescue StandardError; [1]; end',
      'ActiveSupport::SecurityUtils.secure_compare("a", "b")',
      'Base64.strict_decode64(Base64.strict_encode64(value.to_s))',
      'Base64.urlsafe_decode64(Base64.urlsafe_encode64("x"))',
      'Digest::SHA256.digest("d")',
      'URI.join("https://example.com/a/", "b")',
      'begin; 1; rescue KeyError, IndexError; 2; end',
      'raise RuntimeError, "x"',
      'x.is_a?(Float)',
    ].each do |source|
      it "permits #{source.inspect}" do
        expect(errors_for(source)).to be_empty
      end
    end

    it 'judges a multi-segment path once, at its outermost node' do
      uses = uses_for('IPaaS::Job::Outbound::HTTP.raw_param_value(1)')

      expect(uses.map(&:written)).to eq([[:IPaaS, :Job, :Outbound, :HTTP]])
    end
  end

  describe 'unlisted paths' do
    {
      'Psych.parse' => 'Psych',
      'File.read("/etc/passwd")' => 'File',
      '::File' => 'File',
      'Kernel' => 'Kernel',
      'OpenSSL::Digest' => 'OpenSSL::Digest',
      'IPaaS::Job' => 'IPaaS::Job',
      'IPaaS::Job::GraphQL::Schema::Nope' => 'IPaaS::Job::GraphQL::Schema::Nope',
      'Float::INFINITY' => 'Float::INFINITY',
      'x = [Float::INFINITY]' => 'Float::INFINITY',
      'defined?(ENV)' => 'ENV',
      '"#{::ENV}"' => 'ENV', # rubocop:disable Lint/InterpolationCheck
      'Object::ENV["PATH"]' => 'Object::ENV',
      'case 1; in Foo::ENV then 2; end' => 'Foo::ENV',
      'ActiveSupport::SecurityUtils::Foo' => 'ActiveSupport::SecurityUtils::Foo',
      'ActiveSupport' => 'ActiveSupport',
    }.each do |source, name|
      it "refuses #{source.inspect} naming #{name}" do
        expect(errors_for(source)).to contain_exactly(path_message(name))
      end
    end

    it 'reaches a constant in a block argument as well as in the receiver' do
      expect(errors_for('ENV.fetch("PATH") { RUBY_VERSION }'))
        .to contain_exactly(path_message('ENV'), path_message('RUBY_VERSION'))
    end

    it 'reports a path once however often it is written' do
      expect(errors_for('Psych.parse; Psych.parse; Psych')).to contain_exactly(path_message('Psych'))
    end
  end

  describe 'methods on listed paths' do
    {
      'JSON.load("{}")' => %w[load JSON],
      'JSON&.load("{}")' => %w[load JSON],
      'IPaaS::Job::JWT::ASYMMETRIC_JWK_KTYS&.first' => %w[first IPaaS::Job::JWT::ASYMMETRIC_JWK_KTYS],
      'Time.zone = "Tokyo"' => %w[zone= Time],
      'IPaaS::Job::JWT::ASYMMETRIC_JWK_KTYS.first' => %w[first IPaaS::Job::JWT::ASYMMETRIC_JWK_KTYS],
      'IPaaS::Job::Humanize.name' => %w[name IPaaS::Job::Humanize],
    }.each do |source, (method, name)|
      it "refuses #{source.inspect} for the method" do
        expect(errors_for(source)).to contain_exactly(method_message(method, name))
      end
    end

    it 'permits the listed method beside the refused one, so the row is read per method' do
      expect(errors_for('JSON.parse("{}"); JSON.load("{}")')).to contain_exactly(method_message('load', 'JSON'))
    end
  end

  # A row listing a reader must not carry the write of it. The explicit and multiple-assign forms
  # spell the writer as a send and were always judged; a shorthand assignment names only the reader
  # it expands from, so the writer it calls has to be derived from the form.
  describe 'the writer an assignment calls' do
    {
      'IPaaS::Job::CompactHash.compact_hash = 1' => 'IPaaS::Job::CompactHash',
      'IPaaS::Job::CompactHash.compact_hash, y = 1, 2' => 'IPaaS::Job::CompactHash',
      'IPaaS::Job::CompactHash.compact_hash ||= 1' => 'IPaaS::Job::CompactHash',
      'IPaaS::Job::CompactHash.compact_hash &&= 1' => 'IPaaS::Job::CompactHash',
      'IPaaS::Job::CompactHash.compact_hash += 1' => 'IPaaS::Job::CompactHash',
      'IPaaS::Job::CompactHash&.compact_hash ||= 1' => 'IPaaS::Job::CompactHash',
    }.each do |source, name|
      it "refuses #{source.inspect} for the writer" do
        expect(errors_for(source)).to contain_exactly(method_message('compact_hash=', name))
      end
    end

    [
      'IPaaS::Job::CompactHash.compact_hash({})',
      'IPaaS::Job::CompactHash&.compact_hash({})',
      'x = IPaaS::Job::CompactHash.compact_hash({}); x[:a] ||= 1',
    ].each do |source|
      it "permits #{source.inspect}, which calls only the listed reader" do
        expect(errors_for(source)).to be_empty
      end
    end

    it 'judges the reader beside the writer, rather than replacing it' do
      uses = uses_for('IPaaS::Job::CompactHash.compact_hash ||= 1')

      expect(uses.map { |use| [use.method_name, use.outcome] })
        .to eq([[:compact_hash, :allowed], [:compact_hash=, :refused]])
    end

    it 'derives the writer of an index read, which no row may grant through the reader' do
      uses = uses_for('IPaaS::Job::JWT::ASYMMETRIC_JWK_KTYS[:k] ||= 1')

      expect(uses.map(&:method_name)).to eq([:[], :[]=])
    end

    it 'refuses the writer under an owned alias too, where the row applies through the alias' do
      expect(errors_for_block(owner.alias_with_permitted_call)).to be_empty
      expect(errors_for_block(owner.alias_with_op_assigned_call))
        .to contain_exactly(method_message('humanize_field_name=', 'Hum'))
    end
  end

  describe 'a class passed on as a value' do
    {
      't = Time; t.zone = "x"' => %w[Time],
      '[Time].first.zone = "x"' => %w[Time],
      'params.fetch(Time)' => %w[Time],
      'Time' => %w[Time],
      '[Hash, Array].include?(x.class)' => %w[Hash Array],
      'x = JSON::ParserError' => %w[JSON::ParserError],
      't = begin; params[:a]; rescue; Time; end; t.zone = "x"' => %w[Time],
      't = (case params[:a]; when 1 then Time; end); t.zone = "x"' => %w[Time],
      'x.respond_to?(Time)' => %w[Time],
      'x = {a: Time}' => %w[Time],
      'x.kind_of?(&Time)' => %w[Time],
      'x.kind_of?(*[Time])' => %w[Time],
      'x.instance_of?(Time => 1)' => %w[Time],
      'begin; 1; rescue StandardError; [Time]; end' => %w[Time],
      'x = (raise rescue [Time])' => %w[Time],
      'begin; 1; rescue => e; [Time]; end' => %w[Time],
      'x = [[Time]]' => %w[Time],
      'begin; 1; rescue [Time]; 2; end' => %w[Time],
      'x = ActiveSupport::SecurityUtils' => %w[ActiveSupport::SecurityUtils],
    }.each do |source, names|
      it "refuses #{source.inspect}, since the value would reach methods the row does not list" do
        expect(errors_for(source)).to contain_exactly(*names.map { |name| binding_message(name) })
      end
    end

    it 'records the reason as bound, apart from a missing row' do
      expect(uses_for('t = Time').map { |use| [use.outcome, use.reason] }).to eq([[:refused, :bound]])
    end

    it 'refuses an owned alias bound to a value the same way' do
      expect(errors_for_block(owner.alias_bound)).to contain_exactly(binding_message('Hum'))
    end

    it 'consumes a class only through methods the method lists permit, so no entry is dead' do
      lists = IPaaS::Connector::Common::ProcRules::ValidMethodsRule
      permitted = lists::RUBY_METHODS + lists::ADDITIONAL_METHODS

      expect(described_class::READ_METHODS).not_to be_empty
      expect(described_class::READ_METHODS).to all(satisfy { |method| permitted.include?(method) })
    end

    it 'judges a String proc exactly as a source handed over without one, which is the same tier' do
      ['Time.now', 't = Time', 'NOTE', 'x.is_a?(Hash)'].each do |source|
        expect(errors_for(source, procedure: source)).to eq(errors_for(source))
      end
    end

    # Customer expressions and connector code are judged by one list: a block owning nothing is
    # refused and permitted exactly as the same text in an expression field.
    it 'judges a block in a file owning no constants exactly as the same text as a String proc' do
      ['Time.now', 't = Time', 'Psych.parse', 'x.is_a?(Hash)', 'begin; 1; rescue Exception; 2; end'].each do |source|
        block = eval("proc { #{source} }", binding, '/somewhere/else/connector.rb', 1) # rubocop:disable Security/Eval, Style/EvalWithLocation

        expect(errors_for(source, procedure: block)).to eq(errors_for(source, procedure: source))
      end
    end
  end

  # Pattern syntax tests a class through the language rather than through a method call. The two
  # families spell the tested operand on opposite sides, so the accepted child position is inverted.
  describe 'a class matched by a pattern' do
    [
      'case x; in Hash then 1; end',
      'case x; in Hash; end',
      'case x; in Array(a) then a; end',
      'case x; in Array[a] then a; end',
      'case x; in [Hash, Array] then 1; end',
      'case x; in [Hash,] then 1; end',
      'case x; in [*, Hash, *] then 1; end',
      'case x; in Hash | Array then 1; end',
      'case x; in Hash => h then h; end',
      'x in Hash',
      'x => Hash',
      'x => Hash => h',
      'params in Array | Hash',
      'case x; in {a: Hash} then 1; end',
      'case x; in {a: [Hash]} then 1; end',
      'case x; in {a: Hash => h} then h; end',
    ].each do |source|
      it "permits #{source.inspect}, where the class is matched against and never bound" do
        expect(errors_for(source)).to be_empty
      end
    end

    {
      'Hash => a' => 'Hash',
      'Hash in a' => 'Hash',
      'case Hash; in a then a; end' => 'Hash',
      'case Hash; when 1 then 1; end' => 'Hash',
    }.each do |source, name|
      it "refuses #{source.inspect}, where the class is the operand being matched and not the pattern" do
        expect(errors_for(source)).to contain_exactly(binding_message(name))
      end
    end

    {
      'case x; in 1 then Hash; end' => 'Hash',
      'q = (case x; in Hash then Hash; end)' => 'Hash',
      'case x; in a if Hash then 1; end' => 'Hash',
      'case x; in ^(Hash) then 1; end' => 'Hash',
    }.each do |source, name|
      it "refuses #{source.inspect}, where the construct evaluates the class rather than matching it" do
        expect(errors_for(source)).to contain_exactly(binding_message(name))
      end
    end

    it 'records the refusal of the inverted form as bound, so it is the position and not a missing row' do
      expect(uses_for('Hash => a').map { |use| [use.written, use.outcome, use.reason] })
        .to eq([[[:Hash], :refused, :bound]])
    end

    it 'judges an owned alias in a pattern as the module it names, the one path reaching the check late' do
      procedure = owner.pattern_on_alias

      expect(errors_for_block(procedure)).to be_empty
      expect(uses_for_block(procedure).map(&:canonical)).to eq([[:IPaaS, :Job, :Humanize]])
    end

    it 'refuses an unlisted class in a pattern at the row, before the position is consulted' do
      expect(uses_for('case x; in Psych then 1; end').map { |use| [use.outcome, use.reason] })
        .to eq([[:refused, :path]])
    end
  end

  # A deadline interrupt is not a StandardError; a value in a rescue clause makes Ruby raise a TypeError,
  # which a StandardError rescue around it catches, swallowing the interrupt that reached the clause.
  describe 'what a rescue list may name' do
    {
      'begin; 1; rescue IPaaS::Job::JWT::MAX_TOKEN_BYTES; 2; end' => 'IPaaS::Job::JWT::MAX_TOKEN_BYTES',
      'begin; 1; rescue StandardError, IPaaS::Job::JWT::MAX_TOKEN_BYTES; 2; end' => 'IPaaS::Job::JWT::MAX_TOKEN_BYTES',
      'begin; 1; rescue Hash; 2; end' => 'Hash',
      'begin; 1; rescue JSON; 2; end' => 'JSON',
    }.each do |source, name|
      it "refuses #{source.inspect}, since a rescue clause needs an error class" do
        expect(errors_for(source)).to contain_exactly(rescue_message(name))
      end
    end

    [
      'begin; 1; rescue JSON::ParserError; 2; end',
      'begin; 1; rescue StandardError, IPaaS::Error => e; e; end',
    ].each do |source|
      it "permits #{source.inspect}, which rescues an error class" do
        expect(errors_for(source)).to be_empty
      end
    end

    it 'refuses a value the block\'s own file assigns, which no row judges' do
      expect(errors_for_block(owner.owned_value_rescued)).to contain_exactly(rescue_message('NOTE'))
    end
  end

  describe 'paths that are not purely constants' do
    {
      'foo::Time' => [[:path, 'Time']],
      'Time.now::JSON' => [[:path, 'JSON']],
      '[Time][0]::JSON' => [[:path, 'JSON'], [:bound, 'Time']],
    }.each do |source, expected|
      it "refuses #{source.inspect} naming the leaf" do
        messages = expected.map { |kind, name| kind == :path ? path_message(name) : binding_message(name) }

        expect(errors_for(source)).to contain_exactly(*messages)
      end
    end

    it 'refuses a listed path that is only the scope of an expression path, and the inner class it passes on' do
      errors, uses = judge('(Time)::JSON')

      expect(errors).to contain_exactly(path_message('JSON'), binding_message('Time'))
      expect(uses.map { |use| [use.written, use.outcome, use.reason] })
        .to contain_exactly([[:JSON], :refused, :scope], [[:Time], :refused, :bound])
    end
  end

  describe 'definition targets' do
    [
      'class << Time; undef now; end',
      'module JSON; end',
      'class JSON::ParserError; end',
      'Time::X = 1',
      'Time::X ||= 1',
      'class << (nil || Time); end',
    ].each do |source|
      it "refuses #{source.inspect} whatever the list says, naming the reopening" do
        expect(errors_for(source)).to contain_exactly(reopening_message(source[/(?:Time|JSON)(?:::ParserError)?/]))
      end
    end
  end

  describe 'a block proc in a file assigning its own constants' do
    it 'permits reading an owned constant and records it as owned' do
      procedure = owner.owned_read

      expect(errors_for_block(procedure)).to be_empty
      expect(uses_for_block(procedure).map { |use| [use.written, use.canonical, use.outcome] })
        .to eq([[[:NOTE], nil, :owned]])
    end

    it 'permits the same constant reached through its own nesting module' do
      expect(errors_for_block(owner.owned_through_nesting_module)).to be_empty
    end

    it 'does not own an absolute path, which names the top-level constant and not the file\'s' do
      expect(errors_for_block(owner.absolute_read)).to contain_exactly(path_message('NOTE'))
    end

    it 'refuses the nesting module bare and as a receiver' do
      expect(errors_for_block(owner.bare_nesting_module))
        .to contain_exactly(path_message('ValidConstantsRuleSpecOwner'))
      expect(errors_for_block(owner.nesting_module_as_receiver))
        .to contain_exactly(path_message('ValidConstantsRuleSpecOwner'))
    end

    it 'refuses a segment below an owned value' do
      expect(errors_for_block(owner.segment_below_owned_value)).to contain_exactly(path_message('NOTE::Foo'))
    end

    it 'refuses a segment another file assigned on the owned module, beside the one this file did' do
      expect(errors_for_block(owner.owned_through_nesting_module)).to be_empty

      expect(errors_for_block(owner.segment_another_file_assigned))
        .to contain_exactly(path_message('ValidConstantsRuleSpecOwner::ELSEWHERE'))
    end

    it 'judges an alias of a permitted module as that module, so its row applies' do
      permitted = owner.alias_with_permitted_call
      expect(errors_for_block(permitted)).to be_empty
      expect(uses_for_block(permitted).map(&:canonical)).to eq([[:IPaaS, :Job, :Humanize]])

      expect(errors_for_block(owner.alias_with_unlisted_call))
        .to contain_exactly(method_message('gql_cache_clear', 'Hum'))
    end

    it 'continues an alias into the listed path below it' do
      procedure = owner.alias_continued_into_listed_path

      expect(errors_for_block(procedure)).to be_empty
      expect(uses_for_block(procedure).map(&:canonical))
        .to eq([[:IPaaS, :Job, :GraphQL, :Schema, :INTROSPECTION_QUERY]])
    end

    it 'refuses an owned alias of a module a connector body may not name, naming the alias' do
      expect(errors_for_block(owner.alias_to_unpermitted_module)).to contain_exactly(path_message('MY'))
    end

    it 'refuses a root nothing defines' do
      expect(errors_for_block(owner.undefined_root)).to contain_exactly(path_message('Nope'))
    end

    it 'does not own a literal an enclosing module took from another file' do
      procedure = owner.enclosing_module_constant_from_another_file

      expect(IPaaS::Connector::Common::ProcRules.const_source_location(:BASIC_RULES).first)
        .not_to eq(procedure.source_location.first)
      expect(errors_for_block(procedure)).to contain_exactly(path_message('BASIC_RULES'))
    end

    it 'still judges a listed path by the list, with the nesting read even where the file shadows Module' do
      expect(owner::Module).to eq('shadowed')
      expect(errors_for_block(owner.listed_path)).to be_empty
      expect(uses_for_block(owner.listed_path).map(&:outcome)).to eq([:allowed])
    end

    it 'refuses the owned constant when the same text is a String proc, which owns nothing' do
      expect(errors_for('NOTE')).to contain_exactly(path_message('NOTE'))
    end

    it 'refuses the owned constant from a proc without a binding, which owns nothing' do
      expect(errors_for('NOTE', procedure: :upcase.to_proc)).to contain_exactly(path_message('NOTE'))
    end

    # A fault of ours reads as its own message rather than as the path refusal, which would send the
    # author looking for a policy that refused nothing.
    it 'refuses the occurrence when resolving it raises, naming the fault rather than the list' do
      allow(described_class).to receive(:permitted_modules).and_raise(RuntimeError, 'boom')
      procedure = owner.alias_with_permitted_call

      expect(errors_for_block(procedure)).to contain_exactly(error_message('Hum'))
      expect(errors_for_block(procedure)).not_to include(path_message('Hum'))
      expect(uses_for_block(procedure).map { |use| [use.reason, use.detail] }).to eq([[:error, 'RuntimeError: boom']])
    end
  end

  # The connector-sdk specs load connectors with a plain `require`.
  describe 'a block proc in a connector file loaded at the top level' do
    let(:fixture) { File.expand_path('../../../../fixtures/top_level_probe_connector.rb', __dir__) }

    def helper_block(name)
      TopLevelProbeConnector.connector(nil).helpers_definition.registered_helper(name).procedure
    end

    it 'is a connector the shape check admits, so the file is a loadable connector' do
      expect(IPaaS::Connector::Common::LoadRules::ConnectorShape.check(File.read(fixture), fixture)).to be_in_shape
    end

    it 'owns a constant reached through its own class, which its file defines on Object' do
      procedure = helper_block(:own_read)

      expect(errors_for_block(procedure)).to be_empty
      expect(uses_for_block(procedure).map { |use| [use.written, use.outcome] })
        .to eq([[[:TopLevelProbeConnector, :LIMIT], :owned]])
    end

    it 'refuses its own class bare, which is a module and not a value' do
      expect(errors_for_block(helper_block(:bare_self))).to contain_exactly(path_message('TopLevelProbeConnector'))
    end

    it 'does not own a top-level constant another file defined' do
      expect(Object.const_source_location(:PROC_FROM_ANOTHER_FILE_MARK)&.first).to end_with('proc_from_another_file.rb')
      expect(errors_for_block(helper_block(:top_level_from_another_file)))
        .to contain_exactly(path_message('PROC_FROM_ANOTHER_FILE_MARK'))
    end
  end

  describe 'a block proc written in one of this gem\'s own files' do
    let(:gem_file) { IPaaS::Connector::OutboundConnectionTemplate.instance_method(:connector).source_location.first }

    # The location is the point: a real file of this gem, so `source_location` reports it. Not
    # `__FILE__`, which would place the block in this spec.
    def gem_proc(body)
      eval("proc { #{body} }", binding, gem_file, 1) # rubocop:disable Security/Eval, Style/EvalWithLocation
    end

    it 'is exempt from the list, whatever it names, and recorded as such' do
      procedure = gem_proc('Nope; File.read("/x"); IPaaS::Connector::Authentication::Outbound.module(:x)')
      source = 'Nope; File.read("/x"); IPaaS::Connector::Authentication::Outbound.module(:x)'

      expect(errors_for(source, procedure: procedure)).to be_empty
      expect(uses_for(source, procedure: procedure).map(&:outcome)).to eq([:gem, :gem, :gem])
    end

    it 'is judged by the list once its file is outside the gem, so the exemption is by provenance' do
      procedure = eval('proc { Nope }', binding, '/somewhere/else/connector.rb', 1) # rubocop:disable Style/EvalWithLocation

      expect(errors_for('Nope', procedure: procedure)).to contain_exactly(path_message('Nope'))
    end

    it 'is judged by the list when its file is where String procs are evaluated, which is an author\'s code' do
      file = IPaaS::Connector::Common::ProcHelper::STRING_PROC_FILE
      procedure = eval('proc { Nope }', binding, file, 1) # rubocop:disable Style/EvalWithLocation

      expect(file).to start_with(IPaaS::Connector::Common::ProcHelper::GEM_LIB)
      expect(errors_for('Nope', procedure: procedure)).to contain_exactly(path_message('Nope'))
    end

    it 'is still refused where it reopens a class, which the gem has no business doing either' do
      procedure = gem_proc('class << Time; end')

      expect(errors_for('class << Time; end', procedure: procedure)).to contain_exactly(reopening_message('Time'))
    end
  end

  describe 'the use observer' do
    it 'receives one use per judged occurrence, listed or not, with every field' do
      uses = uses_for('Time.now; Psych.parse; JSON.load("{}")')

      expect(uses.map(&:to_h)).to eq([
        { written: [:Time], canonical: [:Time], method_name: :now, outcome: :allowed, reason: nil, detail: nil,
          expression: 'Time.now', line: 1, column: 0, },
        { written: [:Psych], canonical: [:Psych], method_name: :parse, outcome: :refused, reason: :path, detail: nil,
          expression: 'Psych.parse', line: 1, column: 10, },
        { written: [:JSON], canonical: [:JSON], method_name: :load, outcome: :refused, reason: :method, detail: nil,
          expression: 'JSON.load("{}")', line: 1, column: 23, },
      ])
    end

    # Four shapes, one message: the path and the method are all `class_access_line` has, so without the
    # expression a report cannot say which of these a refused use was.
    it 'carries the enclosing expression, which one bound message covers four shapes of' do
      uses = ['x.grep(Array)', '[Array, Hash]', 'y = Array', 'params.fetch(Array)'].flat_map { |s| uses_for(s) }

      expect(uses.map(&:reason).uniq).to eq([:bound])
      expect(uses.map(&:expression))
        .to eq(['x.grep(Array)', '[Array, Hash]', '[Array, Hash]', 'y = Array', 'params.fetch(Array)'])
    end

    it 'falls back to the constant where it is the whole expression, unlike one that has a parent' do
      expect(uses_for('Array').map(&:expression)).to eq(['Array'])
      expect(uses_for('Array.new').map(&:expression)).to eq(['Array.new'])
    end

    it 'gives both dispatches of a shorthand assignment the one expression they share' do
      uses = uses_for('IPaaS::Job::CompactHash.compact_hash ||= 1')

      expect(uses.map { |use| [use.method_name, use.expression] })
        .to eq([[:compact_hash, 'IPaaS::Job::CompactHash.compact_hash'],
                [:compact_hash=, 'IPaaS::Job::CompactHash.compact_hash'],])
    end

    it 'carries the expression of an allowed use too, which the census is built from' do
      expect(uses_for('x.kind_of?(Array)').map { |use| [use.outcome, use.expression] })
        .to eq([[:allowed, 'x.kind_of?(Array)']])
    end

    it 'records a read with no method' do
      expect(uses_for('JSON::ParserError').map(&:method_name)).to eq([nil])
    end

    it 'tolerates a nil on_invalid, so an observer can run the rule without a verdict sink' do
      errors, uses = judge('Psych.parse', on_invalid: nil)

      expect(errors).to be_empty
      expect(uses.map(&:outcome)).to eq([:refused])
    end
  end

  describe 'looking constants up on a module' do
    it 'asks Module itself, so a module lying about its constants is not believed' do
      liar = Module.new do
        def self.const_get(*) = File
        def self.const_source_location(*) = ['/elsewhere.rb', 1]
      end
      liar.const_set(:X, 1)

      expect(described_class.const_in(liar, :X)).to eq(1)
      expect(described_class.const_defined_at(liar, :X)).to eq(__FILE__)
    end
  end

  describe 'the list' do
    it 'is read by the rule, so an empty list refuses every path' do
      stub_const("#{described_class}::ALLOWED_CONSTANTS", IPaaS.make_shareable({}))

      expect(errors_for('Time.now')).to contain_exactly(path_message('Time'))
    end

    it 'is deeply frozen, with symbol-array keys and values' do
      list = described_class::ALLOWED_CONSTANTS

      expect(Ractor.shareable?(list)).to be(true)
      expect(list.keys).to all(satisfy { |key| key.is_a?(Array) && key.any? && key.all?(Symbol) })
      expect(list.values).to all(satisfy { |methods| methods.is_a?(Array) && methods.all?(Symbol) })
    end

    it 'cannot be widened or narrowed once built' do
      list = described_class::ALLOWED_CONSTANTS

      expect { list[[:File]] = [:read] }.to raise_error(FrozenError)
      expect { list[[:Time]] << :zone= }.to raise_error(FrozenError)
      expect { list.delete([:Time]) }.to raise_error(FrozenError)
    end

    it 'resolves every module a connector body may alias, by identity' do
      modules = described_class.permitted_modules

      expect(modules.size).to eq(IPaaS::Connector::Common::LoadRules::ConnectorShape::PERMITTED_PATHS.size)
      expect(modules[IPaaS::Job::Humanize]).to eq([:IPaaS, :Job, :Humanize])
      expect(modules.compare_by_identity?).to be(true)
    end

    it 'keeps the resolved modules deeply frozen, so an alias target cannot be swapped once built' do
      modules = described_class.permitted_modules

      expect(Ractor.shareable?(modules)).to be(true)
      expect { modules[File] = [:IPaaS, :Job, :Humanize] }.to raise_error(FrozenError)
      expect { modules[IPaaS::Job::Humanize] << :Nope }.to raise_error(FrozenError)
    end
  end
end
