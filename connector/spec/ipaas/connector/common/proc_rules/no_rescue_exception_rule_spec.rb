require 'spec_helper'

describe IPaaS::Connector::Common::ProcRules::NoRescueExceptionRule do
  def errors_for(source)
    errors = []
    rule = described_class.new(nil, on_invalid: ->(message) { errors << message })
    target = IPaaS::Connector::Common::ProcHelper::TARGET_RUBY_VERSION
    RuboCop::AST::ProcessedSource.new(source, target).ast.each_node { |node| rule.process(node) }
    errors
  end

  LITERAL_REQUIRED = "'rescue' requires literal error classes, e.g. 'rescue StandardError'.".freeze

  # Which literal classes may be rescued is ValidConstantsRule's question, so a literal class of any
  # name passes here; the through-validator pairs live in known_bad_sources_spec.
  describe 'literal rescue classes, whatever their name' do
    [
      'begin; x.to_s; rescue Exception; retry; end',
      'begin; x.to_s; rescue ::Exception; :ok; end',
      'begin; x.to_s; rescue Foo::Exception; :ok; end',
      'begin; x.to_s; rescue StandardError, Exception; :ok; end',
    ].each do |source|
      it "leaves #{source.inspect} to the constants rule" do
        expect(errors_for(source)).to be_empty
      end
    end
  end

  describe 'non-literal rescue classes (the validator cannot see what they catch)' do
    [
      'k = Exception; begin; x.to_s; rescue k; :ok; end',
      'begin; x.to_s; rescue *errors; :ok; end',
      'begin; x.to_s; rescue x.class; :ok; end',
    ].each do |source|
      it "reports #{source.inspect} as requiring literal error classes" do
        expect(errors_for(source)).to contain_exactly(LITERAL_REQUIRED)
      end
    end
  end

  describe 'ensure (its body runs unbounded once the deadline already fired)' do
    [
      'begin; x.to_s; ensure; x.clear; end',
      'begin; x.to_s; rescue StandardError; :ok; ensure; x.clear; end',
    ].each do |source|
      it "reports #{source.inspect} as not allowed" do
        expect(errors_for(source)).to contain_exactly("'ensure' is not allowed.")
      end
    end
  end

  describe 'permitted rescue forms' do
    # Bare rescue catches StandardError only, so a timeout interrupt still propagates;
    # retry after a StandardError rescue re-enters with the deadline timer still armed.
    [
      'begin; x.to_s; rescue; :ok; end',
      'begin; x.to_s; rescue => e; e.message; end',
      'x.to_s rescue nil',
      'begin; x.to_s; rescue StandardError; :ok; end',
      'begin; x.to_s; rescue StandardError; retry; end',
      'begin; x.to_s; rescue JSON::ParserError => e; e.message; end',
      'begin; x.to_s; rescue IPaaS::Error, URI::InvalidURIError; :ok; end',
    ].each do |source|
      it "permits #{source.inspect}" do
        expect(errors_for(source)).to be_empty
      end
    end
  end

  it 'reports each violation once, deduplicating per message' do
    source = 'k = Exception; begin; x.to_s; rescue k; begin; y.to_s; rescue k; :ok; end; end'
    expect(errors_for(source)).to contain_exactly(LITERAL_REQUIRED)
  end
end
