module IPaaS
  module Connector
    module Types
      AVATAR_REGEXP = Regexp.union(URI::DEFAULT_PARSER.make_regexp, %r{/assets/icons/[0-9a-z-]+\.svg}).freeze

      mattr_accessor :registered_types do
        {}
      end

      class << self
        def register(type)
          validate_type(type)
          registered_types[type.key] = type
        end

        def all
          registered_types
        end

        def for(key)
          registered_types[key]
        end

        def validate_type(type)
          [:ruby_class, :example].each do |required_method|
            raise "Please implement #{required_method} for #{type}." unless type.respond_to?(required_method)
          end
        end
      end

      # default base class for shared behaviour of all types
      module Base
        extend ActiveSupport::Concern

        class << self
          def fallback_resolve(raw_value)
            return raw_value if raw_value.is_a?(Mapping::ResolvedMapping)

            if raw_value.is_a?(Array)
              raw_value.map { |r| fallback_resolve(r) }
            elsif raw_value.is_a?(Hash)
              raw_value.with_indifferent_access
            else
              raw_value
            end
          end
        end

        included do
          class << self
            def key
              # Remove the `_type` at the end
              self.name.underscore[0..-6].split('/').last.to_sym
            end

            # Resolves the value, e.g. to create a Field from a Hash
            # or a Regexp from a string or to auto-base64 encode a string.
            def resolve(resolved_value, context: nil)
              if nested? && respond_to?(:schema)
                schema.resolve(context, IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(resolved_value))
              else
                IPaaS::Connector::Types::Base.fallback_resolve(resolved_value)
              end
            end

            def valid?(_value, _errors = [])
              true
            end

            def nested?
              false
            end

            def variable_resolvable?
              false
            end

            private

            # Helper method for nested types to generate the sample based on the nested fields
            def fields_example(fields)
              fields.compact.to_h do |f|
                [f.id, f.example]
              end
            end
          end
        end
      end
    end
  end
end
