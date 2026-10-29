require 'spec_helper'

describe IPaaS::Connector::Common::ProcRules::NoLocationKeywordRule do
  def errors_for(source)
    errors = []
    rule = described_class.new(nil, on_invalid: ->(message) { errors << message })
    target = IPaaS::Connector::Common::ProcHelper::TARGET_RUBY_VERSION
    RuboCop::AST::ProcessedSource.new(source, target).ast.each_node { |node| rule.process(node) }
    errors
  end

  it 'refuses a location keyword in a block' do
    source = IPaaS::Connector::Common::ProcHelper.proc_source(-> { "#{__FILE__}:#{__LINE__}" })

    expect(errors_for(source)).to eq(["Keyword '__FILE__' not allowed.", "Keyword '__LINE__' not allowed."])
  end

  it 'accepts the same block built from its parameters' do
    source = IPaaS::Connector::Common::ProcHelper.proc_source(-> { "#{params[:file]}:#{params[:line]}" })

    expect(errors_for(source)).to be_empty
  end

  it 'accepts the keywords spelled inside a string literal' do
    expect(errors_for('"__FILE__:__LINE__"')).to be_empty
    expect(errors_for('%w[__FILE__ __LINE__]')).to be_empty
  end

  it 'reports each distinct keyword once' do
    expect(errors_for('[[__FILE__], __LINE__, "#{__FILE__}"]')) # rubocop:disable Lint/InterpolationCheck
      .to eq(["Keyword '__FILE__' not allowed.", "Keyword '__LINE__' not allowed."])
  end
end
