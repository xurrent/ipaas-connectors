require 'spec_helper'

RSpec.describe IPaaS::Connector::Schema::ConnectorGenerator do
  subject(:result) { described_class.generate(connector_name, *json_samples) }

  let(:connector_name) { 'Depot' }
  let(:json_samples) { ['{"row_id": "42", "column_name": "Number"}'] }

  describe 'connector generation' do
    describe 'class structure' do
      it 'generates a valid connector class' do
        connector = result[:connector]
        expect(connector).to start_with('class DepotConnector < IPaaS::Connector::Definition')
        expect(connector).to include("name 'Depot'")
        expect(connector).to include("description 'TODO: Add a description for the Depot connector.'")
        expect(connector).to end_with("end\n")
      end

      it 'includes a trigger block' do
        connector = result[:connector]
        expect(connector).to include("name 'Depot Webhook'")
        expect(connector).to include("description 'TODO: Add a description for this trigger.'")
      end

      it 'includes output_schema with fields from Schema::Generator' do
        connector = result[:connector]
        expect(connector).to include('output_schema do')
        expect(connector).to include("field :row_id, 'Row ID', :string")
        expect(connector).to include("field :column_name, 'Column name', :string")
        expect(connector).to include('end')
      end

      it 'includes a parse block with error handling' do
        connector = result[:connector]
        expect(connector).to include('parse do |request|')
        expect(connector).to include('body_content = request.body&.read')
        expect(connector).to include("fail_job!('Request has no body') if body_content.blank?")
        expect(connector).to include('JSON.parse(body_content)')
        expect(connector).to include('rescue JSON::ParserError => e')
        expect(connector).to include("fail_job!(\"Invalid JSON: \#{e.message}\")")
      end
    end

    describe 'class name derivation' do
      {
        'My API' => 'MyApiConnector',
        'datadog' => 'DatadogConnector',
        'N-Central' => 'NCentralConnector',
        'Depot' => 'DepotConnector',
        'My API (v2)' => 'MyApiV2Connector',
        'logic monitor' => 'LogicMonitorConnector',
      }.each do |input, expected|
        it "converts '#{input}' to #{expected}" do
          result = described_class.generate(input, '{"a": 1}')
          expect(result[:connector]).to start_with("class #{expected} < ")
        end
      end
    end

    describe 'UUID generation' do
      it 'generates real UUIDs for connector and trigger' do
        uuid_pattern = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
        connector = result[:connector]
        uuids = connector.scan(uuid_pattern)
        expect(uuids.length).to eq(2)
        expect(uuids[0]).not_to eq(uuids[1])
      end
    end

    describe 'output_schema field indentation' do
      it 'indents fields at 4 levels (8 spaces) inside output_schema' do
        connector = result[:connector]
        field_lines = connector.lines.select { |l| l.include?('field :') }
        field_lines.each do |line|
          expect(line).to match(/\A {8}field :/)
        end
      end
    end

    describe 'nested fields' do
      let(:json_samples) { ['{"user": {"name": "John", "age": 30}}'] }

      it 'renders nested output_schema fields' do
        connector = result[:connector]
        expect(connector).to include("field :user, 'User', :nested do")
        expect(connector).to include("field :name, 'Name', :string")
        expect(connector).to include("field :age, 'Age', :integer")
      end
    end

    describe 'camelCase JSON keys' do
      let(:json_samples) { ['{"assetBasicInfo": {"firstName": "John", "lastName": "Doe"}}'] }

      it 'uses output_schema field IDs that match the spec parse expectations' do
        connector = result[:connector]
        spec = result[:spec]

        # Extract field IDs from the output_schema (e.g. :asset_basic_info or :assetBasicInfo)
        schema_field_ids = connector.scan(/field\s+(?::"|:)(\w+)/).flatten

        # Extract the top-level keys used in the spec's expected output hash
        # The spec generates: expect(output).to eq({\n  key: value,\n})
        eq_block = spec[/expect\(output\).to eq\(\{(.+?)\n\s*\}\)/m, 1]
        # Top-level keys are those at the base indentation level
        spec_keys = eq_block.scan(/^\s{8}(\w+):/).flatten

        # Every key the spec expects in the output must exist as a field ID in the schema
        spec_keys.each do |key|
          expect(schema_field_ids).to include(key),
                                      "Spec expects key '#{key}' in output but schema has fields: #{schema_field_ids}"
        end
      end
    end
  end

  describe 'spec generation' do
    describe 'spec structure' do
      it 'includes spec_helper and trigger tag' do
        spec = result[:spec]
        expect(spec).to start_with("require 'spec_helper'")
        expect(spec).to include("describe 'Depot Webhook', :trigger do")
      end

      it 'includes trigger_template_id matching the connector trigger UUID' do
        uuid_pattern = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
        connector_trigger_uuid = result[:connector].scan(uuid_pattern)[1]
        spec_trigger_uuid = result[:spec].match(/trigger_template_id.*'(#{uuid_pattern})'/)[1]
        expect(spec_trigger_uuid).to eq(connector_trigger_uuid)
      end
    end

    describe 'output_schema assertions' do
      it 'generates one expect per top-level field' do
        spec = result[:spec]
        expect(spec).to include('expect(trigger.output_schema.field(:row_id).type).to eq(:string)')
        expect(spec).to include('expect(trigger.output_schema.field(:column_name).type).to eq(:string)')
      end

      it 'only asserts top-level fields for nested structures' do
        result = described_class.generate('Test', '{"user": {"name": "John"}}')
        spec = result[:spec]
        expect(spec).to include('field(:user).type).to eq(:nested)')
        expect(spec).not_to include('field(:name).type')
      end
    end

    describe 'parse request tests' do
      it 'uses JSON heredoc for sample data' do
        spec = result[:spec]
        expect(spec).to include('data = JSON.parse(<<~JSON)')
        expect(spec).to include('"row_id": "42"')
        expect(spec).to include('"column_name": "Number"')
      end

      it 'uses full output comparison with symbolized keys' do
        spec = result[:spec]
        expect(spec).to include("expect(output).to eq({\n")
        expect(spec).to include("row_id: '42',")
        expect(spec).to include("column_name: 'Number',")
      end

      it 'always includes empty body test' do
        spec = result[:spec]
        expect(spec).to include("it 'rejects empty request body' do")
        expect(spec).to include('post_trigger(nil)')
        expect(spec).to include("expect(output[:error]).to include('Request has no body')")
      end
    end

    describe 'multiple samples' do
      let(:json_samples) do
        [
          '{"status": "open"}',
          '{"status": "closed"}',
        ]
      end

      it 'generates one it block per sample' do
        spec = result[:spec]
        expect(spec).to include("it 'parses sample 1' do")
        expect(spec).to include("it 'parses sample 2' do")
        expect(spec).not_to include("it 'parses the webhook payload' do")
      end

      it 'includes each sample as JSON heredoc' do
        spec = result[:spec]
        expect(spec).to include('"status": "open"')
        expect(spec).to include('"status": "closed"')
      end
    end

    describe 'single sample uses singular description' do
      it 'names it parses the webhook payload' do
        spec = result[:spec]
        expect(spec).to include("it 'parses the webhook payload' do")
      end
    end

    describe 'nested JSON in parse assertions' do
      let(:json_samples) { ['{"user": {"name": "John", "active": true}}'] }

      it 'renders nested expected hash with symbol keys' do
        spec = result[:spec]
        expect(spec).to include('user: {')
        expect(spec).to include("name: 'John',")
        expect(spec).to include('active: true,')
      end
    end

    describe 'various value types in parse assertions' do
      let(:json_samples) { ['{"count": 42, "score": 3.14, "active": true, "note": null}'] }

      it 'renders correct Ruby literals' do
        spec = result[:spec]
        expect(spec).to include('count: 42,')
        expect(spec).to include('score: 3.14,')
        expect(spec).to include('active: true,')
        expect(spec).to include('note: nil,')
      end
    end

    describe 'array values in parse assertions' do
      let(:json_samples) { ['{"tags": ["a", "b"]}'] }

      it 'renders arrays inline' do
        spec = result[:spec]
        expect(spec).to include("tags: ['a', 'b'],")
      end
    end

    describe 'array of objects in parse assertions' do
      let(:json_samples) { ['{"items": [{"id": 1}, {"id": 2}]}'] }

      it 'renders array of hashes with proper indentation' do
        spec = result[:spec]
        expect(spec).to include('items: [')
        expect(spec).to include('id: 1,')
        expect(spec).to include('id: 2,')
      end
    end
  end

  describe 'connector name with special characters' do
    let(:connector_name) { "O'Reilly" }
    let(:json_samples) { ['{"a": 1}'] }

    it 'escapes single quotes in connector name' do
      connector = result[:connector]
      expect(connector).to include("name 'O\\'Reilly'")
    end
  end

  describe 'input validation' do
    it 'raises ArgumentError for blank connector name' do
      expect { described_class.generate('', '{"a": 1}') }.to raise_error(ArgumentError, /blank/)
    end

    it 'raises ArgumentError for whitespace-only connector name' do
      expect { described_class.generate('   ', '{"a": 1}') }.to raise_error(ArgumentError, /blank/)
    end

    it 'raises ArgumentError for name with only special characters' do
      expect { described_class.generate('---', '{"a": 1}') }.to raise_error(ArgumentError, /alphanumeric/)
    end

    it 'raises ArgumentError when no JSON samples are provided' do
      expect { described_class.generate('Test') }.to raise_error(ArgumentError, /at least one/)
    end
  end

  describe 'generated output is valid Ruby' do
    it 'generates syntactically valid connector code' do
      expect { RubyVM::InstructionSequence.compile(result[:connector]) }.not_to raise_error
    end

    it 'generates syntactically valid spec code' do
      expect { RubyVM::InstructionSequence.compile(result[:spec]) }.not_to raise_error
    end
  end

  describe 'deeply nested structures (3+ levels)' do
    let(:json_samples) { ['{"a": {"b": {"c": {"d": "deep"}}}}'] }

    it 'renders nested output_schema fields at all levels' do
      connector = result[:connector]
      expect(connector).to include("field :a, 'A', :nested do")
      expect(connector).to include("field :b, 'B', :nested do")
      expect(connector).to include("field :c, 'C', :nested do")
      expect(connector).to include("field :d, 'D', :string")
    end

    it 'renders nested expected hash in parse assertions' do
      spec = result[:spec]
      expect(spec).to include('a: {')
      expect(spec).to include('b: {')
      expect(spec).to include('c: {')
      expect(spec).to include("d: 'deep',")
    end

    it 'produces syntactically valid Ruby' do
      expect { RubyVM::InstructionSequence.compile(result[:connector]) }.not_to raise_error
      expect { RubyVM::InstructionSequence.compile(result[:spec]) }.not_to raise_error
    end
  end

  describe 'digit-leading keys' do
    let(:json_samples) { ['{"3d_view": "val"}'] }

    it 'uses quoted symbol syntax in schema assertions' do
      spec = result[:spec]
      expect(spec).to include('field(:"3d_view")')
    end

    it 'uses quoted symbol syntax in parse assertions' do
      spec = result[:spec]
      expect(spec).to include("'3d_view': 'val',")
    end

    it 'uses quoted symbol in connector output_schema' do
      expect(result[:connector]).to include('field :"3d_view",')
    end

    it 'generates syntactically valid connector and spec code' do
      expect { RubyVM::InstructionSequence.compile(result[:connector]) }.not_to raise_error
      expect { RubyVM::InstructionSequence.compile(result[:spec]) }.not_to raise_error
    end
  end

  describe 'empty JSON sample' do
    let(:json_samples) { ['{}'] }

    it 'generates empty output_schema block' do
      connector = result[:connector]
      expect(connector).to include("output_schema do\n      end")
    end

    it 'generates empty expected hash in parse assertion' do
      spec = result[:spec]
      expect(spec).to include('expect(output).to eq({})')
    end
  end
end
