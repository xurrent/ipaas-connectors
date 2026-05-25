module IPaaS
  module Connector
    class Schema
      # Builds {Field} instances from an inferred structure hash.
      #
      # Takes the output of {StructureInferrer} and converts each field
      # in the structure into a {Schema::Field} instance, including nested fields.
      #
      # @example Build fields from a structure
      #   structure = StructureInferrer.infer('{"name": "John", "age": 30}')
      #   fields = FieldBuilder.build(structure)
      #   fields.first.id    # => :name
      #   fields.first.type  # => :string
      class FieldBuilder
        ACRONYMS = %w[id api url uri aws sqs http ftp ssl ip ipv4 ipv6 md5 cpu io fqdn].freeze

        class << self
          # Converts a JSON key to a snake_case field ID symbol.
          #
          # @param key [String] the original JSON key
          # @return [Symbol] the field ID
          def to_field_id(key)
            key.to_s
               .gsub(/[^a-zA-Z0-9]/, '_')
               .gsub(/\A_+|_+\z/, '')
               .squeeze('_')[0, 40].to_sym
          end

          # Converts a JSON key to a human-readable label.
          #
          # @param key [String] the original JSON key
          # @return [String] the label
          def to_label(key)
            normalized = key.to_s
                            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                            .downcase
                            .gsub(/[^a-z0-9]/, '_')
                            .gsub(/\A_+|_+\z/, '')
                            .squeeze('_')
            words = normalized.split('_')
            words.each { |w| w.upcase! if ACRONYMS.include?(w) }
            words.join(' ').sub(/\A./, &:upcase)
          end

          # Resolves a field type, falling back to :string for :null.
          #
          # @param field_struct [Hash] a field structure with a :type key
          # @return [Symbol] the resolved type
          def resolved_type(field_struct)
            field_struct[:type] == :null ? :string : field_struct[:type]
          end

          # Extracts a sample value from a field structure.
          #
          # @param field_struct [Hash] a field structure with :type, :values, :array keys
          # @param max_sample_values [Integer] maximum number of values for array samples
          # @return [Object, nil] the sample value
          def extract_sample(field_struct, max_sample_values: 3)
            return nil if field_struct[:type] == :nested

            sorted = values_by_frequency(field_struct)
            return nil if sorted.nil?

            return sorted.first unless field_struct[:array]

            limited = sorted.first(max_sample_values)
            limited.empty? ? nil : limited
          end

          # Extracts a hint string from a field structure.
          #
          # @param field_struct [Hash] a field structure with :type, :values, :array keys
          # @param max_hint_values [Integer] maximum number of values to include in the hint
          # @return [String, nil] the hint string
          def extract_hint(field_struct, max_hint_values: 10)
            return nil if field_struct[:type] == :nested

            unique = unique_hint_values(field_struct, max_hint_values)
            return nil if unique.nil?

            prefix = field_struct[:array] ? 'A list of values, for example' : 'For example'
            "#{prefix}: #{unique.join(', ')}"
          end

          # Builds an array of {Field} instances from an inferred structure.
          #
          # @param structure [Hash] the inferred structure from {StructureInferrer}
          # @param max_sample_values [Integer] maximum number of values for array samples
          # @param max_hint_values [Integer] maximum number of values to include in hints
          # @return [Array<Field>] the built fields
          def build(structure, max_sample_values: 3, max_hint_values: 10)
            new(structure, max_sample_values: max_sample_values, max_hint_values: max_hint_values).build
          end

          private

          def values_by_frequency(field_struct)
            values = field_struct[:values]
            return nil if values.nil? || values.empty?

            values.sort_by { |val, count| [-count, val.to_s] }.map(&:first)
          end

          def unique_hint_values(field_struct, max_hint_values)
            sorted = values_by_frequency(field_struct)
            return nil if sorted.nil?

            stringified = sorted.map(&:to_s).reject(&:empty?).first(max_hint_values)
            stringified.empty? ? nil : stringified
          end
        end

        # @param structure [Hash] the inferred structure from {StructureInferrer}
        # @param max_sample_values [Integer] maximum number of values for array samples
        # @param max_hint_values [Integer] maximum number of values to include in hints
        def initialize(structure, max_sample_values: 3, max_hint_values: 10)
          @structure = structure
          @max_sample_values = max_sample_values
          @max_hint_values = max_hint_values
        end

        # Builds the array of {Field} instances.
        #
        # @return [Array<Field>] the built fields
        def build
          build_fields(@structure)
        end

        private

        def build_fields(structure)
          return [] unless structure[:fields]

          seen_ids = Hash.new(0)
          used_ids = Set.new
          structure[:fields].map { |key, field_struct| build_field(key, field_struct, seen_ids, used_ids) }
        end

        def build_field(key, field_struct, seen_ids = {}, used_ids = Set.new)
          attrs = field_attributes(key, field_struct)
          resolve_unique_id(attrs, seen_ids, used_ids)
          used_ids << attrs[:id]
          field = Schema::Field.new(attrs)
          field.fields = build_fields(field_struct) if attrs[:type] == :nested
          field
        end

        def resolve_unique_id(attrs, seen_ids, used_ids)
          base_id = attrs[:id]
          seen_ids[base_id] += 1
          return unless used_ids.include?(base_id)

          n = seen_ids[base_id]
          loop do
            suffix = "_#{n}"
            candidate = :"#{base_id.to_s[0, 40 - suffix.length]}#{suffix}"
            break attrs[:id] = candidate unless used_ids.include?(candidate)
            n += 1
          end
        end

        def field_attributes(key, field_struct)
          type = self.class.resolved_type(field_struct)
          attrs = {
            id: self.class.to_field_id(key),
            label: self.class.to_label(key),
            type: type,
          }
          add_optional_attributes(attrs, field_struct)
        end

        def add_optional_attributes(attrs, field_struct)
          attrs[:array] = true if field_struct[:array]
          sample = self.class.extract_sample(field_struct, max_sample_values: @max_sample_values)
          attrs[:sample] = coerce_sample(sample, attrs[:type]) if sample
          hint = self.class.extract_hint(field_struct, max_hint_values: @max_hint_values)
          attrs[:hint] = hint if hint
          attrs
        end

        def coerce_sample(sample, type)
          type_def = IPaaS::Connector::Types.for(type)
          return sample unless type_def.respond_to?(:resolve)

          if sample.is_a?(Array)
            sample.map { |v| try_resolve_value(type_def, v) }
          else
            try_resolve_value(type_def, sample)
          end
        end

        def try_resolve_value(type_def, value)
          type_def.resolve(value)
        rescue StandardError
          value
        end
      end
    end
  end
end
