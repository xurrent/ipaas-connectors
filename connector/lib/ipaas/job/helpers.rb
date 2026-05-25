module IPaaS
  module Job
    module Helpers
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :camel_to_snake, :keys_to_field_id

      def camel_to_snake(data, except = [])
        transform_keys_to_snake(data, except) { |key| key.to_s.underscore.to_sym }
      end

      def keys_to_field_id(data)
        transform_keys_to_snake(data) { |key| IPaaS::Connector::Schema::FieldBuilder.to_field_id(key) }
      end

      private

      def transform_keys_to_snake(data, except = [], &normalize_key)
        transform_value_to_snake(data, Array(except).map(&:to_s), &normalize_key)
      end

      def transform_value_to_snake(data, except_keys, &normalize_key)
        return transform_hash_to_snake(data, except_keys, &normalize_key) if data.is_a?(Hash)
        return data.map { |item| transform_value_to_snake(item, except_keys, &normalize_key) } if data.is_a?(Array)

        data
      end

      def transform_hash_to_snake(data, except_keys, &normalize_key)
        data.each_with_object({}) do |(key, value), normalized|
          add_transformed_pair(normalized, key, value, except_keys, &normalize_key)
        end
      end

      def add_transformed_pair(normalized, key, value, except_keys, &normalize_key)
        normalized_key = yield(key)
        return normalized[key] = value if except_keys.include?(key.to_s) || except_keys.include?(normalized_key.to_s)
        normalized[normalized_key] = transform_value_to_snake(value, except_keys, &normalize_key)
      end
    end
  end
end
