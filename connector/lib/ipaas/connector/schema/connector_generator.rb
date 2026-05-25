require 'json'
require 'securerandom'

module IPaaS
  module Connector
    class Schema
      # Generates a complete connector class and trigger spec from JSON samples.
      #
      # Accepts a connector name and one or more JSON webhook payload samples,
      # and produces two ready-to-use Ruby source strings: a connector fixture
      # class with trigger (output_schema + parse block) and an RSpec trigger spec.
      #
      # @example Generate connector and spec
      #   result = ConnectorGenerator.generate('Depot', '{"row_id": "42"}')
      #   result[:connector] # => "class DepotConnector < IPaaS::Connector::Definition\n..."
      #   result[:spec]      # => "require 'spec_helper'\n..."
      class ConnectorGenerator
        # Generates a connector class and trigger spec from JSON samples.
        #
        # @param connector_name [String] human-readable name (e.g. "My API")
        # @param json_samples [Array<String, Hash>] one or more webhook payload samples
        # @return [Hash{ Symbol => String }] :connector and :spec source strings
        def self.generate(connector_name, *json_samples)
          new(connector_name, *json_samples).generate
        end

        # @param connector_name [String] human-readable name (e.g. "My API")
        # @param json_samples [Array<String, Hash>] one or more webhook payload samples
        # @raise [ArgumentError] if connector_name is blank or produces an empty class prefix,
        #   or if no JSON samples are provided
        def initialize(connector_name, *json_samples)
          @connector_name = connector_name
          validate_inputs!(json_samples)
          @samples = json_samples.map { |s| s.is_a?(String) ? JSON.parse(s) : s }
          @connector_uuid = SecureRandom.uuid_v7
          @trigger_uuid = SecureRandom.uuid_v7
        end

        # Generates both the connector class and trigger spec source strings.
        #
        # @return [Hash{ Symbol => String }] :connector and :spec source strings
        def generate
          { connector: generate_connector, spec: generate_spec }
        end

        private

        def generate_connector
          lines = connector_header_lines + trigger_header_lines
          lines += output_schema_lines + [''] + parse_block_lines
          lines += ['    end', '  end', 'end']
          "#{lines.join("\n")}\n"
        end

        def generate_spec
          lines = spec_header_lines + schema_context_lines + ['']
          lines += parse_context_lines
          lines << 'end'
          "#{lines.join("\n")}\n"
        end

        def connector_header_lines
          name = escape_single_quotes(@connector_name)
          [
            "class #{class_name} < IPaaS::Connector::Definition",
            "  connector '#{@connector_uuid}' do",
            "    name '#{name}'",
            "    description 'TODO: Add a description for the #{name} connector.'",
            '',
          ]
        end

        def trigger_header_lines
          [
            "    trigger '#{@trigger_uuid}' do",
            "      name '#{escape_single_quotes(trigger_name)}'",
            "      description 'TODO: Add a description for this trigger.'",
            '',
          ]
        end

        def output_schema_lines
          field_lines = schema_fields.chomp.lines.map { |l| "        #{l.chomp}" }
          ['      output_schema do'] + field_lines + ['      end']
        end

        def parse_block_lines
          parse_block_open + parse_block_body + ['      end']
        end

        def parse_block_open
          [
            '      parse do |request|',
            '        body_content = request.body&.read',
            "        fail_job!('Request has no body') if body_content.blank?",
            '',
          ]
        end

        def parse_block_body
          [
            '        begin',
            '          json = JSON.parse(body_content)',
            '          keys_to_field_id(json)',
            '        rescue JSON::ParserError => e',
            "          fail_job!(\"Invalid JSON: \#{e.message}\")",
            '        end',
          ]
        end

        def spec_header_lines
          [
            "require 'spec_helper'",
            '',
            "describe '#{escape_single_quotes(trigger_name)}', :trigger do",
            "  let(:trigger_template_id) { '#{@trigger_uuid}' }",
            '',
          ]
        end

        def schema_context_lines
          assertions = top_level_fields.map do |field_id, type|
            sym = field_id.match?(/\A[a-zA-Z_]/) ? ":#{field_id}" : ":\"#{field_id}\""
            "      expect(trigger.output_schema.field(#{sym}).type).to eq(:#{type})"
          end
          [
            "  context 'output_schema' do",
            "    it 'defines the expected fields' do",
          ] + assertions + ['    end', '  end']
        end

        def parse_context_lines
          lines = ["  context 'parse request' do"]
          lines += render_parse_tests
          lines += [''] + invalid_json_test_lines + ['  end']
          lines
        end

        def invalid_json_test_lines
          [
            "    it 'rejects empty request body' do",
            '      output = post_trigger(nil)',
            "      expect(output[:error]).to include('Request has no body')",
            '    end',
          ]
        end

        def render_parse_tests
          if @samples.length == 1
            render_parse_test(@samples.first, 'parses the webhook payload')
          else
            @samples.each_with_index.flat_map do |sample, idx|
              (idx > 0 ? [''] : []) + render_parse_test(sample, "parses sample #{idx + 1}")
            end
          end
        end

        def render_parse_test(sample, description)
          json_lines = JSON.pretty_generate(sample).lines.map { |l| "        #{l.chomp}" }
          [
            "    it '#{description}' do",
            '      data = JSON.parse(<<~JSON)',
          ] + json_lines + parse_test_assertion(sample)
        end

        def parse_test_assertion(sample)
          [
            '      JSON',
            '      output = post_trigger(data)',
            "      expect(output).to eq(#{render_expected_hash(sample, 8)})",
            '    end',
          ]
        end

        def render_expected_hash(hash, indent)
          return '{}' if hash.empty?

          pairs = hash.map do |key, value|
            field_id = FieldBuilder.to_field_id(key).to_s
            "#{' ' * indent}#{symbolize_key(field_id)}: #{render_ruby_value(value, indent)},"
          end
          "{\n#{pairs.join("\n")}\n#{' ' * (indent - 2)}}"
        end

        def render_ruby_value(value, indent)
          case value
          when Hash then render_expected_hash(value, indent + 2)
          when Array then render_ruby_array(value, indent)
          else DslBuilder.format_scalar(value)
          end
        end

        def render_ruby_array(array, indent)
          return '[]' if array.empty?
          return simple_array(array, indent) unless array.any? { |v| v.is_a?(Hash) || v.is_a?(Array) }

          items = array.map { |v| "#{' ' * (indent + 2)}#{render_ruby_value(v, indent + 2)}," }
          "[\n#{items.join("\n")}\n#{' ' * indent}]"
        end

        def simple_array(array, indent)
          "[#{array.map { |v| render_ruby_value(v, indent) }.join(', ')}]"
        end

        def class_name
          words = @connector_name
                  .gsub(/[^a-zA-Z0-9]/, ' ')
                  .squeeze(' ').strip
                  .split(/\s+/).map(&:capitalize)
          "#{words.join}Connector"
        end

        def trigger_name
          "#{@connector_name} Webhook"
        end

        def generator
          @generator ||= Schema::Generator.new(*@samples)
        end

        def schema_fields
          @schema_fields ||= generator.dsl_lines
        end

        def top_level_fields
          @top_level_fields ||= (generator.structure[:fields] || {}).map do |key, field_struct|
            [FieldBuilder.to_field_id(key).to_s, FieldBuilder.resolved_type(field_struct).to_s]
          end
        end

        def validate_inputs!(json_samples)
          raise ArgumentError, 'connector_name must not be blank' if @connector_name.to_s.strip.empty?
          raise ArgumentError, 'at least one JSON sample is required' if json_samples.empty?

          class_prefix = @connector_name.gsub(/[^a-zA-Z0-9]/, ' ').strip
          raise ArgumentError, 'connector_name must contain alphanumeric characters' if class_prefix.empty?
        end

        def symbolize_key(key)
          key_str = key.to_s
          return key_str if key_str.match?(/\A[a-zA-Z_]\w*\z/)

          "'#{escape_single_quotes(key_str)}'"
        end

        def escape_single_quotes(str)
          DslBuilder.escape_single_quotes(str)
        end
      end
    end
  end
end
