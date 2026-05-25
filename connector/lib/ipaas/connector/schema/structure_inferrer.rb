require 'json'

module IPaaS
  module Connector
    class Schema
      # Infers a unified type structure from one or more JSON samples.
      #
      # Accepts JSON strings or parsed hashes, infers types for each field,
      # and merges multiple samples into a single structure hash.
      #
      # @example From a single JSON string
      #   IPaaS::Connector::Schema::StructureInferrer.infer('{"name": "John", "age": 30}')
      #   # => { type: :nested, fields: { "name" => { type: :string, values: { "John" => 1 } }, ... } }
      #
      # @example From multiple samples
      #   inferrer = IPaaS::Connector::Schema::StructureInferrer.new(json1, json2)
      #   inferrer.infer
      class StructureInferrer
        DATE_TIME_PATTERN = /\A\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}/
        DATE_PATTERN = /\A\d{4}-\d{2}-\d{2}\z/
        TIME_OF_DAY_PATTERN = /\A([012]?\d):([012345]?\d)(?::([012345]?\d))?(?:\.(\d+))?\z/
        PRIMITIVE_TYPES = [:string, :integer, :float, :boolean, :null, :uri, :date_time, :date, :time_of_day].freeze

        class << self
          # Infers a unified structure from one or more JSON samples.
          #
          # @param json_samples [Array<String, Hash>] one or more JSON strings or parsed hashes
          # @return [Hash] the inferred structure
          def infer(*json_samples)
            new(*json_samples).infer
          end
        end

        # @param json_samples [Array<String, Hash>] one or more JSON strings or parsed hashes
        def initialize(*json_samples)
          @samples = json_samples.map { |s| s.is_a?(String) ? JSON.parse(s) : s }
        end

        # Infers and merges all samples into a single structure hash.
        #
        # @return [Hash] the inferred structure
        def infer
          merge_samples(@samples)
        end

        private

        def merge_samples(samples)
          samples.reduce({}) do |merged, sample|
            structure = infer_structure(sample)
            merged.empty? ? structure : merge_structures(merged, structure)
          end
        end

        def infer_structure(value)
          return infer_hash_structure(value) if value.is_a?(Hash)
          return infer_array_structure(value) if value.is_a?(Array)

          infer_scalar_structure(value)
        end

        def infer_hash_structure(hash)
          fields = hash.to_h do |key, val|
            child = infer_structure(val)
            child[:values] = { val => 1 } unless val.is_a?(Hash) || val.is_a?(Array) || val.nil?
            [key, child]
          end
          { type: :nested, fields: fields }
        end

        def infer_scalar_structure(value)
          { type: scalar_type(value) }
        end

        def scalar_type(value)
          case value
          when Integer then :integer
          when Float then :float
          when TrueClass, FalseClass then :boolean
          when NilClass then :null
          when String then infer_string_type(value)
          else :string
          end
        end

        def infer_array_structure(value)
          return { type: :string, array: true } if value.empty?

          element_structures = value.map { |el| infer_structure(el) }
          types = element_structures.map { |s| s[:type] }.uniq

          return infer_nested_array(element_structures, value) if types == [:nested]

          infer_primitive_array(types, value)
        end

        def infer_nested_array(element_structures, value)
          merged_fields = element_structures.reduce({}) do |acc, str|
            merge_field_maps(acc, str[:fields] || {})
          end
          collect_array_element_values(merged_fields, value)
          { type: :nested, array: true, fields: merged_fields }
        end

        def infer_primitive_array(types, value)
          if types.length == 1 && !types.include?(:null)
            { type: types.first, array: true, values: value.compact.tally }
          elsif PRIMITIVE_TYPES.intersect?(types)
            resolve_mixed_primitive_array(types, value)
          else
            { type: :string, array: true, values: value.map(&:to_s).tally }
          end
        end

        def resolve_mixed_primitive_array(types, value)
          resolved = types - [:null]
          if resolved.length == 1
            { type: resolved.first, array: true, values: value.compact.tally }
          else
            { type: :string, array: true, values: value.map(&:to_s).tally }
          end
        end

        def collect_array_element_values(merged_fields, array_elements)
          array_elements.grep(Hash).each do |element|
            collect_scalar_values(merged_fields, element)
          end
        end

        def collect_scalar_values(merged_fields, element)
          element.each do |key, val|
            next if val.is_a?(Hash) || val.is_a?(Array) || !merged_fields[key] || val.nil?

            increment_value(merged_fields[key], val)
          end
        end

        def increment_value(field, val)
          field[:values] ||= {}
          field[:values][val] = (field[:values][val] || 0) + 1
        end

        def infer_string_type(value)
          return :uri if uri?(value)
          return :date_time if value.match?(DATE_TIME_PATTERN)
          return :date if value.match?(DATE_PATTERN)
          return :time_of_day if valid_time_of_day?(value)

          :string
        end

        def uri?(value)
          value.match?(%r{\A[a-z][a-z0-9+\-.]*://}i)
        end

        def valid_time_of_day?(value)
          match = value.match(TIME_OF_DAY_PATTERN)
          return false unless match

          hours, minutes, seconds, _fraction = match.captures
          hours.to_i <= 23 && minutes.to_i < 60 && seconds.to_i < 60
        end

        def merge_structures(left, right)
          left_type = resolve_null(left[:type], right[:type])
          right_type = resolve_null(right[:type], left[:type])

          return merge_nested_structures(left, right) if left_type == :nested && right_type == :nested
          return merge_array_structures(left, right, left_type, right_type) if left[:array] || right[:array]

          merge_scalar_structures(left, right, left_type, right_type)
        end

        def merge_nested_structures(left, right)
          merged_fields = merge_field_maps(left[:fields] || {}, right[:fields] || {})
          result = { type: :nested, fields: merged_fields }
          result[:array] = true if left[:array] || right[:array]
          result
        end

        def merge_array_structures(left, right, left_type, right_type)
          resolved_type = left[:array] && right[:array] && left_type == right_type ? left_type : :string
          build_merged_result(resolved_type, true, left[:values], right[:values])
        end

        def merge_scalar_structures(left, right, left_type, right_type)
          resolved_type = left_type == right_type ? left_type : :string
          build_merged_result(resolved_type, false, left[:values], right[:values])
        end

        def build_merged_result(type, array, left_values, right_values)
          result = { type: type }
          result[:array] = true if array
          values = merge_values(left_values, right_values)
          result[:values] = values if values
          result
        end

        def resolve_null(type, other_type)
          type == :null ? other_type : type
        end

        def merge_field_maps(left, right)
          merged = left.dup
          right.each do |key, right_struct|
            merged[key] = merged[key] ? merge_structures(merged[key], right_struct) : right_struct
          end
          merged
        end

        def merge_values(left, right)
          merged = (left || {}).merge(right || {}) { |_key, l, r| l + r }
          merged.empty? ? nil : merged
        end
      end
    end
  end
end
