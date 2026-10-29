require 'spec_helper'

describe IPaaS::Connector::Common::LocationKeyword do
  def ast_of(source)
    RuboCop::AST::ProcessedSource.new(source, IPaaS::Connector::Common::ProcHelper::TARGET_RUBY_VERSION).ast
  end

  def nodes_of(source)
    ast_of(source).each_node(:str, :int).to_a
  end

  def keywords_in(source)
    nodes_of(source).filter_map { |node| described_class.of(node) }
  end

  # rubocop:disable Lint/InterpolationCheck
  {
    '__FILE__' => ['__FILE__'],
    '__LINE__' => ['__LINE__'],
    '"x#{__FILE__}"' => ['__FILE__'],
    '[__LINE__, 1]' => ['__LINE__'],
  }.each do |source, keywords|
    it "recognises #{keywords.inspect} in #{source.inspect}" do
      expect(keywords_in(source)).to eq(keywords)
      expect(nodes_of(source).count { |node| described_class.keyword?(node) }).to eq(keywords.size)
    end
  end

  [
    "'__FILE__'",
    '"__FILE__"',
    '%q(__FILE__)',
    '"#{a}__FILE__"',
    '"__LINE__#{a}"',
    '%w[__FILE__ __LINE__]',
    '/__FILE__#{a}/',
    '`__FILE__`',
    "<<~X\n  \#{a}\n__FILE__\nX",
    '7',
  ].each do |source|
    it "does not recognise a literal spelled like a keyword in #{source.inspect}" do
      expect(nodes_of(source)).not_to be_empty
      expect(keywords_in(source)).to be_empty
      expect(nodes_of(source).map { |node| described_class.keyword?(node) }).to all(be(false))
    end
  end
  # rubocop:enable Lint/InterpolationCheck

  it 'does not recognise a symbol spelled like a keyword' do
    sym = ast_of(':__FILE__')

    expect(described_class.of(sym)).to be_nil
    expect(described_class.keyword?(sym)).to be(false)
  end
end
