$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'ipaas/connector/sdk/version'

Gem::Specification.new do |s|
  s.required_ruby_version = '>= 3.4'
  s.name = 'ipaas-connector-sdk'
  s.version = IPaaS::Connector::SDK::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ['Xurrent, Inc.']
  s.email = 'support@xurrent.com'
  s.license = 'MIT'
  s.homepage = 'https://github.com/xurrent'
  s.summary = 'iPaaS Connector Definition'
  s.description = 'Module for defining iPaaS connectors'
  s.files = Dir['lib/**/*'] + Dir['matchers/*'] + %w[
    MIT-LICENSE
    README.rdoc
    Gemfile
    ipaas-connector-sdk.gemspec
  ]

  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.require_paths = ['lib']
  s.rdoc_options = ['--charset=UTF-8']

  s.add_dependency 'activesupport', '>= 8.1', '< 8.2'
  s.add_dependency 'tzinfo-data', '>= 1.2025.0'

  s.metadata['rubygems_mfa_required'] = 'true'
end
