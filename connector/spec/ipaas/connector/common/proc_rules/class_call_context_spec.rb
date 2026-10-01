require 'spec_helper'

describe IPaaS::Connector::Common::ProcRules::ClassCallContext do
  def class_nodes(source)
    ast = RuboCop::AST::ProcessedSource.new(source, IPaaS::Connector::Common::ProcHelper::TARGET_RUBY_VERSION).ast
    ast.each_node(:send, :csend, :block_pass).select do |node|
      node.block_pass_type? ? node.children.first&.value == :class : node.method?(:class)
    end
  end

  def class_node(source)
    nodes = class_nodes(source)
    raise "expected one .class call in #{source}, found #{nodes.size}" unless nodes.one?

    nodes.first
  end

  describe '.of' do
    {
      "\"a \#{params.class}\"" => [:interpolated, nil],
      ":\"a \#{params.class}\"" => [:interpolated, nil],
      'params.class.name' => [:stringified, :name],
      'params.class.to_s' => [:stringified, :to_s],
      'params.class.inspect' => [:stringified, :inspect],
      'params.class == Hash' => [:compared, :==],
      'params.class != Hash' => [:compared, :!=],
      'params.class === 1' => [:compared, :===],
      'case params.class when Hash then 1 end' => [:compared, nil],
      'params.class.new' => [:receiver, :new],
      'params.class::FOO' => [:scope, nil],
      'params.is_a?(params.class)' => [:argument, :is_a?],
      'k = params.class' => [:bound, nil],
      '[params.class]' => [:bound, nil],
      'params.class' => [:returned, nil],
      '[1].map(&:class)' => [:block_pass, nil],
      'params.class; 1' => [:other, :begin],
      'params.class && 1' => [:other, :and],
      'params && params.class' => [:returned, nil],
      'case 1 when params.class then 2 end' => [:compared, nil],
      'begin; 1; params.class; end.to_s' => [:stringified, :to_s],
      'params ? params.class : 1' => [:returned, nil],
      'case 1 when 1 then params.class end' => [:returned, nil],
      '[params].reduce(nil) { |acc, v| acc || v.class }.to_s' => [:other, :block],
      '[params].inject(nil) { |acc, v| acc || v.class }.to_s' => [:other, :block],
      '[params].reduce(nil) { _1 || _2.class }.to_s' => [:other, :numblock],
    }.each do |source, (context, method_name)|
      it "places #{source} as #{[context, method_name].compact.join(' ')}" do
        expect(described_class.of(class_node(source)).first(2)).to eq([context, method_name])
      end
    end

    {
      "solution&.name&.presence || 'x'" => [:stringified, :name],
      'solution.uuid' => [:receiver, :uuid],
      "solution.uuid ||= 'x'" => [:receiver, :uuid],
      "solution.uuid = 'x'" => [:receiver, :uuid=],
      's = solution' => [:bound, nil],
      'log(solution)' => [:argument, :log],
      'solution' => [:returned, nil],
    }.each do |source, (context, method_name)|
      it "places the solution send in #{source} as #{[context, method_name].compact.join(' ')}" do
        node = RuboCop::AST::ProcessedSource.new(source, IPaaS::Connector::Common::ProcHelper::TARGET_RUBY_VERSION)
                                            .ast.each_node(:send).find { |n| n.method?(:solution) }
        expect(described_class.of(node).first(2)).to eq([context, method_name])
      end
    end

    it 'holds the node the value lands in' do
      expect(described_class.of(class_node('params.class.new'))[2].source).to eq('params.class.new')
      expect(described_class.of(class_node('k = params.class'))[2].source).to eq('k = params.class')
    end

    {
      "\"\#{[params].map { |v| v.class }}\"" => 'block',
      "\"\#{[params].map { _1.class }}\"" => 'numbered-parameter block',
      "\"\#{[params].map { it.class }}\"" => 'it block',
    }.each do |source, kind|
      it "notes a climb through a #{kind} body" do
        expect(described_class.of(class_node(source))).to match([:interpolated, nil, anything, true])
      end
    end

    it 'notes no block when the text is built inside the block' do
      expect(described_class.of(class_node("[params].map { |v| \"\#{v.class}\" }")))
        .to match([:interpolated, nil, anything, false])
    end

    it 'notes no block for a block pass or a returned value' do
      expect(described_class.of(class_node('[1].map(&:class)')).last).to be(false)
      expect(described_class.of(class_node('params.class')).last).to be(false)
    end
  end

  describe '.permitted?' do
    it 'permits interpolation in a heredoc' do
      expect(described_class.permitted?(class_node("<<~TEXT\n  a \#{params.class}\nTEXT"))).to be(true)
    end

    [
      "\"a \#{params.class}\"",
      ":\"a \#{params.class}\"",
      "\"a \#{params ? params.class : 1}\"",
      "\"a \#{params && params.class}\"",
      "\"a \#{case 1 when 1 then params.class end}\"",
      "\"a \#{params || params.class}\"",
      'params.class.name',
      'params.class.to_s',
      'params&.class.to_s',
      'params.class&.to_s',
      '->(v) { "#{v.class}" }', # rubocop:disable Lint/InterpolationCheck
      '[params].map { |v| v.class.name }',
      'log(params.class)',
      'log(params.class) { 1 }',
    ].each do |source|
      it "permits #{source}" do
        expect(described_class.permitted?(class_node(source))).to be(true)
      end
    end

    [
      'params.class == Hash',
      'params.class != Hash',
      'Hash == params.class',
      'case params.class when Hash then 1 end',
      'case 1 when params.class then 2 end',
      'params.class.new',
      'params.class.present?',
      '(params.class).new',
      'params.class::FOO',
      'params.is_a?(params.class)',
      'raise params.class',
      'k = params.class',
      '[params.class]',
      '{ a: params.class }',
      'params.class',
      'self.class',
      '[1].map(&:class)',
      'params.class; 1',
      'params.class ? 1 : 2',
      'params.class && 1',
      "\"a \#{params.class rescue 1}\"",
      "\"a \#{params.class && 1}\"",
      "\"a \#{case 1 when params.class then 2 end}\"",
      "/\#{params.class}/",
      '->(v) { v.class }',
      "\"a \#{-> { params.class }.call}\"",
      "\"a \#{[params].map { |v| v.class }}\"",
      "\"a \#{[params].map { _1.class }}\"",
      "\"a \#{[params].map { it.class }}\"",
      '[params].map { |v| v.class }.to_s',
      "\"a \#{helpers.fmt { params.class }}\"",
      'log(params.fetch(:k) { params.class })',
      '[params].reduce(nil) { |acc, v| acc || v.class }.to_s',
      'log(params.class, {})',
      'self.log(params.class)',
      'helpers.log(params.class)',
      'params.log(params.class)',
      'log(*[params.class])',
      'log(params.class, &:to_s)',
      'log(k: params.class)',
      'puts(params.class)',
    ].each do |source|
      it "refuses #{source}" do
        expect(described_class.permitted?(class_node(source))).to be(false)
      end
    end
  end
end
