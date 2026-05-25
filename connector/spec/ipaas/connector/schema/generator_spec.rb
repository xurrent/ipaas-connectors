require 'spec_helper'

RSpec.describe IPaaS::Connector::Schema::Generator do
  describe '#dsl_lines' do
    subject(:output) { described_class.dsl_lines(*samples) }

    describe 'simple flat object' do
      let(:samples) { ['{"name": "John", "age": 30}'] }

      it 'generates string and integer fields' do
        expect(output).to include(<<~FIELD.chomp)
          field :name, 'Name', :string,
                sample: 'John'
        FIELD
        expect(output).to include(<<~FIELD.chomp)
          field :age, 'Age', :integer,
                sample: 30
        FIELD
      end
    end

    describe 'nested object' do
      let(:samples) { ['{"user": {"name": "John"}}'] }

      it 'generates nested field with sub-field' do
        expect(output).to eq(<<~DSL)
          field :user, 'User', :nested do
            field :name, 'Name', :string,
                  sample: 'John',
                  hint: 'For example: John'
          end
        DSL
      end
    end

    describe 'array of primitives' do
      let(:samples) { ['{"tags": ["a", "b"]}'] }

      it 'generates string array field' do
        expect(output).to include(<<~FIELD.chomp)
          field :tags, 'Tags', :string, array: true,
                sample: ['a', 'b'],
                hint: 'A list of values, for example: a, b'
        FIELD
      end
    end

    describe 'array of objects' do
      let(:samples) { ['{"items": [{"id": 1}, {"id": 2}]}'] }

      it 'generates nested array with sub-fields' do
        expect(output).to eq(<<~DSL)
          field :items, 'Items', :nested, array: true do
            field :id, 'ID', :integer,
                  sample: 1,
                  hint: 'For example: 1, 2'
          end
        DSL
      end
    end

    describe 'boolean and null values' do
      let(:samples) { ['{"active": true, "deleted": null}'] }

      it 'detects boolean and falls back to string for null' do
        expect(output).to include(<<~FIELD.chomp)
          field :active, 'Active', :boolean,
                sample: true
        FIELD
        expect(output).to include("field :deleted, 'Deleted', :string")
        expect(output).not_to match(/deleted.*sample:/)
      end
    end

    describe 'float values' do
      let(:samples) { ['{"score": 3.14}'] }

      it 'detects float type' do
        expect(output).to include(<<~FIELD.chomp)
          field :score, 'Score', :float,
                sample: 3.14
        FIELD
      end
    end

    describe 'multiple samples merging' do
      let(:samples) { ['{"name": "John"}', '{"age": 30}'] }

      it 'produces union of fields' do
        expect(output).to include("field :name, 'Name', :string")
        expect(output).to include("field :age, 'Age', :integer")
      end
    end

    describe 'type conflict across samples' do
      let(:samples) { ['{"value": "hello"}', '{"value": 42}'] }

      it 'falls back to string' do
        expect(output).to include("field :value, 'Value', :string")
        expect(output).not_to include(':integer')
      end
    end

    describe 'deeply nested (3+ levels)' do
      let(:samples) { ['{"a": {"b": {"c": {"d": "deep"}}}}'] }

      it 'handles deep nesting with proper indentation' do
        expect(output).to eq(<<~DSL)
          field :a, 'A', :nested do
            field :b, 'B', :nested do
              field :c, 'C', :nested do
                field :d, 'D', :string,
                      sample: 'deep',
                      hint: 'For example: deep'
              end
            end
          end
        DSL
      end
    end

    describe 'empty array' do
      let(:samples) { ['{"items": []}'] }

      it 'falls back to string array' do
        expect(output).to include("field :items, 'Items', :string, array: true")
      end
    end

    describe 'mixed-type array' do
      let(:samples) { [{ 'values' => [1, 'two'] }] }

      it 'falls back to string array' do
        expect(output).to include("field :values, 'Values', :string, array: true")
      end
    end

    describe 'camelCase keys' do
      let(:samples) { ['{"firstName": "John"}'] }

      it 'preserves original case in field id with readable label' do
        expect(output).to include(<<~FIELD.chomp)
          field :firstName, 'First name', :string,
                sample: 'John'
        FIELD
      end
    end

    describe 'array of objects merging' do
      let(:samples) { ['{"items": [{"a": 1}, {"b": "x"}]}'] }

      it 'merges all array element structures' do
        expect(output).to include("field :items, 'Items', :nested, array: true do")
        expect(output).to include("field :a, 'A', :integer")
        expect(output).to include("field :b, 'B', :string")
      end
    end

    describe 'multiple samples with arrays of objects' do
      let(:samples) do
        [
          '{"items": [{"a": 1}]}',
          '{"items": [{"b": "x"}]}',
        ]
      end

      it 'merges array element structures across samples' do
        expect(output).to include("field :a, 'A', :integer")
        expect(output).to include("field :b, 'B', :string")
      end
    end

    describe 'null in one sample, typed in another' do
      let(:samples) { ['{"name": null}', '{"name": "John"}'] }

      it 'resolves to the typed type' do
        expect(output).to include("field :name, 'Name', :string")
        expect(output).not_to include(':null')
      end
    end

    describe 'smart string sub-type detection' do
      describe 'URI detection' do
        it 'detects http:// and https:// URLs' do
          output = described_class.dsl_lines('{"url": "https://example.com/path"}')
          expect(output).to include(':uri')
        end

        it 'detects ftp:// URLs' do
          output = described_class.dsl_lines('{"url": "ftp://files.example.com"}')
          expect(output).to include(':uri')
        end

        it 'does not detect colon-separated strings as URI' do
          output = described_class.dsl_lines('{"tag": "host:Xurrent-FNX2Y3Q7FK"}')
          expect(output).to include(':string')
          expect(output).not_to include(':uri')
        end

        it 'does not detect plain strings as URI' do
          output = described_class.dsl_lines('{"name": "just a string"}')
          expect(output).not_to include(':uri')
        end
      end

      describe 'date-time detection' do
        let(:samples) { ['{"created_at": "2024-01-15T10:30:00Z"}'] }

        it 'detects date_time type' do
          expect(output).to include("field :created_at, 'Created at', :date_time")
        end
      end

      describe 'date detection' do
        let(:samples) { ['{"birth_date": "2024-01-15"}'] }

        it 'detects date type' do
          expect(output).to include("field :birth_date, 'Birth date', :date")
        end
      end

      describe 'time of day detection' do
        let(:samples) { ['{"start_time": "14:23:50"}'] }

        it 'detects time_of_day type' do
          expect(output).to include("field :start_time, 'Start time', :time_of_day")
        end
      end

      describe 'base64-like string stay string' do
        let(:samples) { ['{"data": "SGVsbG8="}'] }

        it 'does not detect as base64' do
          expect(output).to include("field :data, 'Data', :string")
          expect(output).not_to include(':base64')
        end
      end
    end

    describe 'sample and hint generation' do
      describe 'hint with unique values' do
        let(:samples) { ['{"status": "open"}', '{"status": "closed"}'] }

        it 'includes hint with all unique values' do
          expect(output).to include("hint: 'For example: closed, open'")
        end
      end

      describe 'hint deduplicates' do
        let(:samples) { ['{"status": "open"}', '{"status": "open"}'] }

        it 'deduplicates hint values' do
          expect(output).to include("hint: 'For example: open'")
        end
      end

      describe 'null values excluded from sample and hint' do
        let(:samples) { ['{"name": null}', '{"name": "John"}'] }

        it 'excludes null from sample and hint' do
          expect(output).to include("sample: 'John'")
          expect(output).to include("hint: 'For example: John'")
        end
      end

      describe 'no hint when all null' do
        let(:samples) { ['{"name": null}'] }

        it 'omits sample and hint' do
          expect(output).not_to include('sample:')
          expect(output).not_to include('hint:')
        end
      end

      describe 'integer sample' do
        let(:samples) { ['{"count": 42}'] }

        it 'includes integer sample' do
          expect(output).to include('sample: 42')
        end
      end

      describe 'array values collected' do
        let(:samples) { ['{"tags": ["a", "b"]}', '{"tags": ["b", "c"]}'] }

        it 'collects unique values across samples for hint ordered by frequency' do
          expect(output).to include("hint: 'A list of values, for example: b, a, c'")
        end
      end

      describe 'sample and hint are on separate indented lines' do
        let(:samples) { ['{"name": "John"}'] }

        it 'places sample and hint each on their own line' do
          expect(output).to eq(<<~DSL)
            field :name, 'Name', :string,
                  sample: 'John',
                  hint: 'For example: John'
          DSL
        end
      end
    end

    describe 'field ID truncation' do
      let(:samples) { [{ 'a_very_long_key_name_that_exceeds_forty_characters_total' => 'val' }] }

      it 'truncates field id to 40 characters' do
        expect(output).to match(/field :(\w{1,40}),/)
      end
    end

    describe 'hash input (not just JSON strings)' do
      let(:samples) { [{ 'name' => 'John', 'age' => 30 }] }

      it 'accepts parsed hashes' do
        expect(output).to include("field :name, 'Name', :string")
        expect(output).to include("field :age, 'Age', :integer")
      end
    end

    describe 'keys with special characters' do
      it 'sanitizes dots in keys' do
        output = described_class.dsl_lines('{"some.thing": "val"}')
        expect(output).to include("field :some_thing, 'Some thing', :string")
      end

      it 'sanitizes @ in keys' do
        output = described_class.dsl_lines('{"@type": "Event"}')
        expect(output).to include("field :type, 'Type', :string")
      end

      it 'sanitizes spaces in keys' do
        output = described_class.dsl_lines('{"my field": "val"}')
        expect(output).to include("field :my_field, 'My field', :string")
      end

      it 'handles keys with leading digits using quoted symbol syntax' do
        output = described_class.dsl_lines('{"3d_view": "val"}')
        expect(output).to include('field :"3d_view",')
      end
    end

    describe 'single quotes in values' do
      let(:samples) { [{ 'name' => "O'Brien" }] }

      it 'escapes single quotes in sample and hint values' do
        expect(output).to include("sample: 'O\\'Brien'")
        expect(output).to include("hint: 'For example: O\\'Brien'")
      end
    end

    describe 'empty string values' do
      let(:samples) { ['{"note": ""}'] }

      it 'includes sample but omits hint for empty string' do
        expect(output).to include("sample: ''")
        expect(output).not_to include('hint:')
      end
    end

    describe 'invalid time-of-day strings' do
      it 'rejects hour 25' do
        output = described_class.dsl_lines('{"time": "25:00:00"}')
        expect(output).to include(':string')
        expect(output).not_to include(':time_of_day')
      end

      it 'rejects minute 60' do
        output = described_class.dsl_lines('{"time": "14:60:00"}')
        expect(output).to include(':string')
        expect(output).not_to include(':time_of_day')
      end
    end

    describe 'merged array sample deduplication' do
      let(:samples) { ['{"tags": ["a", "b"]}', '{"tags": ["b", "c"]}'] }

      it 'deduplicates array sample values sorted by frequency' do
        expect(output).to include("sample: ['b', 'a', 'c']")
      end
    end

    describe 'integration tests with real connector JSON samples' do
      describe 'Datadog host list' do
        let(:samples) do
          [<<~JSON]
            {
              "total_matching": 1,
              "total_returned": 1,
              "has_next_page": false,
              "host_list": [
                {
                  "id": 123145537712914,
                  "name": "Xurrent-FNX2Y3Q7FK",
                  "host_name": "Xurrent-FNX2Y3Q7FK",
                  "aliases": ["Xurrent-FNX2Y3Q7FK"],
                  "apps": ["agent", "ntp"],
                  "sources": ["agent"],
                  "up": true,
                  "is_muted": false,
                  "mute_timeout": null,
                  "last_reported_time": 1770967634,
                  "tags_by_source": {
                    "Datadog": ["host:Xurrent-FNX2Y3Q7FK"]
                  },
                  "meta": {
                    "cpu_cores": 12,
                    "agent_version": "7.75.3",
                    "timezones": ["IST"],
                    "platform": "darwin",
                    "machine": "arm64",
                    "processor": "Apple M4 Pro",
                    "install_method": {
                      "installer_version": null,
                      "tool": null,
                      "tool_version": "install_script_mac"
                    },
                    "logs_agent": {
                      "transport": ""
                    },
                    "agent_flavor": "agent",
                    "host_id": 123145537712914,
                    "gohai": {
                      "cpu": { "cpu_cores": "12", "model_name": "Apple M4 Pro" },
                      "memory": { "swap_total": "2097152kB", "total": "25769803776" }
                    }
                  },
                  "metrics": {
                    "cpu": 8.087143,
                    "iowait": 0,
                    "load": 0.1817419
                  }
                }
              ]
            }
          JSON
        end

        it 'generates the full schema' do
          expected = <<~DSL
            field :total_matching, 'Total matching', :integer,
                  sample: 1,
                  hint: 'For example: 1'
            field :total_returned, 'Total returned', :integer,
                  sample: 1,
                  hint: 'For example: 1'
            field :has_next_page, 'Has next page', :boolean,
                  sample: false,
                  hint: 'For example: false'
            field :host_list, 'Host list', :nested, array: true do
              field :id, 'ID', :integer,
                    sample: 123145537712914,
                    hint: 'For example: 123145537712914'
              field :name, 'Name', :string,
                    sample: 'Xurrent-FNX2Y3Q7FK',
                    hint: 'For example: Xurrent-FNX2Y3Q7FK'
              field :host_name, 'Host name', :string,
                    sample: 'Xurrent-FNX2Y3Q7FK',
                    hint: 'For example: Xurrent-FNX2Y3Q7FK'
              field :aliases, 'Aliases', :string, array: true,
                    sample: ['Xurrent-FNX2Y3Q7FK'],
                    hint: 'A list of values, for example: Xurrent-FNX2Y3Q7FK'
              field :apps, 'Apps', :string, array: true,
                    sample: ['agent', 'ntp'],
                    hint: 'A list of values, for example: agent, ntp'
              field :sources, 'Sources', :string, array: true,
                    sample: ['agent'],
                    hint: 'A list of values, for example: agent'
              field :up, 'Up', :boolean,
                    sample: true,
                    hint: 'For example: true'
              field :is_muted, 'Is muted', :boolean,
                    sample: false,
                    hint: 'For example: false'
              field :mute_timeout, 'Mute timeout', :string
              field :last_reported_time, 'Last reported time', :integer,
                    sample: 1770967634,
                    hint: 'For example: 1770967634'
              field :tags_by_source, 'Tags by source', :nested do
                field :Datadog, 'Datadog', :string, array: true,
                      sample: ['host:Xurrent-FNX2Y3Q7FK'],
                      hint: 'A list of values, for example: host:Xurrent-FNX2Y3Q7FK'
              end
              field :meta, 'Meta', :nested do
                field :cpu_cores, 'CPU cores', :integer,
                      sample: 12,
                      hint: 'For example: 12'
                field :agent_version, 'Agent version', :string,
                      sample: '7.75.3',
                      hint: 'For example: 7.75.3'
                field :timezones, 'Timezones', :string, array: true,
                      sample: ['IST'],
                      hint: 'A list of values, for example: IST'
                field :platform, 'Platform', :string,
                      sample: 'darwin',
                      hint: 'For example: darwin'
                field :machine, 'Machine', :string,
                      sample: 'arm64',
                      hint: 'For example: arm64'
                field :processor, 'Processor', :string,
                      sample: 'Apple M4 Pro',
                      hint: 'For example: Apple M4 Pro'
                field :install_method, 'Install method', :nested do
                  field :installer_version, 'Installer version', :string
                  field :tool, 'Tool', :string
                  field :tool_version, 'Tool version', :string,
                        sample: 'install_script_mac',
                        hint: 'For example: install_script_mac'
                end
                field :logs_agent, 'Logs agent', :nested do
                  field :transport, 'Transport', :string,
                        sample: ''
                end
                field :agent_flavor, 'Agent flavor', :string,
                      sample: 'agent',
                      hint: 'For example: agent'
                field :host_id, 'Host ID', :integer,
                      sample: 123145537712914,
                      hint: 'For example: 123145537712914'
                field :gohai, 'Gohai', :nested do
                  field :cpu, 'CPU', :nested do
                    field :cpu_cores, 'CPU cores', :string,
                          sample: '12',
                          hint: 'For example: 12'
                    field :model_name, 'Model name', :string,
                          sample: 'Apple M4 Pro',
                          hint: 'For example: Apple M4 Pro'
                  end
                  field :memory, 'Memory', :nested do
                    field :swap_total, 'Swap total', :string,
                          sample: '2097152kB',
                          hint: 'For example: 2097152kB'
                    field :total, 'Total', :string,
                          sample: '25769803776',
                          hint: 'For example: 25769803776'
                  end
                end
              end
              field :metrics, 'Metrics', :nested do
                field :cpu, 'CPU', :float,
                      sample: 8.087143,
                      hint: 'For example: 8.087143'
                field :iowait, 'Iowait', :integer,
                      sample: 0,
                      hint: 'For example: 0'
                field :load, 'Load', :float,
                      sample: 0.1817419,
                      hint: 'For example: 0.1817419'
              end
            end
          DSL
          expect(output).to eq(expected)
        end
      end

      describe 'Logic Monitor trigger' do
        let(:samples) do
          [<<~JSON]
            {
              "alert_id": "LM-123456",
              "alert_message": "Production DB broke",
              "alert_level": "warn",
              "alert_status": "active",
              "alert_type": "critical"
            }
          JSON
        end

        it 'generates the full schema' do
          expected = <<~DSL
            field :alert_id, 'Alert ID', :string,
                  sample: 'LM-123456',
                  hint: 'For example: LM-123456'
            field :alert_message, 'Alert message', :string,
                  sample: 'Production DB broke',
                  hint: 'For example: Production DB broke'
            field :alert_level, 'Alert level', :string,
                  sample: 'warn',
                  hint: 'For example: warn'
            field :alert_status, 'Alert status', :string,
                  sample: 'active',
                  hint: 'For example: active'
            field :alert_type, 'Alert type', :string,
                  sample: 'critical',
                  hint: 'For example: critical'
          DSL
          expect(output).to eq(expected)
        end
      end

      describe 'Depot field update trigger' do
        let(:samples) do
          [<<~JSON]
            {
              "row_id": "42",
              "column_name": "Number",
              "old_value": null,
              "new_value": "33"
            }
          JSON
        end

        it 'generates the full schema' do
          expected = <<~DSL
            field :row_id, 'Row ID', :string,
                  sample: '42',
                  hint: 'For example: 42'
            field :column_name, 'Column name', :string,
                  sample: 'Number',
                  hint: 'For example: Number'
            field :old_value, 'Old value', :string
            field :new_value, 'New value', :string,
                  sample: '33',
                  hint: 'For example: 33'
          DSL
          expect(output).to eq(expected)
        end
      end

      describe 'N-Central trigger' do
        let(:samples) do
          [<<~JSON]
            {
              "action": "CREATE",
              "title": "Test Ticket",
              "details": "Test Details",
              "ncentralTicketId": "12345"
            }
          JSON
        end

        it 'generates the full schema' do
          expected = <<~DSL
            field :action, 'Action', :string,
                  sample: 'CREATE',
                  hint: 'For example: CREATE'
            field :title, 'Title', :string,
                  sample: 'Test Ticket',
                  hint: 'For example: Test Ticket'
            field :details, 'Details', :string,
                  sample: 'Test Details',
                  hint: 'For example: Test Details'
            field :ncentralTicketId, 'Ncentral ticket ID', :string,
                  sample: '12345',
                  hint: 'For example: 12345'
          DSL
          expect(output).to eq(expected)
        end
      end

      describe 'Nested with booleans (Xurrent App style)' do
        let(:samples) do
          [<<~JSON]
            {
              "customer_account_id": "acme-corp",
              "disabled": false,
              "enabled_by_customer": true,
              "suspended": false,
              "customer_representative": {
                "id": 42,
                "disabled": true,
                "name": "Jane Doe",
                "account": {
                  "id": "acme-123",
                  "name": "ACME Corp"
                }
              }
            }
          JSON
        end

        it 'generates the full schema' do
          expected = <<~DSL
            field :customer_account_id, 'Customer account ID', :string,
                  sample: 'acme-corp',
                  hint: 'For example: acme-corp'
            field :disabled, 'Disabled', :boolean,
                  sample: false,
                  hint: 'For example: false'
            field :enabled_by_customer, 'Enabled by customer', :boolean,
                  sample: true,
                  hint: 'For example: true'
            field :suspended, 'Suspended', :boolean,
                  sample: false,
                  hint: 'For example: false'
            field :customer_representative, 'Customer representative', :nested do
              field :id, 'ID', :integer,
                    sample: 42,
                    hint: 'For example: 42'
              field :disabled, 'Disabled', :boolean,
                    sample: true,
                    hint: 'For example: true'
              field :name, 'Name', :string,
                    sample: 'Jane Doe',
                    hint: 'For example: Jane Doe'
              field :account, 'Account', :nested do
                field :id, 'ID', :string,
                      sample: 'acme-123',
                      hint: 'For example: acme-123'
                field :name, 'Name', :string,
                      sample: 'ACME Corp',
                      hint: 'For example: ACME Corp'
              end
            end
          DSL
          expect(output).to eq(expected)
        end
      end
    end
  end

  describe '#fields' do
    let(:generator) { described_class.new('{"name": "John", "age": 30}') }

    it 'returns an array of Schema::Field instances' do
      fields = generator.fields
      expect(fields.length).to eq(2)
      expect(fields.map(&:id)).to eq([:name, :age])
      expect(fields.map(&:type)).to eq([:string, :integer])
      expect(fields.map(&:class).uniq).to eq([IPaaS::Connector::Schema::Field])
    end

    it 'returns valid Field objects' do
      expect(generator.fields).to all(be_valid)
    end
  end
end
