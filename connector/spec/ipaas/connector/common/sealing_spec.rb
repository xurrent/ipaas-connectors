require 'spec_helper'

describe IPaaS::Connector::Common::Sealing do
  let(:definition) do
    proc do
      name 'Sealed'
      helper(:greeting) { 'hello' }
      inbound_connection { api_key_validator }
      outbound_connection do
        api_key_authenticator
        helper(:host_url) { "https://#{config[:host]}" }
        config_schema { field :host, 'Host', :string, default: 'example.com' }
      end
      trigger('sealing-trigger') do
        name 'Trigger one'
        parse { {} }
      end
      action('sealing-action') do
        name 'Action one'
        input_schema do
          field :choice, 'Choice', :string, enumeration: %w[a b]
          field :when, 'When', :recurrence
          field :code, 'Code', :string, pattern: '\A\d+\z'
          field :defs, 'Defs', [:schema_field], default: [{ id: 'a', label: 'A', type: 'string' }]
          field :held, 'Held', :schema_field, default: { id: 'b', label: 'B', type: 'string' }
          field :start, 'Start', :time, default: '2020-01-01 10:00:00 +0200'
          field(:pick, 'Pick', :string) { options { [] } }
          field(:person, 'Person', :nested) { field :name, 'Name', :string, enumeration: %w[ann bob] }
        end
        output_schema('result') { field :outcome, 'Outcome', :string, sample: 'done' }
        run { 1 }
      end
    end
  end

  # In a scope of its own, so an example can build several.
  def build_connector(uuid)
    skip_function_capture_validation
    IPaaS::Connector::Connector.uuid_scope({}) { IPaaS::Connector::Connector.new(uuid, &definition) }
  end

  # An independent reachability check for the walk under test: it follows every instance variable, taking none of
  # the walk's shortcuts, so a kind of object the walk stops reaching shows up. It deliberately shares two of the
  # walk's assumptions, the declared writable ivars and Modules as references, so it cannot judge those.
  # `===` because the proxy answers no method.
  # rubocop:disable Style/CaseEquality
  def crawl(root)
    seen = {}.compare_by_identity
    pending = [root]
    until pending.empty?
      object = pending.pop
      next if seen.key?(object) || Module === object || IPaaS::Connector::Common::HelpersProxy === object

      seen[object] = true
      pending.concat(held_by(object))
    end
    seen.keys
  end

  def held_by(object)
    case object
    when Hash then object.keys + object.values
    when Array, Set then object.to_a
    else
      writable = described_class::Member === object ? object.class.writable_ivars : []
      (object.instance_variables - writable).map { |ivar| object.instance_variable_get(ivar) }
    end
  end
  # rubocop:enable Style/CaseEquality

  # Every read the designer and a connection make of a template, none of which may write.
  def read_everything(connector)
    connector.attributes
    templates = [connector.inbound_connection, connector.outbound_connection, *connector.triggers, *connector.actions]
    templates.each do |template|
      template.attributes
      template.helpers
      schemas_of(template).flat_map(&:fields).each { |field| read_field(field) }
    end
  end

  def schemas_of(template)
    [template.try(:input_schema), *template.try(:output_schemas), template.try(:config_schema)].compact
  end

  def read_field(field)
    field.attributes
    field.fields
    field.example
  end

  describe '.seal!' do
    it 'leaves nothing the connector is made of writable' do
      connector = build_connector('sealing-all')

      described_class.seal!(connector)

      expect(described_class.unsealed(connector)).to be_empty
    end

    # Contrast case for the above: the same graph unsealed is reported object by object, so an empty report
    # is the seal's doing rather than a walk that reached nothing.
    it 'reports every object of a connector that was not sealed' do
      kinds = described_class.unsealed(build_connector('sealing-none')).map(&:class).uniq

      expect(kinds).to include(IPaaS::Connector::Connector, IPaaS::Connector::ActionTemplate,
                               IPaaS::Connector::TriggerTemplate, IPaaS::Connector::InboundConnectionTemplate,
                               IPaaS::Connector::OutboundConnectionTemplate, IPaaS::Connector::Schema,
                               IPaaS::Connector::Schema::Field, IPaaS::Connector::Common::Helpers,
                               IPaaS::Connector::Common::ProcHelper, String, Array, Hash, Proc, Regexp, Time)
    end

    it 'reaches every object an unsealed connector holds' do
      connector = build_connector('sealing-reach')

      expect(described_class.unsealed(connector))
        .to match_array(crawl(connector).reject(&:frozen?))
    end

    # Each kind is left out of the seal in turn, and read off the live graph, so one added to it is judged
    # without this spec changing.
    it 'names whatever a seal leaves writable' do
      kinds = described_class.unsealed(build_connector('sealing-kinds')).map(&:class).uniq

      misjudged = kinds.reject do |kind|
        connector = build_connector('sealing-without-kind')
        allow(described_class).to receive(:sealable?).and_wrap_original do |original, object|
          !kind.===(object) && original.call(object) # rubocop:disable Style/CaseEquality
        end
        described_class.seal!(connector)
        described_class.unsealed(connector).map(&:__id__).sort == crawl(connector).reject(&:frozen?).map(&:__id__).sort
      end

      expect(kinds.size).to be >= 10
      expect(misjudged).to be_empty
    end

    it 'keeps writable the state an object writes on every use' do
      connector = build_connector('sealing-writable')
      action = connector.action('sealing-action')

      described_class.seal!(connector)

      expect([connector.errors, action.errors, connector.proc_validations, action.helpers_definition.errors])
        .to all(satisfy { |state| !state.frozen? })
      expect([connector.valid?, action.valid?]).to eq([true, true])
    end

    it 'stores every default before freezing, so a sealed connector reads as before' do
      connector = build_connector('sealing-defaults')

      described_class.seal!(connector)

      expect { read_everything(connector) }.not_to raise_error
    end

    # Contrast case for the above: frozen without being warmed, the same reads write, so the spec proves the warm.
    it 'would refuse those reads had the defaults not been stored' do
      connector = build_connector('sealing-cold')
      # Seals with the warm switched off, so nothing is stored before freezing.
      allow(described_class).to receive(:reached).and_wrap_original do |original, root, **|
        original.call(root, warm: false)
      end

      described_class.seal!(connector)

      expect { read_everything(connector) }.to raise_error(FrozenError)
    end

    # A loader changes a connector after validating it, as when it rewrites a bundled avatar, so a seal that
    # validated again would judge what the loader made rather than what the connector declared.
    it 'leaves the verdict of the last validation as it was' do
      connector = build_connector('sealing-unjudged')
      connector.avatar = 'not an avatar'

      described_class.seal!(connector)

      expect(connector.errors).to be_empty
      expect(connector.valid?).to be(false)
    end

    it 'leaves alone what the connector only points at, and reports what it should not hold' do
      connector = build_connector('sealing-references')
      other = IPaaS::Connector::Connector.uuid_scope({}) { IPaaS::Connector::Connector.new('sealing-other') { name 'Other' } }
      stray = IPaaS::Connector::Action.new
      connector.instance_variable_set(:@other, other)
      connector.instance_variable_set(:@stray, stray)

      described_class.seal!(connector)

      type_def = connector.action('sealing-action').input_schema.field(:choice).type_def
      expect([other, stray, type_def]).to all(satisfy { |reference| !reference.frozen? })
      expect(described_class.unsealed(connector)).to contain_exactly(stray)
    end

    it 'does not walk a sealed connector again' do
      connector = build_connector('sealing-twice')
      described_class.seal!(connector)
      allow(described_class).to receive(:reached).and_call_original

      expect(described_class.seal!(connector)).to be(connector)
      expect(described_class).not_to have_received(:reached)
    end
  end

  describe '.refusal' do
    let(:connector) { build_connector('sealing-refusal').tap { |built| described_class.seal!(built) } }

    def frozen_error
      yield
    rescue FrozenError => e
      e
    end

    it "names the class without the receiver's inspect" do
      error = frozen_error { connector.actions << 1 }

      refusal = described_class.refusal(error)

      expect(error.message).to include('#<IPaaS::Connector::ActionTemplate')
      expect(refusal.message).to eq("can't modify frozen Array")
      expect([refusal.receiver, refusal.backtrace]).to eq([error.receiver, error.backtrace])
    end

    it 'says why when the receiver is part of a connector' do
      refusal = described_class.refusal(frozen_error { connector.name = 'Renamed' })

      expect(refusal.message)
        .to eq("can't modify frozen IPaaS::Connector::Connector; it is shared by every solution on the connector")
    end

    it 'keeps an error raised with no receiver, whose message names no object' do
      error = FrozenError.new('sealed')

      expect(described_class.refusal(error)).to be(error)
    end
  end

  describe '.seal_globals!' do
    let(:extensions) { described_class.instance_variable_get(:@global_modules) }

    it 'has sealed every type schema and extension module while the gem loaded' do
      schemas = IPaaS::Connector::Types.all.values.select { |type| type.respond_to?(:schema) }.map(&:schema)

      expect(described_class.unsealed_globals).to be_empty
      expect(schemas.size).to be >= 4
      expect(schemas + extensions).to all(be_frozen)
    end

    # An empty report from a check that never ran would read as a pass.
    it 'refuses to judge the globals had they never been sealed' do
      sealed = described_class.instance_variable_get(:@global_schemas)
      described_class.remove_instance_variable(:@global_schemas)

      expect { described_class.unsealed_globals }.to raise_error(IPaaS::Error, /never sealed/)
    ensure
      described_class.instance_variable_set(:@global_schemas, sealed)
    end

    it 'finds the extension modules by what they include, not by registration' do
      registered = [IPaaS::Connector::Authentication::Inbound, IPaaS::Connector::Authentication::Outbound]
                   .flat_map { |kind| kind.keys.map { |key| kind.module(key) } }

      expect(extensions).to include(*registered, IPaaS::Connector::Authentication::Outbound::ProxyServer)
    end

    it 'refuses a helper or a schema planted on an authentication module' do
      basic_auth = IPaaS::Connector::Authentication::Outbound::BasicAuth

      expect { basic_auth.helper(:planted) { 'planted' } }.to raise_error(FrozenError, /sealed/)
      expect { basic_auth.schema { field :planted, 'Planted', :string } }.to raise_error(FrozenError)
    end

    # Why the helper registry is sealed as well: freezing the module leaves the registry it holds writable.
    it 'needs more than freezing the module to refuse a helper' do
      extension = Module.new do
        include IPaaS::Connector::Schema::Extension
        include IPaaS::Connector::Authentication::Outbound::Extension
      end
      extension.helpers_definition
      extension.freeze

      expect { extension.helper(:planted) { 'planted' } }.not_to raise_error
    end

    it 'resolves a recurrence on a copy of its sealed schema' do
      resolved = IPaaS::Connector::Types::RecurrenceType.resolve({ frequency: 'weekly', interval: 1 })

      expect(resolved[:frequency]).to eq('weekly')
      expect(IPaaS::Connector::Types::RecurrenceType.schema).to be_frozen
    end

    # Contrast case for the above: a sealed schema not marked shared cannot be resolved at all, since resolving
    # writes to the schema itself.
    it 'refuses to resolve a sealed schema that is not marked shared' do
      schema = IPaaS::Connector::Schema.new('sealing-unshared') { field :plain, 'Plain', :string }
      described_class.seal!(schema)

      expect { schema.resolve(Object.new, []) }.to raise_error(FrozenError)
    end
  end
end
