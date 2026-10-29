module IPaaS
  module Connector
    module Dsl
      # The AttributeMixin module provides a DSL for defining and validating
      # attributes in a class. It allows specifying default values, required
      # attributes, format and length validations, and type checking for both
      # single values and arrays. This module is intended to be included in
      # classes that need to define and enforce structured attributes.
      #
      # Example:
      #   class Test
      #     include IPaaS::Connector::Model
      #     attribute :foo, default: 'Foo', required: true, length: { in: 4..120 }
      #   end
      #
      #   test = Test.new.tap
      #   test.valid?
      #   => false
      #   test.errors.full_messages
      #   => ["Foo can't be blank."]
      #
      #   test.foo = 'Bar'
      #   test.valid?
      #   => false
      #   test.errors.full_messages
      #   => ["Foo is too short (minimum is 4 characters)"]
      #
      #   test.foo 'A longer value'
      #   test.valid?
      #   => true
      module AttributeMixin
        extend ActiveSupport::Concern

        class_methods do
          def loaded_text(value)
            return value if value.nil? || value.is_a?(IPaaS::Connector::Common::UnresolvedNode)

            text = String(value.to_s)
            return text if text.encoding != Encoding::BINARY && text.valid_encoding?

            text.dup.force_encoding(Encoding::UTF_8).scrub
          end

          def loaded_binary_as_text(value)
            case value
            when Hash then value.to_h { |key, inner| [loaded_binary_as_text(key), loaded_binary_as_text(inner)] }
            when Array then value.map { |inner| loaded_binary_as_text(inner) }
            when String then loaded_text(value)
            when IPaaS::Encryption::SecretString
              value.dup.tap { |secret| secret.encrypted = loaded_binary_as_text(secret.encrypted) }
            else value
            end
          end

          def refuse_non_text_uuid!(hash)
            return unless [hash['uuid'], hash[:uuid]].any? { |uuid| non_text_uuid?(uuid) }

            raise IPaaS::Error, 'UUID must be text.'
          end

          def non_text_uuid?(uuid)
            case uuid
            when Hash, Array then true
            when String then uuid.encoding == Encoding::BINARY || !uuid.valid_encoding?
            else false
            end
          end

          private :loaded_text, :loaded_binary_as_text, :refuse_non_text_uuid!, :non_text_uuid?
        end

        included do
          def self.attribute(name, default: nil, required: nil, format: nil, length: nil, type: String)
            attr_accessor(name) { default.dup }
            (@attributes_names ||= []) << name

            validates name, presence: { message: "can't be blank." } if required
            validates name, format: format.merge({ message: 'is invalid.' }), allow_blank: true if format
            validates name, length: length, allow_blank: true if length

            validate do |record|
              record.send(:validate_type, name, type)
            end
          end

          def self.attribute_names
            @attributes_names
          end

          def attributes
            self.class.attribute_names.each_with_object({}) do |attribute_name, hash|
              value = self.send(attribute_name)
              hash[attribute_name] = value.respond_to?(:attributes) ? value.attributes : value
            end
          end

          def attributes=(hash)
            hash.each do |attribute_name, value|
              if value.is_a?(Proc)
                self.send(attribute_name, &value)
              elsif !value.nil?
                self.send(attribute_name, value)
              end
            end
          end

          def to_json(options = nil)
            attributes.to_json(options)
          end

          private

          def validate_type(name, type)
            value = self.send(name)
            return if value.nil?

            return report_unresolved_values(name, value) if IPaaS::Connector::Common::UnresolvedNode.within?(value)

            resolved_type = resolve_type(type)
            if resolved_type.is_a?(Array)
              validate_array_type(name, value, resolved_type.first)
            else
              validate_single_type(name, value, resolved_type)
            end
          end

          def report_unresolved_values(name, value)
            IPaaS::Connector::Common::UnresolvedNode.all_within(value).each { |node| errors.add(name, node.message) }
          end

          def resolve_type(type)
            type.is_a?(Proc) ? self.instance_exec(&type) : type
          end

          def validate_single_type(name, value, resolved_type)
            return if matches_type?(value, resolved_type)

            errors.add(name, "Invalid type. Found #{value.class.name}, expected #{resolved_type}.")
          end

          def validate_array_type(name, value, resolved_type)
            unless value.is_a?(Array)
              errors.add(name, 'Invalid type. Expected array.')
              return
            end

            value.each do |v|
              unless matches_type?(v, resolved_type)
                errors.add(name, "Invalid type. Found #{v.class.name} (#{v.inspect}), expected #{resolved_type}.")
              end
            end
          end

          def matches_type?(value, resolved_type)
            return true if value.is_a?(resolved_type)
            return true if try_resolve(value).is_a?(resolved_type)

            false
          end

          def try_resolve(value)
            self.try(:type_def)&.resolve(value)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
