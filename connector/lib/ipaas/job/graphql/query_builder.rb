module IPaaS
  module Job
    module GraphQL
      module QueryBuilder
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :gql_build_field_selection, :gql_type_ref_string

        class << self
          def gql_build_field_selection(schema_data, type_name, depth, include_data: nil)
            return '' if type_name.blank? || depth > Schema::MAX_FIELD_DEPTH

            gql_fields = Schema.gql_collect_fields(schema_data, type_name)
            return 'id' if gql_fields.empty?

            included_fields = FieldBuilder.extract_included_field_names(include_data)
            build_selection_parts(schema_data, gql_fields, included_fields,
                                  include_data: include_data, depth: depth).join(' ')
          end

          def gql_type_ref_string(type_ref)
            case type_ref['kind']
            when 'NON_NULL'
              "#{gql_type_ref_string(type_ref['ofType'])}!"
            when 'LIST'
              "[#{gql_type_ref_string(type_ref['ofType'])}]"
            else
              type_ref['name']
            end
          end

          private

          def build_selection_parts(schema_data, gql_fields, included_fields,
                                    include_data:, depth:)
            gql_fields.each_with_object([]) do |gql_field, parts|
              add_selection_part(parts, schema_data, gql_field, included_fields,
                                 include_data: include_data, depth: depth)
            end
          end

          def add_selection_part(parts, schema_data, gql_field, included_fields,
                                 include_data:, depth:)
            return if Schema.gql_skip_field?(gql_field)

            type_info = Schema.gql_unwrap_type(gql_field['type'])
            if Schema.gql_to_ipaas_type(type_info) == :nested
              add_nested_selection(parts, schema_data, gql_field['name'], type_info,
                                   included_fields, include_data: include_data, depth: depth)
            else
              parts << gql_field['name']
            end
          end

          def add_nested_selection(parts, schema_data, field_name, type_info, included_fields,
                                   include_data:, depth:)
            return unless included_fields.include?(field_name)

            sub_include = FieldBuilder.extract_sub_include(include_data, field_name)
            nodes_field = Schema.gql_find_nodes_field(schema_data, type_info[:name])
            if nodes_field.present?
              add_connection_selection(parts, schema_data, field_name, nodes_field,
                                       depth: depth, sub_include: sub_include)
            else
              add_object_selection(parts, schema_data, field_name, type_info[:name],
                                   sub_include: sub_include, depth: depth)
            end
          end

          def add_connection_selection(parts, schema_data, field_name, nodes_field,
                                       depth:, sub_include:)
            node_type_info = Schema.gql_unwrap_type(nodes_field['type'])
            sub = gql_build_field_selection(schema_data, node_type_info[:name], depth + 1,
                                            include_data: sub_include)
            parts << "#{field_name}(first: 100) { nodes { #{sub} } }" if sub.present?
          end

          def add_object_selection(parts, schema_data, field_name, type_name,
                                   sub_include:, depth:)
            sub = gql_build_field_selection(schema_data, type_name, depth + 1,
                                            include_data: sub_include)
            parts << "#{field_name} { #{sub} }" if sub.present?
          end
        end
      end
    end
  end
end
