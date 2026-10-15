require 'spec_helper'
require 'json'
require 'open3'
require 'rbconfig'

RSpec.describe 'Loading ipaas-connector' do
  it 'parses with the RuboCop parser without loading any file of the RuboCop linter gem' do
    probe = <<~RUBY
      require 'ipaas/connector'
      parsed = RuboCop::AST::ProcessedSource.new('1', IPaaS::Connector::Common::ProcHelper::TARGET_RUBY_VERSION)
      print JSON.generate(parses: parsed.valid_syntax?, linter_files: $LOADED_FEATURES.grep(%r{/gems/rubocop-[0-9]}))
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', File.expand_path('../../../lib', __dir__), '-e', probe)
    raise "probe failed: #{stderr}" unless status.success?

    expect(JSON.parse(stdout)).to eq('parses' => true, 'linter_files' => [])
  end
end
