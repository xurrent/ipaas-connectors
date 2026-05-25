require 'spec_helper'

describe IPaaS::Connector::Authentication::Outbound do
  context 'registry' do
    it 'should contains all registered keys' do
      expect(subject.keys).to eq([:api_key, :basic_auth, :bearer, :oauth2])
    end

    it 'should provide the module given a key' do
      expect(subject.module(:api_key)).to eq(IPaaS::Connector::Authentication::Outbound::ApiKey)
    end
  end

  context 'validation' do
    it 'should check whether authenticate proc is valid' do
      # :nocov:
      module BadOutbound
        include IPaaS::Connector::Schema::Extension
        include IPaaS::Connector::Authentication::Outbound::Extension

        include IPaaS::Connector::Schema::Extension
        include IPaaS::Connector::Authentication::Outbound::Extension

        schema do
          field :foo, 'Foo', :string
        end

        authenticate do |request|
          if config[:foo].start_with?('ES')
            OpenSSL::PKey::EC.new(pem)
          else
            OpenSSL::PKey::RSA.new(pem)
          end
          request.body.rewind
        end
      end
      # :nocov:

      expect do
        IPaaS::Connector::Authentication::Outbound.register(:bad_outbound, BadOutbound)
      rescue ArgumentError => e
        m = e.message
        expect(m).to start_with('BadOutbound is not valid. Errors: [')
        expect(m).to include("Method 'new' not allowed.")
        expect(m).to include("Method 'rewind' not allowed.")
        raise
      end.to raise_error(ArgumentError)
    end

    it 'should check whether helper procs are valid' do
      # :nocov:
      module BadOutbound
        include IPaaS::Connector::Schema::Extension
        include IPaaS::Connector::Authentication::Outbound::Extension

        schema do
          field :foo, 'Foo', :string
        end

        helper :my_helper do |foo|
          if foo.start_with?('ES')
            OpenSSL::PKey::EC.new(foo)
          else
            OpenSSL::PKey::RSA.new(foo)
          end
          helpers.my_other_helper(foo)
        end

        helper :my_other_helper do |_foo|
          request.body.rewind
        end

        authenticate do |_request|
          not_allowed_method
          helpers.my_helper('foo')
        end
      end
      # :nocov:

      expect do
        IPaaS::Connector::Authentication::Outbound.register(:bad_outbound, BadOutbound)
      rescue ArgumentError => e
        m = e.message
        expect(m).to start_with('BadOutbound is not valid. Errors: [')
        expect(m).to include(%("Method 'not_allowed_method' not allowed.", [))
        expect(m).to include(%(["my_helper", ["Method 'new' not allowed."]]))
        expect(m).to include(%(["my_other_helper", ["Method 'rewind' not allowed."]]))
        raise
      end.to raise_error(ArgumentError)
    end
  end
end
