require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)

require 'simplecov'
require 'timecop'

ENV['IPAAS_ENV'] = 'test'

require 'support'
Dir[File.expand_path(File.join(File.dirname(__FILE__), 'support', '**', '*.rb'))].each { |f| require f }

RSpec.configure do |config|
  config.after(:suite) do
    TriggerServer.stop if TriggerServer.running?
  end

  config.before(:each) do
    IPaaS::Connector::Common::UuidMixin.purge
    IPaaS::Encryption::SystemKeyProvider.memcache.clear
    IPaaS::Encryption::IntermediateKeyProvider.memcache.clear
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec

    # Keep as many of these lines as are necessary:
    # with.library :active_record
    with.library :active_model
  end
end
