module IPaaS
  module Connector
    module Common
      class Serializer
        ALLOWED_CLASSES = [Symbol, Time, Date, DateTime].freeze

        class << self
          def parse(value, with_uuid: false)
            case value
            when String, File
              YAML.load(value, permitted_classes: ALLOWED_CLASSES)
            else
              value
            end.tap do |v|
              if with_uuid && v.is_a?(Hash) && !v.key?('uuid') && !v.key?(:uuid)
                v['uuid'] = uuid_from_file(value) || SecureRandom.uuid_v7
              end
            end
          end

          def to_h(value, *attributes)
            attributes.each_with_object({}) do |attr, hash|
              result = value.send(attr)
              next hash unless result.present? || result == false # keep 'false' values in the output

              nested_reference = Array(result).first.respond_to?(:to_h_ref)
              result = result.is_a?(Array) ? result.map(&:to_h_ref) : result.to_h_ref if nested_reference

              hash[attr] = result
            end
          end

          private

          def uuid_from_file(value)
            return unless value.is_a?(File) && value.path.end_with?('.yaml', '.yml')

            File.basename(value, '.*')
          end
        end
      end
    end
  end
end
