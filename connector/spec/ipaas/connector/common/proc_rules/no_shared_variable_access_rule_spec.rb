require 'spec_helper'

describe IPaaS::Connector::Common::ProcRules::NoSharedVariableAccessRule do
  def errors_for(source)
    errors = []
    rule = described_class.new(nil, on_invalid: ->(message) { errors << message })
    target = IPaaS::Connector::Common::ProcHelper::TARGET_RUBY_VERSION
    RuboCop::AST::ProcessedSource.new(source, target).ast.each_node { |node| rule.process(node) }
    errors
  end

  describe 'global variables' do
    {
      '$stdout' => ["Access to '$stdout' not allowed."],
      '$g' => ["Access to '$g' not allowed."],
      '"#{$g}"' => ["Access to '$g' not allowed."], # rubocop:disable Lint/InterpolationCheck
      'x = $LOAD_PATH' => ["Access to '$LOAD_PATH' not allowed."],
    }.each do |source, messages|
      it "reports #{source.inspect} as #{messages.inspect}" do
        expect(errors_for(source)).to contain_exactly(*messages)
      end
    end
  end

  # A write is at least as dangerous as the blocked read, and `gvasgn` carries the name in the same
  # child, so one handler serves both. `for` and `masgn` reach `gvasgn` by their own routes, which
  # is why they are listed rather than assumed; each is paired below with the same construct
  # writing something that is not a global.
  describe 'global variable writes' do
    {
      '$g = 1' => ["Access to '$g' not allowed."],
      '$g ||= 1' => ["Access to '$g' not allowed."],
      '$g &&= 1' => ["Access to '$g' not allowed."],
      '$g += 1' => ["Access to '$g' not allowed."],
      '$stdout = 1' => ["Access to '$stdout' not allowed."],
      '$LOAD_PATH ||= 1' => ["Access to '$LOAD_PATH' not allowed."],
      'for $g in [1] do end' => ["Access to '$g' not allowed."],
      '$g, $h = 1, 2' => ["Access to '$g' not allowed.", "Access to '$h' not allowed."],
      '$g; $g = 1' => ["Access to '$g' not allowed."],
    }.each do |source, messages|
      it "reports #{source.inspect} as #{messages.inspect}" do
        expect(errors_for(source)).to contain_exactly(*messages)
      end
    end
  end

  describe 'instance and class variables' do
    {
      '@secret' => ["Access to '@secret' not allowed."],
      '@x = 1' => ["Access to '@x' not allowed."],
      '@x ||= 1' => ["Access to '@x' not allowed."],
      '@@cv' => ["Access to '@@cv' not allowed."],
      '@@cv = 1' => ["Access to '@@cv' not allowed."],
      '"#{@x}"' => ["Access to '@x' not allowed."], # rubocop:disable Lint/InterpolationCheck
      '@x, @y = 1, 2' => ["Access to '@x' not allowed.", "Access to '@y' not allowed."],
    }.each do |source, message|
      it "reports #{source.inspect} as #{message.inspect}" do
        expect(errors_for(source)).to contain_exactly(*message)
      end
    end

    it 'reports each variable name once' do
      expect(errors_for('@x; @x; @x = 2; @@y; @@y; @@y = 2'))
        .to contain_exactly("Access to '@x' not allowed.", "Access to '@@y' not allowed.")
    end

    it 'reports an instance variable and a global variable in the same source' do
      expect(errors_for('@x; $stdout'))
        .to contain_exactly("Access to '@x' not allowed.", "Access to '$stdout' not allowed.")
    end
  end

  # Locals are the expression's own, and constants are another rule's question: this rule must stay
  # silent on both, or the constants rule's verdict would be duplicated or contradicted here.
  describe 'what stays permitted' do
    [
      'x = 1; x',
      'a = nil; a ||= 1',
      'a = {}; a[:g] = 1',
      'a = []; a[0] ||= 1',
      'for a in [1] do end',
      'a, b = 1, 2',
      'local = params[:a]',
      'params[:a].each { |item| item.to_s }',
      'ENV["PATH"]',
      'File.read("/x")',
      'Foo::BAR',
      'Time.now',
    ].each do |source|
      it "permits #{source.inspect}" do
        expect(errors_for(source)).to be_empty
      end
    end
  end
end
