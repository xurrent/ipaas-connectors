module IPaaS
  module Connector
    class Schema
      # Builds connector DSL field definition strings from a structure hash.
      #
      # Takes the output of {StructureInferrer} and produces valid connector DSL
      # `field` definitions as a Ruby string.
      #
      # @example Build DSL from a structure
      #   structure = StructureInferrer.infer('{"name": "John"}')
      #   DslBuilder.build(structure)
      #   # => "field :name, 'Name', :string,\n      sample: 'John', ..."
      class DslBuilder
        class << self
          # Escapes single quotes in a string for use in Ruby source.
          #
          # @param str [String] the string to escape
          # @return [String] the escaped string
          def escape_single_quotes(str)
            str.to_s.gsub("'", "\\\\'")
          end

          # Formats a scalar Ruby value as a Ruby source literal.
          # Used by both DslBuilder and ConnectorGenerator to avoid duplication.
          #
          # @param value [Object] the value to format (String, NilClass, TrueClass, FalseClass, or Numeric)
          # @return [String] the Ruby source representation
          def format_scalar(value)
            case value
            when String then "'#{escape_single_quotes(value)}'"
            when NilClass then 'nil'
            when TrueClass, FalseClass then value.to_s
            else value.inspect
            end
          end

          # Builds a DSL field definitions string from a structure hash.
          #
          # @param structure [Hash] the inferred structure from {StructureInferrer}
          # @param max_hint_values [Integer] maximum number of values to include in hint text
          # @param max_sample_values [Integer] maximum number of values for array samples
          # @return [String] valid connector DSL field definitions
          def build(structure, max_hint_values: 10, max_sample_values: 3)
            new(structure, max_hint_values: max_hint_values, max_sample_values: max_sample_values).build
          end
        end

        # @param structure [Hash] the inferred structure from {StructureInferrer}
        # @param max_hint_values [Integer] maximum number of values to include in hint text
        # @param max_sample_values [Integer] maximum number of values for array samples
        def initialize(structure, max_hint_values: 10, max_sample_values: 3)
          @structure = structure
          @max_hint_values = max_hint_values
          @max_sample_values = max_sample_values
        end

        # Builds the DSL field definitions string.
        #
        # @return [String] valid connector DSL field definitions
        def build
          build_fields(@structure, 0)
        end

        private

        def build_fields(structure, indent)
          return '' unless structure[:fields]

          structure[:fields].map { |key, field_struct| build_field(key, field_struct, indent) }.join
        end

        def build_field(key, structure, indent)
          line = build_field_line(key, structure, indent)
          prefix = '  ' * indent

          if FieldBuilder.resolved_type(structure) == :nested && structure[:fields]&.any?
            "#{line} do\n#{build_fields(structure, indent + 1)}#{prefix}end\n"
          else
            "#{line}\n"
          end
        end

        def build_field_line(key, structure, indent)
          parts, sample_str, hint_str = build_field_parts(key, structure, indent)
          continuation = "#{'  ' * indent}#{' ' * 6}"
          line = parts.join(', ')
          line << ",\n#{continuation}#{sample_str}" if sample_str
          line << ",\n#{continuation}#{hint_str}" if hint_str
          line
        end

        def build_field_parts(key, structure, indent)
          parts = [field_declaration(key, structure, indent)]
          parts << 'array: true' if structure[:array]
          sample = FieldBuilder.extract_sample(structure, max_sample_values: @max_sample_values)
          sample_str = sample.nil? ? nil : "sample: #{format_ruby_value(sample)}"
          hint = FieldBuilder.extract_hint(structure, max_hint_values: @max_hint_values)
          hint_str = hint && "hint: '#{self.class.escape_single_quotes(hint)}'"
          [parts, sample_str, hint_str]
        end

        def field_declaration(key, structure, indent)
          prefix = '  ' * indent
          label = self.class.escape_single_quotes(FieldBuilder.to_label(key))
          field_id = symbol_literal(FieldBuilder.to_field_id(key))
          type = FieldBuilder.resolved_type(structure)
          "#{prefix}field #{field_id}, '#{label}', :#{type}"
        end

        def symbol_literal(id)
          id.to_s.match?(/\A[a-zA-Z_]/) ? ":#{id}" : ":\"#{id}\""
        end

        def format_ruby_value(value)
          case value
          when Array then "[#{value.map { |v| format_ruby_value(v) }.join(', ')}]"
          else self.class.format_scalar(value)
          end
        end
      end
    end
  end
end
