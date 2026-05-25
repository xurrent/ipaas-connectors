module IPaaS
  module Job
    module GraphQL
      module Schema
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :gql_find_type, :gql_find_root_field, :gql_unwrap_type, :gql_resolve_return_type_name,
                  :gql_resolve_connection_node_type, :gql_mutation_input_type_name, :gql_list_root_fields,
                  :gql_collect_fields, :gql_required_args?, :gql_to_ipaas_type, :gql_find_nodes_field,
                  :gql_skip_field?

        INTROSPECTION_QUERY = { query: <<~GRAPHQL.gsub(/\s+/, ' ').strip }.to_json.freeze
          {
            __schema {
              queryType { name }
              mutationType { name }
              types {
                kind name description
                fields(includeDeprecated: false) {
                  name description
                  args { name description type { ...TypeRef } defaultValue }
                  type { ...TypeRef }
                }
                inputFields { name description type { ...TypeRef } defaultValue }
                enumValues(includeDeprecated: false) { name description }
                possibleTypes { name }
              }
            }
          }
          fragment TypeRef on __Type {
            kind name
            ofType { kind name
              ofType { kind name
                ofType { kind name
                  ofType { kind name
                    ofType { kind name
                      ofType { kind name }
                    }
                  }
                }
              }
            }
          }
        GRAPHQL

        MAX_FIELD_DEPTH = 6
        MAX_INPUT_FIELDS = 5000

        SCALAR_TYPE_MAP = {
          'Int' => :integer,
          'Float' => :float,
          'Boolean' => :boolean,
          'ISO8601DateTime' => :date_time,
          'ISO8601Timestamp' => :date_time,
          'ISO8601Date' => :date,
          'JSON' => :hash,
        }.freeze

        NESTED_KINDS = %w[OBJECT INTERFACE UNION INPUT_OBJECT].freeze
        WRAPPER_KINDS = %w[NON_NULL LIST].freeze

        class << self
          def gql_find_type(schema_data, type_name)
            build_type_index(schema_data) unless schema_data['_type_index']
            schema_data['_type_index'][type_name]
          end

          def gql_find_root_field(schema_data, operation, field_name)
            root_type = find_root_type(schema_data, operation)
            root_type&.[]('fields')&.detect { |f| f['name'] == field_name }
          end

          def gql_unwrap_type(type_ref)
            inner, is_list, is_required = unwrap_wrappers(type_ref)
            build_unwrapped_result(inner, is_list: is_list, is_required: is_required)
          end

          def gql_resolve_return_type_name(schema_data, operation, field_name)
            root_field = gql_find_root_field(schema_data, operation, field_name)
            return nil if root_field.blank?

            gql_unwrap_type(root_field['type'])[:name]
          end

          def gql_resolve_connection_node_type(schema_data, operation, field_name)
            return_type_name = gql_resolve_return_type_name(schema_data, operation, field_name)
            return nil if return_type_name.blank?

            nodes_field = gql_find_nodes_field(schema_data, return_type_name)
            return nil unless nodes_field

            gql_unwrap_type(nodes_field['type'])[:name]
          end

          def gql_mutation_input_type_name(schema_data, mutation_name)
            mutation_field = gql_find_root_field(schema_data, 'mutation', mutation_name)
            fallback = "#{mutation_name[0].upcase}#{mutation_name[1..]}Input"
            return fallback if mutation_field.blank?

            input_arg = mutation_field['args']&.detect { |a| a['name'] == 'input' }
            return fallback if input_arg.blank?

            gql_unwrap_type(input_arg['type'])[:name]
          end

          def gql_list_root_fields(schema_data, operation)
            return [] if schema_data.blank?

            root_type = find_root_type(schema_data, operation)
            return [] unless root_type

            root_type['fields']&.filter_map do |f|
              name = f['name']
              next if name.length > 40

              { id: name, label: IPaaS::Job::Humanize.humanize_field_name(name) }
            end || []
          end

          def gql_collect_fields(schema_data, type_name)
            type_def = gql_find_type(schema_data, type_name)
            return [] unless type_def.present?

            gql_fields = [*(type_def['fields'] || [])]
            if type_def['possibleTypes'].present? && gql_fields.empty?
              append_possible_type_fields(schema_data, type_def, gql_fields)
            end
            gql_fields
          end

          def gql_required_args?(gql_field)
            gql_field['args']&.any? do |arg|
              type_info = gql_unwrap_type(arg['type'])
              type_info[:required] && arg['defaultValue'].blank?
            end
          end

          def gql_to_ipaas_type(type_info)
            return SCALAR_TYPE_MAP.fetch(type_info[:name], :string) if type_info[:kind] == 'SCALAR'
            return :nested if NESTED_KINDS.include?(type_info[:kind])

            :string
          end

          def gql_find_nodes_field(schema_data, type_name)
            return_type = gql_find_type(schema_data, type_name)
            return nil unless return_type.present?

            return_type['fields']&.detect { |f| f['name'] == 'nodes' }
          end

          def gql_skip_field?(gql_field)
            field_name = gql_field['name']
            %w[pageInfo totalCount].include?(field_name) ||
              gql_required_args?(gql_field) ||
              field_name.length > 40
          end

          private

          def find_root_type(schema_data, operation)
            root_type_name = case operation
                             when 'query' then schema_data.dig('queryType', 'name')
                             when 'mutation' then schema_data.dig('mutationType', 'name')
                             end
            return nil if root_type_name.blank?

            gql_find_type(schema_data, root_type_name)
          end

          def build_type_index(schema_data)
            schema_data['_type_index'] = {}
            schema_data['types']&.each { |t| schema_data['_type_index'][t['name']] = t }
          end

          def unwrap_wrappers(type_ref)
            is_list = false
            is_required = false
            inner = type_ref

            while inner.present? && WRAPPER_KINDS.include?(inner['kind'])
              inner, is_list, is_required = unwrap_one_layer(inner, is_list, is_required)
            end

            [inner, is_list, is_required]
          end

          def unwrap_one_layer(inner, is_list, is_required)
            case inner['kind']
            when 'NON_NULL' then [inner['ofType'], is_list, true]
            when 'LIST' then [inner['ofType'], true, is_required]
            end
          end

          def build_unwrapped_result(inner, is_list:, is_required:)
            if inner.present? && inner['kind'].present? && !WRAPPER_KINDS.include?(inner['kind'])
              { kind: inner['kind'], name: inner['name'], list: is_list, required: is_required }
            else
              { kind: 'SCALAR', name: 'String', list: is_list, required: is_required }
            end
          end

          def append_possible_type_fields(schema_data, type_def, gql_fields)
            type_def['possibleTypes']&.each do |possible|
              merge_possible_fields(schema_data, possible['name'], gql_fields)
            end
          end

          def merge_possible_fields(schema_data, possible_name, gql_fields)
            possible_type = gql_find_type(schema_data, possible_name)
            possible_type&.[]('fields')&.each do |f|
              gql_fields << f unless gql_fields.any? { |existing| existing['name'] == f['name'] }
            end
          end
        end
      end
    end
  end
end
