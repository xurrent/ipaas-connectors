require 'spec_helper'

# Every synced connector fixture must load and validate the same way the runtime
# loader does: evaluating the entrypoint returns a connector, which must be `valid?`.
# `rake connector:sync` copies the SDK fixtures here before the suite runs. A bare
# require only registers a fixture and never validates it, so an invalid fixture
# (e.g. a name shorter than the allowed minimum) went undetected. See request #77484427.
describe 'fixtures' do
  fixtures_dir = File.expand_path('../../fixtures/connectors', __dir__)
  fixture_files = Dir[File.join(fixtures_dir, '*.rb')]

  def definition_classes(definitions)
    definitions.constants(false).map { |name| definitions.const_get(name, false) }
  end

  def load_connector(file)
    definitions = Module.new
    definitions.module_eval(File.read(file), file).tap do
      definition_classes(definitions).each { |klass| IPaaS::Connector::Definition.make_constants_shareable(klass) }
    end
  end

  # What the designer and a solution read of a sealed connector, down to every nested field, and the
  # connection-derived copies a solution builds from each template.
  def exercise(connector)
    templates = [connector.inbound_connection, connector.outbound_connection, *connector.triggers, *connector.actions]
    templates.compact.each do |template|
      template.attributes
      template.helpers
      placeholder = template.try(:action) || template.try(:trigger)
      [template, placeholder].compact.flat_map { |owner| schemas_of(owner) }.each { |schema| exercise_schema(schema) }
    end
  end

  def exercise_schema(schema)
    schema.example
    schema.fields.each { |field| exercise_field(field) }
  end

  def schemas_of(owner)
    [owner.try(:input_schema), *owner.try(:output_schemas), owner.try(:iteration_state_schema),
     owner.try(:config_schema),].compact
  end

  def exercise_field(field)
    field.attributes
    field.to_h_ref
    field.example
    field.deep_dup
    field.option_dependencies
    field.fields.each { |nested| exercise_field(nested) } unless field.id == :fields
  end

  it 'has synced connector fixtures to validate' do
    expect(fixture_files).not_to be_empty
  end

  it 'makes every constant the synced fixtures declare deeply immutable' do
    before_freeze = []
    after_freeze = []
    files_with_classes = 0

    fixture_files.each do |file|
      definitions = Module.new
      definitions.module_eval(File.read(file), file)
      classes = definition_classes(definitions)
      files_with_classes += 1 if classes.any?
      classes.each do |klass|
        names = klass.constants(false)
        before_freeze.concat(names.map { |name| Ractor.shareable?(klass.const_get(name)) })
        IPaaS::Connector::Definition.make_constants_shareable(klass)
        after_freeze.concat(names.map { |name| [file, name, Ractor.shareable?(klass.const_get(name))] })
      end
    end

    # Two ways the corpus could stop exercising the freeze: fixtures stopping short of a definition
    # class, and a corpus with nothing mutable left in it.
    expect(files_with_classes).to eq(fixture_files.size)
    expect(before_freeze.count(false)).to be >= 5
    expect(after_freeze.reject(&:last)).to be_empty
  end

  fixture_files.each do |file|
    it "connector #{File.basename(file, '.rb')} does not exceed the loadable source size" do
      expect(File.size(file)).to be <= IPaaS::Connector::Connector::MAX_SOURCE_FILE_BYTES
    end

    it "still validates the #{File.basename(file, '.rb')} fixture once its constants are frozen" do
      connector = load_connector(file)

      expect(connector).to be_a(IPaaS::Connector::Connector)
      expect(connector).to be_valid, -> { "#{connector.name}: #{connector.errors.full_messages.join(', ')}" }
    end

    # Sealed as a loaded connector is, without validating first, then used: any state the seal did not
    # store before freezing raises here.
    it "seals the #{File.basename(file, '.rb')} fixture and can still use it" do
      connector = load_connector(file)

      connector.seal!

      expect(IPaaS::Connector::Common::Sealing.unsealed(connector)).to be_empty
      expect(connector).to be_valid, -> { "#{connector.name}: #{connector.errors.full_messages.join(', ')}" }
      expect { exercise(connector) }.not_to raise_error
    end

    it "keeps the #{File.basename(file, '.rb')} fixture inside the declared shape" do
      outcome = IPaaS::Connector::Common::LoadRules::ConnectorShape.check(File.read(file), file)

      expect(outcome).to be_checked, -> { "#{file}: #{outcome.uncheckable}" }
      expect(outcome).to be_in_shape, -> { "#{file}: #{outcome.findings.join('; ')}" }
    end
  end

  # Contrast case for the sealed fixtures above: frozen with nothing stored first, every fixture breaks, so the
  # exercise can catch a seal that leaves a default to be stored on use.
  it 'cannot use a fixture frozen without storing its state first' do
    # Seals with the warm switched off, so nothing is stored before freezing.
    allow(IPaaS::Connector::Common::Sealing).to receive(:reached).and_wrap_original do |original, root, **|
      original.call(root, warm: false)
    end

    usable = fixture_files.select do |file|
      connector = load_connector(file).seal!
      exercise(connector)
      true
    rescue FrozenError
      false
    end

    expect(usable).to be_empty
  end

  it 'refuses a source outside the shape, so the assertions above can fail' do
    outcome = IPaaS::Connector::Common::LoadRules::ConnectorShape.check(<<~RUBY, 'control')
      class Control < IPaaS::Connector::Definition
        SNEAKED = File.write('/tmp/control', 'x')
        connector 'uuid' do
          name 'Control'
        end
      end
    RUBY

    expect(outcome.findings).to eq(["assigns 'SNEAKED' a value that is not a constant expression"])
  end
end
