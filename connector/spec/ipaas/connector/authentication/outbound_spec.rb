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

  it 'refuses to register a module whose blocks live outside the gem, since nothing owns them' do
    allow(IPaaS.default_logger).to receive(:warn)
    outsider = Module.new do
      include IPaaS::Connector::Schema::Extension
      include IPaaS::Connector::Authentication::Outbound::Extension

      authenticate { |_request| true }
    end

    expect { subject.register(:outsider, outsider) }
      .to raise_error(IPaaS::Connector::Common::ProcHelper::MissingValidationStore)
  end

  it 'ships every registered module from the gem, so its blocks are judged process-wide' do
    gem_lib = IPaaS::Connector::Common::ProcHelper::GEM_LIB
    helpers = subject.keys.flat_map do |key|
      module_klass = subject.module(key)
      [module_klass.authenticate_request_helper(nil)]
    end.compact

    expect(helpers).not_to be_empty
    expect(helpers.map { |helper| helper.procedure.source_location.first }).to all(start_with(gem_lib))
  end

  context 'validation' do
    before(:each) { treat_spec_blocks_as_gem_code }

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
