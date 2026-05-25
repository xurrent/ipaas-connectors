def field_mapping(mapping, schema: nil)
  return [] unless mapping || schema
  return mapping if mapping.is_a?(Array)
  return fixed_mapping(mapping) if mapping.is_a?(Hash)

  fixed_mapping(schema.example)
end

def fixed_mapping(hash)
  IPaaS::Connector::Mapping::FieldMapping.fixed_mapping(hash)
end