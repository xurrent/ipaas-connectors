require 'spec_helper'

describe 'text attributes of YAML-based models' do
  non_text_values = {
    'a map' => [{ 'first' => 'Mapped' }, '{first: "Mapped"}'],
    'a list' => [%w[Alpha Beta], '["Alpha", "Beta"]'],
    'an integer' => [2024, '2024'],
    'a boolean' => [true, 'true'],
  }

  {
    IPaaS::Connector::Runbook => [:name, :description],
    IPaaS::Connector::Connection => [:name, :description],
    IPaaS::Connector::EnvironmentVariable => [:name, :description],
    IPaaS::TestCase::TestCase => [:name, :description, :runbook_uuid],
  }.each do |model, attributes|
    context model.name do
      def loaded(model, attribute, value)
        model.parse({ 'uuid' => 'f0000000-0000-4000-8000-000000000001', attribute.to_s => value }.to_yaml,
                    resolve: false)
      end

      attributes.each do |attribute|
        non_text_values.each do |label, (value, text)|
          it "reads #{label} #{attribute} as its text form" do
            expect(loaded(model, attribute, value).public_send(attribute)).to eq(text)
          end
        end

        it "keeps a text #{attribute} unchanged" do
          expect(loaded(model, attribute, 'Plain text').public_send(attribute)).to eq('Plain text')
        end

        it "keeps a null #{attribute} nil" do
          expect(loaded(model, attribute, nil).public_send(attribute)).to be_nil
        end
      end
    end
  end

  context 'the parts of a runbook file' do
    variable_text_attributes = [:label, :hint, :notice]

    def loaded(**parts)
      file = { 'uuid' => 'f0000000-0000-4000-8000-000000000001', 'name' => 'Runbook' }
      IPaaS::Connector::Runbook.parse(file.merge(parts.deep_stringify_keys).to_yaml, resolve: false)
    end

    non_text_values.each do |label, (value, text)|
      it "reads #{label} trigger description as its text form" do
        expect(loaded(trigger: { description: value }).trigger.description).to eq(text)
      end

      it "reads #{label} action description as its text form" do
        expect(loaded(actions: [{ description: value }]).actions.first.description).to eq(text)
      end

      variable_text_attributes.each do |attribute|
        it "reads #{label} runbook variable #{attribute} as its text form" do
          variable = loaded(runbook_variables: [{ id: 'given', type: 'string', attribute => value }])
                     .runbook_variables.first

          expect(variable.public_send(attribute)).to eq(text)
        end

        it "reads #{label} nested runbook variable #{attribute} as its text form" do
          nested = { id: 'nested', type: 'string', attribute => value }
          variable = loaded(runbook_variables: [{ id: 'given', label: 'Given', type: 'nested', fields: [nested] }])
                     .runbook_variables.first

          expect(variable.fields.first.public_send(attribute)).to eq(text)
        end
      end
    end

    it 'keeps text and absent values of a runbook variable unchanged' do
      variable = loaded(runbook_variables: [{ id: 'given', type: 'string', label: 'Given' }]).runbook_variables.first

      expect(variable.label).to eq('Given')
      expect(variable.hint).to be_nil
    end

    it 'keeps a description that is text unchanged' do
      runbook = loaded(trigger: { description: 'Starts it' }, actions: [{ description: 'Does it' }])

      expect([runbook.trigger.description, runbook.actions.first.description]).to eq(['Starts it', 'Does it'])
    end
  end

  context 'a runbook name the tolerant parse could not fully revive' do
    def loaded(name_yaml)
      IPaaS::Connector::Runbook.parse("uuid: f0000000-0000-4000-8000-000000000001\nname:#{name_yaml}\n",
                                      resolve: false, tolerant: true)
    end

    it 'reads a map holding an unloadable value as its text form' do
      name = loaded("\n  first: !ruby/object:OpenStruct {}").name

      expect(name).to eq('{first: #<IPaaS::Connector::Common::UnresolvedNode OpenStruct>}')
    end

    it 'keeps an unloadable value itself, so its error is reported' do
      runbook = loaded(' !ruby/object:OpenStruct {}')

      expect(runbook.name).to be_a(IPaaS::Connector::Common::UnresolvedNode)
      expect(runbook).not_to be_valid
      expect(runbook.errors[:name]).to include(runbook.name.message)
    end
  end

  describe 'binary values' do
    context 'in a runbook name' do
      def loaded_name(base64)
        IPaaS::Connector::Runbook.parse("uuid: f0000000-0000-4000-8000-000000000001\nname: !!binary #{base64}\n",
                                        resolve: false).name
      end

      it 'reads bytes that are valid UTF-8 as that text' do
        name = loaded_name('Q2Fmw6k=')

        expect(name).to eq('Café')
        expect(name.encoding).to eq(Encoding::UTF_8)
      end

      it 'replaces invalid bytes inside a secret string' do
        yaml = "uuid: f0000000-0000-4000-8000-000000000001\n" \
               "name: !ruby/object:IPaaS::Encryption::SecretString\n  encrypted: !!binary /w==\n"

        expect(IPaaS::Connector::Runbook.parse(yaml, resolve: false).name).to eq("\uFFFD")
      end
    end

    context 'in a uuid' do
      {
        IPaaS::Connector::Runbook => "name: Runbook\n",
        IPaaS::Connector::Connection => "name: Connection\ndirection: outbound\n",
        IPaaS::Connector::EnvironmentVariable => "name: Variable\ntype: string\n",
        IPaaS::TestCase::TestCase => "name: Test case\n",
      }.each do |model, rest|
        it "refuses a binary uuid in a #{model.name.demodulize} file" do
          expect { model.parse("uuid: !!binary /w==\n#{rest}", resolve: false) }
            .to raise_error(IPaaS::Error, 'UUID must be text.')
        end

        it "loads a text uuid in a #{model.name.demodulize} file" do
          expect(model.parse("uuid: f0000000-0000-4000-8000-000000000001\n#{rest}", resolve: false).uuid)
            .to eq('f0000000-0000-4000-8000-000000000001')
        end
      end

      it 'refuses a binary uuid whose bytes are valid UTF-8' do
        expect { IPaaS::Connector::Runbook.parse("uuid: !!binary w6k=\nname: Runbook\n", resolve: false) }
          .to raise_error(IPaaS::Error, 'UUID must be text.')
      end

      it 'refuses a binary uuid given with a symbol key' do
        expect { IPaaS::Connector::Runbook.parse(":uuid: !!binary /w==\nname: Runbook\n", resolve: false) }
          .to raise_error(IPaaS::Error, 'UUID must be text.')
      end
    end

    context 'anywhere in a file' do
      let(:binary) { '!!binary /w==' }

      it 'reads every binary value of a runbook file as text' do
        runbook = IPaaS::Connector::Runbook.parse(<<~YAML, resolve: false)
          uuid: f0000000-0000-4000-8000-000000000001
          name: !!binary Q2Fm/w==
          runbook_variables:
          - id: given
            type: string
            default: #{binary}
          actions:
          - reference: first
            input_mapping:
            - field_id: fixed_value
              fixed: #{binary}
            - field_id: keyed_value
              fixed: {#{binary}: 1}
            - field_id: variable_value
              variable: #{binary}
            - field_id: proc_value
              proc: #{binary}
            - field_id: secret_value
              fixed: !ruby/object:IPaaS::Encryption::SecretString
                encrypted: #{binary}
        YAML
        fixed, keyed, variable, procedure, secret = runbook.actions.first.input_mapping

        expect(runbook.name).to eq("Caf\uFFFD")
        expect(runbook.runbook_variables.first.default).to eq("\uFFFD")
        expect([fixed.fixed, variable.variable, procedure.proc]).to eq(["\uFFFD"] * 3)
        expect(keyed.fixed).to eq({ "\uFFFD": 1 })
        expect(secret.fixed.encrypted).to eq("\uFFFD")
      end

      it 'reads a binary value of a connection file as text' do
        connection = IPaaS::Connector::Connection.parse(<<~YAML, resolve: false)
          uuid: c0000000-0000-4000-8000-000000000001
          name: Connection
          direction: outbound
          config_mapping:
          - field_id: api_key
            fixed: #{binary}
        YAML

        expect(connection.config_mapping.first.fixed).to eq("\uFFFD")
      end

      it 'reports a binary type of an environment variable file as invalid text' do
        variable = IPaaS::Connector::EnvironmentVariable.parse(<<~YAML, resolve: false)
          uuid: e0000000-0000-4000-8000-000000000001
          name: Variable
          type: #{binary}
        YAML

        expect(variable.type.to_s).to eq("\uFFFD")
        expect(variable).not_to be_valid
        expect(variable.errors[:type]).to include('must be one of: string, secret_string, hashed_credential')
      end

      it 'keeps the bytes of a binary value in a test case file' do
        test_case = IPaaS::TestCase::TestCase.parse(<<~YAML, resolve: false)
          uuid: t0000000-0000-4000-8000-000000000001
          name: Test case
          actions:
          - reference: first
            iterations:
            - input_expectations:
              - field_id: given
                matcher: equals
                fixed: #{binary}
        YAML

        expect(test_case.actions.first.iterations.first.input_expectations.first.fixed).to eq("\xFF".b)
      end
    end
  end

  it 'reads a secret string wrapping a map as text' do
    yaml = "uuid: f0000000-0000-4000-8000-000000000001\n" \
           "name: !ruby/object:IPaaS::Encryption::SecretString\n  encrypted:\n    first: Mapped\n"

    expect(IPaaS::Connector::Runbook.parse(yaml, resolve: false).name).to eq('{"first" => "Mapped"}')
  end

  it 'still reports a map assigned through the setter as an invalid type' do
    runbook = IPaaS::Connector::Runbook.new('f0000000-0000-4000-8000-000000000001')
    runbook.name = { first: 'Mapped' }

    expect(runbook).not_to be_valid
    expect(runbook.name).to eq({ first: 'Mapped' })
    expect(runbook.errors[:name]).to include('Invalid type. Found Hash, expected String.')
  end

  describe 'a uuid that is a map or a list' do
    shaped_uuids = { 'a map' => "uuid:\n  first: Mapped\n", 'a list' => "uuid: [first]\n" }

    {
      IPaaS::Connector::Runbook => "name: Runbook\n",
      IPaaS::Connector::Connection => "name: Connection\ndirection: outbound\n",
      IPaaS::Connector::EnvironmentVariable => "name: Variable\ntype: string\n",
      IPaaS::TestCase::TestCase => "name: Test case\n",
    }.each do |model, rest|
      shaped_uuids.each do |label, uuid_yaml|
        it "refuses #{label} uuid in a #{model.name.demodulize} file" do
          expect { model.parse("#{uuid_yaml}#{rest}", resolve: false) }
            .to raise_error(IPaaS::Error, 'UUID must be text.')
        end
      end
    end

    it 'loads a number uuid as before' do
      expect(IPaaS::Connector::Runbook.parse("uuid: 12345\nname: Runbook\n", resolve: false).uuid).to eq(12_345)
    end
  end
end
