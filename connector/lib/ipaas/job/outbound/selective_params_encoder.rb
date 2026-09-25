module IPaaS
  module Job
    module Outbound
      class RawParamValue
        attr_reader :value

        # Deliberately a plain class rather than a Struct: `Array(struct)` unwraps a Struct into its
        # members, and the repeated-parameter handling in connectors calls `Array()`.
        def initialize(value)
          @value = value.to_s.dup.freeze
          reject(/[&\t\r\n]/, "'&', a tab, a carriage return or a newline",
                 'Use %26, %09, %0D or %0A for one that is part of the value.')
          reject(/%(?![0-9A-Fa-f]{2})/, "a '%' that is not followed by two hex digits",
                 "Use %25 for a literal '%'.")
        end

        def to_s
          value
        end

        def inspect
          value.inspect
        end

        private

        # The encoder joins parameters with `&`, so a bare `&` would split the value into an extra
        # parameter on an authenticated request. `;` is a plain character on the wire.
        # `URI::Generic#query=` deletes tab, CR and LF without reporting it, and it raises a bare
        # URI::InvalidURIError on some malformed percent escapes while shipping the rest verbatim.
        def reject(pattern, description, remedy)
          index = @value.index(pattern)
          return if index.nil?

          raise IPaaS::Error,
                "A query parameter value sent without encoding must not contain #{description}, " \
                "found one at index #{index}. #{remedy}"
        end
      end

      module ParamsEncoding
        def encode(params)
          return faraday_encoder.encode(params) unless raw?(params)

          query = params.map { |name, value| encode_pair(name, value) }.join('&')
          if query.match?(/[\t\r\n]/)
            raise IPaaS::Error, 'The encoded query carries a tab, carriage return or newline, which the URL ' \
                                'layer deletes silently; every value must have been escaped or refused before this.'
          end

          query
        end

        def decode(query)
          faraday_encoder.decode(query)
        end

        def raw?(params)
          return false if params.blank?

          param_values(params).any? { |value| Array.wrap(value).any?(RawParamValue) }
        end

        private

        def param_values(params)
          return params.values if params.respond_to?(:values)
          return params.filter_map { |pair| pair.last if pair.is_a?(Array) } if params.is_a?(Array)

          []
        end

        def encode_pair(name, value)
          return faraday_encoder.encode(name => value) unless Array.wrap(value).any?(RawParamValue)

          escaped_name = Faraday::Utils.escape(name)
          Array.wrap(value).map do |element|
            element.nil? ? escaped_name : "#{escaped_name}=#{encode_element(element)}"
          end.join('&')
        end

        # Faraday's own encoder recurses into a Hash or Array element; this one cannot, because a
        # raw sibling has already fixed the group's wire format, so refuse rather than emit `to_s`.
        def encode_element(element)
          return element.to_s if element.is_a?(RawParamValue) && element.value.exclude?('&')

          if element.is_a?(RawParamValue)
            raise IPaaS::Error, "A raw value reached the wire with a bare '&' at index #{element.value.index('&')}."
          end

          if element.is_a?(Hash) || element.is_a?(Array)
            raise IPaaS::Error,
                  'A query parameter grouped with a value sent without encoding must be a scalar, ' \
                  "found #{element.class}."
          end

          Faraday::Utils.escape(element.to_s)
        end
      end

      module SelectiveParamsEncoder
        extend ParamsEncoding

        def self.faraday_encoder
          Faraday::NestedParamsEncoder
        end
        private_class_method :faraday_encoder
      end

      module FlatSelectiveParamsEncoder
        extend ParamsEncoding

        def self.encode(params)
          param_values(params).flat_map { |value| Array.wrap(value) }.each do |element|
            next unless element.is_a?(Hash) || element.is_a?(Array)

            # Faraday's flat encoder does not recurse, caller should have handled them explicitly: complain loudly.
            raise IPaaS::Error, "array_params: :flat needs scalar values, found #{element.class}."
          end
          super
        end

        def self.faraday_encoder
          Faraday::FlatParamsEncoder
        end
        private_class_method :faraday_encoder
      end

      private_constant :ParamsEncoding
    end
  end
end
