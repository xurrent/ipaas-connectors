dir = File.dirname(__FILE__)
$LOAD_PATH.unshift "#{dir}/../lib"
$LOAD_PATH.unshift dir

warn("Ruby version #{RUBY_VERSION}")

require 'rspec'
require 'active_support/all'
require 'shoulda-matchers'
require 'action_dispatch'

require 'ipaas/connector'
