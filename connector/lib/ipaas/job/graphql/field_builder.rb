module IPaaS
  module Job
    module GraphQL
      module FieldBuilder
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :gql_add_dynamic_fields, :gql_add_dynamic_input_fields,
                  :gql_build_order_subfields, :gql_update_include_fields_input,
                  :gql_collect_dynamic_descriptors, :gql_restore_fields_from_descriptors

        class << self
          def gql_add_dynamic_fields(target, schema_data, type_name, depth, include_data: nil)
            return if type_name.blank? || depth > Schema::MAX_FIELD_DEPTH

            gql_fields = Schema.gql_collect_fields(schema_data, type_name)
            ctx = { included: extract_included_field_names(include_data),
                    include_data: include_data, }

            gql_fields.each { |gf| add_output_field(target, schema_data, gf, depth, ctx) }
          end

          def gql_add_dynamic_input_fields(target, schema_data, type_name, depth,
                                           visibility: nil, sort: false,
                                           visited_types: nil, field_counter: nil)
            return if type_name.blank? || depth > Schema::MAX_FIELD_DEPTH

            visited_types ||= Set.new
            return if visited_types.include?(type_name)

            input_ctx = build_input_ctx(visibility, visited_types | Set[type_name], field_counter)
            fetch_input_fields(schema_data, type_name, sort: sort).each do |f|
              break if input_ctx[:field_counter][0] >= Schema::MAX_INPUT_FIELDS

              input_ctx[:field_counter][0] += 1
              add_input_field(target, schema_data, f, depth, input_ctx)
            end
          end

          def gql_build_order_subfields(target, schema_data, order_type_name)
            order_type = Schema.gql_find_type(schema_data, order_type_name)
            return unless order_type.present?

            (order_type['inputFields'] || []).each do |input_field|
              add_order_field(target, schema_data, input_field)
            end
          end

          def gql_update_include_fields_input(target, schema_data, type_name, include_data, depth)
            type_names = Array(type_name).compact_blank
            return if type_names.empty? || depth > Schema::MAX_FIELD_DEPTH

            include_field = target.field(:include_fields)
            return unless include_field

            values = include_data&.[](:include_fields)
            values = {} unless values.is_a?(Hash)
            populate_include_booleans(include_field, schema_data, type_names, values, depth)
          end

          # --- Field descriptors (bundle serialize/restore) ---

          # Excludes the static ids the builder always rebuilds, serializing only the dynamic fields.
          def gql_collect_dynamic_descriptors(schema, static_ids)
            gql_collect_field_descriptors(schema.fields.reject { |f| static_ids.include?(f.id) })
          end

          # Paired with +gql_restore_fields_from_descriptors+ so the cold build and warm restore
          # produce the same fields.
          def gql_collect_field_descriptors(fields)
            fields.map { |f| field_descriptor(f) }
          end

          # The +default+ round-trip preserves an explicit +false+ while an absent default
          # restores as +nil+ (see +descriptor_opts+).
          def gql_restore_fields_from_descriptors(target, descriptors)
            descriptors.each do |desc|
              target.field desc['id'].to_sym, desc['label'], desc['type'].to_sym, **descriptor_opts(desc)
              next if desc['fields'].blank?

              gql_restore_fields_from_descriptors(target.field(desc['id'].to_sym), desc['fields'])
            end
          end

          # Extracts the list of included field names from the boolean hash structure.
          def extract_included_field_names(include_data)
            include_fields = include_data&.[](:include_fields)
            return [] if include_fields.blank? || !include_fields.is_a?(Hash)

            include_fields.filter_map do |key, value|
              key_s = key.to_s
              key_s if !key_s.end_with?('_fields') && value.to_s == 'true'
            end
          end

          # Extracts the sub-include data for a specific field from the boolean hash structure.
          def extract_sub_include(include_data, field_name)
            include_fields = include_data&.[](:include_fields)
            return {} unless include_fields.is_a?(Hash)

            sub = include_fields[:"#{field_name}_fields"] || include_fields["#{field_name}_fields"]
            sub.is_a?(Hash) ? { include_fields: sub } : {}
          end

          private

          # --- Field descriptor helpers ---

          def field_descriptor(field)
            desc = { 'id' => field.id.to_s, 'label' => field.label, 'type' => field.type.to_s }
            desc.merge!(optional_descriptor_attrs(field))
            desc.merge!(nested_descriptor_attrs(field))
          end

          def optional_descriptor_attrs(field)
            attrs = {}
            attrs['array'] = true if field.array
            attrs['required'] = true if field.required
            attrs['default'] = field.default unless field.default.nil? # only when set, so warm matches cold
            attrs['hint'] = field.hint if field.hint.present?
            attrs['visibility'] = field.visibility if non_default_visibility?(field)
            attrs
          end

          def nested_descriptor_attrs(field)
            attrs = {}
            attrs['enumeration'] = serialize_enumeration(field.enumeration) if field.enumeration.present?
            sub_fields = field.fields
            attrs['fields'] = gql_collect_field_descriptors(sub_fields) if sub_fields.is_a?(Array) && sub_fields.any?
            attrs
          end

          def non_default_visibility?(field)
            !field.visibility.nil? && field.visibility != 'visible'
          end

          def serialize_enumeration(enumeration)
            enumeration.map { |e| { 'id' => e[:id].to_s, 'label' => e[:label].to_s } }
          end

          def descriptor_opts(desc)
            opts = {}
            %w[array required hint visibility].each { |k| opts[k.to_sym] = desc[k] if desc[k] }
            opts[:default] = desc['default'] if desc.key?('default') # key check preserves an explicit false
            opts[:enumeration] = restore_enumeration(desc['enumeration']) if desc['enumeration'].present?
            opts
          end

          def restore_enumeration(enumeration)
            enumeration.map { |e| { id: e['id'], label: e['label'] } }
          end

          # --- Order fields ---

          def add_order_field(target, schema_data, input_field)
            name = input_field['name']
            type_info = Schema.gql_unwrap_type(input_field['type'])
            label = Humanize.humanize_field_name(name)
            opts = order_opts(input_field, type_info)

            if type_info[:kind] == 'ENUM'
              values = fetch_enum_labels(schema_data, type_info[:name])
              target.field name.to_sym, label, :string, enumeration: values, **opts
            else
              target.field name.to_sym, label, Schema.gql_to_ipaas_type(type_info), **opts
            end
          end

          def order_opts(input_field, type_info)
            opts = {}
            opts[:required] = true if type_info[:required]
            opts[:hint] = input_field['description'] if input_field['description'].present?
            opts
          end

          # --- Include fields ---

          def populate_include_booleans(container, schema_data, type_names, values, depth)
            include_ctx = { schema_data: schema_data, type_names: type_names, values: values, depth: depth }
            nested_options = union_nested_options(schema_data, type_names)
            return unless nested_options.any?

            nested_options.sort_by { |opt| opt[:id] }.each do |opt|
              container.field opt[:id].to_sym, opt[:label], :boolean, default: false, visibility: 'optional'
              expand_include_sub_fields(container, opt, include_ctx)
            end
          end

          def expand_include_sub_fields(container, opt, ctx) # rubocop:disable Metrics/AbcSize
            field_name = opt[:id]
            values = ctx[:values]
            return unless values[field_name.to_sym].to_s == 'true' && ctx[:depth] < Schema::MAX_FIELD_DEPTH

            sub_types = find_sub_types_with_nested(ctx[:schema_data], ctx[:type_names], field_name)
            return if sub_types.empty?

            fields_key = :"#{field_name}_fields"
            container.field fields_key, "#{opt[:label]} fields", :nested
            sub_values = values[fields_key].is_a?(Hash) ? values[fields_key] : {}
            populate_include_booleans(container.field(fields_key), ctx[:schema_data], sub_types,
                                      sub_values, ctx[:depth] + 1)
          end

          def find_sub_types_with_nested(schema_data, type_names, field_name)
            sub_types = type_names.filter_map { |tn| resolve_field_type_name(schema_data, tn, field_name) }.uniq
            union_nested_options(schema_data, sub_types).any? ? sub_types : []
          end

          def union_nested_options(schema_data, type_names)
            type_names.flat_map { |tn| list_nested_field_options(schema_data, tn) }
                      .uniq { |opt| opt[:id] }
          end

          def list_nested_field_options(schema_data, type_name)
            return [] if type_name.blank?

            Schema.gql_collect_fields(schema_data, type_name).filter_map do |gql_field|
              nested_field_option(gql_field)
            end
          end

          def nested_field_option(gql_field)
            field_name = gql_field['name']
            return if Schema.gql_skip_field?(gql_field)
            return if field_name.length > 40

            type_info = Schema.gql_unwrap_type(gql_field['type'])
            return unless Schema.gql_to_ipaas_type(type_info) == :nested

            { id: field_name, label: Humanize.humanize_field_name(field_name) }
          end

          def resolve_field_type_name(schema_data, parent_type_name, field_name)
            parent_type = Schema.gql_find_type(schema_data, parent_type_name)
            return nil unless parent_type.present?

            gql_field = (parent_type['fields'] || []).detect { |f| f['name'] == field_name }
            return nil unless gql_field.present?

            resolve_inner_type_name(schema_data, gql_field)
          end

          def resolve_inner_type_name(schema_data, gql_field)
            type_info = Schema.gql_unwrap_type(gql_field['type'])

            if %w[OBJECT INTERFACE].include?(type_info[:kind])
              nodes_field = Schema.gql_find_nodes_field(schema_data, type_info[:name])
              return Schema.gql_unwrap_type(nodes_field['type'])[:name] if nodes_field.present?
            end

            type_info[:name]
          end

          # --- Output fields ---

          def add_output_field(target, schema_data, gql_field, depth, ctx)
            return if Schema.gql_skip_field?(gql_field)

            type_info = Schema.gql_unwrap_type(gql_field['type'])
            ipaas_type = Schema.gql_to_ipaas_type(type_info)
            dispatch_output(target, schema_data, gql_field: gql_field, type_info: type_info,
                                                 ipaas_type: ipaas_type, depth: depth, ctx: ctx)
          end

          def dispatch_output(target, schema_data, gql_field:, type_info:,
                              ipaas_type:, depth:, ctx:)
            fld = output_field_attrs(gql_field, type_info)

            if ipaas_type == :nested
              add_nested_output(target, schema_data, type_info: type_info,
                                                     depth: depth, ctx: ctx, **fld)
            else
              add_scalar_output(target, schema_data, type_info: type_info,
                                                     ipaas_type: ipaas_type, **fld)
            end
          end

          def output_field_attrs(gql_field, type_info)
            name = gql_field['name']
            desc = gql_field['description']
            { field_id: name.to_sym, field_name: name, label: Humanize.humanize_field_name(name),
              hint_opts: desc.present? ? { hint: desc } : {}, list: type_info[:list], }
          end

          def add_scalar_output(target, schema_data, field_id:, label:, type_info:,
                                ipaas_type:, hint_opts:, **_)
            if ipaas_type == :string && type_info[:kind] == 'ENUM'
              values = fetch_enum_names(schema_data, type_info[:name])
              target.field field_id, label, :string,
                           array: type_info[:list], enumeration: values, **hint_opts
            else
              target.field field_id, label, ipaas_type, array: type_info[:list], **hint_opts
            end
          end

          def add_nested_output(target, schema_data, field_id:, field_name:, label:,
                                type_info:, hint_opts:, depth:, ctx:, **_)
            return unless ctx[:included].include?(field_name)

            sub_include = FieldBuilder.extract_sub_include(ctx[:include_data], field_name)
            common = { field_id: field_id, label: label, hint_opts: hint_opts,
                       depth: depth, sub_include: sub_include, }
            nodes_field = Schema.gql_find_nodes_field(schema_data, type_info[:name])
            if nodes_field.present?
              add_connection_output(target, schema_data, nodes_field: nodes_field, **common)
            else
              add_object_output(target, schema_data, type_info: type_info, **common)
            end
          end

          def add_object_output(target, schema_data, field_id:, label:,
                                type_info:, hint_opts:, depth:, sub_include:)
            target.field field_id, label, :nested, array: type_info[:list], **hint_opts
            gql_add_dynamic_fields(target.field(field_id), schema_data, type_info[:name],
                                   depth + 1, include_data: sub_include)
          end

          def add_connection_output(target, schema_data, field_id:, label:,
                                    nodes_field:, hint_opts:, depth:, sub_include:)
            node_type = Schema.gql_unwrap_type(nodes_field['type'])[:name]
            target.field field_id, label, :nested, array: true, **hint_opts
            gql_add_dynamic_fields(target.field(field_id), schema_data, node_type,
                                   depth + 1, include_data: sub_include)
          end

          # --- Input fields ---

          def add_input_field(target, schema_data, input_field, depth, input_ctx)
            field_name = input_field['name']
            return if field_name == 'clientMutationId' || field_name.length > 40

            type_info = Schema.gql_unwrap_type(input_field['type'])
            ipaas_type = Schema.gql_to_ipaas_type(type_info)
            opts = build_input_opts(input_field, type_info, field_name,
                                    depth: depth, visibility: input_ctx[:visibility])

            dispatch_input(target, schema_data, field_name: field_name, type_info: type_info,
                                                ipaas_type: ipaas_type, opts: opts, depth: depth,
                                                input_ctx: input_ctx)
          end

          def dispatch_input(target, schema_data, field_name:, type_info:,
                             ipaas_type:, opts:, depth:, input_ctx: {})
            field_id = field_name.to_sym
            label = Humanize.humanize_field_name(field_name)

            unless should_expand_input?(ipaas_type, type_info, depth, input_ctx)
              return add_flat_input(target, schema_data, field_id: field_id, label: label,
                                                         type_info: type_info, ipaas_type: ipaas_type, opts: opts)
            end

            target.field field_id, label, :nested, **opts
            gql_add_dynamic_input_fields(target.field(field_id), schema_data, type_info[:name], depth + 1,
                                         visited_types: input_ctx[:visited_types],
                                         field_counter: input_ctx[:field_counter])
          end

          def should_expand_input?(ipaas_type, type_info, depth, input_ctx)
            return false unless nested_input_object?(ipaas_type, type_info, depth)

            counter = input_ctx[:field_counter] || [0]
            counter[0] < Schema::MAX_INPUT_FIELDS
          end

          def add_flat_input(target, schema_data, field_id:, label:,
                             type_info:, ipaas_type:, opts:)
            if ipaas_type == :nested
              target.field field_id, label, :hash, **opts
            elsif ipaas_type == :string && type_info[:kind] == 'ENUM'
              values = fetch_enum_names(schema_data, type_info[:name])
              target.field field_id, label, :string, enumeration: values, **opts
            else
              target.field field_id, label, ipaas_type, **opts
            end
          end

          def build_input_ctx(visibility, visited_types, field_counter)
            { visibility: visibility, visited_types: visited_types, field_counter: field_counter || [0] }
          end

          def nested_input_object?(ipaas_type, type_info, depth)
            ipaas_type == :nested && type_info[:kind] == 'INPUT_OBJECT' && depth < Schema::MAX_FIELD_DEPTH
          end

          def build_input_opts(input_field, type_info, field_name, depth:, visibility:)
            is_required = !type_info[:list] && type_info[:required] && input_field['defaultValue'].blank?
            opts = { array: type_info[:list], required: is_required }
            opts[:hint] = input_field['description'] if input_field['description'].present?
            apply_visibility(opts, visibility, field_name, is_required, depth)
            opts
          end

          def apply_visibility(opts, visibility, field_name, is_required, depth)
            return unless visibility

            result = visibility.call(field_name, is_required, depth)
            opts[:visibility] = result if result
          end

          # --- Shared helpers ---

          def fetch_input_fields(schema_data, type_name, sort: false)
            type_def = Schema.gql_find_type(schema_data, type_name)
            return [] unless type_def.present?

            fields = type_def['inputFields'] || []
            sort ? fields.sort_by { |f| f['name'] } : fields
          end

          def fetch_enum_names(schema_data, enum_type_name)
            enum_type = Schema.gql_find_type(schema_data, enum_type_name)
            enum_type&.[]('enumValues')&.map { |e| e['name'] } || []
          end

          def fetch_enum_labels(schema_data, enum_type_name)
            enum_type = Schema.gql_find_type(schema_data, enum_type_name)
            enum_type&.[]('enumValues')&.map do |e|
              { id: e['name'], label: Humanize.humanize_field_name(e['name']) }
            end || []
          end
        end
      end
    end
  end
end
