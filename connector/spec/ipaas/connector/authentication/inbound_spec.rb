require 'spec_helper'

describe IPaaS::Connector::Authentication::Inbound do
  context 'registry' do
    it 'should contains all registered keys' do
      expect(subject.keys).to eq([:api_key, :basic_auth, :oauth2_client_credentials])
    end

    it 'should provide the module given a key' do
      expect(subject.module(:api_key)).to eq(IPaaS::Connector::Authentication::Inbound::ApiKey)
    end
  end

  it 'ships every registered module from the gem, so its blocks are judged process-wide' do
    gem_lib = IPaaS::Connector::Common::ProcHelper::GEM_LIB
    helpers = subject.keys.flat_map do |key|
      module_klass = subject.module(key)
      [module_klass.validate_request_helper(nil), module_klass.setup_info_helper(nil)]
    end.compact

    expect(helpers).not_to be_empty
    expect(helpers.map { |helper| helper.procedure.source_location.first }).to all(start_with(gem_lib))
  end

  it 'refuses to register a module whose blocks live outside the gem, since nothing owns them' do
    allow(IPaaS.default_logger).to receive(:warn)
    outsider = Module.new do
      include IPaaS::Connector::Schema::Extension
      include IPaaS::Connector::Authentication::Inbound::Extension

      validate { |_request| true }
    end

    expect { subject.register(:outsider, outsider) }
      .to raise_error(IPaaS::Connector::Common::ProcHelper::MissingValidationStore)
  end

  context 'validation' do
    before(:each) { treat_spec_blocks_as_gem_code }

    it 'should check whether validation proc is valid' do
      # :nocov:
      module BadInbound
        include IPaaS::Connector::Schema::Extension
        include IPaaS::Connector::Authentication::Inbound::Extension

        schema do
          field :foo, 'Foo', :string
        end

        validate do |request|
          if config[:foo].start_with?('ES')
            OpenSSL::PKey::EC.new('foo')
          else
            OpenSSL::PKey::RSA.new('foo')
          end
          request.body.rewind
        end
      end
      # :nocov:

      expect do
        IPaaS::Connector::Authentication::Inbound.register(:bad_inbound, BadInbound)
      rescue ArgumentError => e
        m = e.message
        expect(m).to start_with('BadInbound is not valid. Errors: [')
        expect(m).to include("Method 'new' not allowed.")
        expect(m).to include("Method 'rewind' not allowed.")
        raise
      end.to raise_error(ArgumentError)
    end

    it 'should check whether the setup_info proc is valid' do
      # :nocov:
      module BadSetupInfo
        include IPaaS::Connector::Schema::Extension
        include IPaaS::Connector::Authentication::Inbound::Extension

        schema do
          field :foo, 'Foo', :string
        end

        validate do |_request|
          # no-op
        end

        setup_info do
          not_allowed_method
        end
      end
      # :nocov:

      expect do
        IPaaS::Connector::Authentication::Inbound.register(:bad_setup_info, BadSetupInfo)
      rescue ArgumentError => e
        expect(e.message).to include("Method 'not_allowed_method' not allowed.")
        raise
      end.to raise_error(ArgumentError)
    end

    it 'refuses to register a module without a validate block (would silently skip auth at request time)' do
      # :nocov:
      module SetupInfoOnlyInbound
        include IPaaS::Connector::Schema::Extension
        include IPaaS::Connector::Authentication::Inbound::Extension

        schema do
          field :foo, 'Foo', :string
        end

        setup_info do
          { 'Section' => { 'Label' => { value: 'ok' } } }
        end
      end
      # :nocov:

      expect do
        IPaaS::Connector::Authentication::Inbound.register(:setup_info_only_inbound, SetupInfoOnlyInbound)
      end.to raise_error(ArgumentError, /a validate block is required/)
      expect(IPaaS::Connector::Authentication::Inbound.module(:setup_info_only_inbound)).to be_nil
    end

    it 'aggregates errors from the validate, setup_info, and helper procs together' do
      # :nocov:
      module AllInvalidInbound
        include IPaaS::Connector::Schema::Extension
        include IPaaS::Connector::Authentication::Inbound::Extension

        schema do
          field :foo, 'Foo', :string
        end

        helper :my_helper do |_foo|
          bad_helper_method
        end

        validate do |_request|
          bad_validate_method
        end

        setup_info do
          bad_setup_info_method
        end
      end
      # :nocov:

      expect do
        IPaaS::Connector::Authentication::Inbound.register(:all_invalid_inbound, AllInvalidInbound)
      rescue ArgumentError => e
        m = e.message
        expect(m).to include("Method 'bad_validate_method' not allowed.")
        expect(m).to include("Method 'bad_setup_info_method' not allowed.")
        expect(m).to include(%(["my_helper", ["Method 'bad_helper_method' not allowed."]]))
        raise
      end.to raise_error(ArgumentError)
    end

    it 'should check whether helper procs are valid' do
      # :nocov:
      module BadInbound
        include IPaaS::Connector::Schema::Extension
        include IPaaS::Connector::Authentication::Inbound::Extension

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

        validate do |_request|
          not_allowed_method
          helpers.my_helper('foo')
        end
      end
      # :nocov:

      expect do
        IPaaS::Connector::Authentication::Inbound.register(:bad_inbound, BadInbound)
      rescue ArgumentError => e
        m = e.message
        expect(m).to start_with('BadInbound is not valid. Errors: [')
        expect(m).to include(%("Method 'not_allowed_method' not allowed.", [))
        expect(m).to include(%(["my_helper", ["Method 'new' not allowed."]]))
        expect(m).to include(%(["my_other_helper", ["Method 'rewind' not allowed."]]))
        raise
      end.to raise_error(ArgumentError)
    end
  end
end
