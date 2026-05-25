$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'ipaas/connector/version'

Gem::Specification.new do |s|
  s.required_ruby_version = '>= 3.4'
  s.name = 'ipaas-connector'
  s.version = IPaaS::Connector::VERSION
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
    ipaas-connector.gemspec
  ]

  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.require_paths = ['lib']
  s.rdoc_options = ['--charset=UTF-8']

  s.add_dependency 'activemodel', '>= 8.1', '< 8.2'
  s.add_dependency 'activesupport', '>= 8.1', '< 8.2'
  s.add_dependency 'faraday', '>= 2.10.0'
  s.add_dependency 'faraday-multipart', '>= 1.1.1'
  s.add_dependency 'jwt', '>= 2.9.3'
  s.add_dependency 'method_source', '>= 1.1.0'
  s.add_dependency 'nokogiri', '>= 1.16.0'
  s.add_dependency 'rack', '>= 3.0.0'
  s.add_dependency 'rubocop-ast', '>= 0.1.0'
  s.add_dependency 'tzinfo-data', '>= 1.2025.0'

  s.metadata['rubygems_mfa_required'] = 'true'
end
