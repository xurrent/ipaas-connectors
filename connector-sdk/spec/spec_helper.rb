require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)

require 'timecop'

require 'support'
Dir[File.expand_path(File.join(File.dirname(__FILE__), 'support', '**', '*.rb'))].each { |f| require f }

ENV['IPAAS_ENV'] = 'test'

require 'simplecov'

RSpec.configure do |config|
  config.after(:suite) do
    TriggerServer.stop if TriggerServer.running?
  end

  config.before(:each) do
    IPaaS::Connector::Common::UuidMixin.purge(except: [
      IPaaS::Connector::Connector,
      IPaaS::Connector::TriggerTemplate,
      IPaaS::Connector::ActionTemplate,
    ])
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
