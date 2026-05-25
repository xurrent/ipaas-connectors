module IPaaS
  module Connector
    module Mapping
      class SchemaNameMapping
        include IPaaS::Connector::Common::Model

        attribute :schema_reference, required: true, length: { in: 1..50 }
        attribute :name_mapping, required: true, length: { in: 1..120 }

        class << self
          def parse(schema_name_mapping)
            array_or_hash = IPaaS::Connector::Common::Serializer.parse(schema_name_mapping)
            return array_or_hash.map { |snm| parse(snm) } if array_or_hash.is_a?(Array)
            return schema_name_mapping if schema_name_mapping.is_a?(SchemaNameMapping)

            raise IPaaS::Error, 'Schema name mapping must be a hash.' unless array_or_hash.is_a?(Hash)
            hash = array_or_hash.deep_symbolize_keys

            SchemaNameMapping.new.tap do |new_mapping|
              new_mapping.schema_reference = hash[:schema_reference]
              new_mapping.name_mapping = hash[:name_mapping]
            end
          end
        end

        def to_h_ref
          IPaaS::Connector::Common::Serializer.to_h(self, :schema_reference, :name_mapping)
        end
      end
    end
  end
end
